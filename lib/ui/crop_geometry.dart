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
///
/// When [aspectRatio] (width divided by height) is given, the rect keeps that
/// shape: the edge opposite the drag stays put, the dragged edge follows the
/// pointer, and the other axis grows or shrinks around the rect's center. The
/// rect also slides just enough to stay inside [bounds]. Without it, only the
/// dragged edge moves.
Rect resizeCropEdge({
  required Rect rect,
  required CropEdge edge,
  required Offset delta,
  required Rect bounds,
  double minSide = 56,
  double? aspectRatio,
}) {
  if (aspectRatio != null && aspectRatio > 0) {
    return _resizeCropEdgeFixedRatio(
      rect: rect,
      edge: edge,
      delta: delta,
      bounds: bounds,
      minSide: minSide,
      aspectRatio: aspectRatio,
    );
  }

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

/// Resizes [rect] from one [edge] while keeping [aspectRatio] (width / height).
///
/// The rect is clamped between the smallest one that keeps its shorter side at
/// [minSide] and the largest one that fits inside [bounds].
Rect _resizeCropEdgeFixedRatio({
  required Rect rect,
  required CropEdge edge,
  required Offset delta,
  required Rect bounds,
  required double minSide,
  required double aspectRatio,
}) {
  final maxWidth = math.min(bounds.width, bounds.height * aspectRatio);
  final maxHeight = math.min(bounds.height, bounds.width / aspectRatio);
  final minWidth = math.min(
    aspectRatio >= 1 ? minSide * aspectRatio : minSide,
    maxWidth,
  );
  final minHeight = math.min(
    aspectRatio >= 1 ? minSide : minSide / aspectRatio,
    maxHeight,
  );

  double width;
  double height;
  double left;
  double top;
  switch (edge) {
    case CropEdge.right:
      width = _clamp(rect.width + delta.dx, minWidth, maxWidth);
      height = width / aspectRatio;
      left = rect.left;
      top = rect.center.dy - height / 2;
    case CropEdge.left:
      width = _clamp(rect.width - delta.dx, minWidth, maxWidth);
      height = width / aspectRatio;
      left = rect.right - width;
      top = rect.center.dy - height / 2;
    case CropEdge.bottom:
      height = _clamp(rect.height + delta.dy, minHeight, maxHeight);
      width = height * aspectRatio;
      left = rect.center.dx - width / 2;
      top = rect.top;
    case CropEdge.top:
      height = _clamp(rect.height - delta.dy, minHeight, maxHeight);
      width = height * aspectRatio;
      left = rect.center.dx - width / 2;
      top = rect.bottom - height;
  }

  return Rect.fromLTWH(
    _clamp(left, bounds.left, bounds.right - width),
    _clamp(top, bounds.top, bounds.bottom - height),
    width,
    height,
  );
}

double _clamp(double value, double lower, double upper) =>
    math.max(lower, math.min(upper, value));
