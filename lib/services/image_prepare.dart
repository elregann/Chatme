// image_prepare.dart

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'jpeg_cleaner.dart';

class ImagePrepareException implements Exception {
  final String message;
  const ImagePrepareException(this.message);

  @override
  String toString() => message;
}

class ImagePlan {
  ImagePlan._();

  /// The size that fits the longer side into [maxSide], keeping the shape.
  static ({int width, int height}) fit(int width, int height, {required int maxSide}) {
    final longest = width > height ? width : height;
    if (longest <= maxSide) return (width: width, height: height);
    final scale = maxSide / longest;
    final w = (width * scale).round();
    final h = (height * scale).round();
    return (width: w < 1 ? 1 : w, height: h < 1 ? 1 : h);
  }
}

class PreparedImage {
  final Uint8List bytes;
  final int width;
  final int height;

  const PreparedImage(this.bytes, this.width, this.height);
}

const int _maxSourceBytes = 40 * 1024 * 1024;

class _Job {
  final Uint8List bytes;
  final int maxSide;
  final int quality;

  const _Job(this.bytes, this.maxSide, this.quality);
}

PreparedImage _prepareSync(_Job job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) throw const ImagePrepareException('this is not a picture');

  final upright = img.bakeOrientation(decoded);
  final size = ImagePlan.fit(upright.width, upright.height, maxSide: job.maxSide);
  final resized = (size.width == upright.width && size.height == upright.height)
      ? upright
      : img.copyResize(
          upright,
          width: size.width,
          height: size.height,
          interpolation: img.Interpolation.average,
        );

  final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: job.quality));
  final clean = JpegCleaner.stripMetadata(encoded);
  return PreparedImage(clean, resized.width, resized.height);
}

/// Turns a picked picture into a smaller upright JPEG with no camera or
/// location data, ready to be encrypted and sent. Runs off the main thread.
Future<PreparedImage> prepareImage(
  Uint8List source, {
  int maxSide = 1600,
  int quality = 85,
}) async {
  if (source.isEmpty) throw const ImagePrepareException('this is not a picture');
  if (source.length > _maxSourceBytes) throw const ImagePrepareException('this picture is too large');
  try {
    return await compute(_prepareSync, _Job(source, maxSide, quality));
  } on ImagePrepareException {
    rethrow;
  } on FormatException {
    throw const ImagePrepareException('this picture could not be read');
  }
}
