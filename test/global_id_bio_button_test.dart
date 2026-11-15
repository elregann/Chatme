// global_id_bio_button_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:chatme/services/app_settings.dart';
import 'package:chatme/ui/profile/global_id.dart';

/// The bio input, told apart from the username input by its hint.
final Finder bioField = find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.hintText == 'Tell people a little about yourself',
);

Future<void> pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: GlobalIdPage()));
  await tester.pump();
}

Future<void> focusBioField(WidgetTester tester) async {
  await tester.ensureVisible(bioField);
  await tester.tap(bioField);
  await tester.pump();
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('global_id_bio_button');
  });

  setUp(() async {
    Hive.init(tempDir.path);
    final settings = await Hive.openBox('settings');
    await settings.clear();
    AppSettings.instance.myAbout = '';
    AppSettings.instance.myNip05 = '';
  });

  tearDown(() async {
    await Hive.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('offers Save bio when no bio is stored', (tester) async {
    await pumpPage(tester);

    expect(find.text('Save bio'), findsOneWidget);
    expect(find.text('Remove bio'), findsNothing);
  });

  testWidgets('offers a red Remove bio for an idle, unchanged bio',
      (tester) async {
    AppSettings.instance.myAbout = 'Halo';

    await pumpPage(tester);

    expect(find.text('Remove bio'), findsOneWidget);
    expect(find.text('Save bio'), findsNothing);
  });

  testWidgets('switches back to Save bio as soon as the field is focused',
      (tester) async {
    AppSettings.instance.myAbout = 'Halo';

    await pumpPage(tester);
    await focusBioField(tester);

    expect(find.text('Save bio'), findsOneWidget);
    expect(find.text('Remove bio'), findsNothing);
  });

  testWidgets('keeps Save bio when unsaved edits lose focus', (tester) async {
    AppSettings.instance.myAbout = 'Halo';

    await pumpPage(tester);
    await focusBioField(tester);
    await tester.enterText(bioField, 'Halo dunia');
    await tester.pump();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // The text no longer matches the stored bio, so removing it must not be
    // one tap away: the pending edit could be lost by accident.
    expect(find.text('Save bio'), findsOneWidget);
    expect(find.text('Remove bio'), findsNothing);
  });

  testWidgets('a successful save leaves the button on Remove bio',
      (tester) async {
    await pumpPage(tester);
    await focusBioField(tester);
    await tester.enterText(bioField, 'Halo');
    await tester.pump();

    expect(find.text('Save bio'), findsOneWidget);

    await tester.ensureVisible(find.text('Save bio'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Save bio'));
      await tester.pump();
      // Hive writes real files, so let the tap handler run on the real clock.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(AppSettings.instance.myAbout, 'Halo');
    expect(find.text('Remove bio'), findsOneWidget);
    expect(find.text('Save bio'), findsNothing);
  });

  testWidgets('removes the bio silently and returns to Save bio',
      (tester) async {
    AppSettings.instance.myAbout = 'Halo';

    await pumpPage(tester);

    await tester.ensureVisible(find.text('Remove bio'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Remove bio'));
      await tester.pump();
      // Same reason as above: write the box on the real clock.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(AppSettings.instance.myAbout, '');
    expect(find.text('Save bio'), findsOneWidget);
    expect(find.text('Remove bio'), findsNothing);
    expect(tester.widget<TextField>(bioField).controller?.text, '');
    // Silent on purpose: no dialog, no snackbar.
    expect(find.byType(SnackBar), findsNothing);
  });
}
