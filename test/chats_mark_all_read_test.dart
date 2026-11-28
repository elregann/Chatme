import 'dart:io';

import 'package:chatme/chat_manager.dart';
import 'package:chatme/chat_notification_handler.dart';
import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/notification_entry.dart';
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
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show AndroidFlutterLocalNotificationsPlugin, AndroidNotificationDetails;
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _RecordingNotifications notifications;

  setUpAll(() async {
    notifications = _RecordingNotifications();
    FlutterLocalNotificationsPlatform.instance = notifications;
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
    BgInbox.baseDirectoryOverride = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    BgInbox.baseDirectoryOverride = tempDir;
    notifications.shownIds.clear();
    notifications.cancelledIds.clear();
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

  test('clearing unread count does not republish the group summary', () async {
    await Hive.box<Contact>('contacts').put(
      'carol',
      Contact(
        pubkey: 'carol',
        name: 'CAROL',
        lastMessage: 'hi',
        lastChatTime: 10,
        unreadCount: 1,
      ),
    );
    await BgInbox.addToStack(
      'alice',
      '1',
      const NotificationEntry(sender: 'Alice', message: 'one', timeMs: 30),
    );
    await BgInbox.addToStack(
      'bob',
      '2',
      const NotificationEntry(sender: 'Bob', message: 'two', timeMs: 20),
    );
    await BgInbox.addToStack(
      'carol',
      '3',
      const NotificationEntry(sender: 'Carol', message: 'three', timeMs: 10),
    );

    await ChatManager.instance.clearUnreadCount('carol');

    expect(notifications.shownIds, isEmpty);
    expect(
      notifications.cancelledIds,
      contains(ChatNotificationHandler.notificationId('carol')),
    );
  });
}

class _RecordingNotifications extends AndroidFlutterLocalNotificationsPlugin {
  final List<int> shownIds = <int>[];
  final List<int> cancelledIds = <int>[];

  @override
  Future<void> show(
    int id,
    String? title,
    String? body, {
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shownIds.add(id);
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelledIds.add(id);
  }
}
