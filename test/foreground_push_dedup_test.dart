// foreground_push_dedup_test.dart

import 'dart:io';

import 'package:chatme/chat_notification_handler.dart';
import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/sync_gate.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final List<int> shown = [];

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    shown.add(id);
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('foreground_push_dedup');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    BgInbox.baseDirectoryOverride = tempDir;
    SyncGate.resetForTest();
    ChatNotificationHandler.activeChatPubkey = null;
    await Hive.box('settings').clear();
  });

  tearDown(() {
    BgInbox.baseDirectoryOverride = null;
  });

  // The worker sends data-only FCM: no `notification` block and no `body`
  // key (see chatme-notifier/src/index.js). The foreground handler therefore
  // has nothing to display, and must leave the relay's dedup flag alone.
  test('data-only push shows nothing and leaves the relay flag free', () async {
    final plugin = _FakePlugin();

    await ChatNotificationHandler.handleForegroundMessage(
      const RemoteMessage(
        messageId: 'fcm_1',
        data: {
          'senderPubkey': 'peer_a',
          'senderName': 'Peer',
          'eventId': 'gift_wrap_1',
          'ciphertext': 'sealed',
          'ephemeralPubkey': 'ephemeral',
          'type': 'chat',
        },
      ),
      plugin,
    );

    expect(plugin.shown, isEmpty);
    expect(Hive.box('settings').get('notified_gift_wrap_1'), isNull);
  });

  test('a flag written by the background isolate still suppresses a duplicate',
      () async {
    final plugin = _FakePlugin();
    await Hive.box('settings').put('notified_gift_wrap_2', true);

    await ChatNotificationHandler.handleForegroundMessage(
      const RemoteMessage(
        messageId: 'fcm_2',
        data: {
          'senderPubkey': 'peer_a',
          'senderName': 'Peer',
          'eventId': 'gift_wrap_2',
          'type': 'chat',
        },
      ),
      plugin,
    );

    expect(plugin.shown, isEmpty);
  });

  test('call_cancel keeps claiming its flag', () async {
    final plugin = _FakePlugin();

    await ChatNotificationHandler.handleForegroundMessage(
      const RemoteMessage(
        messageId: 'fcm_3',
        data: {
          'senderPubkey': 'peer_a',
          'senderName': 'Peer',
          'eventId': 'cancel_wrap',
          'type': 'call_cancel',
        },
      ),
      plugin,
    );

    expect(Hive.box('settings').get('notified_cancel_wrap'), isTrue);
  });
}
