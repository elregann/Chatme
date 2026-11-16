// video_thumbnails.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:video_thumbnail/video_thumbnail.dart';

/// One small JPEG poster per video, made once and reused by the media grid.
///
/// The poster lives next to the video as `<video>.thumb.jpg`, so it survives a
/// restart and the grid never needs to open a video decoder just to draw a
/// tile. A missing or broken video simply returns null and the grid keeps its
/// plain dark tile.
class VideoThumbnails {
  /// Turns a video file into JPEG bytes. Replaceable so tests need neither a
  /// real video nor the platform plugin.
  final Future<Uint8List?> Function(String videoPath) generate;

  /// Jobs already running, so two tiles asking for the same video share one.
  final Map<String, Future<String?>> _running = {};

  /// Videos whose poster could not be made, so they are not retried on every
  /// rebuild or scroll.
  final Set<String> _failed = {};

  VideoThumbnails({Future<Uint8List?> Function(String videoPath)? generate})
      : generate = generate ?? _generateWithPlugin;

  /// The one the app uses.
  static final VideoThumbnails instance = VideoThumbnails();

  /// Where the poster of [videoPath] is kept.
  static String pathFor(String videoPath) => '$videoPath.thumb.jpg';

  /// Returns the poster of [videoPath], making it first when it is missing.
  /// Null means there is nothing to show.
  Future<String?> ensure(String videoPath) {
    if (videoPath.isEmpty) return Future.value(null);
    final target = pathFor(videoPath);
    if (File(target).existsSync()) return Future.value(target);
    if (_failed.contains(videoPath)) return Future.value(null);
    return _running.putIfAbsent(videoPath, () => _make(videoPath, target));
  }

  Future<String?> _make(String videoPath, String target) async {
    try {
      if (!File(videoPath).existsSync()) {
        _failed.add(videoPath);
        return null;
      }
      final bytes = await generate(videoPath);
      if (bytes == null || bytes.isEmpty) {
        _failed.add(videoPath);
        return null;
      }
      final file = File(target);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return target;
    } catch (_) {
      _failed.add(videoPath);
      return null;
    } finally {
      _running.remove(videoPath);
    }
  }

  static Future<Uint8List?> _generateWithPlugin(String videoPath) {
    return VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 320,
      quality: 70,
    );
  }
}
