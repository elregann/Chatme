// missed_call_bubble_test.dart

import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/call_manager.dart';
import 'package:chatme/call_overlay.dart';
import 'package:chatme/chat_notification_handler.dart';
import 'package:chatme/chat_manager.dart';
import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/sync_gate.dart';
import 'package:chatme/models/call_log.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/identity_secret_store.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeRelay {
  void sendCallSignal(String peerPubkey, Map<String, dynamic> signal) {}
}

class _SilentNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory inboxDir;
  late InMemoryIdentitySecretStore secretStore;
  final myPubkey = bip340.getPublicKey(_key(1));
  final peer = bip340.getPublicKey(_key(2));

  setUpAll(() async {
    FlutterLocalNotificationsPlatform.instance = _SilentNotifications();
    tempDir = await Directory.systemTemp.createTemp('missed_call_bubble_test');
    inboxDir = Directory('${tempDir.path}${Platform.pathSeparator}inbox');
    await inboxDir.create();
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CallLogAdapter());
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');
    await Hive.openBox<ChatMessage>('chat_msgs');
    await Hive.openBox<CallLog>('call_logs');
  });

  tearDownAll(() async {
    BgInbox.baseDirectoryOverride = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    BgInbox.baseDirectoryOverride = inboxDir;
    SyncGate.resetForTest();
    await Hive.box('chats').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
    await Hive.box<Contact>('contacts').clear();
    await Hive.box<CallLog>('call_logs').clear();
    final settings = Hive.box('settings');
    await settings.clear();
    secretStore = InMemoryIdentitySecretStore();
    AppSettings.instance.setIdentitySecretStoreForTest(secretStore);
    await secretStore.write(privkey: _key(1), mnemonic: '');
    await settings.put('my_pubkey', myPubkey);
    AppSettings.instance.myPrivkey = _key(1);
    AppSettings.instance.myPubkey = myPubkey;
    ChatManager.instance.resetAliasIndex();

    // Bring the shared call state back to idle without writing a log.
    await CallManager.instance.stopCall();
    await Hive.box<CallLog>('call_logs').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
  });

  test('foreground call_cancel leaves a note so the room bubble can be rebuilt', () async {
    await ChatNotificationHandler.handleForegroundMessage(
      RemoteMessage(
        messageId: 'cancel_1',
        data: {
          'senderPubkey': peer,
          'senderName': 'ChatMe',
          'eventId': 'cancel_1',
          'type': 'call_cancel',
        },
      ),
      FlutterLocalNotificationsPlugin(),
    );

    final notes = await BgInbox.takeMissedCalls();
    expect(notes.map((e) => e.key), contains(peer));
  });

  test('ending an unanswered incoming call from the overlay stays an incoming call',
      () async {
    final manager = CallManager.instance;
    manager.currentCallDirection = CallType.incoming;
    manager.setSessionInfo('Peer', peer, Colors.blue);

    await endCallFromOverlay(_FakeRelay(), manager);

    final log = Hive.box<CallLog>('call_logs').values.last;
    expect(log.direction, 'incoming');
  });

  test('a call log entry never exists without its room bubble', () async {
    final settings = Hive.box('settings');
    await settings.put('my_pubkey', '');
    AppSettings.instance.myPubkey = '';

    final manager = CallManager.instance;
    manager.currentCallDirection = CallType.incoming;
    manager.setSessionInfo('Peer', peer, Colors.blue);

    await manager.stopCall(sendHangupSignal: false);

    final logs = Hive.box<CallLog>('call_logs').values.toList();
    final bubbles = Hive.box<ChatMessage>('chat_msgs').values
        .where((m) => m.plaintext.startsWith('[CALL]:'))
        .toList();
    expect(logs, isEmpty);
    expect(bubbles, isEmpty);

    await settings.put('my_pubkey', myPubkey);
    AppSettings.instance.myPubkey = myPubkey;
    manager.currentCallDirection = CallType.incoming;
    manager.setSessionInfo('Peer', peer, Colors.blue);
    await manager.stopCall(sendHangupSignal: false);

    expect(Hive.box<CallLog>('call_logs').values, isNotEmpty);
    expect(
      Hive.box<ChatMessage>('chat_msgs').values
          .where((m) => m.plaintext.startsWith('[CALL]:'))
          .toList(),
      isNotEmpty,
    );
  });

  test('a drained missed call does not consume its notification flag', () async {
    final settings = Hive.box('settings');
    await settings.put('notified_call_9001', true);

    final key = await ChatManager.instance.saveCallBubble(
      myPubkey: myPubkey,
      peerPubkey: peer,
      direction: 'missed',
      durationSeconds: 0,
      timestampMs: 9001,
      notify: false,
    );

    expect(key, isNotNull);
    expect(settings.get('notified_call_9001'), isTrue);
  });

  test('a notified bubble still consumes its flag', () async {
    final settings = Hive.box('settings');
    await settings.put('notified_call_9002', true);

    await ChatManager.instance.saveCallBubble(
      myPubkey: myPubkey,
      peerPubkey: peer,
      direction: 'missed',
      durationSeconds: 0,
      timestampMs: 9002,
    );
    await Future<void>.delayed(Duration.zero);

    expect(settings.get('notified_call_9002'), isNull);
  });

  test('an explicit user end is logged as incoming', () async {
    final manager = CallManager.instance;
    manager.currentCallDirection = CallType.incoming;
    manager.setSessionInfo('Peer', peer, Colors.blue);

    await manager.stopCall(sendHangupSignal: false, byUser: true);

    final log = Hive.box<CallLog>('call_logs').values.last;
    expect(log.direction, 'incoming');
  });
}
