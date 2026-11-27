import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/crypto/key_generator.dart';
import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../services/app_settings.dart';
import '../../services/chatme_toast.dart';
import '../../widgets/chatme_notice.dart';
import '../../widgets/recovery_phrase_words.dart';

/// Creates an identity locally, but only lets the user leave after they
/// explicitly confirm that the recovery phrase was saved.
class CreateAccountPage extends StatefulWidget {
  /// Called after the identity has been persisted. The caller owns the
  /// sync gate, FCM topic and relay connection.
  final VoidCallback onAuthenticated;

  /// Injectable so widget tests can exercise the backup gate without real
  /// disk I/O inside the fake-async test zone. Takes the displayed phrase so
  /// the stored identity always matches what the user wrote down.
  final Future<void> Function(String mnemonic) createIdentity;

  CreateAccountPage({
    super.key,
    required this.onAuthenticated,
    Future<void> Function(String mnemonic)? createIdentity,
  }) : createIdentity = createIdentity ?? AppSettings.instance.createIdentity;

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  late final String _mnemonic;
  bool _confirmed = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _mnemonic = ChatMeVault.generateNewMnemonic();
  }

  Future<void> _copyPhrase() async {
    await Clipboard.setData(ClipboardData(text: _mnemonic));
  }

  Future<void> _continue() async {
    if (!_confirmed || _isLoading) return;
    setState(() => _isLoading = true);
    try {
      await widget.createIdentity(_mnemonic);
      if (mounted) widget.onAuthenticated();
    } catch (e) {
      if (mounted) {
        ChatmeToast.show('Could not create account: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _mnemonic.split(' ');

    return Scaffold(
      backgroundColor: ChatmeColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: ChatmeColors.backgroundPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Create account',
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
            const Text(
              'YOUR RECOVERY PHRASE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                color: ChatmeColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            const ChatmeNotice(
              icon: Icons.info_outline_rounded,
              message:
                  'This phrase is the only way to restore this account. Save it offline before continuing. Anyone who has it can access your messages.',
              iconColor: ChatmeColors.statusWarning,
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ChatmeColors.surfaceMenu,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: ChatmeColors.borderSubtle,
                  width: 0.5,
                ),
              ),
              child: RecoveryPhraseWords(words: words),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _copyPhrase,
                icon: const Icon(Icons.copy_all_rounded, size: 15),
                label: const Text('Copy phrase'),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _confirmed,
              onChanged: _isLoading
                  ? null
                  : (value) => setState(() => _confirmed = value ?? false),
              activeColor: ChatmeColors.accentStrong,
              checkColor: ChatmeColors.onAccent,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I have saved my recovery phrase',
                style: TextStyle(
                  fontSize: 13,
                  color: ChatmeColors.textPrimary,
                ),
              ),
              subtitle: const Text(
                'I understand it cannot be reset.',
                style: TextStyle(
                  fontSize: 11,
                  color: ChatmeColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _ContinueButton(
              enabled: _confirmed && !_isLoading,
              loading: _isLoading,
              onTap: _continue,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  const _ContinueButton({
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
                Icon(Icons.check_rounded, size: 16, color: foreground),
              const SizedBox(width: 8),
              Text(
                loading ? 'Creating account...' : 'Enter Chatme',
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
