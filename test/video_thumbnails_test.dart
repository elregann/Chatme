import 'dart:io';
import 'dart:typed_data';

import 'package:chatme/services/video_thumbnails.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File video;
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chatme_thumbs');
    video = File('${dir.path}${Platform.pathSeparator}clip.mp4');
    await video.writeAsBytes([0, 1, 2, 3]);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('names the poster after the video, next to it', () {
    expect(VideoThumbnails.pathFor(video.path), '${video.path}.thumb.jpg');
  });

  test('makes a poster once and then reuses the file', () async {
    var calls = 0;
    final thumbs = VideoThumbnails(generate: (path) async {
      calls++;
      expect(path, video.path);
      return jpeg;
    });

    final first = await thumbs.ensure(video.path);
    final second = await thumbs.ensure(video.path);

    expect(first, VideoThumbnails.pathFor(video.path));
    expect(second, first);
    expect(calls, 1);
    expect(await File(first!).readAsBytes(), jpeg);
  });

  test('uses a poster that is already on disk', () async {
    final poster = File(VideoThumbnails.pathFor(video.path));
    await poster.writeAsBytes(jpeg);
    var calls = 0;
    final thumbs = VideoThumbnails(generate: (_) async {
      calls++;
      return jpeg;
    });

    expect(await thumbs.ensure(video.path), poster.path);
    expect(calls, 0);
  });

  test('two tiles asking at once share one generation', () async {
    var calls = 0;
    final thumbs = VideoThumbnails(generate: (_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return jpeg;
    });

    final results = await Future.wait<String?>([
      thumbs.ensure(video.path),
      thumbs.ensure(video.path),
    ]);

    expect(results, [VideoThumbnails.pathFor(video.path), VideoThumbnails.pathFor(video.path)]);
    expect(calls, 1);
  });

  test('returns null for a missing video and writes nothing', () async {
    final thumbs = VideoThumbnails(generate: (_) async => jpeg);
    await video.delete();

    expect(await thumbs.ensure(video.path), isNull);
    expect(File(VideoThumbnails.pathFor(video.path)).existsSync(), isFalse);
  });

  test('returns null for an empty path', () async {
    final thumbs = VideoThumbnails(generate: (_) async => jpeg);
    expect(await thumbs.ensure(''), isNull);
  });

  test('a frame that cannot be read is not retried on every rebuild', () async {
    var calls = 0;
    final thumbs = VideoThumbnails(generate: (_) async {
      calls++;
      return null;
    });

    expect(await thumbs.ensure(video.path), isNull);
    expect(await thumbs.ensure(video.path), isNull);
    expect(calls, 1);
  });

  test('a failing generator is treated as no poster', () async {
    final thumbs = VideoThumbnails(
      generate: (_) async => throw const FileSystemException('cannot decode'),
    );

    expect(await thumbs.ensure(video.path), isNull);
    expect(File(VideoThumbnails.pathFor(video.path)).existsSync(), isFalse);
  });
}
