import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/gallery_save.dart';

class FakeGallery implements GalleryBackend {
  final calls = <String>[];
  Object? error;

  @override
  Future<void> saveImage(String path, {required String album}) async {
    calls.add('$album:$path');
    if (error != null) throw error!;
  }
}

void main() {
  late Directory dir;
  late File picture;
  late FakeGallery gallery;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gallery_save_test');
    picture = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
    gallery = FakeGallery();
    GallerySaver.backend = gallery;
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('save', () {
    test('sends the file to the Chatme album', () async {
      await GallerySaver.save(picture.path);
      expect(gallery.calls, ['Chatme:${picture.path}']);
    });

    test('a missing file never reaches the gallery', () async {
      expect(
        () => GallerySaver.save('${dir.path}/gone.jpg'),
        throwsA(isA<GallerySaveException>()),
      );
      expect(gallery.calls, isEmpty);
    });

    test('an empty path is refused', () async {
      expect(() => GallerySaver.save(''), throwsA(isA<GallerySaveException>()));
      expect(gallery.calls, isEmpty);
    });

    test('the message of a gallery failure is kept', () async {
      gallery.error = const GallerySaveException('Allow photo access to save');
      await expectLater(
        GallerySaver.save(picture.path),
        throwsA(isA<GallerySaveException>().having((e) => e.message, 'message', 'Allow photo access to save')),
      );
    });

    test('an unexpected failure becomes a plain message', () async {
      gallery.error = StateError('boom');
      await expectLater(
        GallerySaver.save(picture.path),
        throwsA(isA<GallerySaveException>().having((e) => e.message, 'message', 'Could not save the photo')),
      );
    });
  });

  group('saveIfWanted', () {
    test('does nothing when the setting is off', () async {
      final saved = await GallerySaver.saveIfWanted(enabled: false, received: true, path: picture.path);
      expect(saved, isFalse);
      expect(gallery.calls, isEmpty);
    });

    test('does nothing for pictures you sent', () async {
      final saved = await GallerySaver.saveIfWanted(enabled: true, received: false, path: picture.path);
      expect(saved, isFalse);
      expect(gallery.calls, isEmpty);
    });

    test('saves a received picture when the setting is on', () async {
      final saved = await GallerySaver.saveIfWanted(enabled: true, received: true, path: picture.path);
      expect(saved, isTrue);
      expect(gallery.calls, ['Chatme:${picture.path}']);
    });

    test('a failure is swallowed and reported as not saved', () async {
      gallery.error = const GallerySaveException('Allow photo access to save');
      final saved = await GallerySaver.saveIfWanted(enabled: true, received: true, path: picture.path);
      expect(saved, isFalse);
    });
  });
}
