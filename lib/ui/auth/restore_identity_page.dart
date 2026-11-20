import 'package:flutter/material.dart';

import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../core/utils/key_utils.dart';
import '../../services/app_settings.dart';
import '../../widgets/chatme_notice.dart';

/// Signs in with an existing key. The parser lives in AppSettings so this
/// page and the in-profile restore screen validate the same formats.
class RestoreIdentityPage extends StatefulWidget {
  /// Called after the key has been persisted. The caller owns the sync gate,
  /// FCM topic and relay connection.
  final VoidCallback onAuthenticated;

  /// Injectable so widget tests can exercise validation without real disk
  /// or network I/O inside the fake-async test zone.
  final Future<void> Function(String input) importAccount;

  RestoreIdentityPage({
    super.key,
    required this.onAuthenticated,
    Future<void> Function(String input)? importAccount,
  }) : importAccount = importAccount ?? AppSettings.instance.importAccount;

  @override
  State<RestoreIdentityPage> createState() => _RestoreIdentityPageState();
}

class _RestoreIdentityPageState extends State<RestoreIdentityPage> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _formatError(String input) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return 'Enter your recovery phrase or private key.';
    if (cleaned.startsWith('nsec')) {
      try {
        KeyUtils.fromNsec(cleaned);
        return null;
      } catch (_) {
        return 'That nsec could not be read. Check for typos.';
      }
    }
    if (cleaned.split(RegExp(r'\s+')).length >= 12) return null;
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cleaned)) return null;
    return 'Use an nsec, a 64-character hex key, or a 12-word phrase.';
  }

  Future<void> _restore() async {
    if (_isLoading) return;
    final input = _controller.text.trim().split(RegExp(r'\s+')).join(' ');
    final formatError = _formatError(input);
    if (formatError != null) {
      setState(() => _error = formatError);
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });
    try {
      await widget.importAccount(input);
      if (mounted) widget.onAuthenticated();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not restore account: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.trim().isNotEmpty && !_isLoading;

    return Scaffold(
      backgroundColor: ChatmeColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: ChatmeColors.backgroundPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Restore account',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: ChatmeColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: ChatmeColors.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ChatmeNotice(
              icon: Icons.info_outline_rounded,
              message: 'Make sure you typed your phrase or key exactly.',
              iconColor: ChatmeColors.statusWarning,
            ),
            const SizedBox(height: 28),
            const Text(
              'NSEC, PRIVATE KEY OR RECOVERY PHRASE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                color: ChatmeColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: ChatmeColors.surfaceMenu,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _error == null
                      ? ChatmeColors.borderSubtle
                      : ChatmeColors.statusDanger,
                  width: 0.5,
                ),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 5,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) {
                  // Rebuild every time: the button's enabled state depends on
                  // the controller text, not just on the error message.
                  setState(() => _error = null);
                },
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: ChatmeColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText:
                      'Paste your nsec, hex private key or 12-word phrase...',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: ChatmeColors.textSecondary,
                    fontFamily: 'sans-serif',
                  ),
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: ChatmeColors.statusDanger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ChatmeColors.statusDanger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            _RestoreButton(
              enabled: canSubmit,
              loading: _isLoading,
              onTap: _restore,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _RestoreButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  const _RestoreButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? ChatmeButtonStyles.primaryForeground
        : ChatmeColors.textSubtle;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(ChatmeButtonStyles.radius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: enabled
              ? ChatmeButtonStyles.primaryDecoration()
              : ChatmeButtonStyles.neutralDecoration(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ChatmeButtonStyles.primaryForeground,
                  ),
                )
              else
                Icon(
                  Icons.settings_backup_restore_rounded,
                  size: 16,
                  color: foreground,
                ),
              const SizedBox(width: 8),
              Text(
                loading ? 'Restoring...' : 'Sign in',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
