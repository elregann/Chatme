import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

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
  /// Blobs are deleted on a best-effort basis: logout never waits on a server.
  Future<void> clearAll({http.Client? client}) async {
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
      _deleteRemoteBlobBestEffort(story, client: client);
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

  Future<void> purgeExpired({http.Client? client}) async {
    final expired = await store.purgeExpired();
    if (expired.isEmpty) return;
    for (final story in expired) {
      _deleteLocalMediaBestEffort(story.localPath);
      _deleteRemoteBlobBestEffort(story, client: client);
    }
    notify();
  }

  /// Removes one of my stories from this device, tells the recipients to do
  /// the same, and asks its server to delete the blob. Silent by design: no
  /// snackbar, no dialog on success or failure.
  Future<void> deleteStory(
    StoryItem story, {
    http.Client? client,
    RelayManager? relay,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    if (myPubkey.isEmpty || story.authorPubkey != myPubkey) return;
    await store.delete(story.id);
    _deleteLocalMediaBestEffort(story.localPath);
    notify();
    if (relay != null) {
      await _publishStoryDelete(storyId: story.id, relay: relay);
    }
    _deleteRemoteBlobBestEffort(story, client: client);
  }

  /// Tells every recipient, plus this account's own devices, that a story is
  /// gone. Called on logout before the relay is disconnected and the identity
  /// is wiped. Wrap creation is local work; publishing is already best effort.
  Future<void> publishLogoutRetracts(RelayManager relay) async {
    final myPubkey = AppSettings.instance.myPubkey;
    if (myPubkey.isEmpty) return;
    for (final story in activeStories(authorPubkey: myPubkey)) {
      await _publishStoryDelete(storyId: story.id, relay: relay);
    }
  }

  Future<void> _publishStoryDelete({
    required String storyId,
    required RelayManager relay,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    final myPrivkey = AppSettings.instance.myPrivkey;
    if (myPubkey.isEmpty || myPrivkey.isEmpty || storyId.isEmpty) return;
    try {
      final expiresAtMs = DateTime.now().millisecondsSinceEpoch +
          StoryItem.defaultDuration.inMilliseconds;
      final wraps = await Nip17.wrapMulti(
        plaintext: storyId,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkeys: _storyRecipients(),
        rumorReceiverPubkey: myPubkey,
        kind: Nip17.kindStoryPost,
        customTags: StoryEvent.buildDeleteTags(
          receiverPubkey: myPubkey,
          storyId: storyId,
          expiresAtMs: expiresAtMs,
        ),
        forcedTimestampSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      for (final wrapped in wraps) {
        relay.publishSignedEvent(wrapped.giftWrap);
      }
    } catch (e) {
      DebugLogger.log('[Story] Retract publish failed | $e', type: 'WARN');
    }
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

  void _deleteRemoteBlobBestEffort(StoryItem story, {http.Client? client}) {
    if (story.uploadPrivkey.isEmpty || story.uploadPubkey.isEmpty) return;
    unawaited(_deleteRemoteBlob(story, client: client));
  }

  Future<void> _deleteRemoteBlob(StoryItem story, {http.Client? client}) async {
    if (story.uploadPrivkey.isEmpty || story.uploadPubkey.isEmpty) {
      DebugLogger.log(
        '[Story] Blob delete skipped (no upload key) | ${story.mediaUrl}',
      );
      return;
    }
    try {
      await BlossomService.delete(
        story.mediaUrl,
        hash: story.fileHash,
        key: (
          privkey: story.uploadPrivkey,
          pubkey: story.uploadPubkey,
        ),
        client: client,
      );
    } catch (e) {
      DebugLogger.log('[Story] Blob delete failed | $e', type: 'WARN');
    }
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

    // Only stories keep the upload key, so they can delete the blob later.
    // Chat uploads still use FileSendService.encryptAndUpload and forget it.
    final uploadKey = BlossomService.generateUploadKey();
    final uploaded = await FileSendService.encryptAndUploadWithKey(
      source: file,
      mimeType: mimeType,
      key: uploadKey,
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
      uploadPrivkey: uploadKey.privkey,
      uploadPubkey: uploadKey.pubkey,
    );
    await store.put(item);
    notify();
    return item;
  }

  /// A story is for saved Chatme contacts only. Unsaved rows are chat history
  /// placeholders for anyone who once messaged us, including strangers.
  bool _isStoryContact(String pubkey) {
    if (pubkey.isEmpty) return false;
    if (pubkey == AppSettings.instance.myPubkey) return true;
    final contact = Hive.box<Contact>('contacts').get(pubkey);
    return contact != null && contact.isSaved;
  }

  List<String> _storyRecipients() {
    final myPubkey = AppSettings.instance.myPubkey;
    final contacts = Hive.box<Contact>('contacts')
        .values
        .where((c) => c.pubkey.isNotEmpty && c.pubkey != myPubkey && c.isSaved)
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
    final deleteId = StoryEvent.deleteIdFromTags(tags);
    if (deleteId != null) {
      return _handleIncomingDelete(
        storyId: deleteId,
        authorPubkey: senderPubkey,
      );
    }

    final story = StoryEvent.fromRumor(
      rumorId: rumorId,
      authorPubkey: senderPubkey,
      createdAtMs: timestampMs,
      tags: tags,
      content: content,
    );
    if (story == null) return false;
    if (!_isStoryContact(senderPubkey)) {
      DebugLogger.log('[Story] Ignored story from non-contact | $senderPubkey');
      return true;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (story.isExpiredAt(now)) return true;
    if (store.isTombstoned(story.id, story.authorPubkey)) return true;

    final existing = store.getById(story.id);
    if (existing != null) {
      await store.put(story.copyWith(
        localPath: existing.localPath,
        viewedBy: existing.viewedBy,
        uploadPrivkey: existing.uploadPrivkey,
        uploadPubkey: existing.uploadPubkey,
      ));
    } else {
      await store.put(story);
    }
    notify();
    return true;
  }

  /// Applies a retract from the story's author. The tombstone also covers a
  /// story copy that arrives later from a relay replay.
  Future<bool> _handleIncomingDelete({
    required String storyId,
    required String authorPubkey,
  }) async {
    if (!_isStoryContact(authorPubkey)) return true;
    if (store.isTombstoned(storyId, authorPubkey)) return true;

    final existing = store.getById(storyId);
    if (existing != null && existing.authorPubkey == authorPubkey) {
      await store.delete(storyId);
      _deleteLocalMediaBestEffort(existing.localPath);
      notify();
    }
    await store.putTombstone(
      storyId,
      authorPubkey,
      DateTime.now().millisecondsSinceEpoch +
          StoryItem.defaultDuration.inMilliseconds,
    );
    return true;
  }

  Future<void> markViewed(StoryItem story, {RelayManager? relay}) async {
    final myPubkey = AppSettings.instance.myPubkey;
    if (myPubkey.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final alreadyViewed = story.viewedBy.containsKey(myPubkey);
    if (!alreadyViewed) {
      await store.markViewed(story.id, myPubkey, nowMs);
    }
    // A repeat view has no box change to notify listeners, so bump the
    // revision anyway or the ring can stay stale until an unrelated rebuild.
    notify();
    if (relay == null) return;
    if (story.authorPubkey.isEmpty || story.authorPubkey == myPubkey) return;
    try {
      await relay.sendStoryViewReceipt(
        storyId: story.id,
        authorPubkey: story.authorPubkey,
      );
    } catch (e) {
      DebugLogger.log('[Story] View receipt send failed | $e', type: 'WARN');
    }
  }

  Future<bool> handleIncomingViewReceipt({
    required String senderPubkey,
    required String storyId,
    required int viewedAtMs,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    if (myPubkey.isEmpty || senderPubkey.isEmpty) return false;
    if (senderPubkey == myPubkey) return false;
    if (!StoryEvent.isValidStoryId(storyId)) return false;
    final story = store.getById(storyId);
    if (story == null) return false;
    if (story.authorPubkey != myPubkey) return false;
    if (story.viewedBy.containsKey(senderPubkey)) return false;
    await store.markViewed(storyId, senderPubkey, viewedAtMs);
    notify();
    return true;
  }

  Future<String?> ensureLocalMedia(StoryItem story, {http.Client? client}) async {
    // Old Hive rows may predate id validation. Never let one become a path.
    if (!StoryEvent.isValidStoryId(story.id)) return null;
    if (story.localPath.isNotEmpty && await File(story.localPath).exists()) {
      return story.localPath;
    }
    try {
      final bytes = await BlossomService.download(story.mediaUrl, client: client);
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
      // The caller holds a snapshot from before markViewed ran. Re-read the
      // stored row so caching the path cannot revert a freshly recorded view.
      final current = store.getById(story.id);
      if (current != null) {
        await store.put(current.copyWith(localPath: file.path));
        notify();
      }
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
