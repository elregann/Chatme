// deferred_issues_regression_test.dart
//
// Regression guards for the three issues found while auditing the FCM handoff:
//  1. forged marker ids must not escape the bg_inbox folder,
//  2. a live app must not send a second read receipt for a Hive message,
//  3. the relay and FCM drains must agree on the initial status of history.
//
// These used to fail on v2.7.1. They now describe the fixed behaviour.

import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/main_isolate_ping.dart';
import 'package:chatme/core/utils/sync_gate.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/notification_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ISSUE 1 - marker ids stay inside bg_inbox', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('chatme_marker_test');
      BgInbox.baseDirectoryOverride = temp;
    });

    tearDown(() async {
      BgInbox.baseDirectoryOverride = null;
      await temp.delete(recursive: true);
    });

    test('a forged u_ id cannot write outside the inbox', () async {
      await BgInbox.addUnread('peer', 'x/../../escape');

      final escaped = File('${temp.path}${Platform.pathSeparator}escape');
      expect(await escaped.exists(), isFalse);
    });

    test('a forged r_ id cannot write outside the inbox', () async {
      await BgInbox.recordRead('peer', [r'x\..\..\escape']);

      final escaped = File('${temp.path}${Platform.pathSeparator}escape');
      expect(await escaped.exists(), isFalse);
    });

    test('ordinary and local ids still round-trip', () async {
      await BgInbox.addUnread('peer', _key(9));
      await BgInbox.addUnread('peer', 'call_123');

      final ids = await BgInbox.takeUnread('peer');
      expect(ids, contains(_key(9)));
      expect(ids, contains('call_123'));

      await BgInbox.recordRead('peer', ['temp_abc']);
      expect(await BgInbox.isMarkedRead('peer', 'temp_abc'), isTrue);
      await BgInbox.consumeRead('peer', 'temp_abc');
      expect(await BgInbox.isMarkedRead('peer', 'temp_abc'), isFalse);
    });
  });

  group('ISSUE 2 - mark-read with a live app', () {
    const peer = 'peer';
    late Directory temp;
    late ReceivePort port;
    late List<Map> forwarded;

    setUp(() async {
      port = ReceivePort();
      forwarded = <Map>[];
      port.listen((message) {
        if (answerPing(message)) return;
        if (message is Map) forwarded.add(message);
      });
      IsolateNameServer.registerPortWithName(
        port.sendPort,
        'chatme_notification_port',
      );

      temp = await Directory.systemTemp.createTemp('chatme_markread_test');
      BgInbox.baseDirectoryOverride = temp;
      PathProviderPlatform.instance = _FakePathProvider(temp.path);

      Hive.init(temp.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(ChatMessageAdapter());
      }
      final settings = await Hive.openBox('settings');
      await settings.put('my_privkey', _key(1));
      await settings.put('my_pubkey', bip340.getPublicKey(_key(1)));
      // markRead writes the r_ marker before checking this flag, so receipts
      // stay offline and we can observe the marker without opening relays.
      await settings.put('read_receipts_enabled', false);
    });

    tearDown(() async {
      IsolateNameServer.removePortNameMapping('chatme_notification_port');
      port.close();
      BgInbox.baseDirectoryOverride = null;
      await Hive.close();
      await temp.delete(recursive: true);
    });

    Future<void> tapMarkRead() => backgroundNotificationResponseHandler(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            actionId: 'MARK_READ_ACTION',
            payload: peer,
          ),
        );

    test('the app gets the action', () async {
      await tapMarkRead();
      expect(
        forwarded.any((m) => m['actionId'] == 'MARK_READ_ACTION'),
        isTrue,
      );
    });

    test('no second receipt is recorded for a message already in Hive',
        () async {
      final myPubkey = bip340.getPublicKey(_key(1));
      final sorted = [myPubkey, peer]..sort();
      final chatKey = 'chat_${sorted[0]}_${sorted[1]}';
      final box = await Hive.openBox<ChatMessage>('chat_msgs');
      await box.put(
        '$chatKey\x1f${_key(9)}',
        ChatMessage(
          id: _key(9),
          senderPubkey: peer,
          receiverPubkey: myPubkey,
          content: 'cipher',
          plaintext: 'hello',
          timestamp: 1000,
          status: 'sent',
          chatKey: chatKey,
        ),
      );

      await tapMarkRead();

      // The main isolate sends the receipt for this message. The background
      // isolate must leave Hive alone, otherwise the sender gets it twice.
      expect((await BgInbox.peekReads())[peer], isNull);
    });

    test('spooled messages still get their receipt from the background',
        () async {
      await BgInbox.addUnread(peer, _key(8));

      await tapMarkRead();

      // The main isolate cannot see a message that is still in the spool, so
      // this receipt must still be sent from here.
      expect((await BgInbox.peekReads())[peer], [_key(8)]);
    });
  });

  group('ISSUE 3 - initial status during initial sync', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('chatme_status_test');
      Hive.init(temp.path);
      await Hive.openBox('settings');
      SyncGate.start('test');
      await Hive.box('settings').put('initial_sync_started_at', 5000);
    });

    tearDown(() async {
      SyncGate.resetForTest();
      await Hive.close();
      await temp.delete(recursive: true);
    });

    test('restored history is read for them and sent for me', () {
      expect(
        SyncGate.initialStatusFor(isFromMe: false, timestamp: 1000),
        'read',
      );
      expect(
        SyncGate.initialStatusFor(isFromMe: true, timestamp: 1000),
        'sent',
      );
    });

    test('live messages keep their normal status', () {
      expect(
        SyncGate.initialStatusFor(isFromMe: false, timestamp: 9000),
        'sent',
      );
      expect(
        SyncGate.initialStatusFor(isFromMe: true, timestamp: 9000),
        'sending',
      );
    });
  });
}
