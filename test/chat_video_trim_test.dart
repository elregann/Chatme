import 'package:chatme/ui/chat_video_trim_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatVideoTrimPage.needsTrim', () {
    test('the whole video needs no trim', () {
      expect(
        ChatVideoTrimPage.needsTrim(start: 0, end: 10000, totalMs: 10000),
        isFalse,
      );
    });

    test('an end within 50 ms of the duration counts as the whole video', () {
      expect(
        ChatVideoTrimPage.needsTrim(start: 0, end: 9960, totalMs: 10000),
        isFalse,
      );
    });

    test('handles that never reported a value do not cut the video', () {
      expect(
        ChatVideoTrimPage.needsTrim(start: 0, end: 0, totalMs: 10000),
        isFalse,
      );
    });

    test('an unknown duration does not cut the video', () {
      expect(
        ChatVideoTrimPage.needsTrim(start: 0, end: 5000, totalMs: 0),
        isFalse,
      );
    });

    test('a later start needs a trim', () {
      expect(
        ChatVideoTrimPage.needsTrim(start: 2000, end: 10000, totalMs: 10000),
        isTrue,
      );
    });

    test('an earlier end needs a trim', () {
      expect(
        ChatVideoTrimPage.needsTrim(start: 0, end: 6000, totalMs: 10000),
        isTrue,
      );
    });

    test('an empty or reversed range needs no trim', () {
      expect(
        ChatVideoTrimPage.needsTrim(start: 5000, end: 5000, totalMs: 10000),
        isFalse,
      );
      expect(
        ChatVideoTrimPage.needsTrim(start: 6000, end: 4000, totalMs: 10000),
        isFalse,
      );
    });
  });
}
