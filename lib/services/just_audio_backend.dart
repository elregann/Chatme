// just_audio_backend.dart

import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'voice_player.dart';

class JustAudioBackend implements VoiceBackend {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Stream<bool> get completed => _player.processingStateStream
      .map((s) => s == ProcessingState.completed)
      .distinct();

  @override
  Stream<Duration?> get duration => _player.durationStream;

  @override
  Future<void> load(String path) => _player.setFilePath(path);

  @override
  Future<void> play() async {
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration to) => _player.seek(to);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

VoicePlayer? _shared;

/// The one player the whole app uses, created the first time a voice note is played.
VoicePlayer get voicePlayer => _shared ??= VoicePlayer(JustAudioBackend());

/// Stops playback if a voice note was ever played, without creating the player.
void stopVoicePlayer() => _shared?.stop();
