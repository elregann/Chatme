// lib/core/utils/bg_inbox.dart
//
// Tiny file-based mailbox shared by the FCM isolate, the notification-action
// isolate and the main app. One small file per item, so no isolate ever
// rewrites data written by another (unlike a shared Hive box).

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class BgInbox {
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/bg_inbox');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Remember a message id received while the app was closed.
  static Future<void> addUnread(String peer, String rumorId) async {
    final dir = await _dir();
    await File('${dir.path}/u_${peer}_$rumorId').create();
  }

  /// Returns the remembered ids for [peer] and removes them.
  static Future<List<String>> takeUnread(String peer) async {
    final dir = await _dir();
    final prefix = 'u_${peer}_';
    final ids = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix)) continue;
      ids.add(name.substring(prefix.length));
      try {
        await entity.delete();
      } catch (_) {}
    }
    return ids;
  }

  static Future<void> clearAllUnread() async {
    final dir = await _dir();
    await for (final entity in dir.list()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith('u_')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  /// Note the ids whose read receipts were sent while the app was closed.
  static Future<void> recordRead(String peer, List<String> ids) async {
    final dir = await _dir();
    for (final id in ids) {
      await File('${dir.path}/r_${peer}_$id').create();
    }
  }

  /// Returns {peer: [ids]} for every recorded read and removes the notes.
  static Future<Map<String, List<String>>> takeReads() async {
    final dir = await _dir();
    final result = <String, List<String>>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('r_')) continue;
      final rest = name.substring(2);
      final sep = rest.indexOf('_');
      if (sep <= 0) continue;
      result
          .putIfAbsent(rest.substring(0, sep), () => [])
          .add(rest.substring(sep + 1));
      try {
        await entity.delete();
      } catch (_) {}
    }
    return result;
  }
}