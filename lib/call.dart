// call.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'call_manager.dart';
import 'core/theme/chatme_colors.dart';
import 'core/utils/duration_utils.dart';
import 'widgets/call_control_bar.dart';
import 'widgets/user_avatar.dart';
import 'notification_handler.dart';

class CallScreen extends StatefulWidget {
  final String peerName;
  final String peerPubkey;
  final bool isIncoming;
  final dynamic relay;
  final Color peerColor;
  final String? remoteSdp;
  final bool autoAccept;
  final VoidCallback onClose;

  const CallScreen({
    super.key,
    required this.peerName,
    required this.peerPubkey,
    required this.isIncoming,
    required this.relay,
    required this.peerColor,
    this.remoteSdp,
    this.autoAccept = false,
    required this.onClose,
  })  : assert(peerPubkey != '',
  'CallScreen: peerPubkey must not be empty. '
      'Use CallScreenNavigator.showCallScreen or '
      'CallManager.startCallFlow.');

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallManager _callManager = CallManager.instance;

  bool _isAcceptedByMe = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _isNearProximity = false;

  Timer? _errorAutoCloseTimer;
  StreamSubscription<int>? _proximitySubscription;

  final List<String> _callbackIds = [];
  bool _isInitializing = false;
  bool _isEndingCall = false;
  bool _closing = false;

  /// Captured while the route is still alive so [dispose] can restore the
  /// system UI with the right icon brightness without looking up inherited
  /// widgets after deactivation.
  Brightness _themeBrightness = Brightness.dark;

  bool _systemUiChanged = false;

