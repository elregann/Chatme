// voice_recorder.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// What the recorder needs from the phone, so the rules below can be tested.
abstract class RecorderBackend {
  /// Asks for the microphone permission if needed. True when it is granted.
  Future<bool> hasPermission();
  Future<void> start(String path);

  /// Stops and returns the path of the finished file.
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

enum RecorderStatus { idle, recording }

enum StartResult { started, noPermission, alreadyRecording, failed }

class RecordedVoice {
  final String path;
  final int seconds;
  const RecordedVoice(this.path, this.seconds);
}

/// Records one voice note at a time. There is no length limit.
class VoiceRecorder {
  VoiceRecorder(
    this._backend, {
    required Future<String> Function() newFilePath,
    DateTime Function()? now,
    Future<void> Function(String path)? deleteFile,
    this.minimum = const Duration(seconds: 1),
  })  : _newFilePath = newFilePath,
        _now = now ?? DateTime.now,
        _deleteFile = deleteFile ?? _deleteQuietly;

  final RecorderBackend _backend;
  final Future<String> Function() _newFilePath;
  final DateTime Function() _now;
  final Future<void> Function(String path) _deleteFile;
  final Duration minimum;

  final ValueNotifier<RecorderStatus> status = ValueNotifier(RecorderStatus.idle);
  DateTime? _startedAt;
  bool _starting = false;

  bool get isRecording => status.value == RecorderStatus.recording;

  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    return _now().difference(started);
  }

  Future<StartResult> start() async {
    if (isRecording || _starting) return StartResult.alreadyRecording;
    _starting = true;
    try {
      if (!await _backend.hasPermission()) return StartResult.noPermission;
      final path = await _newFilePath();
      await _backend.start(path);
      _startedAt = _now();
      status.value = RecorderStatus.recording;
      return StartResult.started;
    } catch (_) {
      _startedAt = null;
      return StartResult.failed;
    } finally {
      _starting = false;
    }
  }

  /// Stops and returns the recording, or null when nothing was recording or it
  /// was too short to keep (the file is deleted then).
  Future<RecordedVoice?> finish() async {
    if (!isRecording) return null;
    final length = elapsed;
    _startedAt = null;
    status.value = RecorderStatus.idle;

    String? path;
    try {
      path = await _backend.stop();
    } catch (_) {
      return null;
    }
    if (path == null) return null;

    if (length < minimum) {
      await _deleteFile(path);
      return null;
    }
    return RecordedVoice(path, length.inSeconds < 1 ? 1 : length.inSeconds);
  }

  /// Throws the recording away.
  Future<void> cancel() async {
    if (!isRecording) return;
    _startedAt = null;
    status.value = RecorderStatus.idle;
    try {
      await _backend.cancel();
    } catch (_) {}
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
