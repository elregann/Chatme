import 'dart:io';

import 'package:chatme/ui/profile/recovery_phrase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('chatme_recovery_phrase_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box('settings').put('my_mnemonic', mnemonic);
  });

  testWidgets('revealed words use the shared recovery grid', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RecoveryPhrasePage()));

    await tester.tap(find.text('Tap to reveal'));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);

    final gridTexts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Text),
      ),
    );
    final words = gridTexts
        .map((text) => text.data ?? '')
        .where((text) => !RegExp(r'^\d+$').hasMatch(text))
        .toList();

    expect(words, mnemonic.split(' '));
  });
}
