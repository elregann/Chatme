import 'dart:io';

import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/ui/auth/create_account_page.dart';
import 'package:chatme/ui/auth/restore_identity_page.dart';
import 'package:chatme/ui/auth/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Advances a few frames without waiting for every repeating animation,
/// e.g. the indeterminate progress ring shown while a key is generated.
Future<void> _pumpBriefly(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('chatme_login_flow_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box('settings').clear();
    AppSettings.instance.myPubkey = '';
    AppSettings.instance.myPrivkey = '';
    AppSettings.instance.myMnemonic = '';
  });

  testWidgets('welcome offers both paths on the Chatme background',
      (tester) async {
    var created = 0;
    var restored = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: WelcomePage(
          onCreateAccount: () => created++,
          onRestoreAccount: () => restored++,
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, ChatmeColors.backgroundPrimary);
    expect(find.text('Chatme'), findsOneWidget);
    expect(find.text('Create a new account'), findsOneWidget);
    expect(find.text('Restore an account'), findsOneWidget);

    await tester.tap(find.text('Create a new account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore an account'));
    await tester.pumpAndSettle();

    expect(created, 1);
    expect(restored, 1);
  });

  testWidgets('create account requires a backup confirmation before sign-in',
      (tester) async {
    var authenticated = 0;
    String? capturedMnemonic;

    await tester.pumpWidget(
      MaterialApp(
        home: CreateAccountPage(
          onAuthenticated: () => authenticated++,
          createIdentity: (mnemonic) async {
            capturedMnemonic = mnemonic;
            AppSettings.instance.myPubkey = 'a' * 64;
            AppSettings.instance.myPrivkey = 'b' * 64;
          },
        ),
      ),
    );

    expect(find.text('YOUR RECOVERY PHRASE'), findsOneWidget);
    expect(find.text('Enter Chatme'), findsOneWidget);

    await tester.tap(find.text('Enter Chatme'));
    await _pumpBriefly(tester);
    expect(authenticated, 0);
    expect(AppSettings.instance.hasIdentity, isFalse);

    await tester.tap(find.byType(Checkbox));
    await _pumpBriefly(tester);
    await tester.tap(find.text('Enter Chatme'));
    await _pumpBriefly(tester);

    expect(authenticated, 1);
    expect(AppSettings.instance.hasIdentity, isTrue);

    final shownWords = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((rich) => rich.text.toPlainText())
        .where((text) => RegExp(r'^\d+\. \S+$').hasMatch(text))
        .map((text) => text.split(' ').last)
        .toList();
    expect(shownWords, hasLength(12));
    expect(capturedMnemonic, shownWords.join(' '));
  });

  testWidgets('restore normalizes whitespace before import', (tester) async {
    String? capturedInput;

    await tester.pumpWidget(
      MaterialApp(
        home: RestoreIdentityPage(
          onAuthenticated: () {},
          importAccount: (input) async => capturedInput = input,
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      '  abandon  abandon abandon\nabandon abandon abandon\n'
      '  abandon abandon abandon abandon abandon about  ',
    );
    await _pumpBriefly(tester);
    await tester.tap(find.text('Sign in'));
    await _pumpBriefly(tester);

    expect(
      capturedInput,
      'abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon about',
    );
    expect(find.text('Make sure you typed your phrase or key exactly.'),
        findsOneWidget);
  });

  testWidgets('restore rejects a malformed key with an inline error',
      (tester) async {
    var authenticated = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: RestoreIdentityPage(
          onAuthenticated: () => authenticated++,
          importAccount: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('Sign in'));
    await _pumpBriefly(tester);
    expect(authenticated, 0);

    await tester.enterText(find.byType(TextField), 'not-a-key');
    await _pumpBriefly(tester);
    await tester.tap(find.text('Sign in'));
    await _pumpBriefly(tester);

    expect(
      find.textContaining('Use an nsec, a 64-character hex key'),
      findsOneWidget,
    );
    final errorText = tester.widget<Text>(
      find.textContaining('Use an nsec, a 64-character hex key'),
    );
    expect(errorText.style?.color, ChatmeColors.statusDanger);
    expect(authenticated, 0);
  });
}
