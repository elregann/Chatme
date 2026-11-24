import 'dart:io';

import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/identity_secret_store.dart';
import 'package:chatme/ui/profile/recovery_phrase.dart';
import 'package:chatme/widgets/recovery_phrase_words.dart';
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

  late InMemoryIdentitySecretStore secretStore;

  setUp(() async {
    secretStore = InMemoryIdentitySecretStore();
    AppSettings.instance.setIdentitySecretStoreForTest(secretStore);
    await Hive.box('settings').clear();
    await secretStore.write(
      privkey: '1111111111111111111111111111111111111111111111111111111111111111',
      mnemonic: mnemonic,
    );
    AppSettings.instance.myMnemonic = mnemonic;
  });

  testWidgets('revealed words use the shared recovery grid', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RecoveryPhrasePage()));

    await tester.tap(find.text('Tap to reveal'));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(FittedBox),
      ),
      findsNWidgets(12),
    );

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
    expect(
      gridTexts.any((text) => text.overflow == TextOverflow.ellipsis),
      isFalse,
    );
  });

  testWidgets('long words shrink instead of truncating in a narrow grid',
      (tester) async {
    const words = [
      'abandon', 'abandon', 'abandon', 'abandon',
      'abandon', 'abandon', 'abandon', 'abandon',
      'abandon', 'abandon', 'abandon', 'surround',
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: RecoveryPhraseWords(words: words),
            ),
          ),
        ),
      ),
    );

    final gridTexts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Text),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(FittedBox),
      ),
      findsNWidgets(12),
    );
    expect(
      gridTexts.any((text) => text.overflow == TextOverflow.ellipsis),
      isFalse,
    );
    expect(gridTexts.map((text) => text.data).toList(), contains('surround'));
  });
}
