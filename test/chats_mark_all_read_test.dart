import 'dart:io';

import 'package:chatme/chat_manager.dart';
import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:chatme/models/call_log.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/tab_chat.dart';
import 'package:chatme/widgets/chatme_menu.dart';
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
    tempDir = await Directory.systemTemp.createTemp('chatme_mark_all_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CallLogAdapter());
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox<CallLog>('call_logs');
    await Hive.openBox('chats');
    await Hive.openBox<ChatMessage>('chat_msgs');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    AppSettings.instance.myPubkey = 'me';
    await Hive.box<Contact>('contacts').clear();
    await Hive.box<CallLog>('call_logs').clear();
    await Hive.box('chats').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
  });

  Widget app() => MaterialApp(home: ChatsScreen(relayManager: RelayManager()));

  Future<void> pumpChats(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  Future<void> seed(String peer) async {
    final chatKey = ChatManager.instance.getChatKey('me', peer);
    await Hive.box<Contact>('contacts').put(
      peer,
      Contact(
        pubkey: peer,
        name: peer.toUpperCase(),
        lastMessage: 'hi',
        lastChatTime: 100,
        unreadCount: 1,
      ),
    );
    await Hive.box<ChatMessage>('chat_msgs').put(
      ChatManager.messageStorageKey(chatKey, 'm_$peer'),
      ChatMessage(
        id: 'm_$peer',
        senderPubkey: peer,
        receiverPubkey: 'me',
        content: 'hi',
        plaintext: 'hi',
        timestamp: 100,
        chatKey: chatKey,
        status: 'sent',
      ),
    );
  }

  testWidgets('the chats title and the menu entry are configured',
      (tester) async {
    await pumpChats(tester);

    expect(find.text('Chatme'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.centerTitle, isFalse);
    expect(appBar.titleSpacing, 16);
    final title = tester.widget<Text>(find.text('Chatme'));
    expect(title.style?.color, ChatmeColors.accentPrimary);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    final button = tester.widget<ChatmeMenuButton<String>>(
        find.byType(ChatmeMenuButton<String>));
    expect(button.entries, hasLength(3));
    expect(button.entries.first.value, 'mark_all_read');
    expect(button.entries.first.label, 'Mark all as read');
    expect(button.entries.first.icon, isNull);
    expect(button.entries[1].value, 'calls_history');
    expect(button.entries[1].label, 'Calls History');
    expect(button.entries.last.value, 'add_story');
    expect(button.entries.last.label, 'Add story');
  });

  testWidgets('mark all as read clears badges and message statuses',
      (tester) async {
    await tester.runAsync(() async {
      await seed('peer_a');
      await seed('peer_b');
      await markAllChatsAsRead(RelayManager());
    });

    for (final peer in ['peer_a', 'peer_b']) {
      final contact = Hive.box<Contact>('contacts').get(peer);
      expect(contact?.unreadCount, 0);
      final chatKey = ChatManager.instance.getChatKey('me', peer);
      final msg = ChatManager.instance.getMessageByIdSync('m_$peer', chatKey);
      expect(msg?.status, 'read');
    }
  });
}

class _SilentNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel(int id) async {}
}
