import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chatme_shortcuts_platform_interface.dart';

/// An implementation of [ChatmeShortcutsPlatform] that uses method channels.
class MethodChannelChatmeShortcuts extends ChatmeShortcutsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('chatme_shortcuts');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
