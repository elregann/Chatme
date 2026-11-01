// image_viewer.dart

import 'dart:io';
import 'package:flutter/material.dart';

/// Full screen picture with pinch to zoom.
class ImageViewerPage extends StatelessWidget {
  final String path;

  const ImageViewerPage({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: SizedBox.expand(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
