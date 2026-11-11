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

  group('resizeCropEdge with an aspect ratio', () {
    const bounds = Rect.fromLTWH(10, 20, 300, 400);
    const square = Rect.fromLTRB(60, 100, 160, 200); // 100x100

    test('dragging the right edge keeps the square and the left edge still', () {
      final moved = resizeCropEdge(
        rect: square,
        edge: CropEdge.right,
        delta: const Offset(40, 0),
        bounds: bounds,
        aspectRatio: 1,
      );
      expect(moved, const Rect.fromLTRB(60, 80, 200, 220));
    });

    test('dragging the top edge keeps the square and the bottom edge still', () {
      final moved = resizeCropEdge(
        rect: square,
        edge: CropEdge.top,
        delta: const Offset(0, -30),
        bounds: bounds,
        aspectRatio: 1,
      );
      expect(moved, const Rect.fromLTRB(45, 70, 175, 200));
    });

    test('dragging the left edge grows the square toward the right', () {
      final moved = resizeCropEdge(
        rect: square,
        edge: CropEdge.left,
        delta: const Offset(-20, 0),
        bounds: bounds,
        aspectRatio: 1,
      );
      expect(moved, const Rect.fromLTRB(40, 90, 160, 210));
    });

    test('an edge cannot shrink the square below the minimum side', () {
      final moved = resizeCropEdge(
        rect: square,
        edge: CropEdge.right,
        delta: const Offset(-500, 0),
        bounds: bounds,
        aspectRatio: 1,
      );
      expect(moved.width, 56);
      expect(moved.height, 56);
      expect(moved.left, 60);
    });

    test('a square already filling the shorter side cannot grow', () {
      const wide = Rect.fromLTWH(0, 0, 360, 202);
      const full = Rect.fromLTWH(79, 0, 202, 202);
      const growth = {
        CropEdge.top: Offset(0, -500),
        CropEdge.right: Offset(500, 0),
        CropEdge.bottom: Offset(0, 500),
        CropEdge.left: Offset(-500, 0),
      };
      for (final entry in growth.entries) {
        expect(
          resizeCropEdge(
            rect: full,
            edge: entry.key,
            delta: entry.value,
            bounds: wide,
            aspectRatio: 1,
          ),
          full,
        );
      }
    });

    test('growing past the bounds slides the square to stay inside them', () {
      var current = square;
      const growth = {
        CropEdge.top: Offset(0, -500),
        CropEdge.right: Offset(500, 0),
        CropEdge.bottom: Offset(0, 500),
        CropEdge.left: Offset(-500, 0),
      };
      for (final entry in growth.entries) {
        current = resizeCropEdge(
          rect: current,
          edge: entry.key,
          delta: entry.value,
          bounds: bounds,
          aspectRatio: 1,
        );
        expect(current.width, current.height);
        expect(current.left, greaterThanOrEqualTo(bounds.left));
        expect(current.top, greaterThanOrEqualTo(bounds.top));
        expect(current.right, lessThanOrEqualTo(bounds.right));
        expect(current.bottom, lessThanOrEqualTo(bounds.bottom));
      }
      expect(current, const Rect.fromLTWH(10, 20, 300, 300));
    });

    test('a zero drag changes nothing', () {
      for (final edge in CropEdge.values) {
        expect(
          resizeCropEdge(
            rect: square,
            edge: edge,
            delta: Offset.zero,
            bounds: bounds,
            aspectRatio: 1,
          ),
          square,
        );
      }
    });

    test('a non-square ratio is kept too', () {
      const ratio = 4 / 3;
      const rect = Rect.fromLTRB(60, 100, 260, 250); // already 200x150
      final moved = resizeCropEdge(
        rect: rect,
        edge: CropEdge.bottom,
        delta: const Offset(0, 50),
        bounds: bounds,
        aspectRatio: ratio,
      );
      expect(moved.height, 200);
      expect(moved.width, closeTo(200 * ratio, 0.001));
      expect(moved.width / moved.height, closeTo(ratio, 0.001));
      expect(moved.top, 100);
      expect(moved.left, closeTo(160 - 200 * ratio / 2, 0.001));
    });
  });
}
