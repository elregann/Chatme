// lib/core/utils/bg_inbox.dart
//
// Tiny file-based mailbox shared by the FCM isolate, the notification-action
// isolate and the main app. One small file per item, so no isolate ever
// rewrites data written by another (unlike a shared Hive box).

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'notification_entry.dart';

class BgInbox {
  /// Tests point this at a temporary folder instead of the app folder.
  @visibleForTesting
  static Directory? baseDirectoryOverride;

  static Future<Directory> _dir() async {
    final base = baseDirectoryOverride ?? await getApplicationSupportDirectory();
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

  // ------------------------------------------------------ Notification stack
  //
  // The messages shown in a contact's chat notification. They live on disk so
  // every isolate builds the same notification, and they stay until the chat
  // is read or replied to: dismissing a notification does not forget them.

  static const String _stackPrefix = 'n_';

  /// Remembers a message of [peer]'s notification. [key] identifies the
  /// message, so adding it twice keeps one entry. Only the [keepNewest]
  /// newest messages of a contact are kept.
  static Future<void> addToStack(
    String peer,
    String key,
    NotificationEntry entry, {
    int keepNewest = 10,
  }) async {
    final dir = await _dir();
    await File('${dir.path}/$_stackPrefix${peer}_${_fileSafe(key)}')
        .writeAsString(jsonEncode(entry.toJson()), flush: true);

    final stored = await _readStack(dir, peer);
    for (var i = 0; i < stored.length - keepNewest; i++) {
      try {
        await stored[i].file.delete();
      } catch (_) {}
    }
  }

  /// The messages of [peer]'s notification, oldest first.
  static Future<List<NotificationEntry>> stackOf(String peer) async {
    final dir = await _dir();
    return [for (final item in await _readStack(dir, peer)) item.entry];
  }

  /// How many messages each contact has in its notification.
  static Future<Map<String, int>> stackSizes() async {
    final dir = await _dir();
    final sizes = <String, int>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_stackPrefix)) continue;
      final rest = name.substring(_stackPrefix.length);
      final sep = rest.indexOf('_');
      if (sep <= 0) continue;
      sizes.update(rest.substring(0, sep), (count) => count + 1, ifAbsent: () => 1);
    }
    return sizes;
  }

  /// Forgets the messages of [peer]'s notification (the chat was read).
  static Future<void> clearStack(String peer) =>
      _deleteStack('$_stackPrefix${peer}_');

  /// Forgets the messages of every notification.
  static Future<void> clearAllStacks() => _deleteStack(_stackPrefix);

  static Future<void> _deleteStack(String namePrefix) async {
    final dir = await _dir();
    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is! File) continue;
      if (!entity.uri.pathSegments.last.startsWith(namePrefix)) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  static Future<List<({File file, NotificationEntry entry})>> _readStack(
    Directory dir,
    String peer,
  ) async {
    final prefix = '$_stackPrefix${peer}_';
    final items = <({File file, NotificationEntry entry})>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.uri.pathSegments.last.startsWith(prefix)) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        items.add((
          file: entity,
          entry: NotificationEntry.fromJson(json as Map<String, dynamic>),
        ));
      } catch (_) {}
    }
    items.sort((a, b) {
      final byTime = a.entry.timeMs.compareTo(b.entry.timeMs);
      return byTime != 0 ? byTime : a.file.path.compareTo(b.file.path);
    });
    return items;
  }

  static String _fileSafe(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}