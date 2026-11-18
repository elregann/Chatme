import 'dart:io';

import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/sync_gate.dart';
import 'package:chatme/models/call_log.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/account_logout.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/link_preview_service.dart';
import 'package:chatme/tab_profile.dart';
import 'package:chatme/widgets/chatme_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:hive/hive.dart';

class _FakeRelay extends RelayManager {
  int connects = 0;
  int disconnects = 0;

  @override
  void connect() => connects++;

  @override
  void disconnect() => disconnects++;
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
  late Directory bgDir;
  late Directory mediaDir;
  late Directory voiceDir;

  setUpAll(() async {
    FlutterLocalNotificationsPlatform.instance = _SilentNotifications();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('package_info_plus'),
      (call) async => {
        'appName': 'Chatme',
        'packageName': 'com.pribadi.chatme',
        'version': '2.7.6',
        'buildNumber': '1',
      },
    );

    tempDir = await Directory.systemTemp.createTemp('chatme_logout_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(CallLogAdapter());
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox('chats');
    await Hive.openBox<ChatMessage>('chat_msgs');
    await Hive.openBox<String>('profile_pictures');
    await Hive.openBox('profile_meta');
    await Hive.openBox<CallLog>('call_logs');
    await Hive.openBox('processed_events');
    await LinkPreviewService.instance.init();

    // BgInbox appends /bg_inbox to its base directory itself.
    bgDir = Directory('${tempDir.path}/bg_inbox');
    BgInbox.baseDirectoryOverride = tempDir;
  });

  tearDownAll(() async {
    BgInbox.baseDirectoryOverride = null;
    for (final channel in [
      const MethodChannel('package_info_plus'),
      const MethodChannel('plugins.flutter.io/path_provider'),
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    SyncGate.resetForTest();

    final settings = Hive.box('settings');
    await settings.clear();
    await settings.putAll({
      'my_pubkey': 'old_account_pubkey',
      'my_privkey': 'old_account_privkey',
      'my_mnemonic': 'old account words',
      'my_nip05': 'old@chatme',
      'my_about': 'old bio',
      'my_photo_path': 'old-photo.jpg',
      'relays_inbox': ['wss://old.example'],
      'read_receipts_enabled': false,
    });
    AppSettings.instance.myPubkey = 'old_account_pubkey';
    await AppSettings.instance.load();

    await Hive.box<Contact>('contacts').put(
      'peer',
      Contact(
        pubkey: 'peer',
        name: 'Peer',
        lastMessage: 'hi',
        lastChatTime: 100,
        unreadCount: 1,
      ),
    );
    await Hive.box<ChatMessage>('chat_msgs').put(
      'me_peer_m1',
      ChatMessage(
        id: 'm1',
        senderPubkey: 'peer',
        receiverPubkey: 'old_account_pubkey',
        content: 'hi',
        plaintext: 'hi',
        timestamp: 100,
        chatKey: 'me_peer',
        status: 'sent',
      ),
    );
    await Hive.box('chats').put('me_peer', {'last': 100});
    await Hive.box<String>('profile_pictures').put('peer', 'cached.jpg');
    await Hive.box('profile_meta').put('peer', {'ts': 1, 'id': 'kind0'});
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
    await Hive.box('processed_events').put('e1', true);
    await Hive.box<String>('link_previews').put('https://x', '{}');

    if (await bgDir.exists()) {
      await bgDir.delete(recursive: true);
    }
    await bgDir.create(recursive: true);
    for (final name in [
      'u_peer_m1',
      'r_peer_m1',
      'd_peer_1',
      'm_peer_1',
      's_peer_1',
      'p_abc.json',
      'tmp_p_abc.json',
      'n_peer_m1',
    ]) {
      await File('${bgDir.path}/$name').create();
    }

    mediaDir = Directory('${tempDir.path}/media');
    voiceDir = Directory('${tempDir.path}/voice');
    await mediaDir.create(recursive: true);
    await voiceDir.create(recursive: true);
    await File('${mediaDir.path}/photo.jpg').create();
    await File('${voiceDir.path}/note.m4a').create();
  });

  test('sign out wipes local data and creates a fresh account', () async {
    final relay = _FakeRelay();

    await AccountLogout.signOut(relay);

    expect(relay.disconnects, 1);
    expect(relay.connects, 1);

    final newPubkey = AppSettings.instance.myPubkey;
    expect(newPubkey.isNotEmpty, isTrue);
    expect(newPubkey, isNot('old_account_pubkey'));
    expect(AppSettings.instance.myPrivkey, isNotEmpty);
    expect(AppSettings.instance.myNip05, '');
    expect(AppSettings.instance.myAbout, '');
    expect(AppSettings.instance.myPhotoPath, '');
    expect(AppSettings.instance.linkPreviewsEnabled, isFalse);
    expect(AppSettings.instance.readReceiptsEnabled, isTrue);
    expect(AppSettings.instance.inboxRelays,
        isNot(['wss://old.example']));
    expect(Hive.box('settings').get('my_pubkey'), newPubkey);

    expect(Hive.box<Contact>('contacts').isEmpty, isTrue);
    expect(Hive.box('chats').isEmpty, isTrue);
    expect(Hive.box<ChatMessage>('chat_msgs').isEmpty, isTrue);
    expect(Hive.box<String>('profile_pictures').isEmpty, isTrue);
    expect(Hive.box('profile_meta').isEmpty, isTrue);
    expect(Hive.box<CallLog>('call_logs').isEmpty, isTrue);
    expect(Hive.box('processed_events').isEmpty, isTrue);
    expect(Hive.box<String>('link_previews').isEmpty, isTrue);

    final files = await bgDir.list().toList();
    expect(files, isEmpty);
    expect(await mediaDir.exists(), isFalse);
    expect(await voiceDir.exists(), isFalse);

    expect(SyncGate.isActive, isTrue);
    expect(SyncGate.useFreshWindow, isTrue);
  });

  testWidgets('profile app bar has QR on the left and a logout menu',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(relayManager: _FakeRelay())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsNothing);
    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    expect(appBar.centerTitle, isFalse);
    expect(appBar.title, isNull);
    expect(appBar.leading, isA<IconButton>());
    expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    final button = tester.widget<ChatmeMenuButton<String>>(
        find.byType(ChatmeMenuButton<String>));
    expect(button.entries.single.value, 'logout');
    expect(button.entries.single.label, 'Log out');
    expect(button.entries.single.icon, Icons.logout);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Log out'), findsOneWidget);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
  });
}
