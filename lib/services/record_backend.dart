// record_backend.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'voice_recorder.dart';

class RecordPackageBackend implements RecorderBackend {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) {
    return _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

VoiceRecorder? _shared;

/// The one recorder the app uses, created the first time someone records.
VoiceRecorder get voiceRecorder => _shared ??= VoiceRecorder(
      RecordPackageBackend(),
      newFilePath: () async {
        final dir = await getTemporaryDirectory();
        return '${dir.path}${Platform.pathSeparator}rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      },
    );

/// Throws a recording away if one is running, without creating the recorder.
void cancelVoiceRecording() => _shared?.cancel();
