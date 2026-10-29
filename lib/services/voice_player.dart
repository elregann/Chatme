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
    _subs.add(_backend.position.listen((p) {
      if (state.value.messageId != null && !_completed) {
        state.value = state.value.copyWith(position: p);
      }
    }));
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

  final VoiceBackend _backend;
  final List<StreamSubscription> _subs = [];
  final ValueNotifier<VoicePlayerState> state = ValueNotifier(const VoicePlayerState());
  bool _completed = false;

  Future<void> toggle(String messageId, String path) async {
    final current = state.value;
    final sameNote = current.messageId == messageId && current.error == null;

    if (sameNote) {
      if (current.playing) {
        await _backend.pause();
        return;
      }
      if (_completed) {
        _completed = false;
        await _backend.seek(Duration.zero);
      }
      await _backend.play();
      return;
    }

    _completed = false;
    state.value = VoicePlayerState(messageId: messageId);
    try {
      await _backend.stop();
      await _backend.load(path);
      await _backend.play();
    } catch (e) {
      state.value = VoicePlayerState(messageId: messageId, error: '$e');
    }
  }

  Future<void> seek(String messageId, Duration to) async {
    if (state.value.messageId != messageId || state.value.error != null) return;
    _completed = false;
    await _backend.seek(to);
  }

  Future<void> stop() async {
    _completed = false;
    state.value = const VoicePlayerState();
    try {
      await _backend.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    state.dispose();
    await _backend.dispose();
  }

  Future<void> _onCompleted() async {
    _completed = true;
    state.value = state.value.copyWith(playing: false, position: Duration.zero);
    try {
      await _backend.pause();
      await _backend.seek(Duration.zero);
    } catch (_) {}
  }
}
