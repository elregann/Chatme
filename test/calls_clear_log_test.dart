import 'dart:io';

import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:chatme/models/call_log.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/tab_calls.dart';
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
    tempDir = await Directory.systemTemp.createTemp('chatme_calls_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CallLogAdapter());
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox<CallLog>('call_logs');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box<CallLog>('call_logs').clear();
    await Hive.box<Contact>('contacts').clear();
  });

  testWidgets('Calls has a centered secondary-page header, a text-only clear menu and the standard dialog',
      (tester) async {
    await tester.runAsync(() async {
      await Hive.box<CallLog>('call_logs').put(
        'c1',
        CallLog(
          id: 'c1',
          peerPubkey: 'peer',
          peerName: 'Peer',
          direction: 'missed',
          timestamp: 100,
        ),
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: CallsScreen(relayManager: RelayManager())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Calls'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.centerTitle, isTrue);
    expect(appBar.titleSpacing, isNull);
    expect(appBar.backgroundColor, ChatmeColors.backgroundPrimary);
    expect(appBar.elevation, 0);
    expect(appBar.scrolledUnderElevation, 0);

    final title = tester.widget<Text>(find.text('Calls'));
    expect(title.style?.fontSize, 16);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(title.style?.color, ChatmeColors.textPrimary);

    final back = tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_rounded));
    expect(back.size, 18);
    expect(back.color, ChatmeColors.textPrimary);

    final button = tester.widget<ChatmeMenuButton<String>>(
      find.byType(ChatmeMenuButton<String>),
    );
    final menuIcon = button.icon as Icon;
    expect(menuIcon.size, isNull);
    expect(button.entries.single.value, 'clear_call_log');
    expect(button.entries.single.label, 'Clear call log');
    expect(button.entries.single.icon, isNull);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear call log'));
    await tester.pumpAndSettle();

    expect(find.text('Do you want to clear your entire call log?'),
        findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Ok'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(Hive.box<CallLog>('call_logs').length, 1);
  });
}
