// lib/core/utils/shortcut_helper.dart

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'notification_profile.dart';

class ShortcutHelper {
  static const MethodChannel _channel = MethodChannel('chatme_shortcuts');

  static Future<void> pushConversationShortcut({
    required String id,
    required String name,
    Uint8List? avatarBytes,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    // Callers without avatar bytes still get an icon: the cached photo or the
    // initials avatar. Always push, so a failed lookup never wipes an existing
    // shortcut icon.
    final bytes = avatarBytes ?? await _resolveAvatar(id);

    try {
      await _channel.invokeMethod('pushShortcut', {
        'id': id,
        'name': name,
        'avatarBytes': bytes,
      });
    } catch (e) {
      debugPrint('[ShortcutHelper] Failed to push shortcut: $e');
    }
  }

  /// Cached-only lookup: never waits on a photo download, so shortcut pushes
  /// from the UI stay instant. Falls back to the initials avatar.
  static Future<Uint8List?> _resolveAvatar(String id) async {
    try {
      final profile =
          await NotificationProfile.resolve(id, allowDownload: false);
      return profile.avatarPng;
    } catch (_) {
      return null;
    }
  }
}
