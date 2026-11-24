import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/crypto/nip17.dart';
import '../core/crypto/nip17_file.dart';
import '../core/utils/debug_logger.dart';
import '../models/contact.dart';
import '../relay_manager.dart';
import '../services/app_settings.dart';
import '../services/blossom_service.dart';
import '../services/file_send_service.dart';
import '../services/file_transfer_service.dart';
import '../services/media_storage.dart';
import 'story_event.dart';
import 'story_item.dart';
import 'story_store.dart';

class StoryManager {
  StoryManager._();
  static final StoryManager instance = StoryManager._();

  final StoryStore store = StoryStore();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  Timer? _expiryTimer;

  void notify() => revision.value++;

  void startExpirySweep() {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(purgeExpired());
    });
    unawaited(purgeExpired());
  }

  void dispose() {
    _expiryTimer?.cancel();
  }

  /// Wipes every story on this device, including the previous account's self
  /// envelope. Called by account logout before the settings box is cleared.
  Future<void> clearAll() async {
    if (!Hive.isBoxOpen(StoryStore.boxName)) return;
    final box = Hive.box<Map>(StoryStore.boxName);
    final items = <StoryItem>[];
    for (final raw in box.values) {
      try {
        items.add(StoryItem.fromMap(Map<dynamic, dynamic>.from(raw)));
      } catch (_) {}
    }
    for (final story in items) {
      _deleteLocalMediaBestEffort(story.localPath);
    }
    await box.clear();
    notify();
  }

  List<StoryItem> activeStories({String? authorPubkey}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final items = authorPubkey == null
        ? store.all(nowMs: now)
        : store.byAuthor(authorPubkey, nowMs: now);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  List<String> authorsWithActiveStories() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final items = store.all(nowMs: now);
    final seen = <String>{};
    final authors = <String>[];
    for (final item in items) {
      if (seen.add(item.authorPubkey)) authors.add(item.authorPubkey);
    }
    return authors;
  }

  Future<void> purgeExpired() async {
    final expired = await store.purgeExpired();
    if (expired.isEmpty) return;
    for (final story in expired) {
      _deleteLocalMediaBestEffort(story.localPath);
      _deleteRemoteBlobBestEffort(story.mediaUrl);
    }
    notify();
  }

  void _deleteLocalMediaBestEffort(String path) {
    if (path.isEmpty) return;
    unawaited(() async {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        DebugLogger.log('[Story] Local media cleanup failed | $e', type: 'WARN');
      }
    }());
  }

  void _deleteRemoteBlobBestEffort(String url) {
    if (url.isEmpty) return;
    // Blossom delete is not standardized in current client/service; best-effort
    // cleanup is limited to local expiry. Keep hook for future support.
    DebugLogger.log('[Story] Blob delete best-effort skipped (unsupported) | $url');
  }

  Future<StoryItem> createStory({
    required RelayManager relay,
    required File file,
    required String mimeType,
    String caption = '',
    int? width,
    int? height,
    int? durationSeconds,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    if (myPubkey.isEmpty) throw Exception('Missing identity');

    final uploaded = await FileSendService.encryptAndUpload(
      source: file,
      mimeType: mimeType,
      durationSeconds: durationSeconds,
      width: width,
      height: height,
      servers: AppSettings.instance.blossomServers,
    );

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final expiresAtMs = nowMs + StoryItem.defaultDuration.inMilliseconds;
    final recipients = _storyRecipients();
    final storyId = await _publishStoryRumor(
      relay: relay,
      uploaded: uploaded,
      caption: caption,
      expiresAtMs: expiresAtMs,
      recipients: recipients,
    );

    String localPath = '';
    try {
      final dir = await MediaStorage.instance.dir('stories');
      final ext = _extFromMime(mimeType);
      final saved = await FileSendService.moveIntoFolder(
        file,
        dir,
        'story_${storyId.replaceAll(':', '_')}$ext',
      );
      localPath = saved.path;
    } catch (e) {
      DebugLogger.log('[Story] Local story copy failed | $e', type: 'WARN');
    }

    final item = StoryItem(
      id: storyId,
      authorPubkey: myPubkey,
      createdAt: nowMs,
      expiresAt: expiresAtMs,
      mediaUrl: uploaded.url,
      mimeType: mimeType,
      encryptionKey: uploaded.key,
      encryptionNonce: uploaded.nonce,
      fileHash: uploaded.hash,
      originalHash: uploaded.originalHash ?? '',
      caption: caption.trim(),
      width: width,
      height: height,
      durationSeconds: durationSeconds,
      size: uploaded.plainSize ?? uploaded.size,
      localPath: localPath,
    );
    await store.put(item);
    notify();
    return item;
  }

  List<String> _storyRecipients() {
    final myPubkey = AppSettings.instance.myPubkey;
    final contacts = Hive.box<Contact>('contacts')
        .values
        .where((c) => c.pubkey.isNotEmpty && c.pubkey != myPubkey)
        .map((c) => c.pubkey)
        .toSet()
        .toList();
    contacts.add(myPubkey); // self envelope
    return contacts;
  }

  Future<String> _publishStoryRumor({
    required RelayManager relay,
    required FileMessage uploaded,
    required String caption,
    required int expiresAtMs,
    required List<String> recipients,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    final myPrivkey = AppSettings.instance.myPrivkey;
    if (myPubkey.isEmpty || myPrivkey.isEmpty) {
      throw Exception('Missing identity');
    }
    final tags = StoryEvent.buildTags(
      receiverPubkey: myPubkey,
      file: uploaded,
      expiresAtMs: expiresAtMs,
      caption: caption,
    );
    final wraps = await Nip17.wrapMulti(
      plaintext: uploaded.url,
      senderPrivkey: myPrivkey,
      senderPubkey: myPubkey,
      receiverPubkeys: recipients,
      rumorReceiverPubkey: myPubkey,
      kind: Nip17.kindStoryPost,
      customTags: tags,
      forcedTimestampSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    for (final wrapped in wraps) {
      relay.publishSignedEvent(wrapped.giftWrap);
    }
    return wraps.first.rumorId;
  }

  Future<bool> handleIncomingRumor({
    required String rumorId,
    required String senderPubkey,
    required int timestampMs,
    required List<List<String>> tags,
    required String content,
  }) async {
    final story = StoryEvent.fromRumor(
      rumorId: rumorId,
      authorPubkey: senderPubkey,
      createdAtMs: timestampMs,
      tags: tags,
      content: content,
    );
    if (story == null) return false;
    final myPubkey = AppSettings.instance.myPubkey;
    final isKnownContact = Hive.box<Contact>('contacts').containsKey(senderPubkey);
    if (senderPubkey != myPubkey && !isKnownContact) {
      DebugLogger.log('[Story] Ignored story from non-contact | $senderPubkey');
      return true;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (story.isExpiredAt(now)) return true;

    final existing = store.getById(story.id);
    if (existing != null) {
      await store.put(story.copyWith(
        localPath: existing.localPath,
        viewedBy: existing.viewedBy,
      ));
    } else {
      await store.put(story);
    }
    notify();
    return true;
  }

  Future<void> markViewed(StoryItem story) async {
    final myPubkey = AppSettings.instance.myPubkey;
    if (myPubkey.isEmpty) return;
    await store.markViewed(
      story.id,
      myPubkey,
      DateTime.now().millisecondsSinceEpoch,
    );
    notify();
  }

  Future<String?> ensureLocalMedia(StoryItem story) async {
    if (story.localPath.isNotEmpty && await File(story.localPath).exists()) {
      return story.localPath;
    }
    try {
      final bytes = await BlossomService.download(story.mediaUrl);
      final decrypted = FileTransferService.decryptBytes(
        bytes,
        FileMessage(
          url: story.mediaUrl,
          mimeType: story.mimeType,
          key: story.encryptionKey,
          nonce: story.encryptionNonce,
          hash: story.fileHash,
          originalHash: story.originalHash,
          size: story.size,
        ),
      );
      final dir = await MediaStorage.instance.dir('stories');
      final ext = _extFromMime(story.mimeType);
      final file = File('${dir.path}${Platform.pathSeparator}${story.id}$ext');
      await file.writeAsBytes(decrypted, flush: true);
      final updated = story.copyWith(localPath: file.path);
      await store.put(updated);
      notify();
      return file.path;
    } catch (e) {
      DebugLogger.log('[Story] Download/decrypt failed | $e', type: 'WARN');
      return null;
    }
  }

  static String _extFromMime(String mime) {
    if (mime.contains('png')) return '.png';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('gif')) return '.gif';
    if (mime.contains('mp4')) return '.mp4';
    if (mime.contains('quicktime')) return '.mov';
    if (mime.contains('webm')) return '.webm';
    return mime.startsWith('video/') ? '.mp4' : '.jpg';
  }
}
