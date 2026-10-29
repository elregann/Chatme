// voice_player_test.dart

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/voice_player.dart';

class FakeBackend implements VoiceBackend {
  final positionCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final completedCtl = StreamController<bool>.broadcast();
  final durationCtl = StreamController<Duration?>.broadcast();
  final calls = <String>[];
  Object? loadError;

  @override
  Stream<Duration> get position => positionCtl.stream;
  @override
  Stream<bool> get playing => playingCtl.stream;
  @override
  Stream<bool> get completed => completedCtl.stream;
  @override
  Stream<Duration?> get duration => durationCtl.stream;

  @override
  Future<void> load(String path) async {
    calls.add('load:$path');
    if (loadError != null) throw loadError!;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playingCtl.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playingCtl.add(false);
  }

  @override
  Future<void> seek(Duration to) async => calls.add('seek:${to.inMilliseconds}');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late FakeBackend backend;
  late VoicePlayer player;

  setUp(() {
    backend = FakeBackend();
    player = VoicePlayer(backend);
  });

  test('tapping a new note loads it and starts playing', () async {
    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();

    expect(backend.calls, ['stop', 'load:/x/a.m4a', 'play']);
    expect(player.state.value.messageId, 'a');
    expect(player.state.value.playing, isTrue);
  });

  test('tapping the same note pauses it, and again resumes without loading', () async {
    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();
    backend.calls.clear();

    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();
    expect(backend.calls, ['pause']);
    expect(player.state.value.playing, isFalse);

    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();
    expect(backend.calls, ['pause', 'play']);
    expect(player.state.value.playing, isTrue);
  });

  test('tapping another note replaces the first one', () async {
    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();
    await player.toggle('b', '/x/b.m4a');
    await pumpEventQueue();

    expect(backend.calls.where((c) => c.startsWith('load:')), ['load:/x/a.m4a', 'load:/x/b.m4a']);
    expect(player.state.value.messageId, 'b');
    expect(player.state.value.position, Duration.zero);
  });

  test('position and duration reach the state', () async {
    await player.toggle('a', '/x/a.m4a');
    backend.durationCtl.add(const Duration(seconds: 30));
    backend.positionCtl.add(const Duration(seconds: 4));
    await pumpEventQueue();

    expect(player.state.value.duration, const Duration(seconds: 30));
    expect(player.state.value.position, const Duration(seconds: 4));
  });

  test('when the note ends it goes back to the start and stops', () async {
    await player.toggle('a', '/x/a.m4a');
    backend.positionCtl.add(const Duration(seconds: 29));
    await pumpEventQueue();
    backend.calls.clear();

    backend.completedCtl.add(true);
    await pumpEventQueue();

    expect(player.state.value.playing, isFalse);
    expect(player.state.value.position, Duration.zero);
    expect(backend.calls, ['pause', 'seek:0']);
  });

  test('tapping a finished note plays it again from the start without loading', () async {
    await player.toggle('a', '/x/a.m4a');
    backend.completedCtl.add(true);
    await pumpEventQueue();
    backend.calls.clear();

    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();

    expect(backend.calls, ['seek:0', 'play']);
    expect(player.state.value.playing, isTrue);
  });

  test('a file that cannot be loaded shows an error, and tapping again tries again', () async {
    backend.loadError = Exception('bad file');
    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();

    expect(player.state.value.error, isNotNull);
    expect(player.state.value.playing, isFalse);

    backend.loadError = null;
    backend.calls.clear();
    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();

    expect(backend.calls, ['stop', 'load:/x/a.m4a', 'play']);
    expect(player.state.value.error, isNull);
  });

  test('seek only works on the note that is loaded', () async {
    await player.toggle('a', '/x/a.m4a');
    backend.calls.clear();

    await player.seek('b', const Duration(seconds: 5));
    expect(backend.calls, isEmpty);

    await player.seek('a', const Duration(seconds: 5));
    expect(backend.calls, ['seek:5000']);
  });

  test('stop clears the state', () async {
    await player.toggle('a', '/x/a.m4a');
    await pumpEventQueue();

    await player.stop();

    expect(player.state.value.messageId, isNull);
    expect(player.state.value.playing, isFalse);
  });
}
