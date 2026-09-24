// call_overlay.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'call_manager.dart';
import 'call.dart';

class CallFloatingBar extends StatefulWidget {
  final dynamic relay;

  const CallFloatingBar({super.key, required this.relay});

  @override
  State<CallFloatingBar> createState() => _CallFloatingBarState();
}

class _CallFloatingBarState extends State<CallFloatingBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _getStatusText(CallManager manager) {
    if (manager.callState == CallState.active) {
      return _formatDuration(manager.currentDuration);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final manager = CallManager.instance;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            settings: const RouteSettings(name: '/call'),
            builder: (context) => CallScreen(
              peerName: manager.activePeerName ?? 'Unknown',
              peerPubkey: manager.activePeerPubkey ?? '',
              isIncoming: false,
              relay: widget.relay,
              peerColor: manager.activePeerColor ?? Colors.blue,
              onClose: () {},
            ),
          ),
        );
      },
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(10),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              // Mute Button
              GestureDetector(
                onTap: () {
                  manager.toggleMute();
                  setState(() {});
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withAlpha(25)
                        : Colors.black.withAlpha(20),
                  ),
                  child: Icon(
                    manager.isMuted ? Icons.mic_off : Icons.mic,
                    color: isDark ? Colors.white : Colors.black,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Name + Status/Duration
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      manager.activePeerName ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _getStatusText(manager),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // End Call Button
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
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
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
