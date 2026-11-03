import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/widgets/chatme_menu.dart';

void main() {
  Widget host(ChatmeMenuButton<int> button, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: button)),
    );
  }

  const entries = [
    ChatmeMenuEntry(value: 1, icon: Icons.photo_camera_outlined, label: 'Camera'),
    ChatmeMenuEntry(value: 2, icon: Icons.photo_library_outlined, label: 'Gallery'),
  ];

  testWidgets('shows every entry with its icon and label', (tester) async {
    await tester.pumpWidget(host(ChatmeMenuButton<int>(
      icon: const Icon(Icons.more_vert),
      entries: entries,
      onSelected: (_) {},
    )));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
  });

  testWidgets('choosing an entry reports its value', (tester) async {
    final chosen = <int>[];
    await tester.pumpWidget(host(ChatmeMenuButton<int>(
      icon: const Icon(Icons.more_vert),
      entries: entries,
      onSelected: chosen.add,
    )));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    expect(chosen, [2]);
  });

  testWidgets('uses radius 10 and no padding above or below the items', (tester) async {
    await tester.pumpWidget(host(ChatmeMenuButton<int>(
      icon: const Icon(Icons.more_vert),
      entries: entries,
      onSelected: (_) {},
    )));
    final button = tester.widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>));

    expect(button.shape, isA<RoundedRectangleBorder>());
    expect((button.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(ChatmeMenu.radius));
    expect(button.menuPadding, EdgeInsets.zero);
    expect(button.clipBehavior, Clip.antiAlias);
  });

  testWidgets('opens at the given offset', (tester) async {
    await tester.pumpWidget(host(ChatmeMenuButton<int>(
      icon: const Icon(Icons.more_vert),
      entries: entries,
      onSelected: (_) {},
      offset: const Offset(0, 40),
    )));
    final button = tester.widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>));
    expect(button.offset, const Offset(0, 40));
  });

  testWidgets('follows the theme unless a color is given', (tester) async {
    await tester.pumpWidget(host(
      ChatmeMenuButton<int>(icon: const Icon(Icons.more_vert), entries: entries, onSelected: (_) {}),
      brightness: Brightness.dark,
    ));
    var button = tester.widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>));
    expect(button.color, ChatmeMenu.darkColor);

    await tester.pumpWidget(host(ChatmeMenuButton<int>(
      icon: const Icon(Icons.more_vert),
      entries: entries,
      onSelected: (_) {},
      color: const Color(0xFF1B1425),
    )));
    button = tester.widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>));
    expect(button.color, const Color(0xFF1B1425));
  });

  testWidgets('requestFocus false keeps focus on a text field while the menu is open', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(focusNode: node),
            ChatmeMenuButton<int>(
              requestFocus: false,
              icon: const Icon(Icons.more_vert),
              entries: entries,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    ));

    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    expect(node.hasFocus, isTrue);

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
  });
}
