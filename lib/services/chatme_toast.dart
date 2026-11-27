import 'dart:async';

import 'package:fluttertoast/fluttertoast.dart';

/// Sends a message to the platform's native toast.
typedef ToastSender = Future<bool?> Function(String message);

/// Single entry point for transient user feedback.
///
/// The platform renders the toast, so Chatme does not style it.
class ChatmeToast {
  ChatmeToast._();

  static ToastSender _sender = _systemSender;

  /// Shows [message] using the current sender.
  static void show(String message) {
    unawaited(_send(message));
  }

  /// Replaces the sender, or restores the native sender when [sender] is null.
  static void useSender(ToastSender? sender) {
    _sender = sender ?? _systemSender;
  }

  static Future<void> _send(String message) async {
    try {
      await _sender(message);
    } catch (_) {
      // A failed toast must never break the action that triggered it.
    }
  }

  static Future<bool?> _systemSender(String message) {
    return Fluttertoast.showToast(msg: message);
  }
}
