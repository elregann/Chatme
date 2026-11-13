// call_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'call_manager.dart';
import 'core/theme/chatme_colors.dart';
import 'core/utils/duration_utils.dart';
import 'call.dart';

class CallFloatingBar extends StatefulWidget {
  final dynamic relay;

  const CallFloatingBar({super.key, required this.relay});

  @override
  State<CallFloatingBar> createState() => _CallFloatingBarState();
}

class _CallFloatingBarState extends State<CallFloatingBar> {
  Timer? _ticker;
  CallState _callState = CallState.idle;

  @override
  void initState() {
    super.initState();
    _callState = CallManager.instance.callState;
    CallManager.instance.callStateNotifier.addListener(_onCallStateChanged);
    _syncTicker();
  }

  void _onCallStateChanged() {
    final state = CallManager.instance.callState;
    if (state == _callState) return;
    _callState = state;
    _syncTicker();
    if (mounted) setState(() {});
  }

  /// Only the active state needs a per-second rebuild (for the duration).
  /// Connecting/ringing states used to rebuild once per second for nothing.
  void _syncTicker() {
    if (_callState == CallState.active) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    CallManager.instance.callStateNotifier.removeListener(_onCallStateChanged);
    _ticker?.cancel();
    super.dispose();
  }

  String _getStatusText(CallManager manager) {
    if (manager.callState == CallState.active) {
      return DurationUtils.formatClock(manager.currentDuration);
    }
    switch (manager.callState) {
      case CallState.connecting:
        return 'Connecting';
      case CallState.ringing:
        return 'Ringing';
      case CallState.initializing:
      case CallState.idle:
        return 'Calling';
      case CallState.reconnecting:
        return 'Reconnecting';
      default:
        return 'Calling';
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = CallManager.instance;

    return GestureDetector(
      onTap: () {
        final String peerPubkey = manager.activePeerPubkey ?? '';
        if (peerPubkey.isEmpty) return;
        CallScreenNavigator.showCallScreen(
          context: context,
          peerName: manager.activePeerName ?? 'Unknown',
          peerPubkey: peerPubkey,
          isIncoming: false,
          relay: widget.relay,
          peerColor: manager.activePeerColor ?? ChatmeColors.accentStrong,
        );
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: ChatmeColors.floatingBarBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ChatmeColors.borderSubtle, width: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  manager.toggleMute();
                  setState(() {});
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: ChatmeColors.callControlSurfaceActive,
                  ),
                  child: Icon(
                    manager.isMuted ? Icons.mic_off : Icons.mic,
                    color: ChatmeColors.callControlIcon,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      manager.activePeerName ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ChatmeColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _getStatusText(manager),
                      style: const TextStyle(
                        fontSize: 11,
                        color: ChatmeColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () async {
                  widget.relay.sendCallSignal(
                    manager.activePeerPubkey ?? '',
                    {'type': 'hangup'},
                  );
                  await manager.stopCall(sendHangupSignal: false);
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: ChatmeColors.callEnd,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: ChatmeColors.textPrimary,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
