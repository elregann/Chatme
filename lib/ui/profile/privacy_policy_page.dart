// privacy_policy_page.dart

import 'package:flutter/material.dart';

import '../../core/theme/chatme_colors.dart';
import 'privacy_policy_content.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @visibleForTesting
  static const Key introKey = Key('privacy-policy-intro');

  @visibleForTesting
  static Key sectionKey(String title) => Key('privacy-policy-section-$title');

  @override
  Widget build(BuildContext context) {
    const bgColor = ChatmeColors.backgroundPrimary;
    const textPrimary = ChatmeColors.textPrimary;
    const textSecondary = ChatmeColors.textSecondary;
    const borderColor = ChatmeColors.borderSubtle;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Privacy Policy',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
            color: textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Column(
            key: introKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                PrivacyPolicyContent.intro,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Last updated: ${PrivacyPolicyContent.lastUpdated}',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < PrivacyPolicyContent.sections.length; i++) ...[
            _PolicySection(
              key: sectionKey(PrivacyPolicyContent.sections[i].title),
              section: PrivacyPolicyContent.sections[i],
            ),
            if (i < PrivacyPolicyContent.sections.length - 1)
              const Divider(color: borderColor, height: 40),
          ],
          const SizedBox(height: 32),
          Text(
            'Chatme is beta software and has not been independently audited. '
            'This policy describes current app behavior and may change as '
            'Chatme evolves.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: textSecondary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final PrivacyPolicySection section;

  const _PolicySection({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    const textPrimary = ChatmeColors.textPrimary;
    const textSecondary = ChatmeColors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        for (final paragraph in section.paragraphs) ...[
          const SizedBox(height: 10),
          Text(
            paragraph,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: textSecondary,
            ),
          ),
        ],
        if (section.bullets.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final bullet in section.bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•  ',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: textSecondary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
