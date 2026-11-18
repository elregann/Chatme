// video_viewer.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/duration_utils.dart';
import '../../models/chat_message.dart';
import '../../services/chat_reply.dart';
import '../../services/gallery_save.dart';
import '../../widgets/chatme_menu.dart';

/// The video surface and its controls, used full screen and inside the
/// swipeable gallery.
///
/// It owns one [VideoPlayerController] and starts playing as soon as the
/// decoder is ready. A gallery page that is merely being swiped past is not
/// [active] and owns no decoder at all, so only the video on screen is ever
/// alive, and leaving its page releases it.
class VideoPlayerView extends StatefulWidget {
  final String path;

  /// Whether this page may own a decoder. Always true outside the gallery.
  final bool active;

  /// The length from the message, used when the decoder has not reported one
  /// yet, so the clock is ready the moment the page appears.
  final int? knownDurationSeconds;

  const VideoPlayerView({
    super.key,
    required this.path,
    this.active = true,
    this.knownDurationSeconds,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  int _generation = 0;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(VideoPlayerView old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _stop();
      if (widget.active) _start();
    } else if (old.active != widget.active) {
      if (widget.active) {
        _start();
      } else {
        _stop();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _start() {
    if (_controller != null) return;
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    _ready = false;
    _failed = false;
    final generation = ++_generation;
    _run(controller, generation);
  }

  void _stop() {
    _generation++;
    final controller = _controller;
    _controller = null;
    _ready = false;
    _failed = false;
    controller?.dispose();
  }

  /// A late initialization from a page that has already moved on must not
  /// touch the new controller or the widget tree.
  bool _current(VideoPlayerController controller, int generation) =>
      mounted && identical(_controller, controller) && generation == _generation;

  Future<void> _run(VideoPlayerController controller, int generation) async {
    try {
      await controller.initialize();
      if (!_current(controller, generation)) return;
      await controller.setLooping(false);
      if (!_current(controller, generation)) return;
      await controller.play();
      if (!_current(controller, generation)) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!_current(controller, generation)) return;
      setState(() => _failed = true);
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    if (value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _inactive();

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (_failed || value.hasError) {
          return const Center(
            child: Text(
              'This video cannot be played',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
        if (!_ready || !value.isInitialized) {
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

        // ExoPlayer can report a zero length right after it starts; the
        // message already knows how long the video is.
        final known = widget.knownDurationSeconds;
        final duration = value.duration > Duration.zero
            ? value.duration
            : Duration(seconds: known != null && known > 0 ? known : 0);

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
                        VideoPlayer(controller),
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
            _controls(controller, value, duration),
          ],
        );
      },
    );
  }

  /// A video page that is not on screen yet. It owns no decoder, so a swipe
  /// past it costs the same as a black square.
  Widget _inactive() {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.play_circle_fill_rounded,
          color: Colors.white24,
          size: 64,
        ),
      ),
    );
  }

  Widget _controls(
    VideoPlayerController controller,
    VideoPlayerValue value,
    Duration duration,
  ) {
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
              controller,
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
            '${DurationUtils.formatClock(duration.inSeconds)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// A video played full screen, with a slider and the same menu as a picture.
class VideoViewerPage extends StatelessWidget {
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

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String text;
    try {
      await saveToGallery(path);
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
    final message = this.message;
    if (message == null || !canReplyTo(message)) return;
    onReply?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final canReply = message != null && onReply != null && canReplyTo(message);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
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
            onSelected: (value) => value == 0 ? _save(context) : _reply(),
          ),
        ],
      ),
      body: VideoPlayerView(
        path: path,
        knownDurationSeconds: message?.fileDurationSeconds,
      ),
    );
  }
}
