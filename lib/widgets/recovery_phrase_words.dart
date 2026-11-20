// recovery_phrase_words.dart

import 'package:flutter/material.dart';

import '../core/theme/chatme_buttons.dart';
import '../core/theme/chatme_colors.dart';

/// Numbered recovery words in a fixed grid. Shared by create-account and
/// post-login screens so the same phrase always renders identically.
class RecoveryPhraseWords extends StatelessWidget {
  final List<String> words;

  const RecoveryPhraseWords({super.key, required this.words});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.8,
      ),
      itemCount: words.length,
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: ChatmeButtonStyles.chipDecoration(),
          child: Row(
            children: [
              Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  color: ChatmeColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  words[index],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ChatmeColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
