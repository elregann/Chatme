// voice_recorder_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/voice_recorder.dart';

class FakeRecorderBackend implements RecorderBackend {
  final calls = <String>[];
  bool permission = true;
  Object? startError;
  String? stopPath = '/tmp/rec.m4a';

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start(String path) async {
    calls.add('start:$path');
    if (startError != null) throw startError!;
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
    return stopPath;
  }

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late FakeRecorderBackend backend;
  late DateTime clock;
  late List<String> deleted;
  late VoiceRecorder recorder;

  setUp(() {
    backend = FakeRecorderBackend();
    clock = DateTime(2026, 1, 1, 12);
    deleted = [];
    recorder = VoiceRecorder(
      backend,
      newFilePath: () async => '/tmp/new.m4a',
      now: () => clock,
      deleteFile: (path) async => deleted.add(path),
    );
  });

  test('start begins recording to a new file', () async {
    final result = await recorder.start();

    expect(result, StartResult.started);
    expect(recorder.isRecording, isTrue);
    expect(backend.calls, ['start:/tmp/new.m4a']);
  });

  test('without the microphone permission nothing starts', () async {
    backend.permission = false;

    final result = await recorder.start();

    expect(result, StartResult.noPermission);
    expect(recorder.isRecording, isFalse);
    expect(backend.calls, isEmpty);
  });

  test('a backend that fails to start leaves the recorder idle and able to retry', () async {
    backend.startError = Exception('mic busy');
    expect(await recorder.start(), StartResult.failed);
    expect(recorder.isRecording, isFalse);

    backend.startError = null;
    expect(await recorder.start(), StartResult.started);
  });

  test('a second start while recording is ignored', () async {
    await recorder.start();

    expect(await recorder.start(), StartResult.alreadyRecording);
    expect(backend.calls.where((c) => c.startsWith('start')), hasLength(1));
  });

  test('elapsed follows the clock while recording', () async {
    await recorder.start();
    clock = clock.add(const Duration(seconds: 7, milliseconds: 400));

    expect(recorder.elapsed, const Duration(seconds: 7, milliseconds: 400));
  });

  test('finish returns the file and the length in seconds', () async {
    await recorder.start();
    clock = clock.add(const Duration(seconds: 12, milliseconds: 900));

    final voice = await recorder.finish();

    expect(voice!.path, '/tmp/rec.m4a');
    expect(voice.seconds, 12);
    expect(recorder.isRecording, isFalse);
    expect(recorder.elapsed, Duration.zero);
    expect(deleted, isEmpty);
  });

  test('a recording shorter than a second is deleted', () async {
    await recorder.start();
    clock = clock.add(const Duration(milliseconds: 600));

    final voice = await recorder.finish();

    expect(voice, isNull);
    expect(deleted, ['/tmp/rec.m4a']);
    expect(recorder.isRecording, isFalse);
  });

  test('a recording of exactly one second is kept', () async {
    await recorder.start();
    clock = clock.add(const Duration(seconds: 1));

    final voice = await recorder.finish();

    expect(voice!.seconds, 1);
  });

  test('long recordings are not cut off', () async {
    await recorder.start();
    clock = clock.add(const Duration(hours: 1, minutes: 5, seconds: 3));

    final voice = await recorder.finish();

    expect(voice!.seconds, 3903);
  });

  test('finish when nothing is recording does nothing', () async {
    expect(await recorder.finish(), isNull);
    expect(backend.calls, isEmpty);
  });

  test('finish returns null when the backend gives no file', () async {
    backend.stopPath = null;
    await recorder.start();
    clock = clock.add(const Duration(seconds: 5));

    expect(await recorder.finish(), isNull);
    expect(recorder.isRecording, isFalse);
  });

  test('cancel stops recording and asks the backend to drop the file', () async {
    await recorder.start();

    await recorder.cancel();

    expect(recorder.isRecording, isFalse);
    expect(backend.calls.last, 'cancel');
    expect(recorder.elapsed, Duration.zero);
  });

  test('cancel when idle does nothing', () async {
    await recorder.cancel();
    expect(backend.calls, isEmpty);
  });

  test('after a cancel the next recording starts clean', () async {
    await recorder.start();
    clock = clock.add(const Duration(seconds: 30));
    await recorder.cancel();

    await recorder.start();
    clock = clock.add(const Duration(seconds: 2));

    expect(recorder.elapsed, const Duration(seconds: 2));
  });

  test('status notifies listeners', () async {
    final seen = <RecorderStatus>[];
    recorder.status.addListener(() => seen.add(recorder.status.value));

    await recorder.start();
    await recorder.cancel();

    expect(seen, [RecorderStatus.recording, RecorderStatus.idle]);
  });
}
