// restore_account.dart

import 'package:flutter/material.dart';
import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../core/utils/sync_gate.dart';
import '../../services/app_settings.dart';
import '../../relay_manager.dart';
import '../../widgets/chatme_notice.dart';

class RestoreAccountPage extends StatefulWidget {
  final RelayManager relayManager;

  const RestoreAccountPage({super.key, required this.relayManager});

  @override
  State<RestoreAccountPage> createState() => _RestoreAccountPageState();
}

class _RestoreAccountPageState extends State<RestoreAccountPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = ChatmeColors.backgroundPrimary;
    const cardColor = ChatmeColors.surfaceMenu;
    const borderColor = ChatmeColors.borderSubtle;
    const textSecondary = ChatmeColors.textSecondary;
    const textPrimary = ChatmeColors.textPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Restore Account',
          style: TextStyle(
              fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ChatmeNotice(
              icon: Icons.info_outline_rounded,
              message:
                  'This will replace your current account. Make sure you have backed up your keys first.',
              iconColor: ChatmeColors.statusWarning,
            ),
            const SizedBox(height: 28),
            const Text(
              'NSEC, PRIVATE KEY OR RECOVERY PHRASE',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 5,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                decoration: const InputDecoration(
                  hintText:
                      'Paste your nsec, hex private key or 12-word phrase...',
                  hintStyle: TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                      fontFamily: 'sans-serif'),
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _isLoading
                  ? null
                  : () async {
                      final input = _controller.text.trim();
                      if (input.isEmpty) return;

                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      setState(() => _isLoading = true);
                      try {
                        await AppSettings.instance.importAccount(input);
                        // Open the initial-sync gate BEFORE connecting: the
                        // relays will replay this account's whole backlog, and
                        // that history must arrive silently (no notification
                        // spam, no unread badges) until every relay sends EOSE.
                        SyncGate.start('account restore');
                        widget.relayManager.disconnect();
                        widget.relayManager.connect();
                        if (mounted) navigator.pop();
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: ChatmeColors.statusDanger,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: ChatmeButtonStyles.primaryDecoration(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ChatmeButtonStyles.primaryForeground,
                        ),
                      )
                    else
                      const Icon(
                        Icons.settings_backup_restore_rounded,
                        size: 16,
                        color: ChatmeButtonStyles.primaryForeground,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      _isLoading ? 'Restoring...' : 'Restore account',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ChatmeButtonStyles.primaryForeground,
                      ),
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
