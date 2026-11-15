// storage_space_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/storage_space.dart';

void main() {
  group('requiredFor', () {
    test('a small file still needs the margin on top', () {
      expect(
        StorageSpace.requiredFor(1024 * 1024),
        1024 * 1024 + StorageSpace.marginFloor,
      );
    });

    test('a big file needs a fifth of its own size on top', () {
      const size = 500 * 1024 * 1024;
      expect(StorageSpace.requiredFor(size), size + size ~/ 5);
    });

    test('the margin never drops below the floor', () {
      const size = 40 * 1024 * 1024;
      // A fifth is 8 MB, which is less than the 20 MB floor.
      expect(StorageSpace.requiredFor(size), size + StorageSpace.marginFloor);
    });

    test('an empty file only needs the margin', () {
      expect(StorageSpace.requiredFor(0), StorageSpace.marginFloor);
    });
  });
}
