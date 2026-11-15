// storage_space.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// How much room is left on the phone, asked from the Android side. iOS and
/// web return null: there the download simply fails cleanly when the disk is
/// full instead of being refused up front.
class StorageSpace {
  StorageSpace._();

  static const MethodChannel _channel = MethodChannel('com.chatme.app/storage');

  /// Never try to fill the phone completely: a download also needs room for
  /// the temporary file and for the app to keep working.
  static const int marginFloor = 20 * 1024 * 1024;

  static Future<int?> freeBytes() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final value = await _channel.invokeMethod<int>('freeBytes');
      return value != null && value >= 0 ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// The room a file of [plainSize] bytes needs before it is downloaded:
  /// the file itself plus a fifth of it, or 20 MB, whichever is larger.
  static int requiredFor(int plainSize) {
    return plainSize + math.max(plainSize ~/ 5, marginFloor);
  }
}
