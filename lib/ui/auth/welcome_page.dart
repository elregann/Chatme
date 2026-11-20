import 'package:flutter/material.dart';

import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';

/// Entry point for a device with no local identity.
///
/// Both actions keep the same palette as the rest of Chatme; no local colors
/// are declared here so the login flow can never drift from the app theme.
class WelcomePage extends StatelessWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onRestoreAccount;

  const WelcomePage({
    super.key,
    required this.onCreateAccount,
    required this.onRestoreAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatmeColors.backgroundPrimary,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 0.95,
            colors: [
              ChatmeColors.surfaceAction,
              ChatmeColors.backgroundPrimary,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _buildMark(),
                    const SizedBox(height: 24),
                    const Text(
                      'Chatme',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.8,
                        color: ChatmeColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Private conversations. Your keys, your account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: ChatmeColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 44),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'GET STARTED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          color: ChatmeColors.textSubtle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.add_rounded,
                      title: 'Create a new account',
                      subtitle: 'Generate a 12-word recovery phrase.',
                      primary: true,
                      onTap: onCreateAccount,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.settings_backup_restore_rounded,
                      title: 'Restore an account',
                      subtitle: 'Sign in with nsec, hex key or recovery phrase.',
                      onTap: onRestoreAccount,
                    ),
                    const SizedBox(height: 36),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: ChatmeColors.textSubtle,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Your keys stay on this device. Nobody can reset them for you.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: ChatmeColors.textSubtle,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMark() {
    // Transparent Chatme mark. The scale transform is paint-only, so the
    // 104px layout slot stays identical and the title below never moves.
    return SizedBox(
      width: 104,
      height: 104,
      child: Center(
        child: Transform.scale(
          scale: 1.73,
          child: Image.asset(
            'assets/icon_cyan.png',
            width: 104,
            height: 104,
            fit: BoxFit.contain,
            semanticLabel: 'Chatme logo',
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = primary
        ? ChatmeColors.buttonOnPrimary
        : ChatmeColors.textPrimary;
    final secondary = primary
        ? const Color(0xB704060C)
        : ChatmeColors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ChatmeButtonStyles.radius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: primary
              ? ChatmeButtonStyles.primaryDecoration()
              : ChatmeButtonStyles.neutralDecoration(),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primary
                      ? const Color(0x2604060C)
                      : ChatmeColors.surfaceAction,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: foreground),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
