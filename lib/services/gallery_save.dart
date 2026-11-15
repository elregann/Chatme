// gallery_save.dart

import 'dart:io';
import 'package:gal/gal.dart';
import '../core/utils/debug_logger.dart';

class GallerySaveException implements Exception {
  final String message;
  const GallerySaveException(this.message);

  @override
  String toString() => message;
}

/// Puts a picture or a video in an album of the phone gallery.
abstract class GalleryBackend {
  Future<void> saveImage(String path, {required String album});
  Future<void> saveVideo(String path, {required String album});
}

class GalGalleryBackend implements GalleryBackend {
  const GalGalleryBackend();

  @override
  Future<void> saveImage(String path, {required String album}) {
    return _save(
      (p) => Gal.putImage(p, album: album),
      path,
      label: 'photo',
    );
  }

  @override
  Future<void> saveVideo(String path, {required String album}) {
    return _save(
      (p) => Gal.putVideo(p, album: album),
      path,
      label: 'video',
    );
  }

  Future<void> _save(
    Future<void> Function(String path) put,
    String path, {
    required String label,
  }) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          throw const GallerySaveException('Allow photo access to save');
        }
      }
      await put(path);
    } on GalException catch (e) {
      switch (e.type) {
        case GalExceptionType.accessDenied:
          throw const GallerySaveException('Allow photo access to save');
        case GalExceptionType.notEnoughSpace:
          throw const GallerySaveException('Not enough space on the phone');
        default:
          throw GallerySaveException('Could not save the $label');
      }
    }
  }
}

class GallerySaver {
  GallerySaver._();

  static const String album = 'Chatme';

  static GalleryBackend backend = const GalGalleryBackend();

  /// Copies a picture or a video into the Chatme album of the gallery.
  static Future<void> save(String path, {bool video = false}) async {
    final label = video ? 'video' : 'photo';
    if (path.isEmpty || !await File(path).exists()) {
      throw GallerySaveException('The $label is not on this phone');
    }
    try {
      if (video) {
        await backend.saveVideo(path, album: album);
      } else {
        await backend.saveImage(path, album: album);
      }
    } on GallerySaveException {
      rethrow;
    } catch (e) {
      DebugLogger.log('[Gallery] Save failed | $e', type: 'ERROR');
      throw GallerySaveException('Could not save the $label');
    }
  }

  /// Saves a received picture or video when the user turned that on. Never
  /// throws, and returns whether the file was saved.
  static Future<bool> saveIfWanted({
    required bool enabled,
    required bool received,
    required String path,
    bool video = false,
  }) async {
    if (!enabled || !received) return false;
    try {
      await save(path, video: video);
      return true;
    } catch (e) {
      DebugLogger.log('[Gallery] Automatic save failed | $e', type: 'WARN');
      return false;
    }
  }
}