  @override
  void initState() {
    super.initState();
    CallScreenNavigator.openScreens++;
    _setupCallbacks();

    _logCallEvent('call_screen_init', {
      'isIncoming': widget.isIncoming,
      'peerName': widget.peerName,
      'hasRemoteSdp': widget.remoteSdp != null && widget.remoteSdp!.isNotEmpty
    });

    _initProximitySensor();

    if (_callManager.callState != CallState.idle) {
      debugPrint("Screen reopened: Skipping new call initialization.");
      // A brand-new outgoing call can be requested while the previous call is
      // still in its `ending` grace window. Wait for that teardown to finish
      // instead of leaving the user on a screen that never dials.
      if (!widget.isIncoming && _callManager.callState == CallState.ending) {
        _startOutgoingWhenIdle();
      }
    } else {
      if (!widget.isIncoming) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startAfterTransition(_startOutgoingCall);
        });
      } else {
        _callManager.currentCallDirection = CallType.incoming;
        _callManager.setSessionInfo(widget.peerName, widget.peerPubkey, widget.peerColor);
        _startMissedCallTimeout();
        _callManager.incomingScreenAccept = _acceptIncomingCall;
        _callManager.incomingScreenDecline = _endCall;
        if (widget.autoAccept) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _acceptIncomingCall();
          });
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeBrightness = Theme.of(context).brightness;
  }

  @override
  void dispose() {
    _cancelAllTimers();
    _cleanupResources();
    CallScreenNavigator.openScreens--;
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
    if (kIsWeb) return;
    try {
      _proximitySubscription = ProximitySensor.events.listen((int event) {
        final bool isNear = event == 1;
        // The sensor emits on every report, including repeats of the same
        // value. Skipping those avoids a full-screen rebuild and a redundant
        // SystemChrome call while a call is in progress.
        if (isNear == _isNearProximity) return;
        _isNearProximity = isNear;
        _updateSystemUIMode();
        if (mounted) setState(() {});
      });
    } catch (e) {
      debugPrint('Proximity sensor not available: $e');
    }
  }

  void _updateSystemUIMode() {
    if (!kIsWeb) {
      _systemUiChanged = true;
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
        _errorMessage = 'Call not answered';
      });
      _callManager.stopCall(sendHangupSignal: false);
      _scheduleAutoClose();
    }
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

  void _startAfterTransition(VoidCallback action) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      action();
      return;
    }
    bool started = false;
    void run() {
      if (started || !mounted) return;
      started = true;
      action();
    }

    late AnimationStatusListener listener;
    listener = (status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(listener);
        run();
      }
    };
    animation.addStatusListener(listener);
    Future.delayed(const Duration(milliseconds: 700), () {
      animation.removeStatusListener(listener);
      run();
    });
  }

  /// Waits for a previous call to finish its `ending` teardown, then starts
  /// this outgoing call. Without this, tapping call on a contact right after
  /// hanging up could open a call screen that never dials.
  Future<void> _startOutgoingWhenIdle() async {
    for (int i = 0; i < 50; i++) {
      if (!mounted || _callManager.callState != CallState.ending) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || _callManager.callState != CallState.idle) return;
    _startAfterTransition(_startOutgoingCall);
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

    // Re-assert the session after any previous call finished its teardown:
    // CallManager clears activePeer* when it reaches `idle`.
    _callManager.currentCallDirection = CallType.outgoing;
    _callManager.setSessionInfo(
      widget.peerName,
      widget.peerPubkey,
      widget.peerColor,
    );

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
        _handleError('Failed to start call: ${e.toString()}');
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
    NotificationHandler.cancelIncomingCall();

    setState(() {
      _isInitializing = true;
      _isAcceptedByMe = true;
      _hasError = false;
    });

    try {
      // Capture the SDP if it already exists
      String? sdp = widget.remoteSdp ?? _callManager.pendingIncoming?.remoteSdp;

      // If SDP is not ready (cold start), wait for the relay to populate it
      int retries = 0;
      while ((sdp == null || sdp.isEmpty) && retries < 150 && mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
        sdp = _callManager.pendingIncoming?.remoteSdp;
        retries++;
      }

      // Now that we have the SDP (or timed out), clear the pending call
      _callManager.pendingIncoming = null;

      if (sdp == null || sdp.isEmpty) {
        throw Exception('Remote SDP not received in time');
      }

      await _callManager.handleOffer(
        sdp,
        widget.peerPubkey,
        widget.relay,
        _onCallConnected,
      );

      _logCallEvent('call_accepted_manually');
    } catch (e) {
      if (mounted && !_hasError) {
        _handleError('Failed to accept call');
      }
    } finally {
      if (mounted && _isInitializing) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _endCall({bool isTimeout = false}) {
    if (_isEndingCall || !mounted) return;

    // Stays true until the screen is disposed. Resetting it in a finally
    // block allowed a second hangup tap to start a parallel teardown.
    _isEndingCall = true;
    _logCallEvent('call_ending_started', {'isTimeout': isTimeout});

    // Declined or timed out from the screen: stop the ringing notification too.
    if (widget.isIncoming) {
      NotificationHandler.cancelIncomingCall();
      _callManager.pendingIncoming = null;
    }

    try {
      if (!isTimeout && widget.relay != null) {
        widget.relay.sendCallSignal(
          widget.peerPubkey,
          {'type': CallConstants.signalHangup},
        );
      }

      _cancelAllTimers();

      // The `byUser` flag tells CallManager that the user explicitly
      // tapped end. This changes the resulting label for incoming calls:
      // if the user did anything (accept or reject), the log shows
      // "Incoming Call"; only unanswered, un-actioned calls become
      // "Missed Call".
      //
      // Timeout-driven closes (isTimeout: true) are NOT user actions
      // and must remain "missed".
      //
      // stopCall emits `ending` synchronously; _onCallStateChanged starts the
      // pop animation there, while media teardown/Hive writes wait inside
      // stopCall's ~300 ms window. The screen therefore never blocks on the
      // teardown before dismissing.
      _callManager.stopCall(
        sendHangupSignal: false,
        byUser: !isTimeout,
      );

      if (isTimeout && mounted) setState(() => _hasError = true);

      // Fallback for the case where another stopCall is already in flight and
      // did not emit a state change for this screen.
      if (!isTimeout) _closeScreen();
    } catch (e) {
      _logCallEvent('call_ending_error', {'error': e.toString()});
    }
  }

  void _onCallConnected() {
    if (!mounted) return;

    setState(() {
      _hasError = false;
      _errorMessage = null;
    });
  }

  void _onCallError(String? error) {
    if (!mounted || _hasError || _isEndingCall) return;

    setState(() {
      _hasError = true;
      _errorMessage = error ?? 'An error occurred';
    });

    _scheduleAutoClose();
  }

  Future<void> _closeScreen() async {
    if (_closing) return;
    _closing = true;
    if (ModalRoute.of(context)?.isFirst != true) {
      Navigator.of(context).pop();
      return;
    }
    for (int i = 0; i < 50 && _callManager.callState != CallState.idle; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 700));
    SystemNavigator.pop();
  }

  void _minimize() {
    if (ModalRoute.of(context)?.isFirst == true) {
      if (!_isAcceptedByMe) {
        SystemNavigator.pop();
        return;
      }
      CallManager.instance.launchCallerPubkey = null;
      CallManager.instance.launchAutoAccept = false;
      Navigator.of(context).pushReplacementNamed('/');
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onCallEnded() {
    if (mounted) {
      _logCallEvent('Call ended callback: Closing screen');
      CallScreenNavigator._endedOnScreen = true;
      if (ModalRoute.of(context)?.isCurrent == true) {
        _closeScreen();
      }
    }
  }

  void _onCallStateChanged(CallState state) {
    if (!mounted) return;

    _logCallEvent('ui_state_sync', {'state': state.toString()});

    final bool hasError;
    switch (state) {
      case CallState.active:
      case CallState.connecting:
      case CallState.reconnecting:
      case CallState.ringing:
      case CallState.initializing:
        hasError = false;
        break;
      case CallState.error:
        hasError = true;
        break;
      case CallState.idle:
      case CallState.ending:
        hasError = false;
        break;
    }

    // Navigation is intentionally kept outside setState: calling pop() from
    // inside a builder-style callback while the element tree is locked is
    // fragile and made the close order hard to reason about.
    setState(() {
      _hasError = hasError;
    });

    if (state == CallState.ending || state == CallState.idle) {
      _logCallEvent('closing_screen_due_to_terminal_state');
      CallScreenNavigator._endedOnScreen = true;
      if (ModalRoute.of(context)?.isCurrent == true) {
        // Pop now (on `ending`) so the route animation overlaps the teardown
        // that CallManager performs during its ~300 ms grace window.
        _closeScreen();
      }
    }
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
  }

  void _cleanupResources() {
    _cancelAllTimers();
    _proximitySubscription?.cancel();
    _proximitySubscription = null;

    if (widget.isIncoming) {
      _callManager.incomingScreenAccept = null;
      _callManager.incomingScreenDecline = null;
    }

    _isInitializing = false;
    _isEndingCall = false;

    if (!kIsWeb) {
      if (_systemUiChanged) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
      }

      final Brightness iconBrightness = _themeBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      Future.delayed(const Duration(milliseconds: 300), () {
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: iconBrightness,
          systemNavigationBarIconBrightness: iconBrightness,
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

    final isRoot = ModalRoute.of(context)?.isFirst == true;
    return PopScope(
      canPop: !isRoot,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          _logCallEvent('navigating_to_background');
        } else {
          _minimize();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            SafeArea(
              // The header area scrolls when the screen is short, while the
              // control bar stays pinned at the bottom. This replaces the
              // IntrinsicHeight + Spacer combo, which forced an expensive
              // double layout pass on every rebuild.
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 10, top: 10),
                              child: IconButton(
                                icon: const Icon(Icons.keyboard_arrow_down, size: 35),
                                color: ChatmeColors.textSecondary,
                                onPressed: _minimize,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildHeaderSection(isDark),
                          if (_hasError) _buildErrorDisplay(isDark),
                        ],
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: _buildControlSection(isDark),
                  ),
                ],
              ),
            ),

            if (_isNearProximity && !kIsWeb)
              Positioned.fill(
                child: Container(
                  color: ChatmeColors.backgroundPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSection(bool isDark) {
    final stateText = _getStateText();

    return Center(
      child: Column(
        children: [
          // End-to-end encryption label (plain, no background)
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 13,
                color: ChatmeColors.textMuted,
              ),
              SizedBox(width: 6),
              Text(
                'End-to-end encrypted',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ChatmeColors.textMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // profile picture
          UserAvatar(
            pubkey: widget.peerPubkey,
            name: widget.peerName,
            radius: 50,
            relayManager: widget.relay,
          ),
          const SizedBox(height: 25),
          Text(
            widget.peerName,
            style: const TextStyle(
              fontSize: 24,
              color: ChatmeColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          _buildStatusTextWidget(isDark),
          if (stateText.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              stateText,
              style: const TextStyle(
                color: ChatmeColors.statusWarning,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusTextWidget(bool isDark) {
    if (_hasError) {
      return Text(
        _errorMessage ?? "Error",
        style: const TextStyle(
          color: ChatmeColors.statusDanger,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (_callManager.callState == CallState.active) {
      return const _CallDurationText(
        style: TextStyle(
          color: ChatmeColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final isIncoming = widget.isIncoming;
    String statusStr;
    switch (_callManager.callState) {
      case CallState.connecting:
        statusStr = "Connecting";
        break;
      case CallState.reconnecting:
        statusStr = "Reconnecting";
        break;
      case CallState.ringing:
        statusStr = isIncoming ? "Incoming Call" : "Ringing";
        break;
      case CallState.initializing:
      case CallState.idle:
        statusStr = isIncoming ? "Incoming Call" : "Calling";
        break;
      default:
        statusStr = isIncoming ? "Incoming Call" : "Calling";
        break;
    }

    return Text(
      statusStr,
      style: const TextStyle(
        color: ChatmeColors.textSubtle,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
    );
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
        color: ChatmeColors.statusDanger.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChatmeColors.statusDanger.withAlpha(76)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: ChatmeColors.statusDanger, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage ?? 'An error occurred',
              style: const TextStyle(
                color: ChatmeColors.statusDanger,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlSection(bool isDark) {
    final incomingPending = widget.isIncoming && !_isAcceptedByMe;

    return Container(
      padding: const EdgeInsets.only(top: 20, bottom: 32),
      child: CallControlBar(
        isDark: isDark,
        expanded: incomingPending || _showCallControls,
        showControls: _showCallControls,
        showAccept: incomingPending && !_hasError,
        isMuted: _callManager.isMuted,
        isSpeakerOn: _callManager.isSpeakerOn,
        onMute: _toggleMute,
        onSpeaker: _toggleSpeaker,
        onAccept: _acceptIncomingCall,
        onHangup: _endCall,
      ),
    );
  }

  bool get _showCallControls =>
      _callManager.callState == CallState.active ||
          _callManager.callState == CallState.reconnecting ||
          _isAcceptedByMe;

  void _toggleMute() {
    _callManager.toggleMute();
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    await _callManager.toggleSpeaker();
    if (mounted) setState(() {});
  }
}

/// Dedicated widget that updates duration text locally every second
/// without rebuilding the entire CallScreen tree.
class _CallDurationText extends StatefulWidget {
  final TextStyle style;

  const _CallDurationText({required this.style});

  @override
  State<_CallDurationText> createState() => _CallDurationTextState();
}

class _CallDurationTextState extends State<_CallDurationText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = CallManager.instance.currentDuration;
    return Text(
      DurationUtils.formatClock(duration),
      style: widget.style,
    );
  }
}

// ==================== NAVIGATION HELPER ====================
class CallScreenNavigator {
  /// Guards against stacking multiple CallScreens on top of each other.
  ///
  /// A static flag is used instead of inspecting the top route name
  /// because `ModalRoute.of(context)` always returns null when the
  /// context comes from a global navigator key — the context belongs to
  /// the Navigator itself, not to any specific route. The previous
  /// implementation silently did nothing, allowing two offers to stack
  /// two CallScreens.
  static bool _isShowing = false;
  static int openScreens = 0;

  /// Set by the call screen when it closes because the call ended (not when the
  /// user minimizes it).
  static bool _endedOnScreen = false;

  static Future<void> showCallScreen({
    required BuildContext context,
    required String peerName,
    required String peerPubkey,
    required bool isIncoming,
    required dynamic relay,
    required Color peerColor,
    String? remoteSdp,
    bool autoAccept = false,
    bool closeAppWhenCallEnds = false,
    VoidCallback? onCallEnded,
  }) async {
    if (_isShowing) {
      debugPrint('[CallScreenNavigator] Call screen already active, ignoring');
      return;
    }

    _isShowing = true;
    _endedOnScreen = false;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          // No RouteSettings(name: ...) here — the platform will fall back
          // to a generic name, so the web URL hash will not become
          // "#/call" and cannot be restored as a ghost call.
          builder: (context) => CallScreen(
            peerName: peerName,
            peerPubkey: peerPubkey,
            isIncoming: isIncoming,
            relay: relay,
            peerColor: peerColor,
            remoteSdp: remoteSdp,
            autoAccept: autoAccept,
            onClose: onCallEnded ?? () {},
          ),
        ),
      );
    } finally {
      _isShowing = false;
      // The call ended while the screen was open and the app was launched by
      // the ringing notification: leave nothing of ChatMe on screen.
      if (closeAppWhenCallEnds && _endedOnScreen) {
        _endedOnScreen = false;

        // Let stopCall finish first: it saves the call records after closing
        // the connection, and the app must not be closed before that.
        for (int i = 0;
        i < 50 && CallManager.instance.callState != CallState.idle;
        i++) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await Future.delayed(const Duration(milliseconds: 700));

        SystemNavigator.pop();
      }
    }
  }
}