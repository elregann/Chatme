import 'dart:math' as math;

import 'package:chatme/story/story_item.dart';
import 'package:chatme/story/story_strip.dart';
import 'package:chatme/story/story_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StoryItem _story(String id, int createdAt, {required bool viewedByMe}) {
  return StoryItem(
    id: id,
    authorPubkey: 'peer',
    createdAt: createdAt,
    expiresAt: createdAt + 86400000,
    mediaUrl: 'https://example.com/$id',
    mimeType: 'image/jpeg',
    encryptionKey: 'k',
    encryptionNonce: 'n',
    fileHash: 'f$id',
    originalHash: 'o$id',
    viewedBy: viewedByMe ? const {'me': 1} : const {},
  );
}

Widget _host({
  required VoidCallback onHoldStart,
  required VoidCallback onHoldEnd,
  required VoidCallback onNext,
  required VoidCallback onPrevious,
}) {
  return MaterialApp(
    home: Scaffold(
      body: StoryViewerGestures(
        onHoldStart: onHoldStart,
        onHoldEnd: onHoldEnd,
        onNext: onNext,
        onPrevious: onPrevious,
        child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
      ),
    ),
  );
}

void main() {
  group('StoryViewerGestures', () {
    testWidgets('holding pauses immediately and releasing resumes',
        (tester) async {
      final events = <String>[];
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(_host(
        onHoldStart: () => events.add('pause'),
        onHoldEnd: () => events.add('resume'),
        onNext: () => next++,
        onPrevious: () => previous++,
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(StoryViewerGestures)),
      );
      await tester.pump();
      expect(events, ['pause']);

      await tester.pump(const Duration(milliseconds: 600));
      expect(events, ['pause']);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(events, ['pause', 'resume']);
      expect(next, 0);
      expect(previous, 0);
    });

    testWidgets('a hold longer than the tap limit does not change stories',
        (tester) async {
      final events = <String>[];
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(_host(
        onHoldStart: () => events.add('pause'),
        onHoldEnd: () => events.add('resume'),
        onNext: () => next++,
        onPrevious: () => previous++,
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(StoryViewerGestures)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(events, ['pause', 'resume']);
      expect(next, 0);
      expect(previous, 0);
    });

    testWidgets('short tap on the right half advances', (tester) async {
      final events = <String>[];
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(_host(
        onHoldStart: () => events.add('pause'),
        onHoldEnd: () => events.add('resume'),
        onNext: () => next++,
        onPrevious: () => previous++,
      ));

      final rect = tester.getRect(find.byType(StoryViewerGestures));
      await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
      await tester.pumpAndSettle();

      expect(events, ['pause', 'resume']);
      expect(next, 1);
      expect(previous, 0);
    });

    testWidgets('short tap on the left half goes back', (tester) async {
      final events = <String>[];
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(_host(
        onHoldStart: () => events.add('pause'),
        onHoldEnd: () => events.add('resume'),
        onNext: () => next++,
        onPrevious: () => previous++,
      ));

      final rect = tester.getRect(find.byType(StoryViewerGestures));
      await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
      await tester.pumpAndSettle();

      expect(events, ['pause', 'resume']);
      expect(previous, 1);
      expect(next, 0);
    });

    testWidgets('horizontal fling moves to the next or previous story',
        (tester) async {
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(_host(
        onHoldStart: () {},
        onHoldEnd: () {},
        onNext: () => next++,
        onPrevious: () => previous++,
      ));

      await tester.fling(
        find.byType(StoryViewerGestures),
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(next, 1);
      expect(previous, 0);

      await tester.fling(
        find.byType(StoryViewerGestures),
        const Offset(400, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(previous, 1);
      expect(next, 1);
    });

    testWidgets('vertical drag changes no story', (tester) async {
      final events = <String>[];
      var next = 0;
      var previous = 0;
      await tester.pumpWidget(_host(
        onHoldStart: () => events.add('pause'),
        onHoldEnd: () => events.add('resume'),
        onNext: () => next++,
        onPrevious: () => previous++,
      ));

      await tester.drag(
        find.byType(StoryViewerGestures),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();

      expect(events, ['pause', 'resume']);
      expect(next, 0);
      expect(previous, 0);
    });
  });

  group('StoryRingStatus', () {
    test('own stories stay gray no matter how many are unviewed', () {
      final status = StoryRingStatus.fromStories(
        pubkey: 'me',
        stories: [
          _story('1', 10, viewedByMe: false),
          _story('2', 20, viewedByMe: true),
          _story('3', 30, viewedByMe: false),
        ],
        isMine: true,
      );

      expect(status.hasStory, isTrue);
      expect(status.segments.length, 3);
      expect(status.segments, [false, false, false]);
      expect(status.hasUnviewed, isFalse);
    });

    test('other stories mark unseen segments and keep seen ones gray', () {
      final status = StoryRingStatus.fromStories(
        pubkey: 'me',
        stories: [
          _story('1', 10, viewedByMe: true),
          _story('2', 20, viewedByMe: false),
          _story('3', 30, viewedByMe: true),
          _story('4', 40, viewedByMe: false),
        ],
        isMine: false,
      );

      expect(status.hasStory, isTrue);
      expect(status.segments, [false, true, false, true]);
      expect(status.hasUnviewed, isTrue);
    });

    test('all viewed stories keep a gray segmented ring', () {
      final status = StoryRingStatus.fromStories(
        pubkey: 'me',
        stories: [
          _story('1', 10, viewedByMe: true),
          _story('2', 20, viewedByMe: true),
        ],
        isMine: false,
      );

      expect(status.hasStory, isTrue);
      expect(status.segments, [false, false]);
      expect(status.hasUnviewed, isFalse);
    });

    test('segments are evenly sized and gaps are symmetric', () {
      const size = Size.square(60);
      for (final count in [2, 3, 4, 5]) {
        final painter = StoryRingPainter(
          segments: List<bool>.filled(count, true),
        );
        final sweeps = List<double>.generate(
          count,
          (i) => painter.sweepFor(i, size: size),
        );
        final gaps = painter.gapsFor(size: size);

        for (var i = 1; i < count; i++) {
          expect(sweeps[i], closeTo(sweeps[0], 0.0001));
          expect(gaps[i], closeTo(gaps[0], 0.0001));
        }
        expect(gaps[0], greaterThan(0));

        final total = sweeps.fold<double>(0, (a, b) => a + b) +
            gaps.fold<double>(0, (a, b) => a + b);
        expect(total, closeTo(math.pi * 2, 0.0001));

        for (var i = 0; i < count; i++) {
          final end = painter.startFor(i, size: size) + sweeps[i];
          final nextStart = painter.startFor((i + 1) % count, size: size);
          var gap = nextStart - end;
          while (gap < 0) {
            gap += math.pi * 2;
          }
          while (gap >= math.pi * 2) {
            gap -= math.pi * 2;
          }
          expect(gap, closeTo(gaps[0], 0.0001));
        }
      }
    });

    test('unviewed segments use the full-circle gradient slice', () {
      const painter = StoryRingPainter(segments: [true, false, true]);
      const size = Size.square(60);

      expect(StoryRingPainter.strokeWidth, 2.5);
      expect(painter.colorFor(false, 0, size: size), isNull);
      expect(painter.colorFor(true, 0, size: size), isNotNull);
      expect(painter.colorFor(true, 2, size: size), isNotNull);
      expect(
        painter.colorFor(true, 0, size: size),
        isNot(painter.colorFor(true, 2, size: size)),
      );
    });
  });

  group('StoryMoreMenu', () {
    testWidgets('own story offers a silent delete entry', (tester) async {
      var deletes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                StoryMoreMenu(
                  canDelete: true,
                  onDelete: () => deletes++,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Delete story'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

      await tester.tap(find.text('Delete story'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
    });

    testWidgets('another person story offers Message and pauses while the menu is open', (tester) async {
      final events = <String>[];
      var messages = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                StoryMoreMenu(
                  canDelete: false,
                  onDelete: () => fail('delete must not be offered'),
                  onMessage: () => messages++,
                  onMenuOpened: () => events.add('pause'),
                  onMenuDismissed: () => events.add('resume'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Delete story'), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(events, ['pause']);

      await tester.tap(find.text('Message'));
      await tester.pumpAndSettle();
      expect(messages, 1);
      expect(events, ['pause', 'resume']);
    });

    testWidgets('dismissing the menu without a choice resumes playback', (tester) async {
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                StoryMoreMenu(
                  canDelete: true,
                  onDelete: () => fail('delete was not chosen'),
                  onMenuOpened: () => events.add('pause'),
                  onMenuDismissed: () => events.add('resume'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(events, ['pause']);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(events, ['pause', 'resume']);
    });
  });
}
