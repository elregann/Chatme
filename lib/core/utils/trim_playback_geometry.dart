// Pixel geometry for the app-owned trim playhead.
//
// `video_trimmer 6.0.0` maps its playhead from the trim range onto the two
// handles, not onto the whole viewer. It also rounds the thumbnail strip down
// to whole thumbnails. These helpers follow both rules so the app's line
// stays inside the same box the package draws.

/// Width of the app's playhead line, matching the package's scrubber width.
const double trimPlayheadWidth = 2;

/// Height passed to `TrimViewer` by the trim page.
const double trimViewerHeight = 56;

/// The package's real strip width: `numberOfThumbnails * viewerHeight`, where
/// `numberOfThumbnails = requestedWidth ~/ viewerHeight`.
double trimStripWidth(double requestedWidth) =>
    (requestedWidth / trimViewerHeight).floor() * trimViewerHeight;

double _clamp01(double value) => value < 0 ? 0 : value > 1 ? 1 : value;

/// X of a trim handle, measured from the left edge of the thumbnail strip.
double trimHandleX({
  required double stripWidth,
  required double positionMs,
  required double totalMs,
}) {
  if (stripWidth <= 0 || totalMs <= 0) return 0;
  return stripWidth * _clamp01(positionMs / totalMs);
}

/// Left edge of the playhead line inside `[startX, endX]`.
///
/// The returned value is clamped so the whole `trimPlayheadWidth`-pixel line
/// remains inside the selection, including at the start and end handles.
double trimPlayheadLeft({
  required double startX,
  required double endX,
  required double startMs,
  required double endMs,
  required double positionMs,
}) {
  final clipWidth = endX - startX;
  if (clipWidth <= 0 || endMs <= startMs) return startX;

  final span = endMs - startMs;
  var value = positionMs;
  if (value < startMs) value = startMs;
  if (value > endMs) value = endMs;

  final fraction = (value - startMs) / span;
  final available = clipWidth - trimPlayheadWidth;
  if (available <= 0) return startX;
  return startX + fraction * available;
}
