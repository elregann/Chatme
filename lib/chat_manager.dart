// chat_manager.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'notification_handler.dart';
import 'services/app_settings.dart';
import 'services/file_send_service.dart';
import 'services/file_transfer_service.dart';
import 'services/image_prepare.dart';
import 'services/media_storage.dart';
import 'services/video_thumbnails.dart';
import 'services/voice_storage.dart';
import 'models/contact.dart';
import 'core/utils/debug_logger.dart';
import 'core/utils/sync_gate.dart';
import 'core/utils/temp_id.dart';
import 'models/chat_message.dart';
import 'services/nostr_service.dart';
import 'relay_manager.dart';
import 'core/utils/bg_inbox.dart';

/// Owns the local chat storage.
///
/// Storage layout v2:
///  - `chat_msgs` box: one key per message,
///    `"<chatKey>\x1f<eventId>" -> ChatMessage`. Writing a message is O(1)
///    no matter how long the chat is, which keeps restores and long
///    conversations cheap (v1 rewrote the whole List under one key).
///  - `chats` box: a small registry, `chatKey -> epoch millis` of the last
///    write. The chat list listens to it and rebuilds once per flush.
///
/// `migrateLegacyChats()` moves v1 data (whole lists under `chatKey`) into
/// the new layout once, per chat, and only deletes a legacy list after all
/// of its messages were written — so an interrupted migration simply
/// resumes on the next start.
class ChatManager {
  static final ChatManager _instance = ChatManager._internal();
  factory ChatManager() => _instance;
  ChatManager._internal();

  static ChatManager get instance => _instance;
  final _lock = Lock();

  static const Map<String, int> _statusWeight = {
    'pending': -2,
    'error': -1,
    'sending': 0,
    'sent': 1,
    'read': 2,
  };

  int _getStatusWeight(String status) => _statusWeight[status] ?? 0;

  /// How many of the newest unread messages are acknowledged to the sender
  /// with a read receipt. Older history is only marked read locally: one
  /// receipt means one NIP-17 wrap (ECDH + signature) on the UI isolate, so
  /// acknowledging a whole restored backlog would freeze the app. Matches
  /// the cap already used by the notification-action path.
  static const int maxReadReceipts = 20;

  // ---------------------------------------------------------------- Layout

  /// Separator between chatKey and message id inside a `chat_msgs` key.
  /// Neither part can contain a control character, so it never collides.
  static const String messageKeySeparator = '\x1f';

  /// Public so tests and the notification-action isolate can build keys.
  ///
  /// This builds a key from a *storage identity*: for local sends that is the
  /// stable [ChatMessage.localId]; for incoming / legacy messages, where
  /// `localId` is empty, it is the canonical event ID. Prefer
  /// [messageStorageKeyFor] when a [ChatMessage] is at hand so the two never
  /// drift apart.
  static String messageStorageKey(String chatKey, String messageId) =>
      '$chatKey$messageKeySeparator$messageId';

  /// The stable storage key of [m]. A local send keeps its `temp_<ms>`
  /// identity for the lifetime of the bubble; the canonical Rumor ID lives in
  /// [ChatMessage.id] and is looked up through the alias index below.
  static String messageStorageKeyFor(ChatMessage m) =>
      messageStorageKey(m.chatKey, m.localId.isNotEmpty ? m.localId : m.id);

  Box<ChatMessage> get _messagesBox => Hive.box<ChatMessage>('chat_msgs');

  /// Canonical event ID -> stable storage identity, scoped per chat.
  ///
  /// The key is `<chatKey>\x1f<eventId>` and the value is the `localId` used
  /// as the Hive key suffix. Built lazily from the box (one scan), then kept
  /// in sync under [_lock] whenever an ID is swapped or a message is saved.
  /// It is never persisted: the box itself is the source of truth, and a
  /// fresh map is rebuilt on next access after a hot restart.
  final Map<String, String> _aliasToLocalId = {};
  bool _aliasIndexBuilt = false;

  String _aliasKey(String chatKey, String eventId) =>
      '$chatKey$messageKeySeparator$eventId';

  void _ensureAliasIndex() {
    if (_aliasIndexBuilt) return;
    _aliasIndexBuilt = true;
    try {
      for (final m in _messagesBox.values) {
        if (m.id.isEmpty || m.localId.isEmpty) continue;
        _aliasToLocalId[_aliasKey(m.chatKey, m.id)] = m.localId;
      }
    } catch (_) {}
  }

  void _indexAlias(ChatMessage m) {
    if (m.id.isEmpty || m.localId.isEmpty) return;
    _aliasToLocalId[_aliasKey(m.chatKey, m.id)] = m.localId;
  }

  /// Drops the in-memory alias cache. Called when the message box is wiped
  /// (account logout / switch) so stale aliases from the previous account
  /// cannot resolve to keys that no longer exist. The map rebuilds lazily on
  /// the next read from the box, which is the source of truth.
  void resetAliasIndex() {
    _aliasToLocalId.clear();
    _aliasIndexBuilt = false;
  }

  /// Resolves a caller-supplied event ID (or a legacy local ID) to the stable
  /// Hive key. Returns `null` when the message is not stored.
  String? _resolveStorageKey(String eventId, String chatKey) {
    _ensureAliasIndex();
    final alias = _aliasToLocalId[_aliasKey(chatKey, eventId)];
    final candidates = <String>{
      if (alias != null) messageStorageKey(chatKey, alias),
      messageStorageKey(chatKey, eventId),
    };
    for (final key in candidates) {
      if (_messagesBox.containsKey(key)) return key;
    }
    return null;
  }

  /// Like [messageStorageKey] but resolves canonical IDs through the alias
  /// index. Use this everywhere a caller passes an event ID; keeps callers
  /// unchanged while the underlying key stays stable.
  String _storageKeyForId(String messageId, String chatKey) =>
      _resolveStorageKey(messageId, chatKey) ??
      messageStorageKey(chatKey, messageId);

