// Bounds regression for the app-owned trim playhead.
//
// References:
// - Flutter RenderSlider._calcThumbCenter clamps the thumb to the track with
//   `clampDouble(..., trackRect.left + thumbPadding, trackRect.right - thumbPadding)`.
// - video_trimmer 6.0.0 TrimPlayback.scrubberX maps the playhead linearly from
//   the trim range onto [startX, endX], and TrimPlayback.positionMs clamps it
//   into the trim range first.
// - FixedTrimViewer quantizes the thumbnail strip to
//   `numberOfThumbnails * viewerHeight`, which can be narrower than the width
//   requested by the caller.

import 'package:chatme/core/utils/trim_playback_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const double _totalMs = 10000;

void main() {
  group('trim playhead bounds', () {
    test('uses the real thumbnail strip width, not the requested width', () {
      expect(trimStripWidth(398), 392);
      expect(trimStripWidth(392), 392);
      expect(trimStripWidth(56), 56);
    });

    test('maps trim handles from the trim range onto the strip', () {
      expect(
        trimHandleX(stripWidth: 392, positionMs: 0, totalMs: _totalMs),
        0,
      );
      expect(
        trimHandleX(stripWidth: 392, positionMs: 2000, totalMs: _totalMs),
        78.4,
      );
      expect(
        trimHandleX(stripWidth: 392, positionMs: 8000, totalMs: _totalMs),
        313.6,
      );
    });

    test('keeps the whole line inside the trim handles', () {
      const strip = 392.0;
      const startMs = 2000.0;
      const endMs = 8000.0;
      final startX = trimHandleX(
        stripWidth: strip,
        positionMs: startMs,
        totalMs: _totalMs,
      );
      final endX = trimHandleX(
        stripWidth: strip,
        positionMs: endMs,
        totalMs: _totalMs,
      );

      double leftAt(double positionMs) => trimPlayheadLeft(
            startX: startX,
            endX: endX,
            startMs: startMs,
            endMs: endMs,
            positionMs: positionMs,
          );

      expect(leftAt(startMs), startX);
      expect(leftAt(endMs) + trimPlayheadWidth, endX);

      for (final position in <double>[
        startMs - 500,
        startMs,
        4000,
        6000,
        endMs,
        endMs + 500,
      ]) {
        final left = leftAt(position);
        expect(left, greaterThanOrEqualTo(startX));
        expect(left + trimPlayheadWidth, lessThanOrEqualTo(endX));
      }
    });

    test('keeps the line inside a full-video strip', () {
      const strip = 392.0;
      const startMs = 0.0;
      const endMs = _totalMs;
      final endX = trimHandleX(
        stripWidth: strip,
        positionMs: endMs,
        totalMs: _totalMs,
      );

      final left = trimPlayheadLeft(
        startX: 0,
        endX: endX,
        startMs: startMs,
        endMs: endMs,
        positionMs: endMs,
      );

      expect(left + trimPlayheadWidth, lessThanOrEqualTo(strip));
      expect(left + trimPlayheadWidth, strip);
    });

    test('does not draw a line for an empty selection', () {
      expect(
        trimPlayheadLeft(
          startX: 10,
          endX: 10,
          startMs: 1000,
          endMs: 1000,
          positionMs: 1000,
        ),
        10,
      );
    });
  });
}
