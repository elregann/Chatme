// call.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:proximity_sensor/proximity_sensor.dart';
import 'call_manager.dart';

class CallScreen extends StatefulWidget {
  final String peerName;
  final String peerPubkey;
  final bool isIncoming;
  final dynamic relay;
  final Color peerColor;
  final String? remoteSdp;
  final VoidCallback onClose;

  const CallScreen({
    super.key,
    required this.peerName,
    required this.peerPubkey,
    required this.isIncoming,
    required this.relay,
    required this.peerColor,
    this.remoteSdp,
    required this.onClose,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallManager _callManager = CallManager.instance;

  bool _isAcceptedByMe = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isNearProximity = false;

  Timer? _callTimer;
  Timer? _errorAutoCloseTimer;
  StreamSubscription<int>? _proximitySubscription;

  final List<String> _callbackIds = [];
  bool _isInitializing = false;
  bool _isEndingCall = false;

  @override
  void initState() {
    super.initState();
    _setupCallbacks();

    _logCallEvent('call_screen_init', {
      'isIncoming': widget.isIncoming,
      'peerName': widget.peerName,
      'hasRemoteSdp': widget.remoteSdp != null && widget.remoteSdp!.isNotEmpty
    });

    _initProximitySensor();

    if (_callManager.callState != CallState.idle) {
      if (_callManager.callState == CallState.active) {
        _startTimer();
      }
      debugPrint("Layar dibuka kembali: Melewatkan inisialisasi telfon baru.");
    } else {
      if (!widget.isIncoming) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startOutgoingCall();
        });
      } else {
        _startMissedCallTimeout();
      }
    }
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _cleanupResources();
    super.dispose();
  }

  void _setupCallbacks() {
    _callbackIds.clear();
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
      SystemChrome.setEnabledSystemUIMode(
        _isNearProximity ? SystemUiMode.leanBack : SystemUiMode.edgeToEdge,
      );
    }
  }

  void _startMissedCallTimeout() {
    _cancelTimer(_errorAutoCloseTimer);
    _errorAutoCloseTimer = Timer(
        const Duration(seconds: CallConstants.connectionTimeoutSeconds + 10),
        _handleMissedCallTimeout
    );
  }

  void _handleMissedCallTimeout() {
    if (mounted && !_isAcceptedByMe && _callManager.callState != CallState.active && !_hasError) {
      _logCallEvent('missed_call_timeout');
      setState(() {
        _hasError = true;
        _errorMessage = 'Panggilan tidak diangkat';
      });
      _scheduleAutoClose();
    }
  }

  void _startTimer() {
    _cancelTimer(_callTimer);
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
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

  Future<void> _startOutgoingCall() async {
    if (_callManager.callState == CallState.active ||
        _callManager.callState == CallState.connecting) {
      _logCallEvent('already_in_call_skipping_offer');
      _onCallConnected();
      return;
    }

    if (_isInitializing || _callManager.callState != CallState.idle || _isEndingCall || _hasError) {
      _logCallEvent('call_start_skipped', {
        'initializing': _isInitializing,
        'callState': _callManager.callState.toString(),
        'ending': _isEndingCall,
        'hasError': _hasError
      });
      return;
    }

    setState(() {
      _isInitializing = true;
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
    if (_isAcceptedByMe || _isInitializing || _callManager.callState != CallState.idle || _isEndingCall) {
      return;
    }

    _cancelTimer(_errorAutoCloseTimer);

    setState(() {
      _isInitializing = true;
      _isAcceptedByMe = true;
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

      _logCallEvent('call_accepted_manually');
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
          _hasError = isTimeout;
        });
      }
    } catch (e) {
      _logCallEvent('call_ending_error', {'error': e.toString()});
    } finally {
      _isEndingCall = false;
    }
  }

  void _onCallConnected() {
    if (!mounted) return;

    setState(() {
      _hasError = false;
      _errorMessage = null;
      _startTimer();
    });
  }

  void _onCallError(String? error) {
    if (!mounted || _hasError || _isEndingCall) return;

    setState(() {
      _hasError = true;
      _errorMessage = error ?? 'Terjadi kesalahan';
    });

    _scheduleAutoClose();
  }

  void _onCallEnded() {
    if (mounted) {
      _logCallEvent('Call ended callback: Closing screen');
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    }
  }

  void _onCallStateChanged(CallState state) {
    if (!mounted) return;

    _logCallEvent('ui_state_sync', {'state': state.toString()});

    setState(() {
      switch (state) {
        case CallState.active:
          _hasError = false;
          _startTimer();
          break;
        case CallState.connecting:
        case CallState.reconnecting:
        case CallState.ringing:
        case CallState.initializing:
          _hasError = false;
          break;
        case CallState.error:
          _hasError = true;
          break;
        case CallState.idle:
        case CallState.ending:
          _hasError = false;
          if (mounted) {
            _logCallEvent('closing_screen_due_to_idle_state');
            if (ModalRoute.of(context)?.isCurrent == true) {
              Navigator.of(context).pop();
            }
          }
          break;
      }
    });
  }

  void _handleError(String error) {
    if (!mounted || _hasError || _isEndingCall) return;

    _logCallEvent('ui_error_handled', {'error': error});

    setState(() {
      _hasError = true;
      _errorMessage = error;
    });

    _scheduleAutoClose();
  }

  void _logCallEvent(String event, [Map<String, dynamic>? data]) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    debugPrint('📞 [$timeStr] CallScreen: $event ${data != null ? '- $data' : ''}');
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
    _isEndingCall = false;

    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );

      Future.delayed(const Duration(milliseconds: 300), () {
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ));
      });
    }

    _removeAllCallbacks();
    widget.onClose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          _logCallEvent('navigating_to_background');
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, top: 10),
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 35),
                        color: isDark ? Colors.white70 : Colors.black54,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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

            if (_isNearProximity && !kIsWeb)
              Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.black,
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
                  : (_callManager.callState == CallState.active
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

  String _getStatusText() {
    if (_hasError) return _errorMessage ?? "Error";

    if (_callManager.callState == CallState.active) {
      final totalSecs = _callManager.currentDuration;
      final minutes = (totalSecs ~/ 60).toString().padLeft(2, '0');
      final secs = (totalSecs % 60).toString().padLeft(2, '0');
      return "$minutes:$secs";
    }

    final isIncoming = widget.isIncoming;
    switch (_callManager.callState) {
      case CallState.connecting:   return "Connecting";
      case CallState.ringing:      return isIncoming ? "Incoming Call" : "Ringing";
      case CallState.initializing:
      case CallState.idle:         return isIncoming ? "Incoming Call" : "Calling";
      default:                     return isIncoming ? "Incoming Call" : "Calling";
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
            if (_callManager.callState == CallState.active || _isAcceptedByMe) ...[
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
    if (_callManager.callState == CallState.active || _isAcceptedByMe) return 235;
    return 72;
  }

  Alignment _getHangupButtonAlignment() {
    if (widget.isIncoming && !_isAcceptedByMe) return const Alignment(0.94, 0);
    if (_callManager.callState == CallState.active || _isAcceptedByMe) return const Alignment(0.95, 0);
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
          boxShadow: null,
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
          onClose: onCallEnded ?? () {},
        ),
      ),
    );
  }
}