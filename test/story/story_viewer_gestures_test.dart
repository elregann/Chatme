import 'package:chatme/story/story_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
