// auth_required_requeue_test.dart

import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/chat_manager.dart';
import 'package:chatme/chat_notification_handler.dart';
import 'package:chatme/core/utils/sync_gate.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

class _AuthRelay extends RelayManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const chatKey = 'chat_auth_required';
  final myPubkey = bip340.getPublicKey(_key(1));
  final peer = bip340.getPublicKey(_key(2));

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('chatme_auth_required_test');
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
    SyncGate.resetForTest();
    await Hive.box('chats').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
    await Hive.box<Contact>('contacts').clear();
    final settings = Hive.box('settings');
    await settings.clear();
    await settings.put('my_privkey', _key(1));
    await settings.put('my_pubkey', myPubkey);

    AppSettings.instance.myPrivkey = _key(1);
    AppSettings.instance.myPubkey = myPubkey;
    ChatManager.instance.resetAliasIndex();
  });

  Future<void> saveRow(String status, String giftWrapId) =>
      ChatManager.instance.saveMessage(
        ChatMessage(
          id: 'rumor_$giftWrapId',
          localId: 'local_$giftWrapId',
          senderPubkey: myPubkey,
          receiverPubkey: peer,
          content: '',
          plaintext: 'test1',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          status: status,
          chatKey: chatKey,
          giftWrapId: giftWrapId,
        ),
        notify: false,
        updateContactPreview: false,
      );

  test('auth-required rejection requeues a sending row at once', () async {
    final relay = _AuthRelay();
    await saveRow('sending', 'gw_sending');

    await relay.handleOkForTest(
      ['OK', 'gw_sending', false, 'auth-required: please authenticate'],
      'wss://auth.example',
    );

    final saved = ChatManager.instance.getMessageByIdSync('local_gw_sending', chatKey)!;
    expect(saved.status, 'pending');
  });

  test('auth-required rejection never rolls back a sent or read row',
      () async {
    final relay = _AuthRelay();
    await saveRow('sent', 'gw_sent');
    await saveRow('read', 'gw_read');

    await relay.handleOkForTest(
      ['OK', 'gw_sent', false, 'auth-required: please authenticate'],
      'wss://auth.example',
    );
    await relay.handleOkForTest(
      ['OK', 'gw_read', false, 'auth-required: please authenticate'],
      'wss://auth.example',
    );

    expect(
      ChatManager.instance.getMessageByIdSync('local_gw_sent', chatKey)!.status,
      'sent',
    );
    expect(
      ChatManager.instance.getMessageByIdSync('local_gw_read', chatKey)!.status,
      'read',
    );
  });

  test('accepted AUTH clears the queue backoff', () async {
    final relay = _AuthRelay();
    relay.rememberAuthEventForTest('auth_event', 'wss://auth.example');
    relay.queueAttemptForTest('rumor_store',
        setValue: DateTime.now().millisecondsSinceEpoch);

    await relay.handleOkForTest(
      ['OK', 'auth_event', true, ''],
      'wss://auth.example',
    );

    expect(relay.queueAttemptForTest('rumor_store'), 0);
  });

  test('notification stack uses the rumor, not the per-wrap id', () async {
    final first = ChatNotificationHandler.notificationMessageId(
      rumorId: 'rumor_stable',
      eventId: 'gw_first',
    );
    final retry = ChatNotificationHandler.notificationMessageId(
      rumorId: 'rumor_stable',
      eventId: 'gw_retry',
    );

    expect(first, 'rumor_stable');
    expect(retry, 'rumor_stable');
  });
}
