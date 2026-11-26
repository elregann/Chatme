import 'dart:io';

import 'package:chatme/core/crypto/nip17.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/story/story_event.dart';
import 'package:chatme/story/story_item.dart';
import 'package:chatme/story/story_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:bip340/bip340.dart' as bip340;

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

StoryItem _story({
  required String id,
  required String authorPubkey,
}) {
  return StoryItem(
    id: id,
    authorPubkey: authorPubkey,
    createdAt: 1000,
    expiresAt: DateTime.now().millisecondsSinceEpoch + 86400000,
    mediaUrl: 'https://example.com/$id.enc',
    mimeType: 'image/jpeg',
    encryptionKey: 'k',
    encryptionNonce: 'n',
    fileHash: 'f$id',
    originalHash: 'o$id',
  );
}

void main() {
  group('Story view receipts', () {
    final alicePriv = _key(1);
    final bobPriv = _key(2);
    final alicePub = bip340.getPublicKey(alicePriv);
    final bobPub = bip340.getPublicKey(bobPriv);
    const validId =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('NIP-17 round trip keeps story view receipt kind and story id', () async {
      final wrapped = await Nip17.wrap(
        plaintext: 'viewed',
        senderPrivkey: bobPriv,
        senderPubkey: bobPub,
        receiverPubkey: alicePub,
        kind: Nip17.kindStoryViewReceipt,
        customTags: StoryEvent.buildViewReceiptTags(
          receiverPubkey: alicePub,
          storyId: validId,
        ),
      );

      final result = await Nip17.unwrap(
        giftWrapEvent: wrapped.giftWrap,
        receiverPrivkey: alicePriv,
        receiverPubkey: alicePub,
      );

      expect(result.rumorKind, Nip17.kindStoryViewReceipt);
      expect(result.senderPubkey, bobPub);
      expect(result.receiverPubkey, alicePub);
      expect(StoryEvent.storyViewIdFromTags(result.rumorTags), validId);
    });

    test('StoryEvent ignores invalid story view ids', () {
      expect(
        StoryEvent.storyViewIdFromTags([
          ['e', '../../evil'],
          ['p', alicePub],
        ]),
        isNull,
      );
      expect(StoryEvent.storyViewIdFromTags(const []), isNull);
    });

    group('StoryManager', () {
      late Directory tempDir;

      setUpAll(() async {
        tempDir = await Directory.systemTemp.createTemp('story_view_receipt_');
        Hive.init(tempDir.path);
        Hive.registerAdapter(ContactAdapter());
        await Hive.openBox<Map>('stories');
        await Hive.openBox<Contact>('contacts');
        await Hive.openBox('settings');
      });

      tearDownAll(() async {
        await Hive.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      setUp(() async {
        await Hive.box<Map>('stories').clear();
        await Hive.box<Contact>('contacts').clear();
        await Hive.box('settings').clear();
        AppSettings.instance.myPubkey = '';
        AppSettings.instance.myPrivkey = '';
      });

      test('records view receipt for my story from another user', () async {
        AppSettings.instance.myPubkey = alicePub;
        await Hive.box<Contact>('contacts').put(
          bobPub,
          Contact(pubkey: bobPub, name: 'Bob', isSaved: true),
        );
        final story = _story(id: validId, authorPubkey: alicePub);
        await StoryManager.instance.store.put(story);

        final handled = await StoryManager.instance.handleIncomingViewReceipt(
          senderPubkey: bobPub,
          storyId: validId,
          viewedAtMs: 5000,
        );

        expect(handled, isTrue);
        final updated = StoryManager.instance.store.getById(validId);
        expect(updated?.viewedBy[bobPub], 5000);
      });

      test('ignores view receipt for story I do not own', () async {
        AppSettings.instance.myPubkey = alicePub;
        final story = _story(id: validId, authorPubkey: bobPub);
        await StoryManager.instance.store.put(story);

        final handled = await StoryManager.instance.handleIncomingViewReceipt(
          senderPubkey: bobPub,
          storyId: validId,
          viewedAtMs: 5000,
        );

        expect(handled, isFalse);
      });

      test('dedupes repeated view receipt from same viewer', () async {
        AppSettings.instance.myPubkey = alicePub;
        final story = _story(id: validId, authorPubkey: alicePub).copyWith(
          viewedBy: {bobPub: 1000},
        );
        await StoryManager.instance.store.put(story);

        final handled = await StoryManager.instance.handleIncomingViewReceipt(
          senderPubkey: bobPub,
          storyId: validId,
          viewedAtMs: 5000,
        );

        expect(handled, isFalse);
        final updated = StoryManager.instance.store.getById(validId);
        expect(updated?.viewedBy[bobPub], 1000);
      });
    });
  });
}