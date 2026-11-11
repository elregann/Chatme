// crop_geometry.dart

import 'dart:math' as math;
import 'dart:ui';

enum CropEdge { top, right, bottom, left }

/// Where an image of [image] size is drawn when it is centered and scaled to
/// fit inside a viewport of [viewport] size.
Rect fittedImageRect(Size viewport, Size image) {
  if (viewport.isEmpty || image.isEmpty) return Rect.zero;

  final scale = math.min(
    viewport.width / image.width,
    viewport.height / image.height,
  );
  final width = image.width * scale;
  final height = image.height * scale;
  return Rect.fromLTWH(
    (viewport.width - width) / 2,
    (viewport.height - height) / 2,
    width,
    height,
  );
}

/// Moves one edge of [rect] by [delta], keeping the result inside [bounds] and
/// at least [minSide] wide and tall (or as large as [bounds] allows).
Rect resizeCropEdge({
  required Rect rect,
  required CropEdge edge,
  required Offset delta,
  required Rect bounds,
  double minSide = 56,
}) {
  final minWidth = math.min(minSide, bounds.width);
  final minHeight = math.min(minSide, bounds.height);

  var left = rect.left;
  var top = rect.top;
  var right = rect.right;
  var bottom = rect.bottom;

  switch (edge) {
    case CropEdge.top:
      top = _clamp(top + delta.dy, bounds.top, bottom - minHeight);
    case CropEdge.right:
      right = _clamp(right + delta.dx, left + minWidth, bounds.right);
    case CropEdge.bottom:
      bottom = _clamp(bottom + delta.dy, top + minHeight, bounds.bottom);
    case CropEdge.left:
      left = _clamp(left + delta.dx, bounds.left, right - minWidth);
  }

  return Rect.fromLTRB(left, top, right, bottom);
}

double _clamp(double value, double lower, double upper) =>
    math.max(lower, math.min(upper, value));
