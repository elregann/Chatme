import 'dart:io';

import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/tab_contact.dart';
import 'package:chatme/widgets/chatme_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:hive/hive.dart';

class _FakeRelay extends RelayManager {
  int refreshes = 0;

  @override
  void refreshProfileSubscription() => refreshes++;
}

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
    tempDir = await Directory.systemTemp.createTemp('chatme_contacts_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    await Hive.openBox<Contact>('contacts');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('Contacts has a left title and a text-only refresh menu',
      (tester) async {
    final relay = _FakeRelay();
    await tester.runAsync(() async {
      await Hive.box<Contact>('contacts').clear();
    });

    await tester.pumpWidget(
      MaterialApp(home: ContactsScreen(relayManager: relay)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Contacts'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.centerTitle, isFalse);
    expect(appBar.titleSpacing, 16);

    final button = tester.widget<ChatmeMenuButton<String>>(
      find.byType(ChatmeMenuButton<String>),
    );
    expect(button.entries.single.value, 'refresh_profiles');
    expect(button.entries.single.label, 'Refresh profiles');
    expect(button.entries.single.icon, isNull);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh profiles'));
    await tester.pumpAndSettle();

    expect(relay.refreshes, 1);
  });
}
