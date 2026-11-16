// media_history_grid.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../chat_manager.dart';
import '../core/utils/debug_logger.dart';
import '../core/utils/duration_utils.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import '../relay_manager.dart';
import '../services/chat_reply.dart';
import '../services/file_transfer_service.dart';
import '../services/media_download.dart';
import '../services/media_history.dart';
import '../services/video_thumbnails.dart';
import '../ui/media/image_viewer.dart';

/// All pictures and videos of one chat as a grid of square tiles, newest first.
class MediaHistoryGrid extends StatelessWidget {
  static const int columns = 3;
  static const double gap = 6;
  static const double radius = 10;

  final String chatKey;
  final Contact contact;
  final RelayManager relayManager;
  final Widget empty;
  final Color placeholderColor;
  final Color iconColor;

  const MediaHistoryGrid({
    super.key,
    required this.chatKey,
    required this.contact,
    required this.relayManager,
    required this.empty,
    required this.placeholderColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<ChatMessage>>(
      // Filtered listenable: only this chat's messages rebuild the grid.
      valueListenable: ChatManager.instance.chatMessagesListenable(chatKey),
      builder: (context, box, _) {
        final media =
            mediaNewestFirst(ChatManager.instance.messagesForChatSync(chatKey));
        if (media.isEmpty) return empty;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
          ),
          itemCount: media.length,
          itemBuilder: (context, i) => _MediaTile(
            key: ValueKey(media[i].id),
            message: media[i],
            all: media,
            contact: contact,
            relayManager: relayManager,
            placeholderColor: placeholderColor,
            iconColor: iconColor,
          ),
        );
      },
    );
  }
}

class _MediaTile extends StatefulWidget {
  final ChatMessage message;
  final List<ChatMessage> all;
  final Contact contact;
  final RelayManager relayManager;
  final Color placeholderColor;
  final Color iconColor;

  const _MediaTile({
    super.key,
    required this.message,
    required this.all,
    required this.contact,
    required this.relayManager,
    required this.placeholderColor,
    required this.iconColor,
  });

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  bool _downloading = false;
  bool _failed = false;
  String? _thumb;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(_MediaTile old) {
    super.didUpdateWidget(old);
    if (old.message.localPath != widget.message.localPath) _loadThumb();
  }

  /// Shows the poster of a downloaded video, making it once when it is not
  /// there yet. Videos that are not downloaded keep their download arrow.
  void _loadThumb() {
    _thumb = null;
    if (!widget.message.isVideo) return;
    final path = widget.message.localPath;
    if (path.isEmpty) return;
    final cached = VideoThumbnails.pathFor(path);
    if (File(cached).existsSync()) {
      _thumb = cached;
      return;
    }
    VideoThumbnails.instance.ensure(path).then((thumb) {
      if (!mounted || thumb == null) return;
      setState(() => _thumb = thumb);
    });
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _failed = false;
    });
    try {
      if (widget.message.isVideo) {
        await downloadVideo(widget.message);
      } else {
        await downloadImage(widget.message);
      }
      if (!mounted) return;
      setState(() => _downloading = false);
    } catch (e) {
      DebugLogger.log(
        '[Image] Grid download failed | ${e is FileTransferException ? e.message : e}',
        type: 'ERROR',
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _failed = true;
      });
    }
  }

  void _open() {
    final set = viewerSetFor(widget.all, widget.message.id);
    if (set == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          paths: set.paths,
          initialIndex: set.index,
          messages: set.messages,
          onReply: (message) => ChatReplyNavigator.instance.openReply(
            context,
            message,
            contact: widget.contact,
            relayManager: widget.relayManager,
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    final Widget icon;
    if (_downloading) {
      icon = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: widget.iconColor),
      );
    } else {
      icon = Icon(
        _failed ? Icons.refresh_rounded : Icons.arrow_downward_rounded,
        color: widget.iconColor,
        size: 26,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _downloading ? null : _download,
      child: ColoredBox(color: widget.placeholderColor, child: Center(child: icon)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.message.localPath;
    final side = (MediaQuery.sizeOf(context).width - 40 - MediaHistoryGrid.gap * 2) /
        MediaHistoryGrid.columns;

    if (path.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(MediaHistoryGrid.radius),
        child: _placeholder(),
      );
    }

    if (widget.message.isVideo) {
      final seconds = widget.message.fileDurationSeconds;
      final thumbPath = _thumb;
      final hasThumb = thumbPath != null;
      return ClipRRect(
        borderRadius: BorderRadius.circular(MediaHistoryGrid.radius),
        child: GestureDetector(
          onTap: _open,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbPath != null) ...[
                Image.file(
                  File(thumbPath),
                  fit: BoxFit.cover,
                  cacheWidth: (side * MediaQuery.devicePixelRatioOf(context)).round(),
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) =>
                      ColoredBox(color: widget.placeholderColor),
                ),
                // Keeps the play icon and the duration readable on a bright
                // frame, while the middle of the video stays visible.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                ),
              ] else
                ColoredBox(color: widget.placeholderColor),
              Center(
                child: Icon(
                  Icons.play_circle_outline_rounded,
                  color: hasThumb ? Colors.white : widget.iconColor,
                  size: 30,
                  shadows: hasThumb
                      ? const [Shadow(color: Colors.black54, blurRadius: 8)]
                      : null,
                ),
              ),
              if (seconds != null && seconds > 0)
                Positioned(
                  right: 5,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: hasThumb
                          ? Colors.black.withAlpha(120)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: hasThumb ? 5 : 0,
                        vertical: hasThumb ? 1 : 0,
                      ),
                      child: Text(
                        DurationUtils.formatClock(seconds),
                        style: TextStyle(
                          color: hasThumb ? Colors.white : widget.iconColor,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(MediaHistoryGrid.radius),
      child: GestureDetector(
        onTap: _open,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: (side * MediaQuery.devicePixelRatioOf(context)).round(),
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => ColoredBox(
            color: widget.placeholderColor,
            child: Center(
              child: Icon(Icons.broken_image_outlined, color: widget.iconColor, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}
