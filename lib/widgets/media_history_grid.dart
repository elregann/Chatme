// media_history_grid.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/utils/debug_logger.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import '../relay_manager.dart';
import '../services/chat_reply.dart';
import '../services/file_transfer_service.dart';
import '../services/media_download.dart';
import '../services/media_history.dart';
import '../ui/media/image_viewer.dart';

/// All pictures of one chat as a grid of square tiles, newest first.
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
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('chats').listenable(keys: [chatKey]),
      builder: (context, box, _) {
        final raw = box.get(chatKey);
        final images = imagesNewestFirst(raw is List ? raw.cast<ChatMessage>() : const []);
        if (images.isEmpty) return empty;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
          ),
          itemCount: images.length,
          itemBuilder: (context, i) => _MediaTile(
            key: ValueKey(images[i].id),
            message: images[i],
            all: images,
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

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _failed = false;
    });
    try {
      await downloadImage(widget.message);
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(MediaHistoryGrid.radius),
      child: path.isEmpty
          ? _placeholder()
          : GestureDetector(
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
