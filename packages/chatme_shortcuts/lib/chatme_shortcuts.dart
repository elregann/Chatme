
import 'chatme_shortcuts_platform_interface.dart';

class ChatmeShortcuts {
  Future<String?> getPlatformVersion() {
    return ChatmeShortcutsPlatform.instance.getPlatformVersion();
  }
}
