/// Monotonic clock for the trim scrubber drawn by the app.
///
/// `video_player` reports its position only every few hundred milliseconds and
/// those reports can arrive late. Letting them re-anchor a running playhead
/// makes the scrubber move forward and then jump back. This clock is moved by
/// the commands the UI gives the player, so a late report can never pull it
/// backwards.
class TrimPlaybackClock {
  TrimPlaybackClock({
    DateTime Function()? now,
    this.settle = const Duration(milliseconds: 300),
  }) : _now = now ?? DateTime.now;

  static const tickInterval = Duration(milliseconds: 40);

  /// Fresh playback and seeks wait this long before the line starts moving.
  /// A resume from pause must not restart it, or repeated taps accumulate lag.
  final Duration settle;

  final DateTime Function() _now;
  Duration _anchor = Duration.zero;
  DateTime? _startsAt;
  bool _running = false;

  bool get running => _running;

  Duration get position {
    if (!_running || _startsAt == null) return _anchor;
    final elapsed = _now().difference(_startsAt!);
    if (elapsed <= Duration.zero) return _anchor;
    return _anchor + elapsed;
  }

  /// Explicitly re-anchors after a seek or a trim-handle change.
  void seek(Duration to) {
    _running = false;
    _startsAt = null;
    _anchor = to;
  }

  /// Starts from [from]. Only fresh playback or a seek uses [withSettle].
  void start(Duration from, {bool withSettle = false}) {
    _anchor = from;
    _startsAt = _now().add(withSettle ? settle : Duration.zero);
    _running = true;
  }

  /// Freezes at the current visual position, not at the player's late report.
  void pause() {
    _anchor = position;
    _running = false;
    _startsAt = null;
  }

  /// Ends playback visually at the exact trim end.
  void snapTo(Duration to) {
    _anchor = to;
    _running = false;
    _startsAt = null;
  }

  void reset([Duration to = Duration.zero]) => snapTo(to);
}
