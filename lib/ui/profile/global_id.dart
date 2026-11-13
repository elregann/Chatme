// global_id.dart

import '../../widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../services/app_settings.dart';
import '../../services/directory_service.dart';
import '../../relay_manager.dart';
import '../../widgets/chatme_notice.dart';

class GlobalIdPage extends StatefulWidget {
  final RelayManager? relayManager;
  const GlobalIdPage({super.key, this.relayManager});

  @override
  State<GlobalIdPage> createState() => _GlobalIdPageState();
}

class _GlobalIdPageState extends State<GlobalIdPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final current = AppSettings.instance.myNip05;
    if (current.isNotEmpty) {
      _controller.text = current.split('@')[0];
    }
  }

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

    final currentHandle = AppSettings.instance.myNip05;
    final hasHandle = currentHandle.isNotEmpty;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Global ID',
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
                  'Claim a unique username to make it easier for others to find you.',
            ),

            const SizedBox(height: 28),

            // Current handle display
            if (hasHandle) ...[
              const Text(
                'CURRENT ID',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: textSecondary),
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
                child: Text(
                  currentHandle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Username input
            Text(
              hasHandle ? 'CHANGE TO' : 'CLAIM USERNAME',
              style: const TextStyle(
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
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16),
                    child: Text('@',
                        style: TextStyle(
                            fontSize: 16,
                            color: textSecondary,
                            fontWeight: FontWeight.w500)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 14, color: textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'username',
                        hintStyle:
                            TextStyle(fontSize: 14, color: textSecondary),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Text('@chatme',
                        style: TextStyle(fontSize: 13, color: textSecondary)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Claim / Update button
            GestureDetector(
              onTap: _isLoading
                  ? null
                  : () async {
                      final input = _controller.text
                          .trim()
                          .toLowerCase()
                          .replaceAll(RegExp(r'[^a-z0-9_]'), '');
                      if (input.length < 3) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Username must be at least 3 characters'),
                              behavior: SnackBarBehavior.floating),
                        );
                        return;
                      }

                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _isLoading = true);

                      final result = await DirectoryService.claim(input);
                      final success = result == DirectoryResult.ok;

                      if (!mounted) return;
                      setState(() => _isLoading = false);

                      if (success) {
                        await AppSettings.instance
                            .updateNip05('$input@chatme', true);
                        try {
                          await widget.relayManager?.broadcastProfileKind0();
                        } catch (_) {}
                        if (!mounted) return;
                        setState(() {});
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              '$input@chatme claimed!',
                              style: const TextStyle(
                                  color: ChatmeColors.textPrimary),
                            ),
                            backgroundColor: ChatmeColors.statusPositive,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              result == DirectoryResult.taken
                                  ? 'Username already taken'
                                  : 'Could not reach the server, try again',
                              style: const TextStyle(
                                  color: ChatmeColors.textPrimary),
                            ),
                            backgroundColor: ChatmeColors.statusDanger,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              child: Container(
                width: double.infinity,
                padding: ChatmeButtonStyles.padding,
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
                      ),
                    if (_isLoading) const SizedBox(width: 8),
                    Text(
                      _isLoading
                          ? 'Claiming...'
                          : (hasHandle ? 'Update ID' : 'Claim ID'),
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

            if (hasHandle) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _isLoading ? null : _showDisconnectDialog,
                child: Container(
                  width: double.infinity,
                  padding: ChatmeButtonStyles.padding,
                  decoration: ChatmeButtonStyles.dangerDecoration(),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.link_off_rounded,
                        size: 16,
                        color: ChatmeButtonStyles.dangerForeground,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Disconnect ID',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ChatmeButtonStyles.dangerForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> _showDisconnectDialog() async {
    final currentHandle = AppSettings.instance.myNip05;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Disconnect ID?',
      message:
          'Your unique username $currentHandle will be released and removed from your profile. This action cannot be undone.',
      confirmLabel: 'Disconnect',
    );

    if (confirmed && mounted) {
      setState(() => _isLoading = true);
      try {
        if (AppSettings.instance.myNip05.isNotEmpty) {
          await DirectoryService.release();
        }

        await AppSettings.instance.updateNip05('', false);
        try {
          await widget.relayManager?.broadcastProfileKind0();
        } catch (_) {}

        // The identity was just released — clear it from our own contact
        // row too so the chat list immediately falls back to npub.
        await AppSettings.clearContactIdentity(AppSettings.instance.myPubkey);

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _controller.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Global ID disconnected',
              style: TextStyle(color: ChatmeColors.textPrimary),
            ),
            backgroundColor: ChatmeColors.statusPositive,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to disconnect: $e',
              style: const TextStyle(color: ChatmeColors.textPrimary),
            ),
            backgroundColor: ChatmeColors.statusDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
