import 'package:chatme/core/crypto/nip17_file.dart';
import 'package:chatme/story/story_event.dart';
import 'package:chatme/story/story_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoryItem', () {
    test('isExpired returns true when now is at or after expiresAt', () {
      const story = StoryItem(
        id: 's1',
        authorPubkey: 'author',
        createdAt: 1000,
        expiresAt: 2000,
        mediaUrl: 'https://example.com/blob.enc',
        mimeType: 'image/jpeg',
        encryptionKey: 'k',
        encryptionNonce: 'n',
        fileHash: 'h',
        originalHash: 'oh',
      );

      expect(story.isExpiredAt(1999), isFalse);
      expect(story.isExpiredAt(2000), isTrue);
      expect(story.isExpiredAt(2001), isTrue);
    });

    test('toMap/fromMap keeps the upload key used for later deletion', () {
      const story = StoryItem(
        id: 's2',
        authorPubkey: 'author',
        createdAt: 1000,
        expiresAt: 2000,
        mediaUrl: 'https://files.example/blob.enc',
        mimeType: 'image/jpeg',
        encryptionKey: 'k',
        encryptionNonce: 'n',
        fileHash: 'h',
        originalHash: 'oh',
        uploadPrivkey: 'priv',
        uploadPubkey: 'pub',
      );

      final restored = StoryItem.fromMap(story.toMap());

      expect(restored.uploadPrivkey, 'priv');
      expect(restored.uploadPubkey, 'pub');
      expect(story.copyWith(caption: 'hi').uploadPrivkey, 'priv');
      expect(story.copyWith(caption: 'hi').uploadPubkey, 'pub');
    });

    test('toMap/fromMap round trips story fields', () {
      const story = StoryItem(
        id: 's1',
        authorPubkey: 'author',
        createdAt: 1000,
        expiresAt: 2000,
        mediaUrl: 'https://example.com/blob.enc',
        mimeType: 'video/mp4',
        encryptionKey: 'k',
        encryptionNonce: 'n',
        fileHash: 'h',
        originalHash: 'oh',
        caption: 'hi',
        width: 720,
        height: 1280,
        durationSeconds: 12,
        size: 456,
        localPath: '/tmp/story.mp4',
        viewedBy: {'peer1': 1500},
      );

      final restored = StoryItem.fromMap(story.toMap());

      expect(restored.id, story.id);
      expect(restored.authorPubkey, story.authorPubkey);
      expect(restored.createdAt, story.createdAt);
      expect(restored.expiresAt, story.expiresAt);
      expect(restored.mediaUrl, story.mediaUrl);
      expect(restored.mimeType, story.mimeType);
      expect(restored.encryptionKey, story.encryptionKey);
      expect(restored.encryptionNonce, story.encryptionNonce);
      expect(restored.fileHash, story.fileHash);
      expect(restored.originalHash, story.originalHash);
      expect(restored.caption, story.caption);
      expect(restored.width, story.width);
      expect(restored.height, story.height);
      expect(restored.durationSeconds, story.durationSeconds);
      expect(restored.size, story.size);
      expect(restored.localPath, story.localPath);
      expect(restored.viewedBy, story.viewedBy);
    });
  });

  group('StoryEvent ids', () {
    const validId =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('accepts only canonical 64 lowercase hex ids', () {
      expect(StoryEvent.isValidStoryId(validId), isTrue);
      expect(StoryEvent.isValidStoryId(validId.toUpperCase()), isFalse);
      expect(StoryEvent.isValidStoryId('../../evil'), isFalse);
      expect(StoryEvent.isValidStoryId('abc'), isFalse);
      expect(StoryEvent.isValidStoryId(''), isFalse);
    });

    test('fromRumor rejects an id that could escape the stories folder', () {
      final file = FileMessage(
        url: 'https://files.example/blob.enc',
        mimeType: 'image/jpeg',
        key: '00' * 32,
        nonce: '00' * 12,
        hash: 'ab' * 32,
      );
      final tags = StoryEvent.buildTags(
        receiverPubkey: 'peer',
        file: file,
        expiresAtMs: 5000000,
      );

      final bad = StoryEvent.fromRumor(
        rumorId: '../../evil',
        authorPubkey: 'author',
        createdAtMs: 1000,
        tags: tags,
        content: file.url,
      );
      expect(bad, isNull);

      final good = StoryEvent.fromRumor(
        rumorId: validId,
        authorPubkey: 'author',
        createdAtMs: 1000,
        tags: tags,
        content: file.url,
      );
      expect(good, isNotNull);
      expect(good!.id, validId);
    });

    test('delete tags carry the story id and a short expiry', () {
      final tags = StoryEvent.buildDeleteTags(
        receiverPubkey: 'peer',
        storyId: validId,
        expiresAtMs: 5000000,
      );

      expect(tags[0], ['p', 'peer']);
      expect(tags[1], ['story_delete', validId]);
      expect(tags[2], ['expiration', '5000']);
      expect(StoryEvent.deleteIdFromTags(tags), validId);
      expect(
        StoryEvent.deleteIdFromTags([
          ['story', '1'],
          ['p', 'peer'],
        ]),
        isNull,
      );
      expect(
        StoryEvent.deleteIdFromTags([
          ['story_delete', '../../evil'],
        ]),
        isNull,
      );
      expect(StoryEvent.deleteIdFromTags(const []), isNull);
    });
  });
}
