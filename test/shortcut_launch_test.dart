// shortcut_launch_test.dart

import 'package:chatme/core/utils/shortcut_launch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.chatme.app/shortcut');
  late List<MethodCall> calls;

  setUp(() => calls = <MethodCall>[]);

  void mockChannel(
    WidgetTester tester,
    Future<Object?> Function(MethodCall call) handler,
  ) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) {
      calls.add(call);
      return handler(call);
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
  }

  testWidgets('returns the contact of a tapped shortcut', (tester) async {
    mockChannel(tester, (call) async => 'alice-pubkey');

    expect(await ShortcutLaunch.takeLaunchPubkey(), 'alice-pubkey');
    expect(calls.single.method, 'getLaunchChat');
  });

  testWidgets('returns null when no shortcut is pending', (tester) async {
    mockChannel(tester, (call) async => null);

    expect(await ShortcutLaunch.takeLaunchPubkey(), isNull);
  });

  testWidgets('ignores an empty pubkey', (tester) async {
    mockChannel(tester, (call) async => '');

    expect(await ShortcutLaunch.takeLaunchPubkey(), isNull);
  });

  testWidgets('does not throw when the platform side fails', (tester) async {
    mockChannel(
      tester,
      (call) async => throw PlatformException(code: 'failed'),
    );

    expect(await ShortcutLaunch.takeLaunchPubkey(), isNull);
  });

  testWidgets('does nothing outside Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      mockChannel(tester, (call) async => 'alice-pubkey');

      expect(await ShortcutLaunch.takeLaunchPubkey(), isNull);
      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
