// video_bubble.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';
import 'package:video_player/video_player.dart';

import '../core/utils/debug_logger.dart';
import '../core/utils/duration_utils.dart';
import '../models/chat_message.dart';
import '../services/chat_reply.dart';
import '../services/file_transfer_service.dart';
import '../services/media_download.dart';
import '../ui/media/video_viewer.dart';

/// The inside of a chat bubble for a video. A received video waits for a tap
/// before it is downloaded, like a picture; the poster is the first frame of
/// the file that was already downloaded and decrypted.
class VideoBubble extends StatefulWidget {
  final ChatMessage message;

  /// Time and delivery ticks, drawn by the chat screen. Shown over the video.
  final Widget footer;

  /// The widest the video may be, after the chat bubble padding.
  final double maxWidth;

  const VideoBubble({
    super.key,
    required this.message,
    required this.footer,
    this.maxWidth = preferredWidth,
  });

  static const double preferredWidth = 260;

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  late String _path = widget.message.localPath;
  bool _downloading = false;
  double? _progress;
  String? _error;

  VideoPlayerController? _controller;
  bool _ready = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _attachPoster();
  }

  @override
  void didUpdateWidget(covariant VideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.localPath != widget.message.localPath) {
      _path = widget.message.localPath;
      _attachPoster();
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _attachPoster() async {
    final generation = ++_generation;
    final old = _controller;
    _controller = null;
    if (_ready && mounted) setState(() => _ready = false);
    await old?.dispose();

    if (_path.isEmpty || kIsWeb) return;

    final controller = VideoPlayerController.file(File(_path));
    try {
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.seekTo(Duration.zero);
      await controller.pause();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (e) {
      await controller.dispose();
      DebugLogger.log('[Video] Poster failed | $e', type: 'WARN');
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    try {
      final path = await downloadVideo(
        widget.message,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _path = path;
        _downloading = false;
        _progress = null;
      });
      _attachPoster();
    } catch (e) {
      DebugLogger.log('[Video] Download failed | $e', type: 'ERROR');
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
        _error = e is FileTransferException ? e.message : 'download failed';
      });
    }
  }

  void _handleTap() {
    if (_downloading) return;
    if (_path.isEmpty) {
      _download();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoViewerPage(
          path: _path,
          message: widget.message,
          onReply: (message) =>
              ChatReplyNavigator.instance.openReply(context, message),
        ),
      ),
    );
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _placeholder() {
    final String label;
    if (_downloading) {
      final percent = _progress == null ? '' : '${(_progress! * 100).round()}%';
      label = percent.isEmpty ? 'Downloading' : percent;
    } else {
      label = _error ?? _sizeLabel(widget.message.fileSize);
    }

    return ColoredBox(
      color: Colors.black.withAlpha(80),
      child: Center(
        child: _downloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  ),
                  if (label.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ],
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
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _poster() {
    final controller = _controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Icon(Remix.movie_2_line, color: Colors.white54, size: 36),
        ),
      );
    }

    final size = controller.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _durationChip() {
    final seconds = widget.message.fileDurationSeconds;
    if (seconds == null || seconds <= 0) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(110),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          DurationUtils.formatClock(seconds),
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 2),
        child: Text('Videos are not available on web yet'),
      );
    }

    const padding = EdgeInsets.only(top: 6, bottom: 4);
    final width = math.min(VideoBubble.preferredWidth, widget.maxWidth);
    final height = width / widget.message.imageAspectRatio;
    final sending =
        widget.message.status == 'sending' || widget.message.status == 'pending';

    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _path.isEmpty ? _placeholder() : _poster(),
                if (_path.isNotEmpty && !sending)
                  const IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white70,
                        size: 52,
                      ),
                    ),
                  ),
                if (sending)
                  const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _durationChip(),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(110),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: widget.footer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
