// video_viewer.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/duration_utils.dart';
import '../../models/chat_message.dart';
import '../../services/chat_reply.dart';
import '../../services/gallery_save.dart';
import '../../widgets/chatme_menu.dart';

/// A video played full screen, with a slider and the same menu as a picture.
class VideoViewerPage extends StatefulWidget {
  final String path;
  final ChatMessage? message;

  /// Replies to the video. No Reply item is shown without it.
  final ValueChanged<ChatMessage>? onReply;

  /// Saves the video to the gallery. Replaceable for tests.
  final Future<void> Function(String path) saveToGallery;

  const VideoViewerPage({
    super.key,
    required this.path,
    this.message,
    this.onReply,
    this.saveToGallery = saveVideoToGallery,
  });

  static Future<void> saveVideoToGallery(String path) {
    return GallerySaver.save(path, video: true);
  }

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      await _controller.setLooping(false);
      await _controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    String text;
    try {
      await widget.saveToGallery(widget.path);
      text = 'Saved to the Chatme album';
    } on GallerySaveException catch (e) {
      text = e.message;
    } catch (_) {
      text = 'Could not save the video';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  void _reply() {
    final message = widget.message;
    if (message == null || !canReplyTo(message)) return;
    widget.onReply?.call(message);
  }

  void _togglePlay() {
    final value = _controller.value;
    if (!value.isInitialized) return;
    if (value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final canReply =
        message != null && widget.onReply != null && canReplyTo(message);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          ChatmeMenuButton<int>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            entries: [
              const ChatmeMenuEntry(
                value: 0,
                icon: Icons.save_alt_rounded,
                label: 'Save to Gallery',
              ),
              if (canReply)
                const ChatmeMenuEntry(value: 1, icon: Icons.reply, label: 'Reply'),
            ],
            onSelected: (value) => value == 0 ? _save() : _reply(),
          ),
        ],
      ),
      body: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          if (value.hasError) {
            return const Center(
              child: Text(
                'This video cannot be played',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          if (!value.isInitialized) {
            return const Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _togglePlay,
                    child: AspectRatio(
                      aspectRatio: value.aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VideoPlayer(_controller),
                          if (!value.isPlaying)
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white70,
                                size: 64,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _controls(value),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(VideoPlayerValue value) {
    return SafeArea(
      top: false,
      child: Row(
        children: [
          IconButton(
            onPressed: _togglePlay,
            icon: Icon(
              value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.white,
                bufferedColor: Colors.white38,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${DurationUtils.formatClock(value.position.inSeconds)} / '
            '${DurationUtils.formatClock(value.duration.inSeconds)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
