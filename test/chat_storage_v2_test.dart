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
  }) =>
      ChatMessage(
        id: id,
        senderPubkey: sender,
        receiverPubkey: receiver,
        content: '',
        plaintext: 'text of $id',
        timestamp: timestamp,
        status: status,
        chatKey: chatKey,
        replyToId: replyToId,
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

    test('updateMessageIdAndStatus moves the key and repairs replies',
        () async {
      await ChatManager.instance
          .saveMessage(msg('temp_1', status: 'sending'));
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
      expect(box.containsKey(ChatManager.messageStorageKey(chatKey, 'temp_1')),
          isFalse);
      final moved = ChatManager.instance.getMessageByIdSync('real_1', chatKey);
      expect(moved?.giftWrapId, 'gw_1');

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

  test('messageStorageKey layout is stable', () {
    final key = ChatManager.messageStorageKey('chat_a_b', 'id1');
    expect(key, 'chat_a_b\x1fid1');
    expect(key.codeUnitAt(8), 0x1f);
    // The empty-id form is the prefix used for chat scans.
    expect(
      key.startsWith(ChatManager.messageStorageKey('chat_a_b', '')),
      isTrue,
    );
  });
}
