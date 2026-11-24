import 'story_item.dart';

/// Timing rules for the story viewer progress bars.
class StoryTiming {
  StoryTiming._();

  static const Duration imageDuration = Duration(seconds: 5);

  /// Photos get a fixed duration. Videos use the real player duration when it
  /// is available, then the metadata saved with the story, then the same five
  /// second fallback as photos.
  static Duration durationFor(
    StoryItem story, {
    Duration? videoDuration,
  }) {
    if (!story.isVideo) return imageDuration;

    if (videoDuration != null && videoDuration > Duration.zero) {
      return videoDuration;
    }
    final metadataSeconds = story.durationSeconds ?? 0;
    if (metadataSeconds > 0) return Duration(seconds: metadataSeconds);
    return imageDuration;
  }

  static double progress(Duration elapsed, Duration duration) {
    if (duration <= Duration.zero) return 0.0;
    final value = elapsed.inMilliseconds / duration.inMilliseconds;
    if (value <= 0) return 0.0;
    if (value >= 1) return 1.0;
    return value;
  }
}

/// Wall-clock progress for one slide, with pause/resume that preserves the
/// elapsed time. Photos drive their ticker from [progress]; videos pause the
/// player directly but still use this clock to know whether the slide is done.
class StoryPlayback {
  StoryPlayback({
    required this.duration,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration duration;
  final DateTime Function() _now;
  Duration _accumulated = Duration.zero;
  DateTime? _startedAt;

  bool get isPaused => _startedAt == null;

  Duration get elapsed {
    final started = _startedAt;
    final running = started == null ? Duration.zero : _now().difference(started);
    final total = _accumulated +
        (running.isNegative ? Duration.zero : running);
    if (total <= Duration.zero) return Duration.zero;
    if (total >= duration) return duration;
    return total;
  }

  double get progress => StoryTiming.progress(elapsed, duration);

  bool get isFinished => elapsed >= duration;

  void start() {
    if (_startedAt != null) return;
    _startedAt = _now();
  }

  void pause() {
    final started = _startedAt;
    if (started == null) return;
    final delta = _now().difference(started);
    if (!delta.isNegative) _accumulated += delta;
    _startedAt = null;
  }

  void resume() {
    if (_startedAt != null) return;
    _startedAt = _now();
  }
}
