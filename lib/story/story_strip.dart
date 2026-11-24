import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/theme/chatme_colors.dart';
import '../models/contact.dart';
import '../services/app_settings.dart';
import '../widgets/user_avatar.dart';
import '../relay_manager.dart';
import 'story_manager.dart';

class StoryStrip extends StatelessWidget {
  final RelayManager relayManager;
  final VoidCallback onAddStory;
  final void Function(String authorPubkey) onOpenAuthor;

  const StoryStrip({
    super.key,
    required this.relayManager,
    required this.onAddStory,
    required this.onOpenAuthor,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: StoryManager.instance.revision,
      builder: (context, _, __) {
        final myPubkey = AppSettings.instance.myPubkey;
        final myStories =
            StoryManager.instance.activeStories(authorPubkey: myPubkey);
        final authors = StoryManager.instance
            .authorsWithActiveStories()
            .where((p) => p != myPubkey)
            .toList();

        return SizedBox(
          height: 104,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            scrollDirection: Axis.horizontal,
            itemCount: 1 + authors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _StoryAvatar(
                  relayManager: relayManager,
                  label: 'Your story',
                  pubkey: myPubkey,
                  name: AppSettings.instance.myName,
                  hasStory: myStories.isNotEmpty,
                  isMine: true,
                  onTap: myStories.isNotEmpty
                      ? () => onOpenAuthor(myPubkey)
                      : onAddStory,
                  onAddTap: onAddStory,
                );
              }
              final author = authors[index - 1];
              final contact = Hive.box<Contact>('contacts').get(author);
              final name = contact == null
                  ? AppSettings.formatDisplayName(author)
                  : AppSettings.getContactDisplayName(contact);
              return _StoryAvatar(
                relayManager: relayManager,
                label: name,
                pubkey: author,
                name: name,
                hasStory: true,
                isMine: false,
                onTap: () => onOpenAuthor(author),
              );
            },
          ),
        );
      },
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final RelayManager relayManager;
  final String label;
  final String pubkey;
  final String name;
  final bool hasStory;
  final bool isMine;
  final VoidCallback onTap;
  final VoidCallback? onAddTap;

  const _StoryAvatar({
    required this.relayManager,
    required this.label,
    required this.pubkey,
    required this.name,
    required this.hasStory,
    required this.isMine,
    required this.onTap,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    final ring = hasStory
        ? const SweepGradient(
            colors: [
              ChatmeColors.statusDanger,
              ChatmeColors.accentPrimary,
              ChatmeColors.accentStrong,
              ChatmeColors.statusDanger,
            ],
          )
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ring,
                    color: ring == null ? ChatmeColors.borderSubtle : null,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: ChatmeColors.backgroundPrimary,
                    ),
                    child: UserAvatar(
                      pubkey: pubkey,
                      name: name,
                      radius: 27,
                      relayManager: relayManager,
                    ),
                  ),
                ),
                if (isMine)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: onAddTap,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: ChatmeColors.accentPrimary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ChatmeColors.backgroundPrimary,
                            width: 2,
                          ),
                        ),
                        child: const Icon(Icons.add,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, color: ChatmeColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
