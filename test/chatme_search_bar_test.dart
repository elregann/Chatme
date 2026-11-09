// chatme_search_bar_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/widgets/chatme_search_bar.dart';

const _barKey = Key('chatme-search-bar');
const _clearKey = Key('chatme-search-clear');

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  required FocusNode focusNode,
  ValueChanged<String>? onChanged,
  VoidCallback? onClear,
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          ChatmeSearchBar(
            controller: controller,
            focusNode: focusNode,
            hintText: 'Search here',
            onChanged: onChanged ?? (_) {},
            onClear: onClear ?? () {},
          ),
        ],
      ),
    ),
  ));
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('shows the hint and the search icon, and no clear button when empty', (tester) async {
    await _pump(tester, controller: controller, focusNode: focusNode);
    expect(find.text('Search here'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byKey(_clearKey), findsNothing);
  });

  testWidgets('typing reports the text and shows the clear button', (tester) async {
    String? latest;
    await _pump(tester, controller: controller, focusNode: focusNode, onChanged: (v) => latest = v);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    expect(latest, 'Alice');
    expect(find.byKey(_clearKey), findsOneWidget);
  });

  testWidgets('the clear button empties the field, calls onClear once and drops focus', (tester) async {
    var cleared = 0;
    await _pump(tester, controller: controller, focusNode: focusNode, onClear: () => cleared++);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(_clearKey));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(cleared, 1);
    expect(focusNode.hasFocus, isFalse);
    expect(find.byKey(_clearKey), findsNothing);
  });

  testWidgets('tapping the search icon focuses the field', (tester) async {
    await _pump(tester, controller: controller, focusNode: focusNode);
    expect(focusNode.hasFocus, isFalse);
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('the clear button also appears for text set from outside', (tester) async {
    await _pump(tester, controller: controller, focusNode: focusNode);
    controller.text = 'abc';
    await tester.pump();
    expect(find.byKey(_clearKey), findsOneWidget);
    controller.clear();
    await tester.pump();
    expect(find.byKey(_clearKey), findsNothing);
  });

  testWidgets('the bar keeps its height and centers the hint and the icon', (tester) async {
    await _pump(tester, controller: controller, focusNode: focusNode);
    final bar = tester.getRect(find.byKey(_barKey));
    expect(bar.height, 48);
    expect(tester.getCenter(find.text('Search here')).dy, closeTo(bar.center.dy, 1.0));
    expect(tester.getCenter(find.byIcon(Icons.search_rounded)).dy, closeTo(bar.center.dy, 1.0));
  });

  testWidgets('typed text and the clear button stay centered', (tester) async {
    await _pump(tester, controller: controller, focusNode: focusNode);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    final bar = tester.getRect(find.byKey(_barKey));
    expect(tester.getCenter(find.byType(EditableText)).dy, closeTo(bar.center.dy, 1.0));
    expect(tester.getCenter(find.byKey(_clearKey)).dy, closeTo(bar.center.dy, 1.0));
  });

  testWidgets('a large system font does not break the layout or change the bar height', (tester) async {
    await _pump(tester, controller: controller, focusNode: focusNode, textScale: 2.0);
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(_barKey)).height, 48);
  });

  testWidgets('works in the dark theme', (tester) async {
    await _pump(tester, controller: controller, focusNode: focusNode, brightness: Brightness.dark);
    expect(find.text('Search here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
