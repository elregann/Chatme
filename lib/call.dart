import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:proximity_sensor/proximity_sensor.dart';

// ==================== CONSTANTS ====================
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
        // STUN Google tetap dipakai sebagai prioritas pertama (Gratis & Cepat)
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun.relay.metered.ca:80'},

        // TURN Server Metered (Kredensial Pribadi kamu)
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

  // Audio constraints dengan pengaturan optimal
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
  // WebRTC Components
  rtc.RTCPeerConnection? _peerConnection;
  rtc.MediaStream? _localStream;
  rtc.RTCVideoRenderer? _remoteRenderer;

  // Signaling State
  dynamic _currentRelay;
  String? _currentTargetPubkey;
  bool _isMakingOffer = false;
  DateTime? _lastSignalSent;

  // Connection State
  CallState _callState = CallState.idle;
  int _reconnectAttempts = 0;
  bool _isDisposing = false;

  // Audio Control State
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  // Timers
  Timer? _statsTimer;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;

  // Callbacks Storage
  final Map<String, Function> _connectionCallbacks = {};
  final Map<String, Function(String)> _errorCallbacks = {};
  final Map<String, Function()> _callEndedCallbacks = {};
  final Map<String, Function(CallState)> _stateChangeCallbacks = {};

  // Logging
  final List<CallEvent> _callLog = [];

  // ========== PUBLIC GETTERS ==========
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  CallState get callState => _callState;
  rtc.RTCVideoRenderer? get remoteRenderer => _remoteRenderer;
  List<CallEvent> get callLog => List.unmodifiable(_callLog);

  // ========== CALLBACK MANAGEMENT ==========
  String addConnectionCallback(Function callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _connectionCallbacks[id] = callback;
    return id;
  }

  void removeConnectionCallback(String id) {
    _connectionCallbacks.remove(id);
  }

  String addErrorCallback(Function(String) callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _errorCallbacks[id] = callback;
    return id;
  }

  void removeErrorCallback(String id) {
    _errorCallbacks.remove(id);
  }

  String addCallEndedCallback(Function() callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _callEndedCallbacks[id] = callback;
    return id;
  }

  void removeCallEndedCallback(String id) {
    _callEndedCallbacks.remove(id);
  }

  String addStateChangeCallback(Function(CallState) callback) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _stateChangeCallbacks[id] = callback;
    return id;
  }

  void removeStateChangeCallback(String id) {
    _stateChangeCallbacks.remove(id);
  }

  // ========== STATE MANAGEMENT ==========
  void _setCallState(CallState newState) {
    if (_callState == newState) return;

    final oldState = _callState;
    _callState = newState;

    _logCallEvent('state_change', {
      'from': oldState.toString(),
      'to': newState.toString()
    });
    _notifyCallbacks(_stateChangeCallbacks, newState);
  }

  // ========== EVENT LOGGING & NOTIFICATION ==========
  void _logCallEvent(String event, [Map<String, dynamic>? data]) {
    final callEvent = CallEvent(event, data: data);
    _callLog.add(callEvent);
    debugPrint('📞 CallEvent: $callEvent');
  }

  void _notifyConnection() {
    _notifyCallbacks(_connectionCallbacks, null);
  }

  void _notifyError(String error) {
    _logCallEvent('error', {'message': error});
    _notifyCallbacks(_errorCallbacks, error);
  }

  void _notifyCallEnded() {
    _notifyCallbacks(_callEndedCallbacks, null);
  }

  void _notifyCallbacks<T>(Map<String, Function> callbacks, T? value) {
    for (final callback in Map<String, Function>.from(callbacks).values) {
      try {
        if (value != null) {
          callback(value);
        } else {
          callback();
        }
      } catch (e) {
        debugPrint('Error in callback: $e');
      }
    }
  }

  // ========== AUDIO DEVICE MANAGEMENT ==========
  Future<void> initAudio() async {
    try {
      _logCallEvent('init_audio_started');

      if (_remoteRenderer == null) {
        _remoteRenderer = rtc.RTCVideoRenderer();
        await _remoteRenderer!.initialize();
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
      _notifyError('Tidak dapat mengakses mikrofon.');
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
  Future<void> setupPeerConnection(String targetPubkey, dynamic relay, Function onConnected) async {
    if (_peerConnection != null) return;
    try {
      _logCallEvent('peerconnection_setup_started');

      // Konfigurasi dengan dukungan IPv6 untuk jaringan seluler
      _peerConnection = await rtc.createPeerConnection(CallConstants.getIceConfig(), {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
          {'googIPv6': true},
        ]
      });

      _setupConnectionEvents(targetPubkey, relay, onConnected);

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localStream!);
        }
      }
      _logCallEvent('peerconnection_setup_completed');
    } catch (e) {
      _peerConnection = null;
      _notifyError('Gagal menyiapkan koneksi.');
      rethrow;
    }
  }

  void _setupConnectionEvents(String targetPubkey, dynamic relay, Function onConnected) {
    bool isRemoteTrackAttached = false;

    _peerConnection!.onTrack = (rtc.RTCTrackEvent event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        if (_remoteRenderer?.srcObject?.id != event.streams[0].id) {
          _remoteRenderer?.srcObject = event.streams[0];
          _logCallEvent('remote_track_attached');
          if (!isRemoteTrackAttached) {
            isRemoteTrackAttached = true;
            onConnected();
            _notifyConnection();
          }
        }
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      _logCallEvent('ice_connection_state', {'state': state.toString()});
      if (state == rtc.RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == rtc.RTCIceConnectionState.RTCIceConnectionStateCompleted) {
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
  Future<void> makeOffer(String targetPubkey, dynamic relay, Function onConnected) async {
    if (_isMakingOffer || _callState != CallState.idle) return;
    _isMakingOffer = true;
    try {
      _logCallEvent('make_offer_started');
      _setCallState(CallState.initializing);
      _currentRelay = relay;
      _currentTargetPubkey = targetPubkey;
      _startConnectionTimeout();

      await initAudio();
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
      _notifyError('Gagal memulai panggilan.');
    } finally {
      _isMakingOffer = false;
    }
  }

  Future<void> handleOffer(String remoteSdp, String callerPubkey, dynamic relay, Function onConnected) async {
    try {
      _logCallEvent('handle_offer_started');
      _setCallState(CallState.initializing);
      _currentRelay = relay;
      _currentTargetPubkey = callerPubkey;
      _startConnectionTimeout();

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
      await stopCall();
    }
  }

  Future<void> handleAnswer(String sdp, Function onConnected) async {
    if (_peerConnection == null) return;
    if (_peerConnection!.signalingState == rtc.RTCSignalingState.RTCSignalingStateStable) return;

    try {
      await _peerConnection!.setRemoteDescription(rtc.RTCSessionDescription(sdp, 'answer'));
      _setCallState(CallState.connecting);
    } catch (e) {
      debugPrint('Error handling answer: $e');
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
      if (_callState != CallState.active) {
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
      if (_peerConnection == null || _callState != CallState.active) {
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

      if (_localStream != null) {
        _localStream!.getTracks().forEach((t) => t.stop());
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      _setCallState(CallState.idle);
      _notifyCallEnded();
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
  }

  Future<void> dispose() async {
    await stopCall();
    _connectionCallbacks.clear();
    _errorCallbacks.clear();
    _callEndedCallbacks.clear();
    _stateChangeCallbacks.clear();
  }
}

// ==================== CALL SCREEN ====================
class CallScreen extends StatefulWidget {
  final String peerName;
  final String peerPubkey;
  final bool isIncoming;
  final dynamic relay;
  final Color peerColor;
  final String? remoteSdp;
  final VoidCallback? onClose;

  const CallScreen({
    super.key,
    required this.peerName,
    required this.peerPubkey,
    required this.isIncoming,
    required this.relay,
    required this.peerColor,
    this.remoteSdp,
    this.onClose,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // ========== DEPENDENCIES ==========
  final CallManager _callManager = CallManager.instance;
  Function(dynamic)? _originalRelayCallback;

  // ========== UI STATE ==========
  late bool _isCallActive;
  bool _isAcceptedByMe = false;
  bool _hasError = false;
  bool _isConnecting = false;
  String? _errorMessage;
  bool _isNearProximity = false;

  // ========== TIMERS & SUBSCRIPTIONS ==========
  Timer? _callTimer;
  Timer? _errorAutoCloseTimer;
  StreamSubscription<int>? _proximitySubscription;
  int _seconds = 0;

  // ========== FLAGS & IDS ==========
  final List<String> _callbackIds = [];
  bool _isInitializing = false;
  bool _isHandlingHangup = false;
  bool _isEndingCall = false;

  // ========== LIFECYCLE ==========
  @override
  void initState() {
    super.initState();
    _isCallActive = false;

    _logCallEvent('call_screen_init', {
      'isIncoming': widget.isIncoming,
      'peerName': widget.peerName,
      'hasRemoteSdp': widget.remoteSdp != null && widget.remoteSdp!.isNotEmpty
    });

    _setupCallbacks();
    _initProximitySensor();
    _setupRemoteHangupDetection();

    if (!widget.isIncoming) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startOutgoingCall();
      });
    } else {
      _startMissedCallTimeout();
    }
  }

  @override
  void dispose() {
    _cleanupResources();
    super.dispose();
  }

  // ========== INITIALIZATION ==========
  void _setupCallbacks() {
    _callbackIds.add(_callManager.addConnectionCallback(_onCallConnected));
    _callbackIds.add(_callManager.addErrorCallback(_onCallError));
    _callbackIds.add(_callManager.addCallEndedCallback(_onCallEnded));
    _callbackIds.add(_callManager.addStateChangeCallback(_onCallStateChanged));
  }

  void _initProximitySensor() {
    if (!kIsWeb) {
      try {
        _proximitySubscription = ProximitySensor.events.listen((int event) {
          _isNearProximity = event == 1;
          _updateSystemUIMode();
          if (mounted) setState(() {});
        });
      } catch (e) {
        debugPrint('Proximity sensor not available: $e');
      }
    }
  }

  void _updateSystemUIMode() {
    if (!kIsWeb) {
      // Gunakan leanBack agar status bar hanya tersembunyi tanpa mengubah layout dasar (no deg!)
      SystemChrome.setEnabledSystemUIMode(
        _isNearProximity ? SystemUiMode.leanBack : SystemUiMode.edgeToEdge,
      );
    }
  }

  void _setupRemoteHangupDetection() {
    try {
      _originalRelayCallback ??= widget.relay.onSignalReceived;
      widget.relay.onSignalReceived = (Map<String, dynamic> event) {
        _originalRelayCallback?.call(event);
        if (!mounted) return;
        _handleIncomingSignal(event);
      };
    } catch (e) {
      debugPrint('Remote hangup setup failed: $e');
    }
  }

  void _handleIncomingSignal(Map<String, dynamic> event) {
    try {
      final data = jsonDecode(event['content']);
      if (data is Map && data['type'] == CallConstants.signalHangup) {
        _onRemoteHangup();
      }
    } catch (_) {
      // Ignore parsing errors
    }
  }

  // ========== TIMER MANAGEMENT ==========
  void _startMissedCallTimeout() {
    _cancelTimer(_errorAutoCloseTimer);
    _errorAutoCloseTimer = Timer(
        const Duration(seconds: CallConstants.connectionTimeoutSeconds + 10),
        _handleMissedCallTimeout
    );
  }

  void _handleMissedCallTimeout() {
    if (mounted && !_isAcceptedByMe && !_isCallActive && !_hasError) {
      _logCallEvent('missed_call_timeout');
      setState(() {
        _hasError = true;
        _errorMessage = 'Panggilan tidak diangkat';
        _isCallActive = false;
        _isConnecting = false;
      });
      _scheduleAutoClose();
    }
  }

  void _startTimer() {
    _cancelTimer(_callTimer);
    _seconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _seconds++);
      } else {
        timer.cancel();
      }
    });
  }

  void _scheduleAutoClose() {
    _cancelTimer(_errorAutoCloseTimer);
    _errorAutoCloseTimer = Timer(
        const Duration(seconds: CallConstants.errorAutoCloseSeconds),
            () {
          if (mounted && _hasError) {
            _endCall(isTimeout: true);
          }
        }
    );
  }

  // ========== CALL CONTROL ==========
  Future<void> _startOutgoingCall() async {
    if (_isInitializing || _isCallActive || _isEndingCall || _hasError) {
      _logCallEvent('call_start_skipped', {
        'initializing': _isInitializing,
        'callActive': _isCallActive,
        'ending': _isEndingCall,
        'hasError': _hasError
      });
      return;
    }

    setState(() {
      _isInitializing = true;
      _isConnecting = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      await _callManager.makeOffer(
        widget.peerPubkey,
        widget.relay,
        _onCallConnected,
      );
    } catch (e) {
      if (mounted && !_hasError) {
        _handleError('Gagal memulai panggilan: ${e.toString()}');
      }
    } finally {
      if (mounted && _isInitializing) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _acceptIncomingCall() async {
    if (_isAcceptedByMe || _isInitializing || _isCallActive || _isEndingCall) {
      return;
    }

    _cancelTimer(_errorAutoCloseTimer);

    setState(() {
      _isInitializing = true;
      _isAcceptedByMe = true;
      _isConnecting = true;
      _hasError = false;
    });

    try {
      if (widget.remoteSdp == null || widget.remoteSdp!.isEmpty) {
        throw Exception('SDP remote tidak valid');
      }

      await _callManager.handleOffer(
        widget.remoteSdp!,
        widget.peerPubkey,
        widget.relay,
        _onCallConnected,
      );
    } catch (e) {
      if (mounted && !_hasError) {
        _handleError('Gagal menerima panggilan');
      }
    } finally {
      if (mounted && _isInitializing) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _endCall({bool isTimeout = false}) {
    if (_isEndingCall || !mounted) return;

    _isEndingCall = true;
    _logCallEvent('call_ending_started', {'isTimeout': isTimeout});

    if (_isHandlingHangup) {
      _isHandlingHangup = false;
    }

    try {
      if (!isTimeout && widget.relay != null) {
        widget.relay.sendCallSignal(
          widget.peerPubkey,
          {'type': CallConstants.signalHangup},
        );
      }

      _cancelAllTimers();
      _callManager.stopCall(sendHangupSignal: false);

      if (mounted) {
        setState(() {
          _isCallActive = false;
          _isConnecting = false;
          _hasError = isTimeout;
          if (isTimeout) {
            _errorMessage = 'Panggilan berakhir';
          }
        });
      }
    } catch (e) {
      _logCallEvent('call_ending_error', {'error': e.toString()});
    } finally {
      _isEndingCall = false;
    }
  }

  // ========== EVENT HANDLERS ==========
  void _onRemoteHangup() {
    if (!mounted || _isHandlingHangup || _isEndingCall || _hasError) return;

    _isHandlingHangup = true;
    _logCallEvent('remote_hangup_received');

    // Langsung end call (tanpa pesan error)
    _endCall(isTimeout: false);
  }

  void _onCallConnected() {
    if (!mounted || _isCallActive) return;

    setState(() {
      _isCallActive = true;
      _isConnecting = false;
      _hasError = false;
      _errorMessage = null;
      _startTimer();
    });
  }

  void _onCallError(String error) {
    if (!mounted || _hasError || _isEndingCall) return;

    setState(() {
      _hasError = true;
      _errorMessage = error;
      _isConnecting = false;
      _isCallActive = false;
    });

    _scheduleAutoClose();
  }

  void _onCallEnded() {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  void _onCallStateChanged(CallState state) {
    if (!mounted) return;

    _logCallEvent('call_state_changed_ui', {
      'from': _callManager.callState.toString(),
      'to': state.toString(),
      'currentUI': {
        'isCallActive': _isCallActive,
        'isConnecting': _isConnecting,
        'hasError': _hasError
      }
    });

    if (_shouldUpdateUI(state)) {
      setState(() {
        switch (state) {
          case CallState.active:
            _isCallActive = true;
            _isConnecting = false;
            _hasError = false;
            break;

          case CallState.connecting:
          case CallState.reconnecting:
          case CallState.initializing:
          case CallState.ringing:
            _isCallActive = false;
            _isConnecting = true;
            _hasError = false;
            break;

          case CallState.error:
            _isCallActive = false;
            _isConnecting = false;
            _hasError = true;
            _errorMessage ??= 'Kesalahan koneksi';
            break;

          case CallState.ending:
          case CallState.idle:
            _isCallActive = false;
            _isConnecting = false;
            break;
        }
      });
    }
  }

  bool _shouldUpdateUI(CallState state) {
    switch (state) {
      case CallState.active:
        return !_isCallActive || _isConnecting || _hasError;
      case CallState.connecting:
      case CallState.reconnecting:
      case CallState.initializing:
      case CallState.ringing:
        return _isCallActive || !_isConnecting || _hasError;
      case CallState.error:
        return !_hasError;
      case CallState.ending:
      case CallState.idle:
        return _isCallActive || _isConnecting;
    }
  }

  void _handleError(String error) {
    if (!mounted || _hasError || _isEndingCall) return;

    _logCallEvent('ui_error_handled', {'error': error});

    setState(() {
      _hasError = true;
      _errorMessage = error;
      _isConnecting = false;
      _isCallActive = false;
    });

    _scheduleAutoClose();
  }

  // ========== UTILITIES ==========
  void _logCallEvent(String event, [Map<String, dynamic>? data]) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    debugPrint('📞 [$timeStr] CallScreen: $event ${data != null ? '- $data' : ''}');

    if (!kIsWeb) {
      try {
        CallManager.instance.callLog.add(CallEvent(event, data: data));
      } catch (e) {
        // Fallback
      }
    }
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  void _cancelTimer(Timer? timer) {
    timer?.cancel();
  }

  void _cancelAllTimers() {
    _cancelTimer(_errorAutoCloseTimer);
    _errorAutoCloseTimer = null;
    _cancelTimer(_callTimer);
    _callTimer = null;
  }

  void _cleanupResources() {
    _cancelAllTimers();
    _proximitySubscription?.cancel();
    _proximitySubscription = null;

    _isInitializing = false;
    _isHandlingHangup = false;
    _isEndingCall = false;

    // Perbaikan: Kembalikan System UI dengan cara yang lebih lembut
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge, // Pastikan kembali ke standar aplikasi
      );
      // Beri sedikit delay sebelum setOverlayStyle agar tidak 'kaget'
      Future.delayed(const Duration(milliseconds: 300), () {
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ));
      });
    }

    _removeAllCallbacks();
    _restoreRelayCallback();

    widget.onClose?.call();
  }

  void _removeAllCallbacks() {
    for (final id in _callbackIds) {
      try {
        _callManager.removeConnectionCallback(id);
        _callManager.removeErrorCallback(id);
        _callManager.removeCallEndedCallback(id);
        _callManager.removeStateChangeCallback(id);
      } catch (e) {
        debugPrint('Error removing callback: $e');
      }
    }
  }

  void _restoreRelayCallback() {
    try {
      widget.relay.onSignalReceived = _originalRelayCallback;
    } catch (e) {
      debugPrint('Error restoring relay callback: $e');
    }
  }

// ========== UI BUILDING ==========
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: !(_isCallActive || _isConnecting),
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        if (_isCallActive || _isConnecting) {
          final shouldEnd = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('End Call?'),
              content: const Text('Are you sure you want to end the call?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('End', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );

          if (shouldEnd == true) {
            _endCall();
          }
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B0E14) : Colors.white,
        body: Stack(
          children: [
            // 1. Tampilan Utama (Hanya muncul/interaktif jika HP tidak di telinga)
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  _buildHeaderSection(isDark),
                  const Spacer(),
                  if (_hasError) _buildErrorDisplay(isDark),
                  if (_callManager.remoteRenderer != null)
                    SizedBox(
                      width: 1,
                      height: 1,
                      child: rtc.RTCVideoView(_callManager.remoteRenderer!),
                    ),
                  _buildControlSection(isDark),
                ],
              ),
            ),

            // 2. Proximity Black Overlay (Layar mati total ala WhatsApp/AMOLED)
            if (_isNearProximity && !kIsWeb)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black, // Layar menjadi hitam pekat
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(bool isDark) {
    final statusText = _getStatusText();
    final stateText = _getStateText();

    return Center(
      child: Column(
        children: [
          // Indikator lama sudah dihapus sesuai permintaan
          CircleAvatar(
            radius: 50,
            backgroundColor: widget.peerColor.withAlpha(25),
            child: Icon(
              Icons.person,
              size: 55,
              color: widget.peerColor,
            ),
          ),
          const SizedBox(height: 25),
          Text(
            widget.peerName,
            style: TextStyle(
              fontSize: 24,
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Text(
            statusText,
            style: TextStyle(
              color: _hasError
                  ? Colors.redAccent
                  : (_isCallActive
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? Colors.white38 : Colors.black38)),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (stateText.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              stateText,
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Fungsi _buildProximityIndicator lama telah dihapus

  String _getStatusText() {
    if (_hasError) return _errorMessage ?? "Error";

    final isIncoming = widget.isIncoming;

    switch (_callManager.callState) {
      case CallState.initializing:
        return isIncoming ? "Incoming Call" : "Preparing...";
      case CallState.ringing:
      case CallState.idle:
        return isIncoming ? "Incoming Call" : "Calling...";
      case CallState.connecting:
        return "Connecting...";
      case CallState.reconnecting:
        return "Reconnecting...";
      case CallState.active:
        return _formatDuration(_seconds);
      case CallState.ending:
        return "Ending...";
      case CallState.error:
        return "Error";
    }
  }

  String _getStateText() {
    switch (_callManager.callState) {
      case CallState.initializing:
        return "";
      case CallState.reconnecting:
        return "";
      case CallState.error:
        return !_hasError ? "System Error" : "";
      default:
        return "";
    }
  }

  Widget _buildErrorDisplay(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withAlpha(76)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage ?? 'Terjadi kesalahan',
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlSection(bool isDark) {
    final capsuleWidth = _calculateCapsuleWidth();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutBack,
        width: capsuleWidth,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 1.2,
          ),
          color: isDark ? Colors.white.withAlpha(5) : Colors.black.withAlpha(5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isCallActive || _isAcceptedByMe) ...[
              Positioned(
                left: 6,
                child: _unifiedControlBtn(
                  icon: _callManager.isMuted ? Icons.mic_off : Icons.mic,
                  isActive: _callManager.isMuted,
                  onTap: _toggleMute,
                  isDark: isDark,
                ),
              ),
              Positioned(
                left: 88,
                child: _unifiedControlBtn(
                  icon: _callManager.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                  isActive: _callManager.isSpeakerOn,
                  onTap: _toggleSpeaker,
                  isDark: isDark,
                ),
              ),
            ],
            if (widget.isIncoming && !_isAcceptedByMe && !_hasError)
              Positioned(
                left: 6,
                child: _unifiedControlBtn(
                  icon: Icons.call,
                  color: Colors.green,
                  onTap: _acceptIncomingCall,
                  isDark: isDark,
                ),
              ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
              alignment: _getHangupButtonAlignment(),
              child: _unifiedControlBtn(
                icon: Icons.call_end,
                isHangup: true,
                onTap: _endCall,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateCapsuleWidth() {
    if (widget.isIncoming && !_isAcceptedByMe) return 235;
    if (_isCallActive || _isAcceptedByMe) return 235;
    return 72;
  }

  Alignment _getHangupButtonAlignment() {
    if (widget.isIncoming && !_isAcceptedByMe) return const Alignment(0.94, 0);
    if (_isCallActive || _isAcceptedByMe) return const Alignment(0.95, 0);
    return Alignment.center;
  }

  void _toggleMute() {
    _callManager.toggleMute();
    if (mounted) setState(() {});
  }

  void _toggleSpeaker() {
    _callManager.toggleSpeaker();
    if (mounted) setState(() {});
  }

  Widget _unifiedControlBtn({
    required IconData icon,
    bool isActive = false,
    bool isHangup = false,
    Color? color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? (isHangup
              ? Colors.redAccent.withAlpha(229)
              : (isActive
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(13)))),
          boxShadow: isHangup ? [
            const BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 2),
            )
          ] : null,
        ),
        child: Icon(
          icon,
          color: (isActive || isHangup || color != null)
              ? (isDark && !isHangup && color == null ? Colors.black : Colors.white)
              : (isDark ? Colors.white : Colors.black),
          size: 26,
        ),
      ),
    );
  }
}

// ==================== NAVIGATION HELPER ====================
class CallScreenNavigator {
  static Future<void> showCallScreen({
    required BuildContext context,
    required String peerName,
    required String peerPubkey,
    required bool isIncoming,
    required dynamic relay,
    required Color peerColor,
    String? remoteSdp,
    VoidCallback? onCallEnded,
  }) async {
    if (ModalRoute.of(context)?.settings.name == '/call') {
      debugPrint('Call screen already active');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/call'),
        builder: (context) => CallScreen(
          peerName: peerName,
          peerPubkey: peerPubkey,
          isIncoming: isIncoming,
          relay: relay,
          peerColor: peerColor,
          remoteSdp: remoteSdp,
          onClose: onCallEnded,
        ),
      ),
    );
  }
}