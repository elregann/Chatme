import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'call.dart';

class CallConstants {
  // Signal types
  static const String signalOffer = 'offer';
  static const String signalAnswer = 'answer';
  static const String signalCandidate = 'candidate';
  static const String signalHangup = 'hangup';

  // WebRTC constants
  static const String trackAudio = 'audio';
  static const String sdpOffer = 'offer';
  static const String sdpAnswer = 'answer';

  // Timeouts
  static const int connectionTimeoutSeconds = 30;
  static const int errorAutoCloseSeconds = 3;
  static const int reconnectionAttempts = 3;
  static const int reconnectionDelayBaseMs = 1000;

  static Map<String, dynamic> getIceConfig() {
    return {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun.relay.metered.ca:80'},
        {
          'urls': [
            'turn:global.relay.metered.ca:80',
            'turn:global.relay.metered.ca:80?transport=tcp',
            'turn:global.relay.metered.ca:443',
            'turns:global.relay.metered.ca:443?transport=tcp',
          ],
          'username': '2e00e35e35ee4662d8629b77',
          'credential': 'eDDxRR8GiVBH4MXr',
        },
      ],
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 10,
    };
  }

  static const Map<String, dynamic> audioConstraints = {
    'audio': {
      'echoCancellation': {'exact': true},
      'noiseSuppression': {'exact': true},
      'autoGainControl': {'exact': true},
      'channelCount': {'ideal': 1},
      'sampleRate': {'ideal': 48000},
      'sampleSize': {'ideal': 16},
      'latency': {'ideal': 0.01},
    },
    'video': false,
  };
}

// ==================== ENUMS & MODELS ====================
enum CallState {
  idle,
  initializing,
  ringing,
  connecting,
  active,
  reconnecting,
  ending,
  error
}

enum CallType {
  outgoing,
  incoming
}

class CallEvent {
  final String event;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  CallEvent(this.event, {this.data}) : timestamp = DateTime.now();

  @override
  String toString() => '$event - ${timestamp.toIso8601String()} ${data != null ? '- $data' : ''}';
}

// ==================== CALL MANAGER ====================
class CallManager {
  // ========== SINGLETON PATTERN ==========
  static final CallManager instance = CallManager._internal();
  CallManager._internal();

  // ========== STATE VARIABLES ==========
  rtc.RTCPeerConnection? _peerConnection;
  rtc.MediaStream? _localStream;
  rtc.RTCVideoRenderer? _remoteRenderer;

  String? activePeerName;
  String? activePeerPubkey;
  Color? activePeerColor;

  dynamic _currentRelay;
  String? _currentTargetPubkey;
  bool _isMakingOffer = false;

  static CallState _sharedCallState = CallState.idle;
  int _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;
  static final ValueNotifier<CallState> _sharedNotifier = ValueNotifier(CallState.idle);
  int _actualSeconds = 0;
  Timer? _durationTimer;
  DateTime? callStartTime;
  int _reconnectAttempts = 0;
  bool _isDisposing = false;

  bool _isMuted = false;
  bool _isSpeakerOn = false;

  Timer? _statsTimer;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;

  final Map<String, ValueChanged<CallState>> _stateChangeCallbacks = {};
  final Map<String, ValueChanged<String?>> _errorCallbacks = {};
  final Map<String, VoidCallback> _callEndedCallbacks = {};
  final Map<String, VoidCallback> _connectionCallbacks = {};

  final List<CallEvent> _callLog = [];

  // ========== PUBLIC GETTERS ==========
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  rtc.RTCVideoRenderer? get remoteRenderer => _remoteRenderer;
  List<CallEvent> get callLog => List.unmodifiable(_callLog);
  CallState get callState => _sharedCallState;
  ValueNotifier<CallState> get callStateNotifier => _sharedNotifier;

  // ========== CALLBACK MANAGEMENT ==========
  String addConnectionCallback(VoidCallback callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _connectionCallbacks[id] = callback;
    return id;
  }

  void removeConnectionCallback(String id) {
    _connectionCallbacks.remove(id);
  }

  String addErrorCallback(ValueChanged<String?> callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _errorCallbacks[id] = callback;
    return id;
  }

  void removeErrorCallback(String id) {
    _errorCallbacks.remove(id);
  }

  String addCallEndedCallback(VoidCallback callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _callEndedCallbacks[id] = callback;
    return id;
  }

  void removeCallEndedCallback(String id) {
    _callEndedCallbacks.remove(id);
  }

  String addStateChangeCallback(ValueChanged<CallState> callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _stateChangeCallbacks[id] = callback;
    return id;
  }

  void removeStateChangeCallback(String id) {
    _stateChangeCallbacks.remove(id);
  }

