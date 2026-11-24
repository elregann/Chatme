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
}
