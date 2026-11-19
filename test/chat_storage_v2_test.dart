import 'dart:io';

import 'package:chatme/chat_manager.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const chatKey = 'chat_me_peer';
  const otherChatKey = 'chat_me_other';

  ChatMessage msg(
    String id, {
    String sender = 'me',
    String receiver = 'peer',
    int timestamp = 1000,
    String status = 'sent',
    String chatKey = chatKey,
    String? replyToId,
    Map<String, String>? file,
    String localPath = '',
    String localId = '',
  }) =>
      ChatMessage(
        id: id,
        localId: localId,
        senderPubkey: sender,
        receiverPubkey: receiver,
        content: '',
        plaintext: 'text of $id',
        timestamp: timestamp,
        status: status,
        chatKey: chatKey,
        replyToId: replyToId,
        file: file ?? const {},
        localPath: localPath,
      );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('chatme_storage_v2_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');
    await Hive.openBox<ChatMessage>('chat_msgs');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    AppSettings.instance.myPubkey = 'me';
    await Hive.box('chats').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
    await Hive.box<Contact>('contacts').clear();
    await Hive.box('settings').clear();
  });

  group('migration', () {
    test('moves legacy lists into one-key-per-message storage', () async {
      final legacy = [
        msg('a1', timestamp: 1000),
        msg('a2', timestamp: 2000),
      ];
      await Hive.box('chats').put(chatKey, legacy);

      await ChatManager.instance.migrateLegacyChats();

      final msgs = Hive.box<ChatMessage>('chat_msgs');
      expect(msgs.keys.toSet(), {
        ChatManager.messageStorageKey(chatKey, 'a1'),
        ChatManager.messageStorageKey(chatKey, 'a2'),
      });
      // The legacy list is replaced by a registry entry (epoch millis).
      final registryValue = Hive.box('chats').get(chatKey);
      expect(registryValue, isA<int>());
      expect(ChatManager.instance.allChatKeys(), [chatKey]);
    });

    test('is idempotent and can resume after an interruption', () async {
      // Simulate a half-finished migration: 'a1' already moved, 'a2' not.
      await Hive.box<ChatMessage>('chat_msgs').put(
        ChatManager.messageStorageKey(chatKey, 'a1'),
        msg('a1', timestamp: 1000),
      );
      await Hive.box('chats').put(chatKey, [
        msg('a1', timestamp: 1000),
        msg('a2', timestamp: 2000),
      ]);

      await ChatManager.instance.migrateLegacyChats();

      final msgs = Hive.box<ChatMessage>('chat_msgs');
      expect(
        msgs.get(ChatManager.messageStorageKey(chatKey, 'a2'))?.id,
        'a2',
      );
      // Put-if-absent must not have duplicated or clobbered anything.
      expect(msgs.length, 2);
      expect(Hive.box('chats').get(chatKey), isA<int>());

      // Running again changes nothing.
      await ChatManager.instance.migrateLegacyChats();
      expect(msgs.length, 2);
    });

    test('never clobbers a live update with the legacy copy', () async {
      // The v2 copy is newer (status upgraded by a read receipt) while the
      // legacy list still holds the old status.
      await Hive.box<ChatMessage>('chat_msgs').put(
        ChatManager.messageStorageKey(chatKey, 'a1'),
        msg('a1', timestamp: 1000, status: 'read'),
      );
      await Hive.box('chats').put(chatKey, [
        msg('a1', timestamp: 1000, status: 'sent'),
      ]);

      await ChatManager.instance.migrateLegacyChats();

      expect(
        ChatManager.instance.getMessageByIdSync('a1', chatKey)?.status,
        'read',
      );
    });
  });

  group('save & read', () {
    test('saveMessage inserts once and merges duplicates', () async {
      final first = await ChatManager.instance
          .saveMessage(msg('m1', status: 'sending'));
      final second = await ChatManager.instance
          .saveMessage(msg('m1', status: 'sent'));

      expect(first, isTrue);
      expect(second, isFalse);
      expect(
        ChatManager.instance.getMessageByIdSync('m1', chatKey)?.status,
        'sent',
      );
    });

    test('messagesForChatSync returns one chat oldest-first', () async {
      await ChatManager.instance.saveMessage(msg('m2', timestamp: 2000));
      await ChatManager.instance.saveMessage(msg('m1', timestamp: 1000));
      await ChatManager.instance
          .saveMessage(msg('x1', chatKey: otherChatKey, receiver: 'other'));

      final messages = ChatManager.instance.messagesForChatSync(chatKey);
      expect(messages.map((m) => m.id).toList(), ['m1', 'm2']);

      expect(
          ChatManager.instance.allChatKeys().toSet(), {chatKey, otherChatKey});
      expect(ChatManager.instance.allMessagesSync().length, 3);
    });

    test('isMessageExists and getMessageByIdSync', () async {
      await ChatManager.instance.saveMessage(msg('m1'));
      expect(await ChatManager.instance.isMessageExists('m1', chatKey), isTrue);
      expect(await ChatManager.instance.isMessageExists('nope', chatKey),
          isFalse);
      expect(ChatManager.instance.getMessageByIdSync('nope', chatKey), isNull);
    });
  });

  group('delete for me', () {
    Contact? peer() => Hive.box<Contact>('contacts').get('peer');

    Future<void> seedChat() async {
      await ChatManager.instance.saveMessage(msg('m1', timestamp: 1000));
      await ChatManager.instance.saveMessage(msg('m2', timestamp: 2000));
      await Hive.box<Contact>('contacts').put(
        'peer',
        Contact(
          pubkey: 'peer',
          name: 'Peer',
          isSaved: true,
          lastMessage: 'text of m2',
          lastChatTime: 2000,
        ),
      );
    }

    test('deleting the newest message moves the preview back one', () async {
      await seedChat();

      await ChatManager.instance.deleteMessageForMe('m2', chatKey);

      expect(await ChatManager.instance.isMessageExists('m2', chatKey), isFalse);
      expect(peer()?.lastMessage, 'text of m1');
      expect(peer()?.lastChatTime, 1000);
    });

    test('deleting an older message leaves the preview alone', () async {
      await seedChat();

      await ChatManager.instance.deleteMessageForMe('m1', chatKey);

      expect(peer()?.lastMessage, 'text of m2');
      expect(peer()?.lastChatTime, 2000);
    });

    test('deleting the last message empties the preview', () async {
      await seedChat();

      await ChatManager.instance.deleteMessageForMe('m2', chatKey);
      await ChatManager.instance.deleteMessageForMe('m1', chatKey);

      expect(peer()?.lastMessage, '');
      expect(peer()?.lastChatTime, 0);
    });

    test('the preview follows messages from either side', () async {
      await ChatManager.instance.saveMessage(
        msg('m1', timestamp: 1000, sender: 'peer', receiver: 'me'),
      );
      await ChatManager.instance.saveMessage(msg('m2', timestamp: 2000));
      await Hive.box<Contact>('contacts').put(
        'peer',
        Contact(
          pubkey: 'peer',
          name: 'Peer',
          lastMessage: 'text of m2',
          lastChatTime: 2000,
        ),
      );

      await ChatManager.instance.deleteMessageForMe('m2', chatKey);

      expect(peer()?.lastMessage, 'text of m1');
      expect(peer()?.lastChatTime, 1000);
    });

    test('does not create a contact that does not exist', () async {
      await ChatManager.instance.saveMessage(
        msg('m1', timestamp: 1000),
        updateContactPreview: false,
      );

      await ChatManager.instance.deleteMessageForMe('m1', chatKey);

      expect(peer(), isNull);
    });

    test('plain deleteMessage leaves the preview untouched', () async {
      await seedChat();

      await ChatManager.instance.deleteMessage('m2', chatKey);

      expect(peer()?.lastMessage, 'text of m2');
      expect(peer()?.lastChatTime, 2000);
    });
  });

  group('status updates', () {
    test('updateMessageStatus upgrades and never downgrades', () async {
      await ChatManager.instance.saveMessage(msg('m1', status: 'sent'));

      expect(
        await ChatManager.instance
            .updateMessageStatus('m1', 'read', chatKey: chatKey),
        isTrue,
      );
      expect(
        ChatManager.instance.getMessageByIdSync('m1', chatKey)?.status,
        'read',
      );

      // 'sending' is a lower weight than 'read': must not overwrite.
      await ChatManager.instance
          .updateMessageStatus('m1', 'sending', chatKey: chatKey);
      expect(
        ChatManager.instance.getMessageByIdSync('m1', chatKey)?.status,
        'read',
      );
    });

    test('updateMessageIdAndStatus keeps one stable key and repairs replies',
        () async {
      await ChatManager.instance.saveMessage(
          msg('temp_1', status: 'sending', localId: 'temp_1'));
      await ChatManager.instance
          .saveMessage(msg('r1', timestamp: 2000, replyToId: 'temp_1'));

      await ChatManager.instance.updateMessageIdAndStatus(
        'temp_1',
        'real_1',
        'sending',
        chatKey,
        newGiftWrapId: 'gw_1',
      );

      final box = Hive.box<ChatMessage>('chat_msgs');
      // The storage key never changes: no put-under-new-key, no delete.
      expect(box.containsKey(ChatManager.messageStorageKey(chatKey, 'temp_1')),
          isTrue);
      expect(box.containsKey(ChatManager.messageStorageKey(chatKey, 'real_1')),
          isFalse);
      expect(box.length, 2);

      // Both the old local ID and the new canonical ID resolve to the same
      // row, which now carries the Rumor ID in its `id` field.
      final moved = ChatManager.instance.getMessageByIdSync('real_1', chatKey);
      expect(moved?.id, 'real_1');
      expect(moved?.localId, 'temp_1');
      expect(moved?.giftWrapId, 'gw_1');
      expect(
        identical(
          moved,
          ChatManager.instance.getMessageByIdSync('temp_1', chatKey),
        ),
        isTrue,
      );

      // The reply now points at the canonical id, and its preview can be
      // repaired from the stored original (whose plaintext is unchanged
      // by the id swap).
      final reply = ChatManager.instance.getMessageByIdSync('r1', chatKey);
      expect(reply?.replyToId, 'real_1');
      await ChatManager.instance.repairPendingReplies(chatKey);
      expect(
        ChatManager.instance.getMessageByIdSync('r1', chatKey)?.replyToContent,
        'text of temp_1',
      );
    });

    test('markMessagePending flips sending to pending in place', () async {
      await ChatManager.instance.saveMessage(
          msg('temp_p', status: 'sending', localId: 'temp_p'));
      final box = Hive.box<ChatMessage>('chat_msgs');
      final beforeLength = box.length;

      await ChatManager.instance.markMessagePending('temp_p', chatKey);

      expect(box.length, beforeLength);
      expect(box.containsKey(ChatManager.messageStorageKey(chatKey, 'temp_p')),
          isTrue);
      final saved = ChatManager.instance.getMessageByIdSync('temp_p', chatKey);
      expect(saved?.status, 'pending');
      expect(saved?.localId, 'temp_p');
    });
  });

  group('offline queue selection', () {
    const uploadingVideo = <String, String>{
      'type': 'video/mp4',
      'psize': '1700000',
    };

    const uploadedVideo = <String, String>{
      'url': 'https://blossom.example/abc',
      'type': 'video/mp4',
      'alg': 'aes-gcm-chunked',
      'key': 'aa',
      'nonce': 'bb',
      'x': 'cc',
      'psize': '1700000',
    };

    final stale = DateTime.now().millisecondsSinceEpoch - 60000;

    test('does not take a sending video that is still uploading', () async {
      await ChatManager.instance.saveMessage(
        msg(
          'temp_video',
          timestamp: stale,
          status: 'sending',
          file: uploadingVideo,
          localPath: 'C:/videos/chosen.mp4',
        ),
      );

      final pending = await ChatManager.instance.getPendingMessages();
      expect(pending.map((m) => m.id), isNot(contains('temp_video')));
    });

    test('still retries a failed upload saved as pending', () async {
      await ChatManager.instance.saveMessage(
        msg(
          'pending_video',
          timestamp: stale,
          status: 'pending',
          file: uploadingVideo,
          localPath: 'C:/videos/chosen.mp4',
        ),
      );

      final pending = await ChatManager.instance.getPendingMessages();
      expect(pending.map((m) => m.id), contains('pending_video'));
    });

    test('retries a sending message whose file is already uploaded', () async {
      await ChatManager.instance.saveMessage(
        msg(
          'sent_video',
          timestamp: stale,
          status: 'sending',
          file: uploadedVideo,
          localPath: 'C:/videos/chosen.mp4',
        ),
      );

      final pending = await ChatManager.instance.getPendingMessages();
      expect(pending.map((m) => m.id), contains('sent_video'));
    });

    test('still retries an error message that needs its file', () async {
      await ChatManager.instance.saveMessage(
        msg(
          'error_video',
          timestamp: stale,
          status: 'error',
          file: uploadingVideo,
          localPath: 'C:/videos/chosen.mp4',
        ),
      );

      final pending = await ChatManager.instance.getPendingMessages();
      expect(pending.map((m) => m.id), contains('error_video'));
    });
  });

  group('mark incoming as read', () {
    test('marks the whole backlog read but only acks the newest receipts',
        () async {
      // 25 unread incoming + one already read + one of our own.
      for (var i = 1; i <= 25; i++) {
        await ChatManager.instance.saveMessage(
          msg('i$i', sender: 'peer', receiver: 'me', timestamp: i * 1000),
        );
      }
      await ChatManager.instance.saveMessage(
        msg('old', sender: 'peer', receiver: 'me',
            timestamp: 500, status: 'read'),
      );
      await ChatManager.instance.saveMessage(
        msg('mine', sender: 'me', receiver: 'peer', timestamp: 26000),
      );

      final toAck =
          await ChatManager.instance.markIncomingAsRead(peerPubkey: 'peer');

      // Newest first, capped at maxReadReceipts.
      expect(toAck.length, ChatManager.maxReadReceipts);
      expect(toAck.first, 'i25');
      expect(toAck.last, 'i${26 - ChatManager.maxReadReceipts}');

      // Every incoming message is read locally, own message is untouched.
      for (var i = 1; i <= 25; i++) {
        expect(
          ChatManager.instance.getMessageByIdSync('i$i', chatKey)?.status,
          'read',
        );
      }
      expect(
        ChatManager.instance.getMessageByIdSync('mine', chatKey)?.status,
        'sent',
      );

      // Nothing left to acknowledge on the next open.
      expect(
        await ChatManager.instance.markIncomingAsRead(peerPubkey: 'peer'),
        isEmpty,
      );
    });

    test('maxReceipts = 0 still marks everything read locally', () async {
      await ChatManager.instance.saveMessage(
        msg('m1', sender: 'peer', receiver: 'me'),
      );

      final toAck = await ChatManager.instance
          .markIncomingAsRead(peerPubkey: 'peer', maxReceipts: 0);

      expect(toAck, isEmpty);
      expect(
        ChatManager.instance.getMessageByIdSync('m1', chatKey)?.status,
        'read',
      );
    });
  });

  group('reactions', () {
    test('setMessageReaction, mergeReaction and removePendingReaction',
        () async {
      await ChatManager.instance.saveMessage(msg('m1'));

      await ChatManager.instance.setMessageReaction(
        chatKey: chatKey,
        messageId: 'm1',
        reactorPubkey: 'me',
        emoji: '👍',
      );
      expect(
        ChatManager.instance.getMessageByIdSync('m1', chatKey)?.pendingReactions,
        {'me': '👍'},
      );

      // A remote reaction (another user) merges without pending state.
      final applied = await ChatManager.instance.mergeReaction(
        chatKey: chatKey,
        messageId: 'm1',
        reactorPubkey: 'peer',
        emoji: '❤️',
      );
      expect(applied, isTrue);
      final m = ChatManager.instance.getMessageByIdSync('m1', chatKey);
      expect(m?.reactions['peer'], '❤️');
      expect(m?.pendingReactions.containsKey('peer'), isFalse);

      await ChatManager.instance.removePendingReaction(
        chatKey: chatKey,
        messageId: 'm1',
        reactorPubkey: 'me',
      );
      expect(
        ChatManager.instance
            .getMessageByIdSync('m1', chatKey)
            ?.pendingReactions
            .isEmpty,
        isTrue,
      );
    });

    test('mergeReaction reports a missing target', () async {
      final applied = await ChatManager.instance.mergeReaction(
        chatKey: chatKey,
        messageId: 'missing',
        reactorPubkey: 'peer',
        emoji: '👍',
      );
      expect(applied, isFalse);
    });
  });

  group('deleteChatHistory', () {
    test('removes the messages, the registry entry and resets the preview',
        () async {
      await Hive.box<Contact>('contacts').put(
        'peer',
        Contact(pubkey: 'peer', name: 'Peer', lastMessage: 'hello'),
      );
      await ChatManager.instance.saveMessage(msg('m1'));
      await ChatManager.instance.saveMessage(msg('m2', timestamp: 2000));

      await ChatManager.instance.deleteChatHistory(chatKey);

      expect(ChatManager.instance.messagesForChatSync(chatKey), isEmpty);
      expect(Hive.box('chats').containsKey(chatKey), isFalse);
      expect(
        Hive.box('settings').get('cut_off_peer', defaultValue: 0),
        greaterThan(0),
      );
      final contact = Hive.box<Contact>('contacts').get('peer');
      expect(contact?.lastMessage, '');
      expect(contact?.unreadCount, 0);
    });
  });

  group('filtered listenable', () {
    test('only notifies for writes to its own chat', () async {
      var notified = 0;
      final listenable = ChatManager.instance.chatMessagesListenable(chatKey);
      void listener() => notified++;
      listenable.addListener(listener);
      addTearDown(() => listenable.removeListener(listener));

      await ChatManager.instance.saveMessage(msg('m1'));
      await Future<void>.delayed(Duration.zero);
      expect(notified, 1);

      await ChatManager.instance
          .saveMessage(msg('o1', chatKey: otherChatKey, receiver: 'other'));
      await Future<void>.delayed(Duration.zero);
      expect(notified, 1, reason: 'writes to another chat must not notify');

      await ChatManager.instance.saveMessage(msg('m2', timestamp: 2000));
      await Future<void>.delayed(Duration.zero);
      expect(notified, 2);
    });

    test('value exposes the underlying box and reuses the instance', () {
      final listenable = ChatManager.instance.chatMessagesListenable(chatKey);
      expect(listenable.value, isA<Box<ChatMessage>>());
      expect(
        identical(listenable, ChatManager.instance.chatMessagesListenable(chatKey)),
        isTrue,
      );
    });
  });

  group('A audit regressions', () {
    test('cleanupTempMessages keeps a failed local send queued for retry',
        () async {
      await ChatManager.instance.saveMessage(
          msg('temp_fail', status: 'sending', localId: 'temp_fail'));
      await ChatManager.instance.markMessagePending('temp_fail', chatKey);

      await ChatManager.instance.cleanupTempMessages();

      expect(
        ChatManager.instance.getMessageByIdSync('temp_fail', chatKey)?.status,
        'pending',
      );
    });

    test('reconciling a legacy pending row keeps its new ID resolvable',
        () async {
      // A row written by the previous app version: id == Hive key, no localId.
      await ChatManager.instance.saveMessage(msg('pending_old', status: 'pending'));

      await ChatManager.instance.updateMessageIdAndStatus(
        'pending_old',
        'rumor_old',
        'sending',
        chatKey,
      );

      final box = Hive.box<ChatMessage>('chat_msgs');
      expect(box.length, 1);
      expect(
        ChatManager.instance.getMessageByIdSync('rumor_old', chatKey),
        isNotNull,
      );
      final saved = ChatManager.instance.getMessageByIdSync('rumor_old', chatKey);
      expect(saved?.id, 'rumor_old');
      // The old key suffix becomes the permanent localId, so the canonical
      // ID can be resolved for self-wrap dedup, receipts and replies.
      expect(saved?.localId, 'pending_old');
    });

    test('incoming self-copy merges into the local send instead of duplicating',
        () async {
      await ChatManager.instance.saveMessage(
          msg('temp_self', status: 'sending', localId: 'temp_self'));
      await ChatManager.instance.updateMessageIdAndStatus(
        'temp_self',
        'rumor_self',
        'sending',
        chatKey,
      );

      // The self-wrap arrives as a regular incoming event carrying only the
      // canonical ID (the FCM handoff path has no isMessageExists pre-check).
      await ChatManager.instance.saveMessage(
        msg('rumor_self', status: 'sent'),
      );

      final box = Hive.box<ChatMessage>('chat_msgs');
      expect(box.length, 1);
      expect(
        ChatManager.instance.getMessageByIdSync('rumor_self', chatKey)?.localId,
        'temp_self',
      );
    });
  });

  test('messageStorageKey layout is stable', () {
    final key = ChatManager.messageStorageKey('chat_a_b', 'id1');
    expect(key, 'chat_a_b\x1fid1');
    expect(key.codeUnitAt(8), 0x1f);
    // The empty-id form is the prefix used for chat scans.
    expect(
      key.startsWith(ChatManager.messageStorageKey('chat_a_b', '')),
      isTrue,
    );
    // A local send keeps its stable localId as the key suffix even after the
    // canonical ID changes; a legacy/incoming row falls back to its event ID.
    final local = ChatMessage(
      id: 'rumor_1',
      localId: 'temp_1',
      senderPubkey: 'me',
      receiverPubkey: 'peer',
      content: '',
      plaintext: '',
      timestamp: 1,
      status: 'sent',
      chatKey: 'chat_a_b',
    );
    expect(
      ChatManager.messageStorageKeyFor(local),
      ChatManager.messageStorageKey('chat_a_b', 'temp_1'),
    );
    expect(
      ChatManager.messageStorageKeyFor(
        local.copyWith(localId: ''),
      ),
      ChatManager.messageStorageKey('chat_a_b', 'rumor_1'),
    );
  });
}
