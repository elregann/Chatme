// temp_id_test.dart

import 'dart:io';

import 'package:chatme/chat_manager.dart';
import 'package:chatme/core/utils/temp_id.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One millisecond, many sends: the old `temp_<ms>` scheme collapsed them
  // into a single Hive key and silently lost a bubble.
  const sameMs = 1763000000000;

  test('ids stay unique inside one millisecond', () {
    final ids = List.generate(64, (_) => newTempId(sameMs));

    expect(ids.toSet().length, 64);
    expect(ids.every((id) => id.startsWith('temp_')), isTrue);
  });

  test('file tokens stay unique, so two pictures in one frame do not overwrite',
      () {
    final tokens =
        List.generate(64, (_) => tempIdFileToken(newTempId(sameMs)));

    expect(tokens.toSet().length, 64);
  });

  group('storage', () {
    late Directory tempDir;
    const chatKey = 'chat_me_peer';

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('chatme_temp_id_test');
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

    test('four sends in one millisecond leave four rows', () async {
      final ids = List.generate(4, (_) => newTempId(sameMs));

      for (final id in ids) {
        await ChatManager.instance.saveMessage(
          ChatMessage(
            id: id,
            localId: id,
            senderPubkey: 'me',
            receiverPubkey: 'peer',
            content: '',
            plaintext: 'hi',
            timestamp: sameMs,
            status: 'sending',
            chatKey: chatKey,
          ),
          notify: false,
          updateContactPreview: false,
        );
      }

      final stored = ChatManager.instance.messagesForChatSync(chatKey);
      expect(stored.length, 4);
      expect(stored.map((m) => m.localId).toSet().length, 4);
    });
  });
}
