// qr_code_page.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/utils/key_utils.dart';
import '../../relay_manager.dart';
import '../../services/contact_qr.dart';
import '../../widgets/user_avatar.dart';
import '../contacts/add_contact.dart';
import 'qr_scan_page.dart';

/// Full screen QR code of a profile, with a button to scan someone else's code.
class QrCodePage extends StatelessWidget {
  final String pubkey;
  final String name;
  final RelayManager relayManager;

  const QrCodePage({
    super.key,
    required this.pubkey,
    required this.name,
    required this.relayManager,
  });

  Future<void> _scan(BuildContext context) async {
    final navigator = Navigator.of(context);
    final scanned = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (scanned == null) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => AddContactPage(initialPubkey: scanned)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final title = name.isNotEmpty ? name : KeyUtils.formatDisplayName(pubkey);
    final payload = contactQrPayload(pubkey, relays: RelayManager.dmInboxRelays);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      children: [
                        UserAvatar(
                          pubkey: pubkey,
                          name: title,
                          radius: 56,
                          relayManager: relayManager,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          KeyUtils.formatDisplayName(pubkey),
                          style: TextStyle(fontSize: 13, color: textSecondary),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: QrImageView(
                              data: payload,
                              version: QrVersions.auto,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                              backgroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Colors.black,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!kIsWeb)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: GestureDetector(
                  onTap: () => _scan(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(isDark ? 50 : 35),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Text(
                      'Scan QR',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
