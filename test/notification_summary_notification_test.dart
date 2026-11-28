import 'dart:io';

import 'package:chatme/chat_notification_handler.dart';
import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/notification_entry.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationEntry entry(
  String sender,
  String message, {
  required int timeMs,
}) =>
    NotificationEntry(sender: sender, message: message, timeMs: timeMs);

typedef ShownNotification = ({
  int id,
  String? title,
  String? body,
  NotificationDetails? details,
});

class FakePlugin implements FlutterLocalNotificationsPlugin {
  final List<ShownNotification> shown = [];
  final List<int> cancelled = [];

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    shown.add((id: id, title: title, body: body, details: notificationDetails));
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelled.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late FakePlugin plugin;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('chat_notification_summary');
    BgInbox.baseDirectoryOverride = tempDir;
    plugin = FakePlugin();
  });

  tearDown(() async {
    BgInbox.baseDirectoryOverride = null;
    await tempDir.delete(recursive: true);
  });

  test('shows one silent inbox line per conversation, newest first', () async {
    await BgInbox.addToStack(
      'alice',
      'a1',
      entry('Alice', 'Halo', timeMs: 10),
    );
    await BgInbox.addToStack(
      'alice',
      'a2',
      entry('Alice', 'Apa kabar?', timeMs: 15),
    );
    await BgInbox.addToStack(
      'bob',
      'b1',
      entry('Bob', 'Sudah makan?', timeMs: 20),
    );

    await ChatNotificationHandler.showSummaryIfNeeded(plugin);

    final shown = plugin.shown.single;
    expect(shown.id, ChatNotificationHandler.summaryNotificationId);
    // Android already shows the app name, so the title carries a conversation.
    expect(shown.title, 'Bob  Sudah makan?');
    expect(shown.body, 'Alice  Apa kabar?');

    final android = shown.details?.android;
    expect(android, isNotNull);
    expect(android!.setAsGroupSummary, isTrue);
    expect(android.groupKey, ChatNotificationHandler.groupKey);
    expect(android.silent, isTrue);
    expect(android.onlyAlertOnce, isTrue);
    expect(android.groupAlertBehavior, GroupAlertBehavior.children);

    final style = android.styleInformation;
    expect(style, isA<InboxStyleInformation>());
    expect(
      (style as InboxStyleInformation).lines,
      ['Bob  Sudah makan?', 'Alice  Apa kabar?'],
    );
    expect(plugin.cancelled, isEmpty);
  });

  test('adds the hidden conversation count to the second line', () async {
    await BgInbox.addToStack('a', '1', entry('Alice', 'one', timeMs: 30));
    await BgInbox.addToStack('b', '2', entry('Bob', 'two', timeMs: 20));
    await BgInbox.addToStack('c', '3', entry('Carol', 'three', timeMs: 10));

    await ChatNotificationHandler.showSummaryIfNeeded(plugin);

    expect(plugin.shown.single.title, 'Alice  one');
    expect(plugin.shown.single.body, 'Bob  two  ·  +1 more');
  });

  test('keeps a single conversation plain and removes any old summary',
      () async {
    await BgInbox.addToStack('alice', 'a1', entry('Alice', 'Halo', timeMs: 10));

    await ChatNotificationHandler.showSummaryIfNeeded(plugin);

    expect(plugin.shown, isEmpty);
    expect(plugin.cancelled, [ChatNotificationHandler.summaryNotificationId]);
  });

  test('removes any old summary when every conversation is read', () async {
    await ChatNotificationHandler.showSummaryIfNeeded(plugin);

    expect(plugin.shown, isEmpty);
    expect(plugin.cancelled, [ChatNotificationHandler.summaryNotificationId]);
  });

  test(
    'clearing a conversation from room entry does not republish the group summary',
    () async {
      await BgInbox.addToStack('a', '1', entry('Alice', 'one', timeMs: 30));
      await BgInbox.addToStack('b', '2', entry('Bob', 'two', timeMs: 20));
      await BgInbox.addToStack('c', '3', entry('Carol', 'three', timeMs: 10));

      await ChatNotificationHandler.clearNotification(
        'c',
        plugin,
        publishSummary: false,
      );

      expect(plugin.shown, isEmpty);
      expect(
        plugin.cancelled,
        [ChatNotificationHandler.notificationId('c')],
      );
    },
  );

  test(
    'clearing the last remaining conversation still cancels the summary without republishing',
    () async {
      await BgInbox.addToStack('a', '1', entry('Alice', 'one', timeMs: 30));
      await BgInbox.addToStack('b', '2', entry('Bob', 'two', timeMs: 20));

      await ChatNotificationHandler.clearNotification(
        'b',
        plugin,
        publishSummary: false,
      );

      expect(plugin.shown, isEmpty);
      expect(
        plugin.cancelled,
        [
          ChatNotificationHandler.notificationId('b'),
          ChatNotificationHandler.summaryNotificationId,
        ],
      );
    },
  );

  test('clearing a conversation outside room entry still refreshes the summary',
      () async {
    await BgInbox.addToStack('a', '1', entry('Alice', 'one', timeMs: 30));
    await BgInbox.addToStack('b', '2', entry('Bob', 'two', timeMs: 20));
    await BgInbox.addToStack('c', '3', entry('Carol', 'three', timeMs: 10));

    await ChatNotificationHandler.clearNotification('c', plugin);

    expect(plugin.shown.single.id, ChatNotificationHandler.summaryNotificationId);
    expect(plugin.shown.single.title, 'Alice  one');
    expect(plugin.shown.single.body, 'Bob  two');
    expect(plugin.cancelled, [ChatNotificationHandler.notificationId('c')]);
  });
}
