import 'package:chatme/core/utils/trim_playback_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

VideoPlayerValue _value(
  int positionMs, {
  int durationMs = 10000,
  bool isPlaying = false,
  bool isCompleted = false,
}) {
  return VideoPlayerValue(
    duration: Duration(milliseconds: durationMs),
    position: Duration(milliseconds: positionMs),
    isInitialized: true,
    isPlaying: isPlaying,
    isCompleted: isCompleted,
  );
}

void main() {
  const start = 2000.0;
  const end = 8000.0;

  bool restart(
    VideoPlayerValue value, {
    double startValue = start,
    double endValue = end,
  }) {
    return shouldRestartTrimPlayback(
      value: value,
      startValue: startValue,
      endValue: endValue,
    );
  }

  group('shouldRestartTrimPlayback', () {
    test('restarts when the reported position is at the trim end', () {
      expect(restart(_value(8000)), isTrue);
    });

    test('restarts when auto-pause lands before the player reports the end',
        () {
      // TrimPlayback stops the estimated playhead at the end, but the last
      // video_player position report is still 80 ms behind.
      expect(restart(_value(7920)), isTrue);
    });

    test('restarts when completed is set before seekTo(duration) lands', () {
      // video_player marks isCompleted first, then pause().then(seek).
      expect(
        restart(
          _value(7990, durationMs: 8000, isCompleted: true),
          endValue: 8000,
        ),
        isTrue,
      );
    });

    test('restarts when the start handle moved past the player position', () {
      expect(restart(_value(1900)), isTrue);
    });

    test('does not restart when paused in the middle of the selection', () {
      expect(restart(_value(5000)), isFalse);
    });

    test('does not restart exactly at the start', () {
      expect(restart(_value(2000)), isFalse);
    });

    test('does not restart before the video is initialized', () {
      expect(restart(const VideoPlayerValue.uninitialized()), isFalse);
    });

    test('caps the tolerance at half of a very short selection', () {
      // A 100 ms selection must not treat its whole range as the end.
      expect(
        restart(_value(1020), startValue: 1000, endValue: 1100),
        isFalse,
      );
    });

    test('uses a 300 ms end tolerance', () {
      expect(restart(_value(7700)), isTrue);
      expect(restart(_value(7699)), isFalse);
    });
  });
}
