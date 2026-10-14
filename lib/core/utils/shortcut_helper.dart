// lib/core/utils/shortcut_helper.dart

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ShortcutHelper {
  static const MethodChannel _channel = MethodChannel('chatme_shortcuts');

  static Future<void> pushConversationShortcut({
    required String id,
    required String name,
    Uint8List? avatarBytes,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('pushShortcut', {
          'id': id,
          'name': name,
          'avatarBytes': avatarBytes,
        });
      } catch (e) {
        debugPrint('[ShortcutHelper] Failed to push shortcut: $e');
      }
    }
  }
}