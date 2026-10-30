// voice_history_list.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/utils/debug_logger.dart';
import '../models/chat_message.dart';
import '../services/file_transfer_service.dart';
import '../services/just_audio_backend.dart';
import '../services/voice_download.dart';
import '../services/voice_history.dart';
import '../services/voice_player.dart';

/// All voice notes of one chat as a card of rows, newest first.
class VoiceHistoryList extends StatelessWidget {
  final String chatKey;
  final String contactName;
  final Widget empty;
  final Color cardColor;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;

  const VoiceHistoryList({
    super.key,
    required this.chatKey,
    required this.contactName,
    required this.empty,
    required this.cardColor,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('chats').listenable(keys: [chatKey]),
      builder: (context, box, _) {
        final raw = box.get(chatKey);
        final notes = voiceNotesNewestFirst(raw is List ? raw.cast<ChatMessage>() : const []);
        if (notes.isEmpty) return empty;

        final children = <Widget>[];
        for (var i = 0; i < notes.length; i++) {
          if (i > 0) {
            children.add(Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 76));
          }
          children.add(_VoiceHistoryRow(
            key: ValueKey(notes[i].id),
            message: notes[i],
            sender: notes[i].isMe ? 'You' : contactName,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Column(children: children),
            ),
          ],
        );
      },
    );
  }
}

class _VoiceHistoryRow extends StatefulWidget {
  final ChatMessage message;
  final String sender;
  final Color textPrimary;
  final Color textSecondary;

  const _VoiceHistoryRow({
    super.key,
    required this.message,
    required this.sender,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  State<_VoiceHistoryRow> createState() => _VoiceHistoryRowState();
}

class _VoiceHistoryRowState extends State<_VoiceHistoryRow> {
  bool _downloading = false;
  bool _failed = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _failed = false;
    });
    try {
      await downloadVoiceNote(widget.message);
      if (!mounted) return;
      setState(() => _downloading = false);
    } catch (e) {
      DebugLogger.log(
        '[Voice] History download failed | ${e is FileTransferException ? e.message : e}',
        type: 'ERROR',
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final hasPath = message.localPath.isNotEmpty;

    return ValueListenableBuilder<VoicePlayerState>(
      valueListenable: voicePlayer.state,
      builder: (context, state, _) {
        final active = state.messageId == message.id;
        final playing = active && state.playing;
        final failed = _failed || (active && state.error != null);

        final Widget icon;
        if (_downloading) {
          icon = const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          );
        } else if (failed) {
          icon = const Icon(Icons.refresh_rounded, color: Colors.white, size: 28);
        } else if (!hasPath) {
          icon = const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 28);
        } else {
          icon = Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 30,
          );
        }

        final VoidCallback? onTap;
        if (_downloading) {
          onTap = null;
        } else if (_failed || !hasPath) {
          onTap = _download;
        } else {
          onTap = () => voicePlayer.toggle(message.id, message.localPath);
        }

        final subtitle = failed
            ? 'Tap to try again'
            : voiceSubtitle(widget.sender, message.fileDurationSeconds ?? 0);

        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blue),
                  alignment: Alignment.center,
                  child: icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voiceDateLabel(DateTime.fromMillisecondsSinceEpoch(message.timestamp)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: widget.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: widget.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
