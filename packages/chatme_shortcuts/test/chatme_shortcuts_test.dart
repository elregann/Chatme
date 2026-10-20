import 'package:flutter_test/flutter_test.dart';
import 'package:chatme_shortcuts/chatme_shortcuts.dart';
import 'package:chatme_shortcuts/chatme_shortcuts_platform_interface.dart';
import 'package:chatme_shortcuts/chatme_shortcuts_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockChatmeShortcutsPlatform
    with MockPlatformInterfaceMixin
    implements ChatmeShortcutsPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ChatmeShortcutsPlatform initialPlatform = ChatmeShortcutsPlatform.instance;

  test('$MethodChannelChatmeShortcuts is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelChatmeShortcuts>());
  });

  test('getPlatformVersion', () async {
    ChatmeShortcuts chatmeShortcutsPlugin = ChatmeShortcuts();
    MockChatmeShortcutsPlatform fakePlatform = MockChatmeShortcutsPlatform();
    ChatmeShortcutsPlatform.instance = fakePlatform;

    expect(await chatmeShortcutsPlugin.getPlatformVersion(), '42');
  });
}
