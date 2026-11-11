// crop_geometry_test.dart

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/ui/crop_geometry.dart';

void main() {
  group('fittedImageRect', () {
    test('a tall image fills the viewport height and is centered sideways', () {
      final rect = fittedImageRect(const Size(360, 700), const Size(1000, 2000));
      expect(rect.height, closeTo(700, 0.001));
      expect(rect.width, closeTo(350, 0.001));
      expect(rect.left, closeTo(5, 0.001));
      expect(rect.top, closeTo(0, 0.001));
    });

    test('a wide image fills the viewport width and is centered vertically', () {
      final rect = fittedImageRect(const Size(360, 700), const Size(1600, 900));
      expect(rect.width, closeTo(360, 0.001));
      expect(rect.height, closeTo(202.5, 0.001));
      expect(rect.left, closeTo(0, 0.001));
      expect(rect.top, closeTo(248.75, 0.001));
    });

    test('a small image is scaled up to fit', () {
      final rect = fittedImageRect(const Size(400, 400), const Size(100, 50));
      expect(rect, const Rect.fromLTWH(0, 100, 400, 200));
    });

    test('an empty viewport or image gives an empty rect', () {
      expect(fittedImageRect(Size.zero, const Size(10, 10)), Rect.zero);
      expect(fittedImageRect(const Size(10, 10), Size.zero), Rect.zero);
    });
  });

  group('resizeCropEdge', () {
    const bounds = Rect.fromLTWH(10, 20, 300, 400);
    const rect = Rect.fromLTRB(60, 100, 260, 300);

    test('moves only the dragged edge', () {
      final moved = resizeCropEdge(
        rect: rect,
        edge: CropEdge.top,
        delta: const Offset(30, 25),
        bounds: bounds,
      );
      expect(moved, const Rect.fromLTRB(60, 125, 260, 300));
    });

    test('each edge follows its own axis', () {
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.right, delta: const Offset(-20, 9), bounds: bounds),
        const Rect.fromLTRB(60, 100, 240, 300),
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.bottom, delta: const Offset(9, -20), bounds: bounds),
        const Rect.fromLTRB(60, 100, 260, 280),
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.left, delta: const Offset(15, 9), bounds: bounds),
        const Rect.fromLTRB(75, 100, 260, 300),
      );
    });

    test('an edge cannot leave the bounds', () {
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.top, delta: const Offset(0, -500), bounds: bounds).top,
        bounds.top,
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.right, delta: const Offset(500, 0), bounds: bounds).right,
        bounds.right,
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.bottom, delta: const Offset(0, 500), bounds: bounds).bottom,
        bounds.bottom,
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.left, delta: const Offset(-500, 0), bounds: bounds).left,
        bounds.left,
      );
    });

    test('an edge cannot shrink the rect below the minimum side', () {
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.top, delta: const Offset(0, 500), bounds: bounds).height,
        56,
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.left, delta: const Offset(500, 0), bounds: bounds).width,
        56,
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.bottom, delta: const Offset(0, -500), bounds: bounds).height,
        56,
      );
      expect(
        resizeCropEdge(rect: rect, edge: CropEdge.right, delta: const Offset(-500, 0), bounds: bounds).width,
        56,
      );
    });

    test('a zero drag changes nothing', () {
      for (final edge in CropEdge.values) {
        expect(
          resizeCropEdge(rect: rect, edge: edge, delta: Offset.zero, bounds: bounds),
          rect,
        );
      }
    });

    test('the full image rect can be shrunk and grown back without leaving the bounds', () {
      var current = bounds;
      for (final edge in CropEdge.values) {
        current = resizeCropEdge(rect: current, edge: edge, delta: const Offset(80, 80), bounds: bounds);
        expect(current.left, greaterThanOrEqualTo(bounds.left));
        expect(current.top, greaterThanOrEqualTo(bounds.top));
        expect(current.right, lessThanOrEqualTo(bounds.right));
        expect(current.bottom, lessThanOrEqualTo(bounds.bottom));
      }
      expect(current, isNot(bounds));

      const growth = {
        CropEdge.top: Offset(0, -500),
        CropEdge.right: Offset(500, 0),
        CropEdge.bottom: Offset(0, 500),
        CropEdge.left: Offset(-500, 0),
      };
      for (final entry in growth.entries) {
        current = resizeCropEdge(rect: current, edge: entry.key, delta: entry.value, bounds: bounds);
      }
      expect(current, bounds);
    });

    test('bounds smaller than the minimum side do not throw', () {
      const tiny = Rect.fromLTWH(0, 0, 40, 40);
      final moved = resizeCropEdge(
        rect: tiny,
        edge: CropEdge.left,
        delta: const Offset(30, 0),
        bounds: tiny,
      );
      expect(moved, tiny);
    });
  });
}
