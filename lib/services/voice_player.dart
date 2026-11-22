// voice_player.dart

import 'dart:async';
import 'package:flutter/foundation.dart';

/// What the player needs from an audio engine, so the rules below can be
/// tested without a phone.
abstract class VoiceBackend {
  Stream<Duration> get position;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<Duration?> get duration;
  Future<void> load(String path);

  /// Starts playing and returns right away, not when the file ends.
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);
  Future<void> stop();
  Future<void> dispose();
}

class VoicePlayerState {
  final String? messageId;
  final bool playing;
  final Duration position;
  final Duration? duration;
  final String? error;

  const VoicePlayerState({
    this.messageId,
    this.playing = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });

  VoicePlayerState copyWith({bool? playing, Duration? position, Duration? duration}) {
    return VoicePlayerState(
      messageId: messageId,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      error: error,
    );
  }
}

/// One voice note plays at a time. Tapping another one stops the first.
class VoicePlayer {
  VoicePlayer(this._backend) {
    // Native position is deliberately not consumed. On Android it can emit a
    // stale anchor right after play or seek, which makes the slider run forward
    // and then jump backward. Progress is owned by the local clock below.
    _subs.add(_backend.playing.listen((p) {
      if (state.value.messageId != null) {
        state.value = state.value.copyWith(playing: p && !_completed);
      }
    }));
    _subs.add(_backend.duration.listen((d) {
      if (state.value.messageId != null && d != null) {
        state.value = state.value.copyWith(duration: d);
      }
    }));
    _subs.add(_backend.completed.listen((done) {
      if (done) _onCompleted();
    }));
  }

  /// Gives the engine a moment to actually start on fresh playback or seek.
  /// Resuming from a pause must not restart this, or repeated taps accumulate lag.
  static const _playSettle = Duration(milliseconds: 300);
  static const _tickInterval = Duration(milliseconds: 40);

  final VoiceBackend _backend;
  final List<StreamSubscription> _subs = [];
  final ValueNotifier<VoicePlayerState> state = ValueNotifier(const VoicePlayerState());

  Timer? _ticker;
  Duration _anchor = Duration.zero;
  DateTime? _startsAt;
  bool _running = false;
  bool _completed = false;

  /// The only source of progress while a note is playing.
  Duration get _progress {
    if (!_running || _startsAt == null) return _anchor;
    final elapsed = DateTime.now().difference(_startsAt!);
    if (elapsed <= Duration.zero) return _anchor;
    return _anchor + elapsed;
  }

  void _publishPosition(Duration position) {
    if (state.value.messageId == null) return;
    state.value = state.value.copyWith(position: position);
  }

  void _startClock(Duration from, {bool settle = true}) {
    _ticker?.cancel();
    _anchor = from;
    _startsAt = DateTime.now().add(settle ? _playSettle : Duration.zero);
    _running = true;
    _publishPosition(from);
    _ticker = Timer.periodic(_tickInterval, (_) => _publishPosition(_progress));
  }

  void _freezeClock() {
    final at = _progress;
    _running = false;
    _startsAt = null;
    _anchor = at;
    _ticker?.cancel();
    _ticker = null;
    _publishPosition(at);
  }

  void _resetClock() {
    _ticker?.cancel();
    _ticker = null;
    _running = false;
    _startsAt = null;
    _anchor = Duration.zero;
  }

  Future<void> toggle(String messageId, String path) async {
    final current = state.value;
    final sameNote = current.messageId == messageId && current.error == null;

    if (sameNote) {
      if (current.playing) {
        _freezeClock();
        state.value = state.value.copyWith(playing: false);
        await _backend.pause();
        return;
      }
      final restart = _completed;
      final from = restart ? Duration.zero : current.position;
      _completed = false;
      state.value = state.value.copyWith(playing: true, position: from);
      if (restart) await _backend.seek(Duration.zero);
      await _backend.play();
      // A resumed pause continues immediately; a completed note plays fresh.
      _startClock(from, settle: restart);
      return;
    }

    _resetClock();
    _completed = false;
    state.value = VoicePlayerState(messageId: messageId, playing: true);
    try {
      await _backend.stop();
      await _backend.load(path);
      await _backend.play();
      _startClock(Duration.zero);
    } catch (e) {
      state.value = VoicePlayerState(messageId: messageId, error: '$e');
    }
  }

  Future<void> seek(String messageId, Duration to) async {
    if (state.value.messageId != messageId || state.value.error != null) return;
    _completed = false;
    if (_running) {
      _startClock(to);
    } else {
      _anchor = to;
      _publishPosition(to);
    }
    await _backend.seek(to);
  }

  Future<void> stop() async {
    _resetClock();
    _completed = false;
    state.value = const VoicePlayerState();
    try {
      await _backend.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _resetClock();
    for (final s in _subs) {
      await s.cancel();
    }
    state.dispose();
    await _backend.dispose();
  }

  Future<void> _onCompleted() async {
    _completed = true;
    _resetClock();
    state.value = state.value.copyWith(playing: false, position: Duration.zero);
    try {
      await _backend.pause();
      await _backend.seek(Duration.zero);
    } catch (_) {}
  }
}
