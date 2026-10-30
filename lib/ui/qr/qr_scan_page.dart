// qr_scan_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/app_settings.dart';
import '../../services/contact_qr.dart';

/// Camera view that closes with the public key (hex) of the first contact code it reads.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  Timer? _hintTimer;
  String? _hint;
  bool _done = false;

  @override
  void dispose() {
    _hintTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _showHint(String text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final pubkey = contactFromScan(raw);
      if (pubkey == null) {
        _showHint('This is not a contact code');
        continue;
      }
      if (pubkey == AppSettings.instance.myPubkey) {
        _showHint('This is your own code');
        continue;
      }

      _done = true;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, pubkey);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(controller: _controller, onDetect: _onDetect),
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white70, width: 3),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10, top: 10),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: Text(
                  _hint ?? 'Point the camera at a contact code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _hint == null ? Colors.white : Colors.redAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
