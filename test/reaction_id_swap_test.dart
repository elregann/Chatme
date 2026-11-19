// reaction_id_swap_test.dart

import 'dart:io';

import 'package:chatme/chat_manager.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const chatKey = 'chat_me_peer';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('chatme_reaction_swap_test');
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
    ChatManager.instance.resetAliasIndex();
    await Hive.box('chats').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
    await Hive.box<Contact>('contacts').clear();
    await Hive.box('settings').clear();
  });

  test('pending reaction survives the ID swap and is cleared through the alias',
      () async {
    const tempId = 'temp_1234';
    const rumorId = 'rumor_abcdef';

    await ChatManager.instance.saveMessage(
      ChatMessage(
        id: tempId,
        localId: tempId,
        senderPubkey: 'peer',
        receiverPubkey: 'me',
        content: '',
        plaintext: 'hi',
        timestamp: 1000,
        status: 'sending',
        chatKey: chatKey,
      ),
      notify: false,
      updateContactPreview: false,
    );

    await ChatManager.instance.setMessageReaction(
      chatKey: chatKey,
      messageId: tempId,
      reactorPubkey: 'me',
      emoji: '👍',
    );

    final before = ChatManager.instance.getMessageByIdSync(tempId, chatKey)!;
    expect(before.pendingReactions['me'], '👍');
    final stableKey = ChatManager.messageStorageKeyFor(before);

    await ChatManager.instance.updateMessageIdAndStatus(
      tempId,
      rumorId,
      'sent',
      chatKey,
    );

    final after = ChatManager.instance.getMessageByIdSync(rumorId, chatKey)!;
    expect(after.localId, tempId);
    expect(after.pendingReactions['me'], '👍');
    // Reaction retry/backoff must key off this, not the changeable Rumor ID.
    expect(ChatManager.messageStorageKeyFor(after), stableKey);

    await ChatManager.instance.removePendingReaction(
      chatKey: chatKey,
      messageId: rumorId,
      reactorPubkey: 'me',
    );

    final cleared = ChatManager.instance.getMessageByIdSync(rumorId, chatKey)!;
    expect(cleared.pendingReactions, isEmpty);
  });
}
