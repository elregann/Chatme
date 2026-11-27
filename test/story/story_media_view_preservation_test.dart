import 'dart:io';

import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/story/story_item.dart';
import 'package:chatme/story/story_manager.dart';
import 'package:chatme/story/story_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const _nonce = '00112233445566778899aabbccddeeff';
const _storyId =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('story_media_view_preservation');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox<Map>(StoryStore.boxName);
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await Hive.box<Map>(StoryStore.boxName).clear();
    AppSettings.instance.myPubkey = 'me';
  });

  test('caching local media preserves a view recorded during the download',
      () async {
    final encrypted = FileCrypto.encryptWith(
      Uint8List.fromList(List<int>.generate(32, (i) => i)),
      key: _key,
      nonce: _nonce,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final story = StoryItem(
      id: _storyId,
      authorPubkey: 'peer',
      createdAt: now - 1000,
      expiresAt: now + 86400000,
      mediaUrl: 'https://example.com/$_storyId.enc',
      mimeType: 'image/png',
      encryptionKey: _key,
      encryptionNonce: _nonce,
      fileHash: encrypted.hash,
      originalHash: encrypted.originalHash,
    );
    await StoryManager.instance.store.put(story);
    await StoryManager.instance.markViewed(story);

    final client = MockClient(
        (request) async => http.Response.bytes(encrypted.bytes, 200));
    final path =
        await StoryManager.instance.ensureLocalMedia(story, client: client);

    expect(path, isNotNull);
    final stored = StoryManager.instance.store.getById(_storyId);
    expect(stored, isNotNull);
    expect(stored!.localPath, path);
    expect(stored.viewedBy.containsKey('me'), isTrue,
        reason: 'a media cache write must not revert a stored view');
  });
}
