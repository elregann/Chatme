// jpeg_cleaner.dart

import 'dart:typed_data';

/// Removes the metadata blocks of a JPEG (camera data, location, thumbnails,
/// text comments) and leaves the picture bytes untouched.
class JpegCleaner {
  JpegCleaner._();

  static bool _isMetadata(int marker) {
    if (marker == 0xFE) return true;
    return marker >= 0xE1 && marker <= 0xEF && marker != 0xEE;
  }

  static Uint8List stripMetadata(Uint8List jpeg) {
    if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
      throw const FormatException('not a jpeg');
    }

    final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
    var i = 2;
    while (i + 1 < jpeg.length) {
      if (jpeg[i] != 0xFF) throw const FormatException('bad jpeg marker');
      final marker = jpeg[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD9) {
        out.add(const [0xFF, 0xD9]);
        return out.takeBytes();
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        out.add(jpeg.sublist(i, i + 2));
        i += 2;
        continue;
      }
      if (i + 3 >= jpeg.length) throw const FormatException('jpeg ends early');
      final length = (jpeg[i + 2] << 8) | jpeg[i + 3];
      if (length < 2 || i + 2 + length > jpeg.length) {
        throw const FormatException('jpeg segment is too long');
      }
      if (marker == 0xDA) {
        out.add(jpeg.sublist(i));
        return out.takeBytes();
      }
      if (!_isMetadata(marker)) out.add(jpeg.sublist(i, i + 2 + length));
      i += 2 + length;
    }
    throw const FormatException('jpeg has no picture data');
  }
}
