// shortcut_helper_test.dart

import 'dart:io';

import 'package:chatme/core/utils/shortcut_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('chatme_shortcuts');
  late List<MethodCall> calls;
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('chatme_shortcut_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() => calls = <MethodCall>[]);

  void mockChannel(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
  }

  testWidgets('sends an avatar icon even when the caller has none',
      (tester) async {
    mockChannel(tester);

    // resolve() opens Hive boxes, so it needs real async I/O.
    await tester.runAsync(
      () => ShortcutHelper.pushConversationShortcut(
          id: 'alice-pubkey', name: 'Alice'),
    );

    expect(calls, hasLength(1));
    final args = calls.single.arguments as Map;
    expect(args['id'], 'alice-pubkey');
    expect(args['name'], 'Alice');
    expect(args['avatarBytes'], isA<Uint8List>());
    expect(args['avatarBytes'] as Uint8List, isNotEmpty);
  });

  testWidgets('keeps the avatar the caller already has', (tester) async {
    mockChannel(tester);

    await tester.runAsync(
      () => ShortcutHelper.pushConversationShortcut(
        id: 'bob-pubkey',
        name: 'Bob',
        avatarBytes: Uint8List.fromList([1, 2, 3, 4]),
      ),
    );

    expect(calls, hasLength(1));
    expect((calls.single.arguments as Map)['avatarBytes'], [1, 2, 3, 4]);
  });

  testWidgets('does nothing outside Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockChannel(tester);

      await ShortcutHelper.pushConversationShortcut(
        id: 'carol-pubkey',
        name: 'Carol',
        avatarBytes: Uint8List.fromList([1]),
      );

      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
