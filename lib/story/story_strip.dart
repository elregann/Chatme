import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/theme/chatme_colors.dart';
import '../models/contact.dart';
import '../services/app_settings.dart';
import '../widgets/user_avatar.dart';
import '../relay_manager.dart';
import 'story_item.dart';
import 'story_manager.dart';
import 'story_store.dart';

class StoryRingStatus {
  final bool hasStory;
  final List<bool> segments;
  final bool hasUnviewed;

  const StoryRingStatus._({
    required this.hasStory,
    required this.segments,
    required this.hasUnviewed,
  });

  static const empty = StoryRingStatus._(
    hasStory: false,
    segments: <bool>[],
    hasUnviewed: false,
  );

  factory StoryRingStatus.fromStories({
    required String? pubkey,
    required List<StoryItem> stories,
    required bool isMine,
  }) {
    if (stories.isEmpty) return empty;
    final ordered = List<StoryItem>.from(stories)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final segments = ordered
        .map((story) => !isMine && pubkey != null && !story.viewedBy.containsKey(pubkey))
        .toList(growable: false);
    return StoryRingStatus._(
      hasStory: true,
      segments: segments,
      hasUnviewed: segments.any((unviewed) => unviewed),
    );
  }
}

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
    // View receipts and local view marks are persisted directly to the Hive
    // box. Listening only to the manual revision counter can leave a ring
    // stale until the page happens to rebuild, so follow the stored data too.
    return ListenableBuilder(
      listenable: Listenable.merge([
        StoryManager.instance.revision,
        if (Hive.isBoxOpen(StoryStore.boxName))
          Hive.box<Map>(StoryStore.boxName).listenable(),
      ]),
      builder: (context, _) {
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
                  ring: StoryRingStatus.fromStories(
                    pubkey: myPubkey,
                    stories: myStories,
                    isMine: true,
                  ),
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
              final stories =
                  StoryManager.instance.activeStories(authorPubkey: author);
              return _StoryAvatar(
                relayManager: relayManager,
                label: name,
                pubkey: author,
                name: name,
                ring: StoryRingStatus.fromStories(
                  pubkey: myPubkey,
                  stories: stories,
                  isMine: false,
                ),
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
  final StoryRingStatus ring;
  final bool isMine;
  final VoidCallback onTap;
  final VoidCallback? onAddTap;

  const _StoryAvatar({
    required this.relayManager,
    required this.label,
    required this.pubkey,
    required this.name,
    required this.ring,
    required this.isMine,
    required this.onTap,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
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
    );

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
                if (ring.hasStory)
                  CustomPaint(
                    painter: StoryRingPainter(segments: ring.segments),
                    child: Padding(
                      padding: const EdgeInsets.all(2.5),
                      child: avatar,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(2.5),
                    child: avatar,
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
                            size: 14, color: Colors.black),
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

class StoryRingPainter extends CustomPainter {
  static const double strokeWidth = 2.5;
  static const double _minGapRadians = 5 * math.pi / 180;
  static const double _maxGapRadians = 12 * math.pi / 180;
  static const double _targetVisualGap = 6.0;

  final List<bool> segments;

  const StoryRingPainter({required this.segments});

  SweepGradient get _gradient => const SweepGradient(
        transform: GradientRotation(-math.pi / 2),
        colors: [
          ChatmeColors.statusDanger,
          ChatmeColors.accentPrimary,
          ChatmeColors.accentStrong,
          ChatmeColors.statusDanger,
        ],
      );

  double _radius(Size size) => (math.min(size.width, size.height) - strokeWidth) / 2;

  double gapRadiansFor({Size size = const Size.square(60)}) {
    if (segments.length <= 1) return 0;
    final radius = _radius(size);
    if (radius <= 0) return _minGapRadians;
    // Round caps extend by strokeWidth/2 on both sides of a visual gap.
    final angular = (_targetVisualGap + strokeWidth) / radius;
    return angular.clamp(_minGapRadians, _maxGapRadians);
  }

  double _step() => segments.isEmpty ? 0 : (2 * math.pi) / segments.length;

  double startFor(int index, {Size size = const Size.square(60)}) {
    final gap = gapRadiansFor(size: size);
    return (-math.pi / 2) + (_step() * index) + (gap / 2);
  }

  double sweepFor(int index, {Size size = const Size.square(60)}) {
    if (segments.isEmpty) return 0;
    return math.max(0, _step() - gapRadiansFor(size: size));
  }

  List<double> gapsFor({Size size = const Size.square(60)}) {
    if (segments.length <= 1) return const [0];
    final sweeps = List<double>.generate(segments.length, (i) => sweepFor(i, size: size));
    final gaps = <double>[];
    for (var i = 0; i < segments.length; i++) {
      final end = startFor(i, size: size) + sweeps[i];
      final nextStart = startFor((i + 1) % segments.length, size: size);
      var gap = nextStart - end;
      while (gap < 0) {
        gap += math.pi * 2;
      }
      while (gap >= math.pi * 2) {
        gap -= math.pi * 2;
      }
      gaps.add(gap);
    }
    return gaps;
  }

  Color? colorFor(bool unviewed, int index, {Size size = const Size.square(60)}) {
    if (!unviewed) return null;
    final start = startFor(index, size: size);
    final mid = start + sweepFor(index, size: size) / 2;
    final colors = _gradient.colors;
    // Sample the same full-circle gradient so each segment is a slice of one ring.
    var t = ((mid + math.pi / 2) / (2 * math.pi)) % 1.0;
    if (t < 0) t += 1.0;
    final scaled = t * (colors.length - 1);
    final i = scaled.floor().clamp(0, colors.length - 2);
    final localT = scaled - i;
    return Color.lerp(colors[i], colors[i + 1], localT)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;
    final rect = Offset.zero & size;
    const inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = _gradient.createShader(rect);
    final seenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = ChatmeColors.textMuted.withAlpha(140);

    for (var i = 0; i < segments.length; i++) {
      final sweep = sweepFor(i, size: size);
      if (sweep <= 0) continue;
      canvas.drawArc(
        arcRect,
        startFor(i, size: size),
        sweep,
        false,
        segments[i] ? gradientPaint : seenPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StoryRingPainter oldDelegate) {
    if (oldDelegate.segments.length != segments.length) return true;
    for (var i = 0; i < segments.length; i++) {
      if (oldDelegate.segments[i] != segments[i]) return true;
    }
    return false;
  }
}
