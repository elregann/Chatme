// video_metadata.dart

import 'dart:io';

import 'package:video_player/video_player.dart';

/// The length and pixel size of a local video.
class VideoMetadata {
  final int seconds;
  final int? width;
  final int? height;

  const VideoMetadata({required this.seconds, this.width, this.height});
}

/// Reads the length and size with the same player that will show the video.
/// Returns null when the file cannot be opened; the video is still sent then,
/// only without a size and a duration.
Future<VideoMetadata?> readVideoMetadata(String path) async {
  final controller = VideoPlayerController.file(File(path));
  try {
    await controller.initialize();
    final value = controller.value;
    final size = value.size;
    return VideoMetadata(
      seconds: value.duration.inSeconds,
      width: size.width > 0 ? size.width.round() : null,
      height: size.height > 0 ? size.height.round() : null,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      await controller.dispose();
    } catch (_) {}
  }
}

const Set<String> _videoExtensions = {
  'mp4',
  'm4v',
  'mov',
  'webm',
  'mkv',
  '3gp',
  '3g2',
  'ogv',
  'avi',
};

/// The mime type of a video picked from the gallery, or null when the file is
/// not a video. The picker usually knows the type; the extension is only a
/// fallback for the times it does not.
String? videoMimeTypeFor(String path, String? mimeType) {
  if (mimeType != null && mimeType.startsWith('video/')) return mimeType;

  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  final extension = name.substring(dot + 1).toLowerCase();
  if (!_videoExtensions.contains(extension)) return null;

  switch (extension) {
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'mkv':
      return 'video/x-matroska';
    case '3gp':
    case '3g2':
      return 'video/3gpp';
    case 'ogv':
      return 'video/ogg';
    case 'avi':
      return 'video/x-msvideo';
    default:
      return null;
  }
}
