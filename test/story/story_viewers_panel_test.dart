import 'package:chatme/story/story_viewers_panel.dart';
import 'package:chatme/widgets/chatme_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required int viewCount,
  List<StoryViewerEntry> viewers = const [],
  VoidCallback? onDelete,
  ValueChanged<String>? onMessageViewer,
  ValueChanged<bool>? onExpandedChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned.fill(
            child: StoryViewersPanel(
              viewCount: viewCount,
              viewers: viewers,
              onDelete: onDelete ?? () {},
              onMessageViewer: onMessageViewer ?? (_) {},
              onExpandedChanged: onExpandedChanged,
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('StoryViewersPanel', () {
    testWidgets('shows pill with views count and menu background color',
        (tester) async {
      await tester.pumpWidget(_host(viewCount: 0));
      expect(find.text('0 views'), findsOneWidget);

      await tester.pumpWidget(_host(viewCount: 1));
      expect(find.text('1 views'), findsOneWidget);

      await tester.pumpWidget(_host(viewCount: 5));
      expect(find.text('5 views'), findsOneWidget);

      final container = tester.widget<Container>(
        find.ancestor(of: find.text('5 views'), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, ChatmeMenu.darkColor);
      expect(decoration.border, isNull);
    });

    testWidgets('tap pill opens panel and hides pill', (tester) async {
      final expanded = <bool>[];
      await tester.pumpWidget(_host(
        viewCount: 5,
        onExpandedChanged: expanded.add,
      ));

      await tester.tap(find.text('5 views'));
      await tester.pump();

      expect(expanded, [true]);
      expect(find.text('Viewed by 5'), findsOneWidget);
      expect(find.text('5 views'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('tap outside closes panel and shows pill again',
        (tester) async {
      final expanded = <bool>[];
      await tester.pumpWidget(_host(
        viewCount: 3,
        onExpandedChanged: expanded.add,
      ));

      await tester.tap(find.text('3 views'));
      await tester.pump();
      expect(find.text('Viewed by 3'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      expect(expanded, [true, false]);
      expect(find.text('3 views'), findsOneWidget);
      expect(find.text('Viewed by 3'), findsNothing);
    });

    testWidgets('menu delete calls onDelete', (tester) async {
      var deletes = 0;
      await tester.pumpWidget(_host(
        viewCount: 2,
        onDelete: () => deletes++,
      ));

      await tester.tap(find.text('2 views'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete story'));
      await tester.pumpAndSettle();

      expect(deletes, 1);
    });

    testWidgets('shows viewer rows with name and Message action',
        (tester) async {
      final messaged = <String>[];
      await tester.pumpWidget(_host(
        viewCount: 2,
        viewers: const [
          StoryViewerEntry(pubkey: 'a', name: 'Alice'),
          StoryViewerEntry(pubkey: 'b', name: 'Bob'),
        ],
        onMessageViewer: messaged.add,
      ));

      await tester.tap(find.text('2 views'));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Message'), findsNWidgets(2));

      await tester.tap(find.text('Message').first);
      await tester.pump();
      expect(messaged, ['a']);
    });

    testWidgets('shows empty state when no viewers', (tester) async {
      await tester.pumpWidget(_host(viewCount: 0));

      await tester.tap(find.text('0 views'));
      await tester.pump();

      expect(find.text('Viewed by 0'), findsOneWidget);
      expect(find.text('No viewers yet'), findsOneWidget);
    });
  });
}
