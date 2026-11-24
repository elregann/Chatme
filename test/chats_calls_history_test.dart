import 'dart:io';

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

class _SilentNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    FlutterLocalNotificationsPlatform.instance = _SilentNotifications();
    tempDir = await Directory.systemTemp.createTemp('chatme_calls_history_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CallLogAdapter());
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox<CallLog>('call_logs');
    await Hive.openBox('chats');
    await Hive.openBox<ChatMessage>('chat_msgs');
  });

  tearDownAll(() async {
    // The pushed Calls route can leave a Hive write in flight in widget tests;
    // do not let teardown wait on it forever. The isolate owns these boxes.
    await Hive.close().timeout(
      const Duration(seconds: 2),
      onTimeout: () => <void>[],
    );
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    AppSettings.instance.myPubkey = 'me';
    await Hive.box<CallLog>('call_logs').clear();
    await Hive.box<Contact>('contacts').clear();
    await Hive.box('chats').clear();
    await Hive.box<ChatMessage>('chat_msgs').clear();
    await Hive.box('settings').delete('calls_history_seen_at');
  });

  Widget app() => MaterialApp(home: ChatsScreen(relayManager: RelayManager()));

  Future<void> seedCall(String direction, int timestamp) async {
    await Hive.box<CallLog>('call_logs').put(
      timestamp.toString(),
      CallLog(
        id: timestamp.toString(),
        peerPubkey: 'peer',
        peerName: 'Peer',
        direction: direction,
        timestamp: timestamp,
      ),
    );
  }

  Future<void> pumpChats(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  testWidgets('Calls History sits below Mark all as read in the Chats menu',
      (tester) async {
    await pumpChats(tester);

    final button = tester.widget<ChatmeMenuButton<String>>(
      find.byType(ChatmeMenuButton<String>),
    );
    expect(button.entries, hasLength(3));
    expect(button.entries.first.value, 'mark_all_read');
    expect(button.entries.first.label, 'Mark all as read');
    expect(button.entries[1].value, 'calls_history');
    expect(button.entries[1].label, 'Calls History');
    expect(button.entries[1].dot, isFalse);
    expect(button.entries.last.value, 'add_story');
    expect(button.entries.last.label, 'Add story');
  });

  testWidgets('a missed call dots Calls History until the page is opened',
      (tester) async {
    await tester.runAsync(() => seedCall('missed', 200));
    await pumpChats(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chatme-menu-dot')), findsOneWidget);
    final dot = tester.widget<DecoratedBox>(
      find.byKey(const Key('chatme-menu-dot')),
    );
    expect((dot.decoration as BoxDecoration).color, ChatmeColors.badgeDanger);

    await tester.tap(find.text('Calls History'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();

    expect(find.text('Calls'), findsOneWidget);
    expect(Hive.box('settings').get('calls_history_seen_at'),
        isA<int>().having((v) => v > 0, 'is a timestamp', true));
    final seenAtOpen = Hive.box('settings').get('calls_history_seen_at') as int;

    // A missed call landing while the history page is open has already been
    // seen on screen; going back must not light the dot again.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.runAsync(
      () => seedCall('missed', DateTime.now().millisecondsSinceEpoch),
    );
    expect(DateTime.now().millisecondsSinceEpoch, greaterThan(seenAtOpen));

    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chatme-menu-dot')), findsNothing);
  });
}
