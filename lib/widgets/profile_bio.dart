// profile_bio.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/theme/chatme_colors.dart';
import '../core/utils/bio_text.dart';
import '../services/profile_meta_store.dart';

/// A short, plain-text preview of a bio.
///
/// The text is never interpreted as markdown or HTML. Tapping it opens a
/// scrollable sheet with the whole bio, because a long biography does not fit
/// under a profile name.
class ProfileBioText extends StatelessWidget {
  final String? about;
  final int maxLines;
  final bool showEmptyHint;
  final String emptyHint;
  final VoidCallback? onEmptyTap;
  final TextAlign textAlign;

  const ProfileBioText({
    super.key,
    required this.about,
    this.maxLines = 3,
    this.showEmptyHint = false,
    this.emptyHint = 'Add a bio',
    this.onEmptyTap,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final text = BioText.sanitize(about);

    if (text.isEmpty) {
      if (!showEmptyHint) return const SizedBox.shrink();
      return GestureDetector(
        onTap: onEmptyTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            emptyHint,
            textAlign: textAlign,
            style: TextStyle(
              fontSize: 13,
              color: ChatmeColors.accentPrimary.withAlpha(200),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showFullBio(context, text),
      behavior: HitTestBehavior.opaque,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: const TextStyle(
          fontSize: 14,
          height: 1.4,
          color: ChatmeColors.textSecondary,
        ),
      ),
    );
  }

  Future<void> _showFullBio(BuildContext context, String text) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: ChatmeColors.surfaceRaised,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bio',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ChatmeColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: ChatmeColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [ProfileBioText] backed by the kind-0 store, for a contact profile.
///
/// Only the bio subtree rebuilds when a newer profile arrives, not the whole
/// page around it.
class ProfileBioBuilder extends StatelessWidget {
  final String pubkey;
  final int maxLines;
  final TextAlign textAlign;

  const ProfileBioBuilder({
    super.key,
    required this.pubkey,
    this.maxLines = 3,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('profile_meta')) {
      return ProfileBioText(
        about: ProfileMetaStore.aboutFor(pubkey),
        maxLines: maxLines,
        textAlign: textAlign,
      );
    }

    return ValueListenableBuilder(
      valueListenable: Hive.box('profile_meta').listenable(keys: [pubkey]),
      builder: (context, _, __) => ProfileBioText(
        about: ProfileMetaStore.aboutFor(pubkey),
        maxLines: maxLines,
        textAlign: textAlign,
      ),
    );
  }
}
