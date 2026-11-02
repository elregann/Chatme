// image_bubble.dart

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/utils/debug_logger.dart';
import '../models/chat_message.dart';
import '../services/file_transfer_service.dart';
import '../services/media_download.dart';
import '../ui/media/image_viewer.dart';

/// The inside of a chat bubble for a picture. A received picture waits for a
/// tap before it is downloaded, like a voice note.
class ImageBubble extends StatefulWidget {
  final ChatMessage message;

  /// Time and delivery ticks, drawn by the chat screen. Shown over the picture.
  final Widget footer;

  /// The widest the picture may be, after the chat bubble padding.
  final double maxWidth;

  const ImageBubble({
    super.key,
    required this.message,
    required this.footer,
    this.maxWidth = preferredWidth,
  });

  static const double preferredWidth = 260;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  late String _path = widget.message.localPath;
  bool _downloading = false;
  String? _error;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final path = await downloadImage(widget.message);
      if (!mounted) return;
      setState(() {
        _path = path;
        _downloading = false;
      });
    } catch (e) {
      DebugLogger.log('[Image] Download failed | $e', type: 'ERROR');
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e is FileTransferException ? e.message : 'download failed';
      });
    }
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _placeholder() {
    final size = _sizeLabel(widget.message.fileSize);
    return Material(
      color: Colors.black.withAlpha(60),
      child: InkWell(
        onTap: _downloading ? null : _download,
        child: Center(
          child: _downloading
              ? const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.6, color: Colors.white),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _error == null
                          ? Icons.download_rounded
                          : Icons.refresh_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _error ?? size,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _picture(double width) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => ImageViewerPage.single(path: _path)),
          ),
          child: Image.file(
            File(_path),
            fit: BoxFit.cover,
            cacheWidth:
                (width * MediaQuery.devicePixelRatioOf(context)).round(),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _placeholder(),
          ),
        ),
        if (widget.message.status == 'sending' ||
            widget.message.status == 'pending')
          const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: Colors.white),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 2),
        child: Text('Photos are not available on web yet'),
      );
    }

    const padding = EdgeInsets.only(top: 6, bottom: 4);
    final width = math.min(ImageBubble.preferredWidth, widget.maxWidth);
    final height = width / widget.message.imageAspectRatio;

    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _path.isEmpty ? _placeholder() : _picture(width),
              Positioned(
                right: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(110),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: widget.footer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
