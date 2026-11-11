// chat_image_crop_page.dart

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'crop_geometry.dart';

const double _cropMarkStroke = 2.0;

class ChatImageCropPage extends StatefulWidget {
  final Uint8List imageBytes;

  const ChatImageCropPage({
    super.key,
    required this.imageBytes,
  });

  static Future<Uint8List?> open(
    BuildContext context,
    Uint8List imageBytes,
  ) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => ChatImageCropPage(imageBytes: imageBytes),
      ),
    );
  }

  @override
  State<ChatImageCropPage> createState() => _ChatImageCropPageState();
}

class _ChatImageCropPageState extends State<ChatImageCropPage> {
  static const double _cropSidePadding = 16;
  static const double _edgeTouchThickness = 30;
  static const double _edgeTouchLength = 56;
  static const double _edgeTouchOutside = 6;
  static const double _edgeBarThickness = _cropMarkStroke;
  static const double _edgeBarLength = 28;

  CropController _cropController = CropController();
  final ValueNotifier<Rect?> _cropRect = ValueNotifier<Rect?>(null);

  late Uint8List _imageBytes;
  Size? _imageSize;
  int _imageRevision = 0;
  bool _isCropReady = false;
  bool _isCropping = false;
  bool _isRotating = false;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.imageBytes;
    _loadImageSize();
  }

  @override
  void dispose() {
    _cropRect.dispose();
    super.dispose();
  }

  Future<void> _loadImageSize() async {
    try {
      final dimensions = await compute(_readImageSize, _imageBytes);
      if (!mounted) return;
      setState(() {
        _imageSize = Size(dimensions[0].toDouble(), dimensions[1].toDouble());
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open image: $error')),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _rotatePhoto() async {
    final size = _imageSize;
    if (size == null || _isRotating || _isCropping) return;
    setState(() => _isRotating = true);

    try {
      final rotatedBytes = await compute(_rotateImageBytes, _imageBytes);
      if (!mounted) return;

      _cropRect.value = null;
      setState(() {
        _imageBytes = rotatedBytes;
        _imageSize = Size(size.height, size.width);
        _cropController = CropController();
        _imageRevision++;
        _isCropReady = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not rotate image: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRotating = false);
    }
  }

  void _onCropStatusChanged(CropStatus status) {
    if (!mounted) return;
    setState(() {
      _isCropReady = status == CropStatus.ready;
      if (status != CropStatus.cropping) _isCropping = false;
    });
  }

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        if (!mounted) return;
        Navigator.of(context).pop<Uint8List>(croppedImage);
        return;
      case CropFailure(:final cause):
        if (!mounted) return;
        setState(() => _isCropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not crop image: $cause')),
        );
        return;
    }
  }

  void _crop() {
    if (!_isCropReady || _isCropping || _isRotating) return;
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  void _resizeEdge(CropEdge edge, Offset delta, Rect bounds) {
    final current = _cropRect.value;
    if (current == null) return;

    _cropController.cropRect = resizeCropEdge(
      rect: current,
      edge: edge,
      delta: delta,
      bounds: bounds,
    );
  }

  Widget _edgeHandle(CropEdge edge, Rect rect, Rect bounds) {
    final horizontal = edge == CropEdge.top || edge == CropEdge.bottom;
    const inside = _edgeTouchThickness - _edgeTouchOutside;
    const barOffset = _edgeTouchOutside;

    final Offset origin;
    final Alignment alignment;
    final EdgeInsets barPadding;
    switch (edge) {
      case CropEdge.top:
        origin = Offset(
          rect.center.dx - _edgeTouchLength / 2,
          rect.top - _edgeTouchOutside,
        );
        alignment = Alignment.topCenter;
        barPadding = const EdgeInsets.only(top: barOffset);
      case CropEdge.bottom:
        origin = Offset(
          rect.center.dx - _edgeTouchLength / 2,
          rect.bottom - inside,
        );
        alignment = Alignment.bottomCenter;
        barPadding = const EdgeInsets.only(bottom: barOffset);
      case CropEdge.left:
        origin = Offset(
          rect.left - _edgeTouchOutside,
          rect.center.dy - _edgeTouchLength / 2,
        );
        alignment = Alignment.centerLeft;
        barPadding = const EdgeInsets.only(left: barOffset);
      case CropEdge.right:
        origin = Offset(
          rect.right - inside,
          rect.center.dy - _edgeTouchLength / 2,
        );
        alignment = Alignment.centerRight;
        barPadding = const EdgeInsets.only(right: barOffset);
    }

    return Positioned(
      left: origin.dx,
      top: origin.dy,
      width: horizontal ? _edgeTouchLength : _edgeTouchThickness,
      height: horizontal ? _edgeTouchThickness : _edgeTouchLength,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _resizeEdge(edge, details.delta, bounds),
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: barPadding,
            child: Container(
              width: horizontal ? _edgeBarLength : _edgeBarThickness,
              height: horizontal ? _edgeBarThickness : _edgeBarLength,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeHandles(Rect rect, Rect bounds) {
    return Stack(
      children: [
        for (final edge in CropEdge.values) _edgeHandle(edge, rect, bounds),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF2196F3);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _cropSidePadding,
                    ),
                    child: _imageSize == null
                        ? const SizedBox.shrink()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final imageSize = _imageSize!;
                              final bounds = fittedImageRect(
                                constraints.biggest,
                                imageSize,
                              );
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Crop(
                                    key: ValueKey(_imageRevision),
                                    image: _imageBytes,
                                    controller: _cropController,
                                    initialRectBuilder:
                                        InitialRectBuilder.withArea(
                                      Rect.fromLTWH(
                                        0,
                                        0,
                                        imageSize.width,
                                        imageSize.height,
                                      ),
                                    ),
                                    onCropped: _onCropped,
                                    onStatusChanged: _onCropStatusChanged,
                                    onMoved: (viewportRect, _) {
                                      _cropRect.value = viewportRect;
                                    },
                                    baseColor: Colors.black,
                                    maskColor: const Color(0x99000000),
                                    cornerDotBuilder: (size, alignment) =>
                                        CustomPaint(
                                      size: Size.square(size),
                                      painter: _CropCornerPainter(alignment),
                                    ),
                                    overlayBuilder: (_, rect) =>
                                        SizedBox.expand(
                                      child: CustomPaint(
                                        painter: _CropGridPainter(),
                                      ),
                                    ),
                                  ),
                                  ValueListenableBuilder<Rect?>(
                                    valueListenable: _cropRect,
                                    builder: (context, rect, _) => rect == null
                                        ? const SizedBox.shrink()
                                        : _buildEdgeHandles(rect, bounds),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  if (_imageSize == null || _isRotating || _isCropping)
                    const ColoredBox(
                      color: Color(0x55000000),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _isCropping || _isRotating
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: accent, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rotate photo',
                    onPressed: _imageSize == null || _isCropping || _isRotating
                        ? null
                        : _rotatePhoto,
                    icon: const Icon(
                      Icons.rotate_right_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  TextButton(
                    onPressed: !_isCropReady || _isCropping || _isRotating
                        ? null
                        : _crop,
                    child: const Text(
                      'Done',
                      style: TextStyle(color: accent, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<int> _readImageSize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image format');
  }

  final upright = img.bakeOrientation(decoded);
  return [upright.width, upright.height];
}

Uint8List _rotateImageBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image format');
  }

  final upright = img.bakeOrientation(decoded);
  final rotated = img.copyRotate(upright, angle: 90);
  final output = rotated.hasAlpha
      ? img.encodePng(rotated)
      : img.encodeJpg(rotated, quality: 95);
  return Uint8List.fromList(output);
}

class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(110)
      ..strokeWidth = 1;

    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropGridPainter oldDelegate) => false;
}

class _CropCornerPainter extends CustomPainter {
  final EdgeAlignment alignment;

  const _CropCornerPainter(this.alignment);

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 16.0;
    const stroke = _cropMarkStroke;
    const shift = stroke / 2;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    final center = size.center(Offset.zero);
    final path = Path();
    switch (alignment) {
      case EdgeAlignment.topLeft:
        final x = center.dx + shift;
        final y = center.dy + shift;
        path
          ..moveTo(x, y + arm)
          ..lineTo(x, y)
          ..lineTo(x + arm, y);
        break;
      case EdgeAlignment.topRight:
        final x = center.dx - shift;
        final y = center.dy + shift;
        path
          ..moveTo(x - arm, y)
          ..lineTo(x, y)
          ..lineTo(x, y + arm);
        break;
      case EdgeAlignment.bottomLeft:
        final x = center.dx + shift;
        final y = center.dy - shift;
        path
          ..moveTo(x, y - arm)
          ..lineTo(x, y)
          ..lineTo(x + arm, y);
        break;
      case EdgeAlignment.bottomRight:
        final x = center.dx - shift;
        final y = center.dy - shift;
        path
          ..moveTo(x - arm, y)
          ..lineTo(x, y)
          ..lineTo(x, y - arm);
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CropCornerPainter oldDelegate) =>
      oldDelegate.alignment != alignment;
}
