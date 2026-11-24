import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/core/crypto/nip17.dart';
import 'package:chatme/core/crypto/nip17_file.dart';
import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/sync_gate.dart';
import 'package:chatme/models/call_log.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/account_logout.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/identity_secret_store.dart';
import 'package:chatme/services/link_preview_service.dart';
import 'package:chatme/story/story_event.dart';
import 'package:chatme/story/story_item.dart';
import 'package:chatme/story/story_manager.dart';
import 'package:chatme/story/story_store.dart';
import 'package:chatme/tab_profile.dart';
import 'package:chatme/widgets/chatme_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeRelay extends RelayManager {
  int connects = 0;
  int disconnects = 0;
  final List<Map<String, dynamic>> published = [];
  int publishedAtDisconnect = 0;

  @override
  void connect() => connects++;

  @override
  void disconnect() {
    publishedAtDisconnect = published.length;
    disconnects++;
  }

  @override
  void publishSignedEvent(Map<String, dynamic> event) {
    published.add(event);
  }
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
  late Future<void> Function() originalWebViewDataCleaner;
  late InMemoryIdentitySecretStore secretStore;
  int webViewClears = 0;

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
    await Hive.openBox<Map>('stories');
    await LinkPreviewService.instance.init();

    // BgInbox appends /bg_inbox to its base directory itself.
    bgDir = Directory('${tempDir.path}/bg_inbox');
    BgInbox.baseDirectoryOverride = tempDir;
    originalWebViewDataCleaner = AccountLogout.clearWebViewData;
  });

  tearDownAll(() async {
    BgInbox.baseDirectoryOverride = null;
    AccountLogout.clearWebViewData = originalWebViewDataCleaner;
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
    webViewClears = 0;
    AccountLogout.clearWebViewData = () async {
      webViewClears++;
    };
    secretStore = InMemoryIdentitySecretStore();
    AppSettings.instance.setIdentitySecretStoreForTest(secretStore);
    await secretStore.write(
      privkey: 'old_account_privkey',
      mnemonic: 'old account words',
    );

    final settings = Hive.box('settings');
    await settings.clear();
    await settings.putAll({
      'my_pubkey': 'old_account_pubkey',
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

    final oldStory = StoryItem(
      id: 'old_account_story',
      authorPubkey: 'old_account_pubkey',
      createdAt: 100,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 3600000,
      mediaUrl: 'https://example.com/blob.enc',
      mimeType: 'image/jpeg',
      encryptionKey: 'k',
      encryptionNonce: 'n',
      fileHash: 'h',
      originalHash: 'oh',
      localPath: '${mediaDir.path}/stories/old_account_story.jpg',
    );
    await Hive.box<Map>('stories').put(oldStory.id, oldStory.toMap());
  });

  test('sign out wipes local data and leaves the app signed out', () async {
    final relay = _FakeRelay();

    await AccountLogout.signOut(relay);

    expect(AppSettings.instance.myPubkey, isEmpty);
    expect(AppSettings.instance.myPrivkey, isEmpty);
    expect(AppSettings.instance.myMnemonic, isEmpty);
    expect(await secretStore.readPrivkey(), isNull);
    expect(await secretStore.readMnemonic(), isNull);

    expect(relay.disconnects, 1);
    expect(relay.connects, 0);

    expect(AppSettings.instance.myNip05, '');
    expect(AppSettings.instance.myAbout, '');
    expect(AppSettings.instance.myPhotoPath, '');
    expect(AppSettings.instance.linkPreviewsEnabled, isFalse);
    expect(AppSettings.instance.readReceiptsEnabled, isTrue);
    expect(AppSettings.instance.inboxRelays,
        isNot(['wss://old.example']));
    expect(Hive.box('settings').get('my_pubkey'), isNull);

    expect(Hive.box<Contact>('contacts').isEmpty, isTrue);
    expect(Hive.box('chats').isEmpty, isTrue);
    expect(Hive.box<ChatMessage>('chat_msgs').isEmpty, isTrue);
    expect(Hive.box<String>('profile_pictures').isEmpty, isTrue);
    expect(Hive.box('profile_meta').isEmpty, isTrue);
    expect(Hive.box<CallLog>('call_logs').isEmpty, isTrue);
    expect(Hive.box('processed_events').isEmpty, isTrue);
    expect(Hive.box<String>('link_previews').isEmpty, isTrue);
    expect(Hive.box<Map>('stories').isEmpty, isTrue);
    expect(StoryManager.instance.activeStories(), isEmpty);
    expect(webViewClears, 1);

    final files = await bgDir.list().toList();
    expect(files, isEmpty);
    expect(await mediaDir.exists(), isFalse);
    expect(await voiceDir.exists(), isFalse);

    expect(SyncGate.isActive, isFalse);
    expect(SyncGate.useFreshWindow, isFalse);
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

  testWidgets('profile keeps Security Vault but has no restore shortcut',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(relayManager: _FakeRelay())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Security Vault'), findsOneWidget);
    expect(find.text('Restore Account'), findsNothing);
  });

  group('story cleanup', () {
    const uploadPrivkey =
        '0000000000000000000000000000000000000000000000000000000000000003';
    final uploadPubkey = bip340.getPublicKey(uploadPrivkey);
    const blobHash =
        'abababababababababababababababababababababababababababababababab';
    const accountPrivkey =
        '0000000000000000000000000000000000000000000000000000000000000001';
    const peerPrivkey =
        '0000000000000000000000000000000000000000000000000000000000000002';

    Future<void> useValidIdentity() async {
      final pubkey = bip340.getPublicKey(accountPrivkey);
      final peerPubkey = bip340.getPublicKey(peerPrivkey);
      await secretStore.write(
        privkey: accountPrivkey,
        mnemonic: 'old account words',
      );
      await Hive.box('settings').put('my_pubkey', pubkey);
      await Hive.box<Contact>('contacts').clear();
      await Hive.box<Contact>('contacts').put(
        peerPubkey,
        Contact(pubkey: peerPubkey, name: 'Peer'),
      );
      AppSettings.instance.myPubkey = pubkey;
      await AppSettings.instance.load();
    }

    StoryItem story({required bool mine, int? expiresAt}) => StoryItem(
          id: mine ? 'mine_story' : 'peer_story',
          authorPubkey: mine ? AppSettings.instance.myPubkey : 'peer',
          createdAt: 100,
          expiresAt: expiresAt ??
              DateTime.now().millisecondsSinceEpoch + const Duration(hours: 1).inMilliseconds,
          mediaUrl: 'https://files.example/$blobHash.enc',
          mimeType: 'image/jpeg',
          encryptionKey: 'k',
          encryptionNonce: 'n',
          fileHash: blobHash,
          originalHash: 'oh',
          localPath: '${mediaDir.path}/stories/cleanup.jpg',
          uploadPrivkey: uploadPrivkey,
          uploadPubkey: uploadPubkey,
        );

    Map<String, dynamic> authEventOf(http.Request request) {
      final encoded = request.headers['Authorization']!.substring(6);
      return jsonDecode(
        utf8.decode(
          base64Url.decode(encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=')),
        ),
      ) as Map<String, dynamic>;
    }

    setUp(() async {
      await Hive.box<Map>('stories').clear();
    });

    test('manual delete drops the story without waiting for the server',
        () async {
      final gate = Completer<void>();
      final seen = Completer<http.Request>();
      final client = MockClient((request) async {
        if (!seen.isCompleted) seen.complete(request);
        await gate.future;
        return http.Response('', 204);
      });
      final item = story(mine: true);
      await Hive.box<Map>('stories').put(item.id, item.toMap());

      await StoryManager.instance
          .deleteStory(item, client: client)
          .timeout(const Duration(seconds: 5));

      expect(Hive.box<Map>('stories').containsKey(item.id), isFalse);
      final request = await seen.future.timeout(const Duration(seconds: 5));
      expect(request.method, 'DELETE');
      expect(request.url.toString(), 'https://files.example/$blobHash');
      final event = authEventOf(request);
      expect(event['pubkey'], uploadPubkey);
      expect(
            (event['tags'] as List).any(
              (t) => t[0] == 't' && t[1] == 'delete',
            ),
        isTrue,
      );
      gate.complete();
    });

    test('manual delete ignores a story that is not mine', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      });
      final item = story(mine: false);
      await Hive.box<Map>('stories').put(item.id, item.toMap());

      await StoryManager.instance.deleteStory(item, client: client);

      expect(requests, isEmpty);
      expect(Hive.box<Map>('stories').containsKey(item.id), isTrue);
    });

    test('expiry sweep signs a delete before dropping the story', () async {
      final seen = Completer<http.Request>();
      final client = MockClient((request) async {
        if (!seen.isCompleted) seen.complete(request);
        return http.Response('', 204);
      });
      final expired = DateTime.now().millisecondsSinceEpoch - 1000;
      final item = story(mine: true, expiresAt: expired);
      await Hive.box<Map>('stories').put(item.id, item.toMap());

      await StoryManager.instance.purgeExpired(client: client);
      final request = await seen.future.timeout(const Duration(seconds: 5));

      expect(request.method, 'DELETE');
      expect(request.url.toString(), 'https://files.example/$blobHash');
      expect(authEventOf(request)['pubkey'], uploadPubkey);
      expect(Hive.box<Map>('stories').containsKey(item.id), isFalse);
    });

    test('logout signs a delete for a story that has not expired', () async {
      final seen = Completer<http.Request>();
      final client = MockClient((request) async {
        if (!seen.isCompleted) seen.complete(request);
        return http.Response('', 204);
      });
      final item = story(mine: true);
      await Hive.box<Map>('stories').put(item.id, item.toMap());

      await StoryManager.instance.clearAll(client: client);
      final request = await seen.future.timeout(const Duration(seconds: 5));

      expect(request.method, 'DELETE');
      expect(request.url.toString(), 'https://files.example/$blobHash');
      expect(authEventOf(request)['pubkey'], uploadPubkey);
      expect(Hive.box<Map>('stories').isEmpty, isTrue);
    });

    test('manual delete publishes retracts to contacts and self', () async {
      await useValidIdentity();
      final relay = _FakeRelay();
      final client = MockClient((_) async => http.Response('', 204));
      final item = story(mine: true);
      await Hive.box<Map>('stories').put(item.id, item.toMap());

      await StoryManager.instance.deleteStory(
        item,
        client: client,
        relay: relay,
      );

      expect(relay.published, hasLength(2));
      for (final event in relay.published) {
        expect(event['kind'], Nip17.kindGiftWrap);
      }
      expect(Hive.box<Map>('stories').containsKey(item.id), isFalse);
    });

    test('published retract unwraps to the story id for the recipient',
        () async {
      await useValidIdentity();
      final relay = _FakeRelay();
      final client = MockClient((_) async => http.Response('', 204));
      final item = story(mine: true);
      await Hive.box<Map>('stories').put(item.id, item.toMap());

      await StoryManager.instance.deleteStory(
        item,
        client: client,
        relay: relay,
      );

      Nip17Result? opened;
      for (final event in relay.published) {
        try {
          opened = await Nip17.unwrap(
            giftWrapEvent: event,
            receiverPrivkey: peerPrivkey,
            receiverPubkey: bip340.getPublicKey(peerPrivkey),
          );
          break;
        } catch (_) {}
      }

      expect(opened, isNotNull);
      expect(opened!.rumorKind, Nip17.kindStoryPost);
      expect(opened.plaintext, item.id);
      expect(
        opened.rumorTags.any((t) => t.length > 1 && t[0] == 'story_delete' && t[1] == item.id),
        isTrue,
      );
    });

    test('incoming retract drops the story and blocks a late resend', () async {
      final item = story(mine: false);
      await Hive.box<Map>('stories').put(item.id, item.toMap());
      final tags = StoryEvent.buildDeleteTags(
        receiverPubkey: AppSettings.instance.myPubkey,
        storyId: item.id,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      final handled = await StoryManager.instance.handleIncomingRumor(
        rumorId: 'retract_rumor',
        senderPubkey: 'peer',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        tags: tags,
        content: item.id,
      );

      expect(handled, isTrue);
      expect(Hive.box<Map>('stories').containsKey(item.id), isFalse);

      final late = StoryItem(
        id: item.id,
        authorPubkey: 'peer',
        createdAt: 100,
        expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
        mediaUrl: 'https://files.example/late.enc',
        mimeType: 'image/jpeg',
        encryptionKey: '00' * 32,
        encryptionNonce: '00' * 12,
        fileHash: blobHash,
        originalHash: blobHash,
      );
      final file = FileMessage(
        url: late.mediaUrl,
        mimeType: late.mimeType,
        key: late.encryptionKey,
        nonce: late.encryptionNonce,
        hash: late.fileHash,
        originalHash: late.originalHash,
      );
      await StoryManager.instance.handleIncomingRumor(
        rumorId: late.id,
        senderPubkey: 'peer',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        tags: StoryEvent.buildTags(
          receiverPubkey: AppSettings.instance.myPubkey,
          file: file,
          expiresAtMs: late.expiresAt,
        ),
        content: file.url,
      );

      expect(Hive.box<Map>('stories').containsKey(late.id), isFalse);
    });

    test('retract from a stranger leaves the story in place', () async {
      final item = story(mine: false);
      await Hive.box<Map>('stories').put(item.id, item.toMap());
      final tags = StoryEvent.buildDeleteTags(
        receiverPubkey: AppSettings.instance.myPubkey,
        storyId: item.id,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      await StoryManager.instance.handleIncomingRumor(
        rumorId: 'retract_rumor',
        senderPubkey: 'stranger',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        tags: tags,
        content: item.id,
      );

      expect(Hive.box<Map>('stories').containsKey(item.id), isTrue);
      expect(StoryManager.instance.activeStories().map((s) => s.id), contains(item.id));
    });

    test('logout retracts own stories before disconnecting', () async {
      await useValidIdentity();
      final relay = _FakeRelay();
      final item = story(mine: true);
      await Hive.box<Map>('stories').put(item.id, item.toMap());

      await AccountLogout.signOut(relay);

      expect(relay.published, hasLength(2));
      expect(relay.publishedAtDisconnect, 2);
      expect(Hive.box<Map>('stories').isEmpty, isTrue);
    });

    test('expired tombstones are pruned with the stories', () async {
      final store = StoryStore();
      await store.putTombstone(
        'gone_story',
        'peer',
        DateTime.now().millisecondsSinceEpoch - 1000,
      );

      expect(store.isTombstoned('gone_story', 'peer'), isFalse);
      await store.purgeExpired();
      expect(
        Hive.box<Map>('stories').containsKey(StoryStore.tombstoneKey('gone_story')),
        isFalse,
      );
    });
  });
}
