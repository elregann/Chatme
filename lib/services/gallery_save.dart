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

/// Puts a picture in an album of the phone gallery.
abstract class GalleryBackend {
  Future<void> saveImage(String path, {required String album});
}

class GalGalleryBackend implements GalleryBackend {
  const GalGalleryBackend();

  @override
  Future<void> saveImage(String path, {required String album}) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          throw const GallerySaveException('Allow photo access to save');
        }
      }
      await Gal.putImage(path, album: album);
    } on GalException catch (e) {
      switch (e.type) {
        case GalExceptionType.accessDenied:
          throw const GallerySaveException('Allow photo access to save');
        case GalExceptionType.notEnoughSpace:
          throw const GallerySaveException('Not enough space on the phone');
        default:
          throw const GallerySaveException('Could not save the photo');
      }
    }
  }
}

class GallerySaver {
  GallerySaver._();

  static const String album = 'Chatme';

  static GalleryBackend backend = const GalGalleryBackend();

  /// Copies the picture into the Chatme album of the gallery.
  static Future<void> save(String path) async {
    if (path.isEmpty || !await File(path).exists()) {
      throw const GallerySaveException('The photo is not on this phone');
    }
    try {
      await backend.saveImage(path, album: album);
    } on GallerySaveException {
      rethrow;
    } catch (e) {
      DebugLogger.log('[Gallery] Save failed | $e', type: 'ERROR');
      throw const GallerySaveException('Could not save the photo');
    }
  }

  /// Saves a received picture when the user turned that on. Never throws,
  /// and returns whether the picture was saved.
  static Future<bool> saveIfWanted({
    required bool enabled,
    required bool received,
    required String path,
  }) async {
    if (!enabled || !received) return false;
    try {
      await save(path);
      return true;
    } catch (e) {
      DebugLogger.log('[Gallery] Automatic save failed | $e', type: 'WARN');
      return false;
    }
  }
}
