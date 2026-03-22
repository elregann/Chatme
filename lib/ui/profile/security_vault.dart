// security_vault.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BackupKeysPage extends StatefulWidget {
  final String pubkey;
  final String privkey;
  final String Function() exportKeys;

  const BackupKeysPage({
    super.key,
    required this.pubkey,
    required this.privkey,
    required this.exportKeys,
  });

  @override
  State<BackupKeysPage> createState() => _BackupKeysPageState();
}

class _BackupKeysPageState extends State<BackupKeysPage> {
  bool _privkeyVisible = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final textPrimary = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Security Vault',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: textPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Warning
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withAlpha(40), width: 0.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.red.withAlpha(200), size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Never share your private key. Anyone with it can access your account.',
                      style: TextStyle(fontSize: 13, color: Colors.red.withAlpha(200), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Public Key
            Text(
              'PUBLIC KEY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.pubkey,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: textSecondary,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.pubkey));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Public key copied'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 13, color: textSecondary),
                            const SizedBox(width: 6),
                            Text('Copy', style: TextStyle(fontSize: 13, color: textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Private Key
            Text(
              'PRIVATE KEY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _privkeyVisible
                      ? Text(
                    widget.privkey,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: textSecondary,
                      height: 1.6,
                    ),
                  )
                      : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_off_outlined, size: 14, color: textSecondary),
                        const SizedBox(width: 8),
                        Text('Hidden for security', style: TextStyle(fontSize: 13, color: textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _privkeyVisible = !_privkeyVisible),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor, width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _privkeyVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 13,
                                color: textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _privkeyVisible ? 'Hide' : 'Reveal',
                                style: TextStyle(fontSize: 13, color: textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_privkeyVisible) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: widget.privkey));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Private key copied — keep it safe'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, size: 13, color: textSecondary),
                                const SizedBox(width: 6),
                                Text('Copy', style: TextStyle(fontSize: 13, color: textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Export button
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.exportKeys()));
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All keys exported to clipboard'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.download_rounded, size: 16, color: textPrimary),
                    const SizedBox(width: 8),
                    Text(
                      'Export all keys',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}