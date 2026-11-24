import 'package:chatme/story/story_item.dart';
import 'package:chatme/story/story_timing.dart';
import 'package:flutter_test/flutter_test.dart';

StoryItem _story({required String mimeType, int? durationSeconds}) {
  return StoryItem(
    id: 's1',
    authorPubkey: 'author',
    createdAt: 1000,
    expiresAt: 2000,
    mediaUrl: 'https://example.com/blob.enc',
    mimeType: mimeType,
    encryptionKey: 'k',
    encryptionNonce: 'n',
    fileHash: 'h',
    originalHash: 'oh',
    durationSeconds: durationSeconds,
  );
}

void main() {
  group('StoryTiming', () {
    test('image stories always use the fixed five second duration', () {
      final story = _story(mimeType: 'image/jpeg');

      expect(StoryTiming.durationFor(story), const Duration(seconds: 5));
      expect(
        StoryTiming.durationFor(story,
            videoDuration: const Duration(seconds: 30)),
        const Duration(seconds: 5),
      );
    });

    test('video stories prefer the real player duration', () {
      final story = _story(mimeType: 'video/mp4', durationSeconds: 8);

      expect(
        StoryTiming.durationFor(story,
            videoDuration: const Duration(seconds: 10)),
        const Duration(seconds: 10),
      );
    });

    test('video stories fall back to stored metadata then five seconds', () {
      final withMetadata = _story(mimeType: 'video/mp4', durationSeconds: 8);
      final withoutMetadata = _story(mimeType: 'video/mp4');

      expect(StoryTiming.durationFor(withMetadata), const Duration(seconds: 8));
      expect(
          StoryTiming.durationFor(withoutMetadata), const Duration(seconds: 5));
    });

    test('progress is clamped between zero and one', () {
      const duration = Duration(seconds: 5);

      expect(StoryTiming.progress(Duration.zero, duration), 0.0);
      expect(
          const Duration(seconds: 1).inMilliseconds / duration.inMilliseconds,
          closeTo(StoryTiming.progress(const Duration(seconds: 1), duration),
              0.0001));
      expect(StoryTiming.progress(const Duration(seconds: 9), duration), 1.0);
      expect(
          StoryTiming.progress(const Duration(seconds: 1), Duration.zero), 0.0);
    });
  });
}
