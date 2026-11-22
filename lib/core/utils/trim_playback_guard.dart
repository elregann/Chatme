import 'package:video_player/video_player.dart';

/// `video_player` reports its position every few hundred milliseconds, while
/// `video_trimmer` pauses its estimated playhead earlier than that. Treat a
/// reported position this close to the trim end as "finished" so a replay
/// starts from the trim start instead of leaking into the rest of the video.
const int trimEndToleranceMs = 300;

/// Decide whether the play button must seek to the trim start before playing.
///
/// The player may still be a fraction behind the end when the trim viewer
/// reports that playback stopped, and `isCompleted` can be set before
/// `seekTo(duration)` lands. Both cases are the end of the selection, not a
/// pause in the middle that should resume from the current position.
bool shouldRestartTrimPlayback({
  required VideoPlayerValue value,
  required double startValue,
  required double endValue,
}) {
  if (!value.isInitialized) return false;

  final startMs = startValue.round();
  final endMs = endValue.round();
  if (endMs <= startMs) return false;

  final positionMs = value.position.inMilliseconds;
  if (value.isCompleted || positionMs >= endMs || positionMs < startMs) {
    return true;
  }

  // Never let the tolerance swallow a very short selection.
  final halfSpanMs = (endMs - startMs) ~/ 2;
  final toleranceMs =
      trimEndToleranceMs < halfSpanMs ? trimEndToleranceMs : halfSpanMs;
  return positionMs >= endMs - toleranceMs;
}

/// The package pauses up to 120 ms before the video's last frame. Once that
/// stop is seen, the app-owned scrubber snaps to the visible end so the line
/// still reaches the trim boundary.
const int trimEndSnapToleranceMs = 300;

bool shouldSnapTrimPlaybackToEnd({
  required Duration position,
  required double startValue,
  required double endValue,
}) {
  final startMs = startValue.round();
  final endMs = endValue.round();
  if (endMs <= startMs) return false;

  // Never let the tolerance swallow a very short selection.
  final halfSpanMs = (endMs - startMs) ~/ 2;
  final toleranceMs =
      trimEndSnapToleranceMs < halfSpanMs ? trimEndSnapToleranceMs : halfSpanMs;
  return position.inMilliseconds >= endMs - toleranceMs;
}
