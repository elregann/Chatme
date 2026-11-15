// video_metadata_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/video_metadata.dart';

void main() {
  group('videoMimeTypeFor', () {
    test('keeps a video mime type the picker already knew', () {
      expect(videoMimeTypeFor('anything.bin', 'video/mp4'), 'video/mp4');
      expect(videoMimeTypeFor('clip.mov', 'video/quicktime'), 'video/quicktime');
    });

    test('reads the type from the extension when the picker did not', () {
      expect(videoMimeTypeFor('/tmp/a.mp4', null), 'video/mp4');
      expect(videoMimeTypeFor('C:\\tmp\\a.MOV', ''), 'video/quicktime');
      expect(videoMimeTypeFor('/tmp/a.webm', null), 'video/webm');
      expect(videoMimeTypeFor('/tmp/a.mkv', null), 'video/x-matroska');
      expect(videoMimeTypeFor('/tmp/a.3gp', null), 'video/3gpp');
      expect(videoMimeTypeFor('/tmp/a.ogv', null), 'video/ogg');
      expect(videoMimeTypeFor('/tmp/a.avi', null), 'video/x-msvideo');
    });

    test('pictures and other files are not videos', () {
      expect(videoMimeTypeFor('/tmp/a.jpg', 'image/jpeg'), isNull);
      expect(videoMimeTypeFor('/tmp/a.jpg', null), isNull);
      expect(videoMimeTypeFor('/tmp/a', null), isNull);
      expect(videoMimeTypeFor('/tmp/a.', null), isNull);
      expect(videoMimeTypeFor('/tmp/a.mp4.txt', null), isNull);
    });
  });
}
