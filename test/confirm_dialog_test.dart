// confirm_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/theme/chatme_buttons.dart';
import 'package:chatme/widgets/confirm_dialog.dart';

Future<bool?> _open(WidgetTester tester) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showConfirmDialog(
              context,
              title: 'Remove contact?',
              message: 'Alice will be removed from your contacts.',
              confirmLabel: 'Remove',
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('shows the title, the message and both buttons', (tester) async {
    await _open(tester);
    expect(find.text('Remove contact?'), findsOneWidget);
    expect(find.text('Alice will be removed from your contacts.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('confirm gives true', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showConfirmDialog(
            context,
            title: 'T',
            message: 'M',
            confirmLabel: 'Go',
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancel and tapping outside give false', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showConfirmDialog(
            context,
            title: 'T',
            message: 'M',
            confirmLabel: 'Go',
          ),
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    result = null;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('both buttons use the accent blue of the theme', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(textButtonTheme: chatmeTextButtonTheme),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showConfirmDialog(
            context,
            title: 'T',
            message: 'M',
            confirmLabel: 'Remove',
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final label in ['Cancel', 'Remove']) {
      final color = DefaultTextStyle.of(tester.element(find.text(label))).style.color;
      expect(color, chatmeAccent, reason: label);
    }
    expect(result, isNull);
  });
}
