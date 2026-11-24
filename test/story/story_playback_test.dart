import 'package:chatme/story/story_timing.dart';
import 'package:flutter_test/flutter_test.dart';

class _Clock {
  DateTime now = DateTime(2026, 1, 1, 12);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

void main() {
  const duration = Duration(seconds: 5);

  StoryPlayback playback(_Clock clock) {
    final value = StoryPlayback(duration: duration, now: clock.call);
    value.start();
    return value;
  }

  group('StoryPlayback', () {
    test('progress advances while the story is running', () {
      final clock = _Clock();
      final value = playback(clock);

      clock.advance(const Duration(seconds: 2));

      expect(value.elapsed, const Duration(seconds: 2));
      expect(value.progress, 0.4);
      expect(value.isPaused, isFalse);
      expect(value.isFinished, isFalse);
    });

    test('pause freezes time and resume continues from the same point', () {
      final clock = _Clock();
      final value = playback(clock);
      clock.advance(const Duration(seconds: 2));

      value.pause();
      clock.advance(const Duration(seconds: 10));

      expect(value.isPaused, isTrue);
      expect(value.elapsed, const Duration(seconds: 2));
      expect(value.progress, 0.4);

      value.resume();
      clock.advance(const Duration(seconds: 1));

      expect(value.isPaused, isFalse);
      expect(value.elapsed, const Duration(seconds: 3));
      expect(value.progress, 0.6);
    });

    test('elapsed and progress clamp to the slide duration', () {
      final clock = _Clock();
      final value = playback(clock);

      clock.advance(const Duration(seconds: 9));

      expect(value.elapsed, duration);
      expect(value.progress, 1.0);
      expect(value.isFinished, isTrue);
    });

    test('pause is idempotent and resume while running does not restart', () {
      final clock = _Clock();
      final value = playback(clock);
      clock.advance(const Duration(seconds: 1));

      value.pause();
      value.pause();
      expect(value.elapsed, const Duration(seconds: 1));

      value.resume();
      value.resume();
      clock.advance(const Duration(seconds: 2));

      expect(value.elapsed, const Duration(seconds: 3));
    });
  });
}
