import 'dart:io';

import 'package:chatme/chat_manager.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/room_chat.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/chat_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    FlutterLocalNotificationsPlatform.instance = _SilentNotifications();
    tempDir = await Directory.systemTemp.createTemp('chatme_jump_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');
    await Hive.openBox<ChatMessage>('chat_msgs');
    await Hive.openBox<String>('profile_pictures');
    await Hive.openBox('processed_events');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    ChatScreenRegistry.clear();
    AppSettings.instance.myPubkey = 'me';
    final chatKey = ChatManager.instance.getChatKey('me', 'peer');
    await Hive.box('chats').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
    await Hive.box('chats').put(chatKey, DateTime.now().millisecondsSinceEpoch);
    for (var i = 1; i <= 60; i++) {
      await Hive.box<ChatMessage>('chat_msgs').put(
        ChatManager.messageStorageKey(chatKey, 'm$i'),
        ChatMessage(
          id: 'm$i',
          senderPubkey: 'me',
          receiverPubkey: 'peer',
          content: '',
          plaintext: 'message $i',
          timestamp: i * 1000,
          chatKey: chatKey,
        ),
      );
    }
  });

  Widget app({String? initialMessageId}) => MaterialApp(
        home: ChatDetailScreen(
          contact: Contact(pubkey: 'peer', name: 'Peer'),
          relayManager: RelayManager(),
          initialMessageId: initialMessageId,
        ),
      );

  testWidgets('without a target the chat opens at the newest message',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('message 60'), findsOneWidget);
    expect(find.text('message 5'), findsNothing);
  });

  testWidgets('a target message is scrolled into view and highlighted',
      (tester) async {
    await tester.pumpWidget(app(initialMessageId: 'm5'));
    await tester.pumpAndSettle();

    expect(find.text('message 5'), findsOneWidget);
    expect(find.text('message 60'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('an unknown target leaves the chat at the newest message',
      (tester) async {
    await tester.pumpWidget(app(initialMessageId: 'missing'));
    await tester.pumpAndSettle();

    expect(find.text('message 60'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}

class _SilentNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel(int id) async {}
}
