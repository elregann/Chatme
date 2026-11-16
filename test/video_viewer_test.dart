import 'dart:async';

import 'package:chatme/models/chat_message.dart';
import 'package:chatme/ui/media/image_viewer.dart';
import 'package:chatme/ui/media/video_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A video player that never touches a real decoder, so tests can watch the
/// calls the app makes: create, play, pause and dispose.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final List<String> calls = <String>[];
  final Map<int, StreamController<VideoEvent>> _streams = {};
  final Duration duration;
  int _nextId = 0;

  FakeVideoPlayerPlatform({this.duration = const Duration(seconds: 12)});

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    calls.add('create');
    final id = _nextId++;
    final stream = StreamController<VideoEvent>();
    _streams[id] = stream;
    stream.add(VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(1080, 1920),
      duration: duration,
    ));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      calls.add('setLooping');

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.shrink();
}

void main() {
  ChatMessage msg(
    String id,
    int ts, {
    Map<String, String> file = const {},
    String path = '',
  }) =>
      ChatMessage(
        id: id,
        senderPubkey: 'a',
        receiverPubkey: 'b',
        content: 'c',
        plaintext: 'p',
        timestamp: ts,
        chatKey: 'k',
        file: file,
        localPath: path,
      );

  const image = {'type': 'image/jpeg'};
  const video = {'type': 'video/mp4', 'duration': '12'};

  late FakeVideoPlayerPlatform player;

  setUp(() {
    player = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = player;
  });

  Widget host(Widget page) => MaterialApp(home: page);

  Future<void> settlePlayer(WidgetTester tester) async {
    // Let the fake report its first frame and the page rebuild around it.
    await tester.pump();
    await tester.pump();
  }

  group('a video page in the gallery', () {
    Future<void> openVideo(WidgetTester tester) async {
      final media = [
        msg('v', 200, file: video, path: '/m/v.mp4'),
        msg('a', 100, file: image, path: '/m/a.jpg'),
      ];
      await tester.pumpWidget(host(ImageViewerPage(
        paths: media.map((m) => m.localPath).toList(),
        messages: media,
      )));
      await settlePlayer(tester);
    }

    testWidgets('opens paused with its clock and the counter', (tester) async {
      await openVideo(tester);

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('00:00 / 00:12'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(player.calls, isNot(contains('play')));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('plays only when the play button is tapped', (tester) async {
      await openVideo(tester);
      expect(player.calls, isNot(contains('play')));

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(player.calls, contains('play'));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      // Stop the position timer before the test ends.
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a swipe silences it and then releases the decoder',
        (tester) async {
      await openVideo(tester);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(player.calls, contains('play'));

      final pausesBefore = player.calls.where((c) => c == 'pause').length;
      await tester.drag(find.byType(PageView), const Offset(-120, 0));
      await tester.pump();
      expect(
        player.calls.where((c) => c == 'pause').length,
        greaterThan(pausesBefore),
      );

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byType(VideoPlayerView, skipOffstage: false), findsNothing);
      expect(player.calls, contains('dispose'));
    });

    testWidgets('Save uses the video gallery, not the picture one',
        (tester) async {
      final saved = <String>[];
      final media = [
        msg('v', 200, file: video, path: '/m/v.mp4'),
        msg('a', 100, file: image, path: '/m/a.jpg'),
      ];
      await tester.pumpWidget(host(ImageViewerPage(
        paths: media.map((m) => m.localPath).toList(),
        messages: media,
        saveToGallery: (path) async => saved.add('photo:$path'),
        saveVideoToGallery: (path) async => saved.add('video:$path'),
      )));
      await settlePlayer(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Gallery'));
      await tester.pumpAndSettle();

      expect(saved, ['video:/m/v.mp4']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('a full screen video', () {
    testWidgets('still plays as soon as it opens', (tester) async {
      await tester.pumpWidget(host(const VideoViewerPage(path: '/m/v.mp4')));
      await settlePlayer(tester);

      expect(player.calls, contains('play'));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
