import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ongoing_call_style_payload.dart';

/// Thin, fail-soft wrapper around the Android shim. The plugin notification is
/// still the source of truth; this channel only restyles the already-posted
/// active call notification on Android 12+.
class OngoingCallStyleChannel {
  OngoingCallStyleChannel._();

  static const String channelName = 'com.chatme.app/ongoing_call_style';
  static const MethodChannel _channel = MethodChannel(channelName);
  static const String _applyMethod = 'applyCallStyle';
  static const String _clearMethod = 'clearCallStyle';

  /// Returns `true` when the native shim actually applied `CallStyle`.
  static Future<bool> apply(OngoingCallStylePayload payload) async {
    if (kIsWeb) return false;
    try {
      final applied = await _channel.invokeMethod<bool>(
        _applyMethod,
        payload.toMap(),
      );
      return applied ?? false;
    } catch (e) {
      debugPrint('[Notification] Call style apply failed | $e');
      return false;
    }
  }

  /// Removes a shim-posted notification so a stopped call never leaves a chip.
  static Future<void> clear({required int notificationId}) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>(_clearMethod, <String, Object?>{
        'notificationId': notificationId,
      });
    } catch (e) {
      debugPrint('[Notification] Call style clear failed | $e');
    }
  }
}