  void cleanupAllCallbacks() {
    _connectionCallbacks.clear();
    _errorCallbacks.clear();
    _callEndedCallbacks.clear();
    _stateChangeCallbacks.clear();
  }

  void setSessionInfo(String name, String pubkey, Color color) {
    activePeerName = name;
    activePeerPubkey = pubkey;
    activePeerColor = color;
  }

  // ========== STATE MANAGEMENT ==========
  void _setCallState(CallState newState) {
    if (_sharedCallState == newState) return;
    _sharedCallState = newState;

    if (newState == CallState.active) {
      callStartTime ??= DateTime.now();
      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _actualSeconds++;
      });
    } else if (newState == CallState.idle) {
      _durationTimer?.cancel();
      _durationTimer = null;
      _actualSeconds = 0;
      callStartTime = null;
      activePeerName = null;
      activePeerPubkey = null;
      activePeerColor = null;
    }

    _sharedNotifier.value = newState;
    _logCallEvent('state_change', {'to': newState.toString()});

    for (final callback in _stateChangeCallbacks.values) {
      try {
        callback(newState);
      } catch (e) {
        debugPrint('Error in state change callback: $e');
      }
    }
  }

  int get currentDuration => _actualSeconds;

  // ========== EVENT LOGGING ==========
  void _logCallEvent(String event, [Map<String, dynamic>? data]) {
    final callEvent = CallEvent(event, data: data);
    _callLog.add(callEvent);
    debugPrint('📞 CallEvent: $callEvent');
  }

  // ========== PUBLIC INTERFACE ==========
  void startCallFlow({
    required BuildContext context,
    required String peerName,
    required String peerPubkey,
    required dynamic relay,
    required Color peerColor,
  }) {
    setSessionInfo(peerName, peerPubkey, peerColor);

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/call'),
        builder: (context) => CallScreen(
          peerName: activePeerName ?? peerName,
          peerPubkey: activePeerPubkey ?? peerPubkey,
          relay: relay,
          isIncoming: false,
          peerColor: activePeerColor ?? peerColor,
          onClose: () {
            debugPrint('Call screen closed');
          },
        ),
      ),
    );

    if (_sharedCallState == CallState.idle) {
      Future.delayed(const Duration(milliseconds: 500), () {
        makeOffer(peerPubkey, relay, () => debugPrint("✅ Connected"));
      });
    }
  }

  // ========== AUDIO DEVICE MANAGEMENT ==========
  Future<void> initAudio() async {
    try {
      _logCallEvent('init_audio_started');

      if (_remoteRenderer == null) {
        _remoteRenderer = rtc.RTCVideoRenderer();
        await _remoteRenderer!.initialize();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final constraints = kIsWeb
          ? {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false
      }
          : CallConstants.audioConstraints;

      _localStream = await rtc.navigator.mediaDevices.getUserMedia(constraints);

      await Future.delayed(const Duration(milliseconds: 50));

      _isMuted = false;
      _isSpeakerOn = false;

      if (!kIsWeb && _localStream!.getAudioTracks().isNotEmpty) {
        try {
          _localStream!.getAudioTracks()[0].enableSpeakerphone(false);
        } catch (e) {
          debugPrint('Cannot set speakerphone: $e');
        }
      }

      _logCallEvent('init_audio_completed', {
        'hasAudio': _localStream!.getAudioTracks().isNotEmpty,
      });
    } catch (e) {
      _logCallEvent('init_audio_failed', {'error': e.toString()});

      for (final callback in _errorCallbacks.values) {
        try {
          callback('Tidak dapat mengakses mikrofon.');
        } catch (e) {
          debugPrint('Error in error callback: $e');
        }
      }
      rethrow;
    }
  }

  void toggleMute() {
    if (_localStream == null || _localStream!.getAudioTracks().isEmpty) return;
    try {
      final track = _localStream!.getAudioTracks()[0];
      _isMuted = !_isMuted;
      track.enabled = !_isMuted;
      _logCallEvent('mute_toggled', {'isMuted': _isMuted});
    } catch (e) {
      debugPrint('Error toggling mute: $e');
    }
  }

  void toggleSpeaker() {
    if (_localStream == null || _localStream!.getAudioTracks().isEmpty) return;
    try {
      final track = _localStream!.getAudioTracks()[0];
      _isSpeakerOn = !_isSpeakerOn;

      if (!kIsWeb) {
        track.enableSpeakerphone(_isSpeakerOn);
      } else {
        debugPrint('Web: Speaker mode $_isSpeakerOn');
      }
      _logCallEvent('speaker_toggled', {'isSpeakerOn': _isSpeakerOn});
    } catch (e) {
      debugPrint('Error toggling speaker: $e');
    }
  }

  // ========== WEBRTC PEER CONNECTION ==========
  Future<void> setupPeerConnection(String targetPubkey, dynamic relay, VoidCallback onConnected) async {
    if (_peerConnection != null) return;
    try {
      _lastProcessedTimestamp = DateTime.now().millisecondsSinceEpoch;

      _logCallEvent('peerconnection_setup_started');
      _currentRelay = relay;
      _currentTargetPubkey = targetPubkey;

      _peerConnection = await rtc.createPeerConnection(CallConstants.getIceConfig(), {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
          {'googIPv6': true},
        ]
      });

      _setupConnectionEvents(targetPubkey, relay, onConnected);

      relay.onSignalReceived = (Map<String, dynamic> event) {
        _handleGlobalIncomingSignal(event);
      };

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }
      _logCallEvent('peerconnection_setup_completed');
    } catch (e) {
      _peerConnection = null;

      for (final callback in _errorCallbacks.values) {
        try {
          callback('Gagal menyiapkan koneksi.');
        } catch (e) {
          debugPrint('Error in error callback: $e');
        }
      }
      rethrow;
    }
  }

  void _handleGlobalIncomingSignal(Map<String, dynamic> event) {
    try {
      final int? msgTimestamp = event['created_at'];

      if (msgTimestamp != null && (msgTimestamp * 1000) < _lastProcessedTimestamp) {
        debugPrint("⚠️ Sinyal basi diabaikan: Ghost Call dari masa lalu terdeteksi.");
        return;
      }

      final data = jsonDecode(event['content']);
      if (data is! Map) return;

      switch (data['type']) {
        case 'ringing':
          if (_sharedCallState == CallState.initializing) {
            _logCallEvent('remote_is_ringing');
            _setCallState(CallState.ringing);
          }
          break;
        case CallConstants.signalHangup:
          _logCallEvent('remote_hangup_received_by_manager');
          stopCall();
          break;
        case CallConstants.signalCandidate:
          addCandidate(data['data']);
          break;
        case CallConstants.signalAnswer:
          handleAnswer(data['data'], () {});
          break;
      }
    } catch (e) {
      debugPrint('Manager signal error: $e');
    }
  }

  void _setupConnectionEvents(String targetPubkey, dynamic relay, VoidCallback onConnected) {
    bool isRemoteTrackAttached = false;

    _peerConnection!.onTrack = (rtc.RTCTrackEvent event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        if (_remoteRenderer?.srcObject?.id != event.streams[0].id) {
          _remoteRenderer?.srcObject = event.streams[0];
          _logCallEvent('remote_track_attached');
          if (!isRemoteTrackAttached) {
            isRemoteTrackAttached = true;
            onConnected();

            for (final callback in _connectionCallbacks.values) {
              try {
                callback();
              } catch (e) {
                debugPrint('Error in connection callback: $e');
              }
            }
          }
        }
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      _logCallEvent('ice_connection_state', {'state': state.toString()});
      if (state == rtc.RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == rtc.RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _startQualityMonitoring();
        _reconnectAttempts = 0;
        _setCallState(CallState.active);
        _connectionTimeoutTimer?.cancel();
      }
      if (state == rtc.RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _attemptReconnection();
      }
    };

    _peerConnection!.onIceCandidate = (rtc.RTCIceCandidate? candidate) {
      if (candidate == null || candidate.candidate == null) return;
      relay.sendCallSignal(targetPubkey, {
        'type': CallConstants.signalCandidate,
        'data': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      });
    };
  }

  // ========== SIGNALING HANDLERS ==========
  Future<void> makeOffer(String targetPubkey, dynamic relay, VoidCallback onConnected) async {
    if (_sharedCallState != CallState.idle || _isMakingOffer) {
      return;
    }

    _isMakingOffer = true;
    try {
      _logCallEvent('make_offer_started');
      _setCallState(CallState.initializing);
      _currentRelay = relay;
      _currentTargetPubkey = targetPubkey;
      _startConnectionTimeout();

      await Future.delayed(const Duration(milliseconds: 200));

      await initAudio();

      await Future.delayed(const Duration(milliseconds: 200));

      await setupPeerConnection(targetPubkey, relay, onConnected);

      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peerConnection!.setLocalDescription(offer);

      relay.sendCallSignal(targetPubkey, {
        'type': CallConstants.signalOffer,
        'data': offer.sdp
      });

      _setCallState(CallState.ringing);
    } catch (e) {
      await stopCall();

      for (final callback in _errorCallbacks.values) {
        try {
          callback('Gagal memulai panggilan.');
        } catch (e) {
          debugPrint('Error in error callback: $e');
        }
      }
    } finally {
      _isMakingOffer = false;
    }
  }

  Future<void> handleOffer(String remoteSdp, String callerPubkey, dynamic relay, VoidCallback onConnected) async {
    try {
      _logCallEvent('handle_offer_received_sending_ringing');
      _setCallState(CallState.initializing);
      _currentRelay = relay;
      _currentTargetPubkey = callerPubkey;
      _startConnectionTimeout();

      relay.sendCallSignal(callerPubkey, {
        'type': 'ringing',
      });

      await initAudio();
      await setupPeerConnection(callerPubkey, relay, onConnected);

      await _peerConnection!.setRemoteDescription(rtc.RTCSessionDescription(remoteSdp, 'offer'));

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peerConnection!.setLocalDescription(answer);

      relay.sendCallSignal(callerPubkey, {
        'type': CallConstants.signalAnswer,
        'data': answer.sdp
      });
      _setCallState(CallState.connecting);
    } catch (e) {
      debugPrint('Error handling offer: $e');
      await stopCall();
    }
  }

  Future<void> handleAnswer(String sdp, VoidCallback onConnected) async {
    if (_peerConnection == null || _isDisposing) return;

    if (_peerConnection!.signalingState == rtc.RTCSignalingState.RTCSignalingStateStable) {
      debugPrint('ℹ️ Connection already stable, skipping duplicate answer');
      return;
    }

    try {
      _logCallEvent('setting_remote_description_answer');
      await _peerConnection!.setRemoteDescription(
          rtc.RTCSessionDescription(sdp, 'answer')
      );
    } catch (e) {
      _logCallEvent('handle_answer_error', {'error': e.toString()});
    }
  }

  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    if (_peerConnection == null || _isDisposing) return;
    try {
      final String candidateStr = candidateData['candidate']?.toString() ?? '';
      if (candidateStr.isEmpty) return;

      int mLineIndex = 0;
      final rawIndex = candidateData['sdpMLineIndex'];
      if (rawIndex is int) {
        mLineIndex = rawIndex;
      } else if (rawIndex is String) {
        mLineIndex = int.tryParse(rawIndex) ?? 0;
      }

      final iceCandidate = rtc.RTCIceCandidate(
          candidateStr,
          candidateData['sdpMid']?.toString() ?? '0',
          mLineIndex
      );

      if (kIsWeb) {
        int retry = 0;
        while (_peerConnection != null &&
            _peerConnection!.signalingState == rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer &&
            retry < 15) {
          await Future.delayed(const Duration(milliseconds: 200));
          retry++;
        }
      }

      await _peerConnection!.addCandidate(iceCandidate);
      debugPrint('✅ Candidate added successfully');
    } catch (e) {
      debugPrint('⚠️ Candidate error ignored: $e');
    }
  }

  // ========== CONNECTION MANAGEMENT ==========
  void _startConnectionTimeout() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (_sharedCallState != CallState.active) {
        if (_currentRelay != null && _currentTargetPubkey != null) {
          _currentRelay.sendCallSignal(_currentTargetPubkey!, {'type': 'hangup'});
        }
        await stopCall();
      }
    });
  }

  Future<void> _attemptReconnection() async {
    if (_reconnectAttempts >= CallConstants.reconnectionAttempts) {
      await stopCall();
      return;
    }
    _reconnectAttempts++;
    _setCallState(CallState.reconnecting);
    final delay = Duration(milliseconds: CallConstants.reconnectionDelayBaseMs * (1 << (_reconnectAttempts - 1)));
    _reconnectTimer = Timer(delay, () async {
      try {
        if (_peerConnection != null) {
          await _peerConnection!.restartIce();
        }
      } catch (e) {
        await _attemptReconnection();
      }
    });
  }

  void _startQualityMonitoring() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_peerConnection == null || _sharedCallState != CallState.active) {
        timer.cancel();
        return;
      }
      try {
        await _peerConnection!.getStats();
      } catch (e) {
        // Ignore stats errors
      }
    });
  }

  // ========== CALL LIFECYCLE ==========
  Future<void> stopCall({bool sendHangupSignal = false, String? targetPubkey, dynamic relay}) async {
    if (_isDisposing) return;
    _isDisposing = true;
    _setCallState(CallState.ending);

    try {
      _cancelAllTimers();

      if (sendHangupSignal && targetPubkey != null && relay != null) {
        relay.sendCallSignal(targetPubkey, {'type': 'hangup'});
      }

      await Future.delayed(const Duration(milliseconds: 300));

      if (_localStream != null) {
        _localStream!.getTracks().forEach((t) => t.stop());
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      _currentRelay?.onSignalReceived = null;
      _currentRelay = null;

      _setCallState(CallState.idle);

      for (final callback in _callEndedCallbacks.values) {
        try {
          callback();
        } catch (e) {
          debugPrint('Error in call ended callback: $e');
        }
      }
    } finally {
      _isDisposing = false;
    }
  }

  void _cancelAllTimers() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  Future<void> dispose() async {
    await stopCall();
    cleanupAllCallbacks();
  }
}