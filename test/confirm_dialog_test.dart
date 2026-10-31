// confirm_dialog_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/widgets/confirm_dialog.dart';

Future<bool?> _open(WidgetTester tester, {bool destructive = false}) async {
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
              destructive: destructive,
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

  testWidgets('a destructive confirm button is red', (tester) async {
    await _open(tester, destructive: true);
    final button = tester.widget<Text>(find.text('Remove'));
    expect(button.style?.color, Colors.red);
  });
}
