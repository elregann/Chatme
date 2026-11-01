// jpeg_cleaner_test.dart

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/jpeg_cleaner.dart';

Uint8List segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return Uint8List.fromList([0xFF, marker, length >> 8, length & 0xFF, ...payload]);
}

Uint8List jpeg(List<Uint8List> segments, {List<int> scan = const [1, 2, 0xFF, 0x00, 3]}) {
  final sos = segment(0xDA, [0x00, 0x01, 0x02]);
  return Uint8List.fromList([
    0xFF, 0xD8,
    for (final s in segments) ...s,
    ...sos,
    ...scan,
    0xFF, 0xD9,
  ]);
}

bool contains(Uint8List bytes, String text) {
  final needle = text.codeUnits;
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  final jfif = segment(0xE0, 'JFIF'.codeUnits);
  final exif = segment(0xE1, [...'Exif'.codeUnits, 0, 0, ...'SecretCam GPS 6.2N'.codeUnits]);
  final xmp = segment(0xE1, 'http://ns.adobe.com/xap/1.0/ SecretXmp'.codeUnits);
  final comment = segment(0xFE, 'SecretComment'.codeUnits);
  final table = segment(0xDB, List.filled(64, 5));

  test('removes the camera and location data', () {
    final input = jpeg([jfif, exif, xmp, comment, table]);
    final output = JpegCleaner.stripMetadata(input);

    expect(contains(output, 'SecretCam'), isFalse);
    expect(contains(output, 'SecretXmp'), isFalse);
    expect(contains(output, 'SecretComment'), isFalse);
    expect(contains(output, 'Exif'), isFalse);
  });

  test('keeps the picture itself byte for byte', () {
    final input = jpeg([jfif, exif, table]);
    final output = JpegCleaner.stripMetadata(input);

    expect(output.sublist(0, 2), [0xFF, 0xD8]);
    expect(contains(output, 'JFIF'), isTrue);
    expect(output.sublist(output.length - 2), [0xFF, 0xD9]);

    final expected = jpeg([jfif, table]);
    expect(output, expected);
  });

  test('copies everything after the start of scan untouched, even bytes that look like markers', () {
    final scan = [0xFF, 0xE1, 0x00, 0x05, 0xAA, 0xBB, 0xCC, 0xFF, 0x00];
    final input = jpeg([exif], scan: scan);
    final output = JpegCleaner.stripMetadata(input);
    expect(output, jpeg(const [], scan: scan));
  });

  test('a jpeg without metadata is unchanged', () {
    final input = jpeg([jfif, table]);
    expect(JpegCleaner.stripMetadata(input), input);
  });

  test('rejects data that is not a jpeg', () {
    expect(() => JpegCleaner.stripMetadata(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
    expect(() => JpegCleaner.stripMetadata(Uint8List(0)), throwsFormatException);
  });

  test('rejects a segment that runs past the end', () {
    final broken = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 1, 2]);
    expect(() => JpegCleaner.stripMetadata(broken), throwsFormatException);
  });
}