  Box get _registryBox => Hive.box('chats');

  /// Marks a chat as recently written. The chat list rebuilds on this.
  Future<void> touchChatRegistry(String chatKey) async {
    try {
      await _registryBox.put(chatKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// All chats that have at least one stored message.
  Iterable<String> allChatKeys() =>
      _registryBox.keys.map((k) => k.toString());

  /// Every stored message (values are cached in memory by Hive).
  List<ChatMessage> allMessagesSync() => _messagesBox.values.toList();

  // ------------------------------------------------------------- Migration

  /// Moves legacy v1 chat lists (`chats` box, `chatKey -> List<ChatMessage>`)
  /// into the v2 layout. Idempotent: a chat whose list was already moved is
  /// skipped message-by-message, so an interrupted run resumes cleanly.
  Future<void> migrateLegacyChats() async {
    try {
      final legacyKeys = _registryBox.keys
          .map((k) => k.toString())
          .where((k) => _registryBox.get(k) is List)
          .toList();
      if (legacyKeys.isEmpty) return;

      var migrated = 0;
      for (final chatKey in legacyKeys) {
        final raw = _registryBox.get(chatKey);
        if (raw is! List) continue;

        for (final m in raw.cast<ChatMessage>()) {
          final effectiveChatKey =
              m.chatKey.isNotEmpty ? m.chatKey : chatKey;
          final key = messageStorageKey(effectiveChatKey, m.id);
          // Put-if-absent: never clobber a newer live update with the
          // legacy copy (e.g. a read receipt applied after a partial
          // migration).
          if (!_messagesBox.containsKey(key)) {
            await _messagesBox.put(key, m);
            migrated++;
          }
        }

        // Only after every message of this chat is safe in v2, replace the
        // legacy list with a registry entry.
        await _registryBox.put(chatKey, DateTime.now().millisecondsSinceEpoch);
        DebugLogger.log('[Migration] Moved ${raw.length} message(s) for $chatKey');
      }

      if (migrated > 0) {
        DebugLogger.log('[Migration] Storage v2 done: $migrated message(s)');
        try {
          // Reclaim the space left by the legacy lists (one-time cost).
          await _registryBox.compact();
        } catch (_) {}
      }
    } catch (e) {
      DebugLogger.log('[Migration] Failed | $e', type: 'ERROR');
    }
  }

  // ------------------------------------------------------------------ Read

  /// Messages of one chat, oldest first. Synchronous: a non-lazy Hive box
  /// caches every value in memory after open.
  List<ChatMessage> messagesForChatSync(String chatKey) {
    try {
      final prefix = '$chatKey$messageKeySeparator';
      final out = <ChatMessage>[];
      for (final k in _messagesBox.keys) {
        if (k is String && k.startsWith(prefix)) {
          final m = _messagesBox.get(k);
          if (m != null) out.add(m);
        }
      }
      out.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return out;
    } catch (_) {
      return [];
    }
  }

  ChatMessage? getMessageByIdSync(String eventId, String chatKey) {
    try {
      final key = _resolveStorageKey(eventId, chatKey);
      return key == null ? null : _messagesBox.get(key);
    } catch (_) {
      return null;
    }
  }

  Future<ChatMessage?> getMessageById(String eventId, String chatKey) async =>
      getMessageByIdSync(eventId, chatKey);

  Future<bool> isMessageExists(String messageId, String chatKey) async {
    try {
      return _resolveStorageKey(messageId, chatKey) != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<ChatMessage>> getMessages(String peerPubkey) async {
    try {
      final chatKey = getChatKey(AppSettings.instance.myPubkey, peerPubkey);
      return messagesForChatSync(chatKey);
    } catch (_) {
      return [];
    }
  }

  String getChatKey(String pubkey1, String pubkey2) {
    final sorted = [pubkey1, pubkey2]..sort();
    return 'chat_${sorted[0]}_${sorted[1]}';
  }

  // ------------------------------------------------------------- Listenable

  final Map<String, _ChatMessagesListenable> _chatListenables = {};

  /// Notifies only when a message of THIS chat is written. A plain
  /// `box.listenable()` would rebuild an open room for every message saved
  /// anywhere else — e.g. the whole backlog of an account restore.
  ValueListenable<Box<ChatMessage>> chatMessagesListenable(String chatKey) {
    return _chatListenables.putIfAbsent(
      chatKey,
      () => _ChatMessagesListenable(
        _messagesBox,
        '$chatKey$messageKeySeparator',
      ),
    );
  }

  // ------------------------------------------------------------------ Save

  /// Returns `true` if the message was newly inserted, `false` if it
  /// already existed and was merged in place. Callers use this to avoid
  /// double-incrementing the unread badge when a duplicate event arrives
  /// from multiple relays (race condition).
  ///
  /// [touchChatList] and [updateContactPreview] exist so the relay burst
  /// drain can defer the UI-side writes (registry + contact preview) and
  /// flush them once per batch instead of once per message.
  /// [notify] is false only for the FCM handoff drain: that message already
  /// notified the user from the background isolate.
  Future<bool> saveMessage(
    ChatMessage message, {
    bool touchChatList = true,
    bool updateContactPreview = true,
    bool notify = true,
  }) async {
    bool wasNew = false;
    await _lock.synchronized(() async {
      try {
        final chatKey = message.chatKey.isNotEmpty
            ? message.chatKey
            : getChatKey(message.senderPubkey, message.receiverPubkey);

        // If this message was marked as read while in background, preserve 'read' status
        if (message.status != 'read') {
          try {
            if (await BgInbox.isMarkedRead(message.senderPubkey, message.id)) {
              message = message.copyWith(status: 'read');
              await BgInbox.consumeRead(message.senderPubkey, message.id);
            }
          } catch (_) {}
        }

        final effective = message.chatKey == chatKey
            ? message
            : message.copyWith(chatKey: chatKey);

        // A local send carries its permanent localId and keeps writing to
        // that same key. An incoming/self-wrap copy carries only the canonical
        // ID: resolve it through the alias index first, otherwise it would be
        // stored under a *second* key and appear as a duplicate bubble (the
        // FCM handoff path has no isMessageExists pre-check).
        final key = message.localId.isNotEmpty
            ? messageStorageKeyFor(effective)
            : _storageKeyForId(message.id, chatKey);
        final existing = _messagesBox.get(key);

        if (existing != null) {
          final String finalStatus =
              (_getStatusWeight(existing.status) > _getStatusWeight(message.status))
                  ? existing.status
                  : message.status;

          await _messagesBox.put(
            key,
            existing.copyWith(
              status: finalStatus,
              replyToContent: message.replyToContent?.isNotEmpty == true
                  ? message.replyToContent
                  : existing.replyToContent,
              plaintext: message.plaintext.isNotEmpty
                  ? message.plaintext
                  : existing.plaintext,
              content: message.content.isNotEmpty
                  ? message.content
                  : existing.content,
              timestamp: message.timestamp,
              reactions: message.reactions.isNotEmpty
                  ? message.reactions
                  : existing.reactions,
              giftWrapId: message.giftWrapId.isNotEmpty
                  ? message.giftWrapId
                  : existing.giftWrapId,
              localId: message.localId.isNotEmpty
                  ? message.localId
                  : existing.localId,
            ),
          );
        } else {
          await _messagesBox.put(key, effective);
          wasNew = true;

          if (notify &&
              message.senderPubkey != AppSettings.instance.myPubkey) {
            Future.microtask(() => _triggerNotification(message));
          }
        }

        _indexAlias(_messagesBox.get(key) ?? effective);

        if (touchChatList) await touchChatRegistry(chatKey);
        if (updateContactPreview) await _updateContactPreview(message);
      } catch (e) {
        DebugLogger.log('[Message] Save failed | $e', type: 'ERROR');
      }
    });
    return wasNew;
  }

  /// Persists a locally generated call bubble and returns its chat key only
  /// when the bubble really exists. Callers use the key as the go-ahead to
  /// write a call-log row, so the two views can never drift apart.
  Future<String?> saveCallBubble({
    required String myPubkey,
    required String peerPubkey,
    required String direction,
    required int durationSeconds,
    required int timestampMs,
    bool notify = true,
  }) async {
    if (myPubkey.isEmpty || peerPubkey.isEmpty) return null;

    final chatKey = getChatKey(myPubkey, peerPubkey);
    final id = 'call_$timestampMs';
    final content = '[CALL]:$direction:voice:duration:$durationSeconds';
    final isIncoming = direction == 'incoming' || direction == 'missed';

    try {
      await saveMessage(
        ChatMessage(
          id: id,
          senderPubkey: isIncoming ? peerPubkey : myPubkey,
          receiverPubkey: isIncoming ? myPubkey : peerPubkey,
          content: content,
          plaintext: content,
          timestamp: timestampMs,
          status: 'read',
          chatKey: chatKey,
        ),
        notify: notify,
      );
      return await isMessageExists(id, chatKey) ? chatKey : null;
    } catch (e) {
      DebugLogger.log('[Call] Save call bubble failed | $e', type: 'ERROR');
      return null;
    }
  }

  void _triggerNotification(ChatMessage message) async {
    if (kIsWeb) return;

    // The initial sync (account restore / first login) is pulling history,
    // not fresh conversation: stay silent until the gate ends.
    if (SyncGate.isActive) return;

    try {
      // Call log messages ([CALL]:...) are generated locally on both
      // devices when a call ends. Only missed calls should trigger a
      // notification — a call that connected has already been seen by the
      // user, and notifying the receiver that their call just ended
      // is confusing. Missed calls get a clean label instead of the raw
      // `[CALL]:missed:voice:duration:0` payload.
      final isCallLog = message.plaintext.startsWith('[CALL]:');
      final isMissedCall = message.plaintext.startsWith('[CALL]:missed:');
      if (isCallLog && !isMissedCall) return;

      final settingsBox = Hive.box('settings');

      // Use the Gift Wrap ID for notification dedup because the background
      // FCM handler stores its "notified_<eventId>" flag using the
      // gift-wrap ID (that's what the Cloudflare worker sends). Falling
      // back to the canonical message ID when no gift-wrap ID is present
      // (legacy NIP-04 messages) keeps behaviour consistent.
      final dedupKey = message.giftWrapId.isNotEmpty
          ? message.giftWrapId
          : message.id;

      final alreadyNotified = settingsBox.get('notified_$dedupKey', defaultValue: false) as bool;
      if (alreadyNotified) {
        await settingsBox.delete('notified_$dedupKey');
        return;
      }

      final contact = Hive.box<Contact>('contacts').get(message.senderPubkey);
      final senderName = contact?.displayName ?? AppSettings.formatDisplayName(message.senderPubkey);

      // Missed calls get a clean label instead of the raw payload.
      final notifBody = isMissedCall ? 'Missed Call' : message.plaintext;

      NotificationHandler.showChatNotification(
        senderPubkey: message.senderPubkey,
        senderName: senderName,
        message: notifBody,
        // The dedup flag above stays keyed by the worker's event id, but the
        // stack key must survive a re-wrap with a different Gift Wrap id.
        messageId: message.id.isNotEmpty ? message.id : dedupKey,
        replyOnly: isMissedCall,
      );
    } catch (e) {
      DebugLogger.log('[Notification] Trigger failed | $e', type: 'ERROR');
    }
  }

  // --------------------------------------------------------------- Updates

  Future<bool> updateMessageStatus(String messageId, String newStatus, {String? chatKey}) async {
    bool found = false;
    await _lock.synchronized<void>(() async {
      try {
        if (chatKey != null) {
          final key = _resolveStorageKey(messageId, chatKey) ??
              messageStorageKey(chatKey, messageId);
          found = await _applyStatus(key, newStatus);
        } else {
          // No chat key: look up by canonical ID across the alias index first
          // (O(1)), then fall back to a key-suffix scan for legacy rows whose
          // ID *is* the key.
          _ensureAliasIndex();
          for (final entry in _aliasToLocalId.entries) {
            if (!entry.key.endsWith('$messageKeySeparator$messageId')) continue;
            final chat = entry.key.substring(0,
                entry.key.lastIndexOf(messageKeySeparator));
            found = await _applyStatus(
                    messageStorageKey(chat, entry.value), newStatus) ||
                found;
          }
          final direct = '$messageKeySeparator$messageId';
          for (final k in _messagesBox.keys.toList()) {
            if (k is String && k.endsWith(direct)) {
              found = await _applyStatus(k, newStatus) || found;
            }
          }
        }
      } catch (e) {
        DebugLogger.log('[Message] Status update failed | $e', type: 'ERROR');
      }
    });
    return found;
  }

  Future<bool> _applyStatus(String storageKey, String newStatus) async {
    final m = _messagesBox.get(storageKey);
    if (m == null) return false;
    if (_getStatusWeight(newStatus) > _getStatusWeight(m.status)) {
      await _messagesBox.put(storageKey, m.copyWithStatus(newStatus));
    }
    return true;
  }

  /// Forces a message to `pending` when an optimistic send failed, without
  /// the monotonic status gate (a failed `sending` message must be allowed to
  /// fall back to `pending`). Keeps the stable key — one in-place put, no
  /// delete-and-recreate, so the bubble never disappears and reappears.
  Future<void> markMessagePending(String messageId, String chatKey) async {
    await _lock.synchronized<void>(() async {
      try {
        final key = _storageKeyForId(messageId, chatKey);
        final m = _messagesBox.get(key);
        if (m == null) return;
        await _messagesBox.put(key, m.copyWithStatus('pending'));
      } catch (e) {
        DebugLogger.log('[Message] Mark pending failed | $e', type: 'ERROR');
      }
    });
  }

  /// Non-monotonic counterpart of [updateMessageStatusByGiftWrap]: only a
  /// `sending` row may fall back to `pending` after a relay rejection.
  Future<void> markPendingByGiftWrap(String giftWrapId) async {
    if (giftWrapId.isEmpty) return;
    await _lock.synchronized<void>(() async {
      try {
        for (final m in _messagesBox.values.toList()) {
          if (m.giftWrapId != giftWrapId) continue;
          if (m.status != 'sending') return;
          await _messagesBox.put(
            messageStorageKeyFor(m),
            m.copyWithStatus('pending'),
          );
          return;
        }
      } catch (e) {
        DebugLogger.log('[Message] Mark pending by wrap failed | $e', type: 'ERROR');
      }
    });
  }

  /// Updates the status of a message identified by its **Gift Wrap ID**.
  ///
  /// This is used to process relay `["OK", <giftWrapId>, true]` acknowledgements.
  /// Because the Gift Wrap ID changes every time a message is re-sent with
  /// a fresh ephemeral key, this method must be called before the message
  /// is re-queued (i.e. while its status is still `sending`).
  ///
  /// Status transitions follow the same monotonic weighting as
  /// [updateMessageStatus] — a `sent` update will not overwrite a `read`.
  Future<void> updateMessageStatusByGiftWrap(String giftWrapId, String newStatus) async {
    if (giftWrapId.isEmpty) return;
    await _lock.synchronized<void>(() async {
      try {
        for (final m in _messagesBox.values.toList()) {
          if (m.giftWrapId != giftWrapId) continue;

          if (_getStatusWeight(newStatus) > _getStatusWeight(m.status)) {
            await _messagesBox.put(
              messageStorageKeyFor(m),
              m.copyWithStatus(newStatus),
            );
            DebugLogger.log('[Message] GiftWrap status updated: $giftWrapId -> $newStatus');
          }
          return;
        }
      } catch (e) {
        DebugLogger.log('[Message] GiftWrap status update failed | $e', type: 'ERROR');
      }
    });
  }

  Future<void> setFile(String messageId, String chatKey, Map<String, String> file) async {
    await _lock.synchronized<void>(() async {
      try {
        final key = _storageKeyForId(messageId, chatKey);
        final m = _messagesBox.get(key);
        if (m == null) return;
        await _messagesBox.put(key, m.copyWith(file: file));
      } catch (e) {
        DebugLogger.log('[Message] Set file failed | $e', type: 'ERROR');
      }
    });
  }

  Future<void> setLocalPath(String messageId, String chatKey, String path) async {
    await _lock.synchronized<void>(() async {
      try {
        final key = _storageKeyForId(messageId, chatKey);
        final m = _messagesBox.get(key);
        if (m == null) return;
        await _messagesBox.put(key, m.copyWith(localPath: path));
      } catch (e) {
        DebugLogger.log('[Message] Set local path failed | $e', type: 'ERROR');
      }
    });
  }

  /// Stores a (pending) reaction on a message, e.g. when the local user
  /// taps an emoji. Remote reactions from NIP-25 use [mergeReaction].
  Future<void> setMessageReaction({
    required String chatKey,
    required String messageId,
    required String reactorPubkey,
    required String emoji,
  }) async {
    await _lock.synchronized<void>(() async {
      try {
        final key = _storageKeyForId(messageId, chatKey);
        final m = _messagesBox.get(key);
        if (m == null) return;
        await _messagesBox.put(
          key,
          m.copyWith(
            reactions: {...m.reactions, reactorPubkey: emoji},
            pendingReactions: {...m.pendingReactions, reactorPubkey: emoji},
          ),
        );
      } catch (_) {}
    });
  }

  /// Applies a remote reaction (NIP-25 over NIP-17). Returns true when the
  /// target message exists.
  Future<bool> mergeReaction({
    required String chatKey,
    required String messageId,
    required String reactorPubkey,
    required String emoji,
  }) async {
    try {
      final key = _storageKeyForId(messageId, chatKey);
      final m = _messagesBox.get(key);
      if (m == null) {
        DebugLogger.log('[Reaction] Target message not found: $messageId', type: 'WARN');
        return false;
      }
      await _messagesBox.put(
        key,
        m.copyWith(reactions: {...m.reactions, reactorPubkey: emoji}),
      );
      return true;
    } catch (e) {
      DebugLogger.log('[Reaction] Update failed | $e', type: 'ERROR');
      return false;
    }
  }

  /// Removes a pending reaction once its gift wrap got an OK from a relay.
  Future<void> removePendingReaction({
    required String chatKey,
    required String messageId,
    required String reactorPubkey,
  }) async {
    await _lock.synchronized<void>(() async {
      try {
        final key = _storageKeyForId(messageId, chatKey);
        final m = _messagesBox.get(key);
        if (m == null) return;
        final pending = Map<String, String>.from(m.pendingReactions)
          ..remove(reactorPubkey);
        await _messagesBox.put(key, m.copyWith(pendingReactions: pending));
      } catch (_) {}
    });
  }

  Future<List<ChatMessage>> getPendingMessages() async {
    List<ChatMessage> pendingQueue = [];
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var m in _messagesBox.values) {
        final bool isPending = m.status == 'pending';
        final bool isError = m.status == 'error';
        // A `sending` message that still needs its file uploaded belongs to
        // the send that started it. Taking it here would encrypt and upload
        // the same file a second time, and that copy would get its own Rumor
        // ID, so the receiver (and our own self-wrap) would show a second
        // bubble. Failed sends are stored as `pending` and still retried.
        final bool isStuckSending = m.status == 'sending' &&
            !m.needsUpload &&
            (now - m.timestamp) > 10000;

        if (isPending || isError || isStuckSending) {
          pendingQueue.add(m);
        }
      }
      pendingQueue.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      DebugLogger.log('[Queue] Load pending failed | $e', type: 'ERROR');
    }
    return pendingQueue;
  }

  /// Replaces a message's local ID with the canonical ID assigned after
  /// NIP-17 wrapping, and optionally updates its Gift Wrap ID and status.
  ///
  /// For a fresh send, [oldId] is the local `temp_<ms>` placeholder and
  /// [newId] is the Rumor ID. [newGiftWrapId] is the outer Gift Wrap ID.
  ///
  /// For a queue retry, [oldId] and [newId] may be the same Rumor ID (since
  /// the Rumor is rebuilt deterministically from the same content + reply
  /// info... actually no, `_realTimestamp` differs each call, so the Rumor
  /// ID will also change on each retry — hence the update path is still
  /// needed for retries too).
  Future<void> updateMessageIdAndStatus(
      String oldId,
      String newId,
      String status,
      String chatKey, {
        String? newContent,
        String? newGiftWrapId,
      }) async {
    await _lock.synchronized(() async {
      try {
        // Resolve through the alias index: `oldId` may be the original local
        // ID (fresh send) or a previous Rumor ID (queue retry). Either way it
        // maps to the same stable Hive key.
        final oldKey = _resolveStorageKey(oldId, chatKey) ??
            messageStorageKey(chatKey, oldId);
        final current = _messagesBox.get(oldKey);
        if (current == null) return;

        final String finalStatus =
            (current.status == 'read' && (status == 'sent' || status == 'pending' || status == 'sending'))
                ? 'read'
                : status;

        // The first time a local/legacy row is reconciled, freeze its old key
        // suffix as the permanent storage identity. Retries already have one,
        // so they keep it. This single in-place put replaces the old
        // put(newKey)/delete(oldKey) pair — no new Hive key, no bubble flap.
        final stableLocalId =
            current.localId.isNotEmpty ? current.localId : oldId;

        final updated = current.copyWith(
          id: newId,
          status: finalStatus,
          giftWrapId: (newGiftWrapId != null && newGiftWrapId.isNotEmpty)
              ? newGiftWrapId
              : current.giftWrapId,
          content: (newContent != null && newContent.isNotEmpty)
              ? newContent
              : current.content,
          localId: stableLocalId,
        );
        await _messagesBox.put(oldKey, updated);
        _indexAlias(updated);

        // Repair: any message that replied to the old ID now points to the
        // canonical one. These are incoming messages, so their key is their
        // own event ID (no localId) — but resolve defensively in case a local
        // reply was also reconciled.
        for (final m in messagesForChatSync(chatKey)) {
          if (m.id == newId || m.replyToId != oldId) continue;
          final replyKey = _resolveStorageKey(m.id, chatKey) ??
              messageStorageKey(chatKey, m.id);
          await _messagesBox.put(
            replyKey,
            m.copyWith(replyToId: newId),
          );
        }

        await touchChatRegistry(chatKey);
        DebugLogger.log('[Message] ID updated in place: $oldId -> $newId ($finalStatus)');
      } catch (e) {
        DebugLogger.log('[Message] ID & status update failed | $e', type: 'ERROR');
      }
    });
  }

  /// Scan all messages in a chat and repair any replyToContent
  /// that is still empty. Called after a batch of messages arrives,
  /// to handle out-of-order event delivery from relays.
  Future<void> repairPendingReplies(String chatKey) async {
    try {
      var changed = 0;
      for (final m in messagesForChatSync(chatKey)) {
        final needsRepair = (m.replyToId != null && m.replyToId!.isNotEmpty) &&
            (m.replyToContent == null || m.replyToContent!.isEmpty);
        if (!needsRepair) continue;

        final original = getMessageByIdSync(m.replyToId!, chatKey);
        if (original == null) continue;

        await _messagesBox.put(
          messageStorageKeyFor(m),
          m.copyWith(
            replyToContent: original.plaintext,
            replyToSenderPubkey: original.senderPubkey,
          ),
        );
        changed++;
      }

      if (changed > 0) {
        DebugLogger.log('[Message] Repaired $changed pending repl(ies) in $chatKey');
      }
    } catch (e) {
      DebugLogger.log('[Message] Repair pending replies failed | $e', type: 'ERROR');
    }
  }

  Future<void> _updateContactPreview(ChatMessage message) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final myPubkey = AppSettings.instance.myPubkey;
      final peerPubkey = (message.senderPubkey == myPubkey) ? message.receiverPubkey : message.senderPubkey;

      var contact = contactsBox.get(peerPubkey);
      if (contact == null) {
        contact = Contact(
          pubkey: peerPubkey,
          name: '',
          isSaved: false,
          lastMessage: message.plaintext,
          lastChatTime: message.timestamp,
        );
        await contactsBox.put(peerPubkey, contact);
      } else if (message.timestamp >= contact.lastChatTime) {
        contact.lastMessage = message.plaintext;
        contact.lastChatTime = message.timestamp;
        await contactsBox.put(peerPubkey, contact);
      }
    } catch (e) {
      DebugLogger.log('[Contact] Preview update failed | $e', type: 'ERROR');
    }
  }

  /// Marks every unread incoming message from [peerPubkey] as read and
  /// returns the ids that should be acknowledged to the sender, newest
  /// first, capped at [maxReceipts].
  ///
  /// Only this newest slice gets a read receipt. The rest of the history is
  /// marked read locally in one batch, so opening a long / restored chat
  /// cannot fire hundreds of NIP-17 wraps on the UI isolate. Callers must
  /// send the receipts after this returns; the local status is already
  /// correct even if a receipt fails.
  Future<List<String>> markIncomingAsRead({
    required String peerPubkey,
    int maxReceipts = maxReadReceipts,
  }) async {
    final receiptIds = <String>[];
    try {
      final chatKey = getChatKey(AppSettings.instance.myPubkey, peerPubkey);
      await _lock.synchronized(() async {
        // messagesForChatSync returns oldest first.
        final unread = messagesForChatSync(chatKey)
            .where((m) => m.senderPubkey == peerPubkey && m.status != 'read')
            .toList();
        if (unread.isEmpty) return;

        for (var i = unread.length - 1;
            i >= 0 && receiptIds.length < maxReceipts;
            i--) {
          receiptIds.add(unread[i].id);
        }

        final updates = <String, ChatMessage>{
          for (final m in unread) messageStorageKeyFor(m): m.copyWithStatus('read'),
        };
        await _messagesBox.putAll(updates);
      });
    } catch (e) {
      DebugLogger.log('[Chat] Mark incoming read failed | $e', type: 'ERROR');
    }
    return receiptIds;
  }

  Future<void> clearUnreadCount(String peerPubkey) async {
    await _lock.synchronized<void>(() async {
      try {
        final contactsBox = Hive.box<Contact>('contacts');
        final contact = contactsBox.get(peerPubkey);
        if (contact != null && contact.unreadCount > 0) {
          contact.unreadCount = 0;
          await contactsBox.put(peerPubkey, contact);
        }
        NotificationHandler.clearNotification(peerPubkey);
      } catch (_) {}
    });
  }

  // --------------------------------------------------------------- Deletes

  Future<void> deleteMessage(String messageId, String chatKey) async {
    await _lock.synchronized(() async {
      try {
        final key = _storageKeyForId(messageId, chatKey);
        if (_messagesBox.containsKey(key)) {
          await _messagesBox.delete(key);
          await touchChatRegistry(chatKey);
          DebugLogger.log('[Message] Deleted: $messageId');
        }
      } catch (_) {}
    });
  }

  /// Removes one message from this device and brings the chat list preview
  /// back in line with what is left. [deleteMessage] alone is for internal
  /// swaps of temporary messages and leaves the preview untouched.
  Future<void> deleteMessageForMe(String messageId, String chatKey) async {
    await deleteMessage(messageId, chatKey);
    await _lock.synchronized(() => _syncContactPreview(chatKey));
  }

  Future<void> _syncContactPreview(String chatKey) async {
    try {
      final parts = chatKey.split('_');
      if (parts.length != 3) return;
      final myPubkey = AppSettings.instance.myPubkey;
      final peerPubkey = (parts[1] == myPubkey) ? parts[2] : parts[1];

      final contactsBox = Hive.box<Contact>('contacts');
      final contact = contactsBox.get(peerPubkey);
      if (contact == null) return;

      final remaining = messagesForChatSync(chatKey);
      if (remaining.isEmpty) {
        contact.lastMessage = '';
        contact.lastChatTime = 0;
      } else {
        final last = remaining.last;
        contact.lastMessage = last.plaintext;
        contact.lastChatTime = last.timestamp;
      }
      await contactsBox.put(peerPubkey, contact);
    } catch (e) {
      DebugLogger.log('[Contact] Preview sync failed | $e', type: 'ERROR');
    }
  }

  Future<void> deleteChatHistory(String chatKey) async {
    try {
      final prefix = '$chatKey$messageKeySeparator';
      final toDelete = _messagesBox.keys
          .whereType<String>()
          .where((k) => k.startsWith(prefix))
          .toList();
      for (final k in toDelete) {
        await _messagesBox.delete(k);
      }
      await _registryBox.delete(chatKey);

      final parts = chatKey.split('_');
      if (parts.length == 3) {
        final myPubkey = AppSettings.instance.myPubkey;
        final peerPubkey = (parts[1] == myPubkey) ? parts[2] : parts[1];
        await Hive.box('settings').put('cut_off_$peerPubkey', DateTime.now().millisecondsSinceEpoch);

        final contactsBox = Hive.box<Contact>('contacts');
        final contact = contactsBox.get(peerPubkey);
        if (contact != null) {
          contact.lastMessage = '';
          contact.lastChatTime = 0;
          contact.unreadCount = 0;
          await contactsBox.put(peerPubkey, contact);
        }
      }
    } catch (e) {
      DebugLogger.log('[Chat] Delete history failed | $e', type: 'ERROR');
    }
  }

  Future<void> cleanupTempMessages() async {
    await _lock.synchronized<void>(() async {
      try {
        var removed = 0;
        final touchedChats = <String>{};
        for (final k in _messagesBox.keys.toList()) {
          if (k is! String) continue;
          final m = _messagesBox.get(k);
          if (m == null || !m.id.startsWith('temp_')) continue;
          // A failed local send keeps its `temp_` identity now (it is no
          // longer renamed to `pending_`). Those rows are the offline queue:
          // deleting them here silently loses messages the user expects to
          // be delivered on the next reconnect. Only drop sends that were
          // interrupted before any retry state was recorded.
          if (m.status == 'pending' || m.status == 'error') continue;
          await _messagesBox.delete(k);
          removed++;
          touchedChats.add(m.chatKey);
        }
        for (final chatKey in touchedChats) {
          await touchChatRegistry(chatKey);
        }
        if (removed > 0) {
          DebugLogger.log('[Cleanup] Removed $removed temp message(s)');
        }
      } catch (_) {}
    });
  }

  // ------------------------------------------------- Outgoing send helpers

  static Future<void> sendReplyFromNotification({
    required String receiverPubkey,
    required String plaintext,
    required RelayManager relayManager,
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final chatKey = ChatManager.instance.getChatKey(myPubkey, receiverPubkey);
      final messageTs = DateTime.now().millisecondsSinceEpoch;
      final tempId = newTempId(messageTs);

      final tempMessage = ChatMessage(
        id: tempId,
        localId: tempId,
        senderPubkey: myPubkey,
        receiverPubkey: receiverPubkey,
        content: '',
        plaintext: plaintext,
        timestamp: messageTs,
        status: 'sending',
        chatKey: chatKey,
      );

      await ChatManager.instance.saveMessage(tempMessage);

      final event = await relayManager.sendMessage(
        receiverPubkey: receiverPubkey,
        plaintext: plaintext,
        messageTimestampMs: messageTs,
      );

      // Reconcile in place: the stable localId keeps the same Hive key while
      // the canonical Rumor ID and Gift Wrap ID are written into the row.
      await ChatManager.instance.updateMessageIdAndStatus(
        tempId,
        event['rumorId'].toString(),
        'sending',
        chatKey,
        newContent: (event['giftWrap'] as Map<String, dynamic>)['content'].toString(),
        newGiftWrapId: event['giftWrapId'].toString(),
      );
      NotificationHandler.clearNotification(receiverPubkey);

    } catch (e) {
      DebugLogger.log('[Notification] Reply send failed | $e', type: 'ERROR');
    }
  }

  /// Saves a recorded voice note in the chat right away, then uploads and sends
  /// it. When that fails it stays in the chat as a pending message, and the
  /// offline queue uploads it again later.
  static Future<void> sendVoiceNote({
    required String recordedPath,
    required int seconds,
    required String receiverPubkey,
    required RelayManager relayManager,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderPubkey,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    final chatKey = ChatManager.instance.getChatKey(myPubkey, receiverPubkey);
    final messageTs = DateTime.now().millisecondsSinceEpoch;
    final tempId = newTempId(messageTs);

    final stored = await FileSendService.moveIntoFolder(
      File(recordedPath),
      await voiceDirectory(),
      'out_${tempIdFileToken(tempId)}.m4a',
    );

    final tempMessage = ChatMessage(
      id: tempId,
      localId: tempId,
      senderPubkey: myPubkey,
      receiverPubkey: receiverPubkey,
      content: '',
      plaintext: 'Voice message',
      timestamp: messageTs,
      status: 'sending',
      chatKey: chatKey,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderPubkey: replyToSenderPubkey,
      file: {'type': FileSendService.voiceMimeType, 'duration': '$seconds'},
      localPath: stored.path,
    );
    await ChatManager.instance.saveMessage(tempMessage);

    try {
      final file = await FileSendService.encryptAndUpload(
        source: stored,
        mimeType: FileSendService.voiceMimeType,
        durationSeconds: seconds,
        servers: AppSettings.instance.blossomServers,
      );
      await ChatManager.instance.setFile(tempId, chatKey, file.toMap());

      final event = await relayManager.sendMessage(
        receiverPubkey: receiverPubkey,
        plaintext: file.url,
        file: file,
        replyToId: replyToId,
        messageTimestampMs: messageTs,
      );

      await ChatManager.instance.updateMessageIdAndStatus(
        tempId,
        event['rumorId'].toString(),
        'sending',
        chatKey,
        newContent: (event['giftWrap'] as Map<String, dynamic>)['content'].toString(),
        newGiftWrapId: event['giftWrapId'].toString(),
      );
    } catch (e) {
      DebugLogger.log('[Voice] Send failed, queued for later | $e', type: 'WARN');
      await ChatManager.instance.markMessagePending(tempId, chatKey);
    }
  }

  /// Saves a prepared picture in the chat right away, then uploads and sends
  /// it. Like a voice note, it stays pending and is retried when sending fails.
  static Future<void> sendImage({
    required PreparedImage image,
    required String receiverPubkey,
    required RelayManager relayManager,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderPubkey,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    final chatKey = ChatManager.instance.getChatKey(myPubkey, receiverPubkey);
    final messageTs = DateTime.now().millisecondsSinceEpoch;
    final tempId = newTempId(messageTs);
    const mimeType = 'image/jpeg';

    final folder = await mediaDirectory();
    await folder.create(recursive: true);
    final stored = File('${folder.path}${Platform.pathSeparator}out_${tempIdFileToken(tempId)}.jpg');
    await stored.writeAsBytes(image.bytes, flush: true);

    final tempMessage = ChatMessage(
      id: tempId,
      localId: tempId,
      senderPubkey: myPubkey,
      receiverPubkey: receiverPubkey,
      content: '',
      plaintext: 'Photo',
      timestamp: messageTs,
      status: 'sending',
      chatKey: chatKey,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderPubkey: replyToSenderPubkey,
      file: {'type': mimeType, 'dim': '${image.width}x${image.height}'},
      localPath: stored.path,
    );
    await ChatManager.instance.saveMessage(tempMessage);

    try {
      final file = await FileSendService.encryptAndUpload(
        source: stored,
        mimeType: mimeType,
        width: image.width,
        height: image.height,
        servers: AppSettings.instance.blossomServers,
      );
      await ChatManager.instance.setFile(tempId, chatKey, file.toMap());

      final event = await relayManager.sendMessage(
        receiverPubkey: receiverPubkey,
        plaintext: file.url,
        file: file,
        replyToId: replyToId,
        messageTimestampMs: messageTs,
      );

      await ChatManager.instance.updateMessageIdAndStatus(
        tempId,
        event['rumorId'].toString(),
        'sending',
        chatKey,
        newContent: (event['giftWrap'] as Map<String, dynamic>)['content'].toString(),
        newGiftWrapId: event['giftWrapId'].toString(),
      );
    } catch (e) {
      DebugLogger.log('[Image] Send failed, queued for later | $e', type: 'WARN');
      await ChatManager.instance.markMessagePending(tempId, chatKey);
    }
  }

  /// Saves a picked video in the chat right away, then encrypts and uploads it
  /// in pieces. Like a picture, it stays pending and is retried when sending
  /// fails; the offline queue uploads it again later.
  static Future<void> sendVideo({
    required String pickedPath,
    required String mimeType,
    required int seconds,
    int? width,
    int? height,
    required String receiverPubkey,
    required RelayManager relayManager,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderPubkey,
  }) async {
    final myPubkey = AppSettings.instance.myPubkey;
    final chatKey = ChatManager.instance.getChatKey(myPubkey, receiverPubkey);
    final messageTs = DateTime.now().millisecondsSinceEpoch;
    final tempId = newTempId(messageTs);

    final stored = await FileSendService.moveIntoFolder(
      File(pickedPath),
      await mediaDirectory(),
      'out_${tempIdFileToken(tempId)}.${FileTransferService.extensionFor(mimeType)}',
    );

    final tempMessage = ChatMessage(
      id: tempId,
      localId: tempId,
      senderPubkey: myPubkey,
      receiverPubkey: receiverPubkey,
      content: '',
      plaintext: 'Video',
      timestamp: messageTs,
      status: 'sending',
      chatKey: chatKey,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderPubkey: replyToSenderPubkey,
      file: {
        'type': mimeType,
        if (width != null && height != null) 'dim': '${width}x$height',
        if (seconds > 0) 'duration': '$seconds',
      },
      localPath: stored.path,
    );
    await ChatManager.instance.saveMessage(tempMessage);

    // Make the poster in the background, so the bubble shows the video's first
    // frame without starting a decoder, and the profile grid has it ready.
    unawaited(VideoThumbnails.instance.ensure(stored.path));

    try {
      final file = await FileSendService.encryptAndUploadStreaming(
        source: stored,
        mimeType: mimeType,
        durationSeconds: seconds > 0 ? seconds : null,
        width: width,
        height: height,
        servers: AppSettings.instance.blossomServers,
      );
      await ChatManager.instance.setFile(tempId, chatKey, file.toMap());

      final event = await relayManager.sendMessage(
        receiverPubkey: receiverPubkey,
        plaintext: file.url,
        file: file,
        replyToId: replyToId,
        messageTimestampMs: messageTs,
      );

      await ChatManager.instance.updateMessageIdAndStatus(
        tempId,
        event['rumorId'].toString(),
        'sending',
        chatKey,
        newContent: (event['giftWrap'] as Map<String, dynamic>)['content'].toString(),
        newGiftWrapId: event['giftWrapId'].toString(),
      );
    } catch (e) {
      DebugLogger.log('[Video] Send failed, queued for later | $e', type: 'WARN');
      await ChatManager.instance.markMessagePending(tempId, chatKey);
    }
  }
}

/// A [ValueListenable] over the messages box that only notifies when a key
/// belonging to one specific chat changes. All chats share one box, so a
/// plain `box.listenable()` would rebuild an open room for every message
/// saved anywhere else — e.g. the full backlog of an account restore.
class _ChatMessagesListenable extends ValueListenable<Box<ChatMessage>> {
  _ChatMessagesListenable(this._box, this._prefix);

  final Box<ChatMessage> _box;
  final String _prefix;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  StreamSubscription<BoxEvent>? _subscription;

  @override
  Box<ChatMessage> get value => _box;

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.isEmpty) {
      _subscription ??= _box.watch().listen(_onBoxEvent);
    }
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _onBoxEvent(BoxEvent event) {
    if (!event.key.toString().startsWith(_prefix)) return;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }
}
