// image_prepare_test.dart

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:chatme/services/image_prepare.dart';

void main() {
  group('ImagePlan.fit', () {
    test('a small picture keeps its size', () {
      final size = ImagePlan.fit(800, 600, maxSide: 1600);
      expect((size.width, size.height), (800, 600));
    });

    test('a wide picture is scaled so the long side fits', () {
      final size = ImagePlan.fit(4000, 3000, maxSide: 1600);
      expect((size.width, size.height), (1600, 1200));
    });

    test('a tall picture is scaled so the long side fits', () {
      final size = ImagePlan.fit(3000, 4000, maxSide: 1600);
      expect((size.width, size.height), (1200, 1600));
    });

    test('never returns an empty side', () {
      final size = ImagePlan.fit(100000, 10, maxSide: 1600);
      expect(size.width, 1600);
      expect(size.height, greaterThanOrEqualTo(1));
    });
  });

  group('prepareImage', () {
    Uint8List sample(int width, int height) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(30, 120, 200));
      return Uint8List.fromList(img.encodeJpg(image));
    }

    test('shrinks a large picture and gives back a jpeg of the new size', () async {
      final prepared = await prepareImage(sample(2400, 1200), maxSide: 1000);
      expect(prepared.width, 1000);
      expect(prepared.height, 500);
      expect(prepared.bytes.sublist(0, 2), [0xFF, 0xD8]);

      final decoded = img.decodeJpg(prepared.bytes)!;
      expect((decoded.width, decoded.height), (1000, 500));
    });

    test('keeps a small picture at its size', () async {
      final prepared = await prepareImage(sample(300, 200), maxSide: 1000);
      expect((prepared.width, prepared.height), (300, 200));
    });

    test('leaves no exif block in the result', () async {
      final prepared = await prepareImage(sample(400, 300), maxSide: 1000);
      final text = String.fromCharCodes(prepared.bytes);
      expect(text.contains('Exif'), isFalse);
    });

    test('refuses something that is not a picture', () async {
      expect(
        prepareImage(Uint8List.fromList(List.filled(200, 7))),
        throwsA(isA<ImagePrepareException>()),
      );
    });
  });
}
