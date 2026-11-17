// lib/core/utils/bg_inbox.dart
//
// Tiny file-based mailbox shared by the FCM isolate, the notification-action
// isolate and the main app. One small file per item, so no isolate ever
// rewrites data written by another (unlike a shared Hive box).

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'notification_entry.dart';

/// One encrypted gift wrap waiting for the main isolate to verify and persist.
typedef PendingGiftWrap = ({
  File file,
  String eventId,
  String ephemeralPubkey,
  String ciphertext,
  int writtenAtMs,
});

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

  // ------------------------------------------------------ Pending messages
  //
  // The FCM isolate drops the raw NIP-17 gift wrap here. The main isolate
  // verifies and persists it later. Hive stays single-isolate; this mailbox
  // is intentionally just small, atomically written ciphertext files.

  static const String _pendingPrefix = 'p_';
  static const String _pendingTempPrefix = 'tmp_p_';
  static const int _maxPendingFiles = 50;
  static const int _maxPendingBytes = 16 * 1024;
  static final RegExp _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Stores one encrypted gift wrap for the main isolate.
  ///
  /// Returns `false` for invalid or duplicate payloads. The JSON is written
  /// to a temp file first and renamed, so readers never see a partial file.
  static Future<bool> writePendingMessage({
    required String eventId,
    required String ephemeralPubkey,
    required String ciphertext,
    int? writtenAtMs,
  }) async {
    if (!_hex64.hasMatch(eventId) ||
        !_hex64.hasMatch(ephemeralPubkey) ||
        ciphertext.isEmpty ||
        ciphertext.length > 4096) {
      return false;
    }

    File? temp;
    try {
      final dir = await _dir();
      final finalPath = '${dir.path}/$_pendingPrefix$eventId.json';
      if (await File(finalPath).exists()) return false;

      final nonce = Random.secure()
          .nextInt(0x7fffffff)
          .toRadixString(16)
          .padLeft(8, '0');
      temp = File('${dir.path}/$_pendingTempPrefix${eventId}_$nonce.json');
      final payload = <String, dynamic>{
        'v': 1,
        'eventId': eventId,
        'ephemeralPubkey': ephemeralPubkey,
        'ciphertext': ciphertext,
        'writtenAtMs': writtenAtMs ?? DateTime.now().millisecondsSinceEpoch,
      };

      await temp.writeAsString(jsonEncode(payload), flush: true);

      // A duplicate FCM delivery can race the rename. Same event id means the
      // same gift wrap, so keeping the first file is always correct.
      if (await File(finalPath).exists()) {
        await temp.delete();
        return false;
      }
      await temp.rename(finalPath);
      await prunePendingMessages();
      return true;
    } catch (_) {
      try {
        await temp?.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Parsed pending gift wraps, oldest first. Malformed files are discarded;
  /// structurally valid ones are left for the caller to verify and consume.
  static Future<List<PendingGiftWrap>> peekPendingMessages() async {
    final dir = await _dir();
    final items = <PendingGiftWrap>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_pendingPrefix) ||
          name.startsWith(_pendingTempPrefix)) {
        continue;
      }
      try {
        if (await entity.length() > _maxPendingBytes) {
          await entity.delete();
          continue;
        }
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) {
          await entity.delete();
          continue;
        }
        final eventId = decoded['eventId']?.toString() ?? '';
        final ephemeralPubkey = decoded['ephemeralPubkey']?.toString() ?? '';
        final ciphertext = decoded['ciphertext']?.toString() ?? '';
        final writtenAtMs = decoded['writtenAtMs'] is int
            ? decoded['writtenAtMs'] as int
            : 0;

        if (decoded['v'] != 1 ||
            !_hex64.hasMatch(eventId) ||
            !_hex64.hasMatch(ephemeralPubkey) ||
            ciphertext.isEmpty ||
            ciphertext.length > 4096) {
          await entity.delete();
          continue;
        }

        items.add((
          file: entity,
          eventId: eventId,
          ephemeralPubkey: ephemeralPubkey,
          ciphertext: ciphertext,
          writtenAtMs: writtenAtMs,
        ));
      } catch (_) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    items.sort((a, b) => a.writtenAtMs.compareTo(b.writtenAtMs));
    return items;
  }

  /// Deletes one pending file after the main isolate persisted its message.
  static Future<void> consumePendingMessage(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }

  /// Keeps the mailbox bounded even when the app is not opened for a while.
  static Future<void> prunePendingMessages({
    int keepNewest = _maxPendingFiles,
  }) async {
    final dir = await _dir();
    final files = <({File file, int writtenAtMs})>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_pendingPrefix) ||
          name.startsWith(_pendingTempPrefix)) {
        continue;
      }
      int ms = 0;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is Map && decoded['writtenAtMs'] is int) {
          ms = decoded['writtenAtMs'] as int;
        }
      } catch (_) {}
      files.add((file: entity, writtenAtMs: ms));
    }
    if (files.length <= keepNewest) return;
    files.sort((a, b) => b.writtenAtMs.compareTo(a.writtenAtMs));
    for (final item in files.skip(keepNewest)) {
      try {
        await item.file.delete();
      } catch (_) {}
    }
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

  /// The newest message of every contact, newest first.
  ///
  /// This is what the grouped notification lists: one entry per conversation,
  /// even if that conversation holds several unread messages.
  static Future<List<NotificationEntry>> latestPerConversation() async {
    final dir = await _dir();
    final latest = <String, ({NotificationEntry entry, String path})>{};

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(_stackPrefix)) continue;
      final rest = name.substring(_stackPrefix.length);
      final sep = rest.indexOf('_');
      if (sep <= 0) continue;

      try {
        final json = jsonDecode(await entity.readAsString());
        final entry = NotificationEntry.fromJson(json as Map<String, dynamic>);
        final peer = rest.substring(0, sep);
        final current = latest[peer];
        if (current == null ||
            entry.timeMs > current.entry.timeMs ||
            (entry.timeMs == current.entry.timeMs &&
                entity.path.compareTo(current.path) > 0)) {
          latest[peer] = (entry: entry, path: entity.path);
        }
      } catch (_) {}
    }

    final entries = [for (final item in latest.values) item.entry];
    entries.sort((a, b) {
      final byTime = b.timeMs.compareTo(a.timeMs);
      if (byTime != 0) return byTime;
      final bySender = a.sender.compareTo(b.sender);
      return bySender != 0 ? bySender : a.message.compareTo(b.message);
    });
    return entries;
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