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
    // Ticker tiap detik buat update durasi
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
        width: double.infinity,
        // Tambah padding atas buat status bar
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // ── Tombol Mute (sekarang ada lingkaran) ──
              GestureDetector(
                onTap: () {
                  manager.toggleMute();
                  setState(() {});
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withAlpha(25)
                        : Colors.black.withAlpha(20),
                  ),
                  child: Icon(
                    manager.isMuted ? Icons.mic_off : Icons.mic,
                    color: isDark ? Colors.white : Colors.black,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Nama + Durasi ──
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                      _formatDuration(manager.currentDuration),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // ── Tombol End Call ──
              GestureDetector(
                onTap: () async {
                  // Kirim hangup signal dulu, baru stop
                  widget.relay.sendCallSignal(
                    manager.activePeerPubkey ?? '',
                    {'type': 'hangup'},
                  );
                  await manager.stopCall(sendHangupSignal: false);
                  // Overlay hilang otomatis karena callState → idle
                  // dan ValueListenableBuilder di MainScreen akan rebuild
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(229),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 18,
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