// lib/core/utils/shortcut_launch.dart
//
// Reads the chat a launcher shortcut asked to open. The Android side keeps it
// as a pending value and answers exactly once, so the same chat is not reopened
// when the app resurfaces from Recents or the activity is recreated.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShortcutLaunch {
  static const MethodChannel _channel =
      MethodChannel('com.chatme.app/shortcut');

  /// The contact from a tapped shortcut, or null when there is none.
  /// Consumes the value, so callers can safely check again on every resume.
  static Future<String?> takeLaunchPubkey() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    try {
      final pubkey = await _channel.invokeMethod<String>('getLaunchChat');
      if (pubkey == null || pubkey.isEmpty) return null;
      return pubkey;
    } catch (e) {
      debugPrint('[ShortcutLaunch] Failed to read the shortcut chat: $e');
      return null;
    }
  }
}
