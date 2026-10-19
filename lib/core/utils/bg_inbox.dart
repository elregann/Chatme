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

  /// Check if a specific message ID was marked as read while app was in background.
  static Future<bool> isMarkedRead(String peer, String id) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/r_${peer}_$id');
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Remove a specific read marker once applied to Hive.
  static Future<void> consumeRead(String peer, String id) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/r_${peer}_$id');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Returns {peer: [ids]} for every recorded read without removing them prematurely.
  static Future<Map<String, List<String>>> peekReads() async {
    final dir = await _dir();
    final result = <String, List<String>>{};
    try {
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
      }
    } catch (_) {}
    return result;
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

  /// Note that a call from [peer] was declined while the app was closed.
  static Future<void> recordDeclinedCall(String peer) async {
    final dir = await _dir();
    await File('${dir.path}/d_${peer}_${DateTime.now().millisecondsSinceEpoch}')
        .create();
  }

  /// Returns (peer, time in ms) for every declined-call note and removes them.
  static Future<List<MapEntry<String, int>>> takeDeclinedCalls() async {
    final dir = await _dir();
    final result = <MapEntry<String, int>>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('d_')) continue;
      final rest = name.substring(2);
      final sep = rest.lastIndexOf('_');
      if (sep <= 0) continue;
      final ts = int.tryParse(rest.substring(sep + 1)) ?? 0;
      result.add(MapEntry(rest.substring(0, sep), ts));
      try {
        await entity.delete();
      } catch (_) {}
    }
    return result;
  }

  /// Note that a call from [peer] went unanswered while the app was closed.
  static Future<void> recordMissedCall(String peer) async {
    final dir = await _dir();
    await File('${dir.path}/m_${peer}_${DateTime.now().millisecondsSinceEpoch}')
        .create();
  }

  /// Returns (peer, time in ms) for every missed-call note and removes them.
  static Future<List<MapEntry<String, int>>> takeMissedCalls() async {
    final dir = await _dir();
    final result = <MapEntry<String, int>>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('m_')) continue;
      final rest = name.substring(2);
      final sep = rest.lastIndexOf('_');
      if (sep <= 0) continue;
      final ts = int.tryParse(rest.substring(sep + 1)) ?? 0;
      result.add(MapEntry(rest.substring(0, sep), ts));
      try {
        await entity.delete();
      } catch (_) {}
    }
    return result;
  }

  /// Note that a reply was sent from a notification while the app was closed.
  static Future<void> recordSentReply(String peer) async {
    final dir = await _dir();
    await File('${dir.path}/s_${peer}_${DateTime.now().millisecondsSinceEpoch}')
        .create();
  }

  /// Returns the peers that got a reply while the app was closed, and removes the notes.
  static Future<List<String>> takeSentReplies() async {
    final dir = await _dir();
    final peers = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('s_')) continue;
      final rest = name.substring(2);
      final sep = rest.lastIndexOf('_');
      if (sep <= 0) continue;
      peers.add(rest.substring(0, sep));
      try {
        await entity.delete();
      } catch (_) {}
    }
    return peers.toList();
  }
}