// voice_note_bubble.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/utils/debug_logger.dart';
import '../core/utils/duration_utils.dart';
import '../models/chat_message.dart';
import '../services/file_transfer_service.dart';
import '../services/just_audio_backend.dart';
import '../services/voice_download.dart';
import '../services/voice_player.dart';

/// The inside of a chat bubble for a voice note: download, then play.
class VoiceNoteBubble extends StatefulWidget {
  final ChatMessage message;
  final Color textColor;

  /// Time and delivery ticks, drawn by the chat screen so they match text bubbles.
  final Widget footer;

  const VoiceNoteBubble({
    super.key,
    required this.message,
    required this.textColor,
    required this.footer,
  });

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  late String _path = widget.message.localPath;
  bool _downloading = false;
  String? _downloadError;
  double? _dragValue;

  String get _id => widget.message.id;

  Future<void> _download() async {
    final file = widget.message.fileMessage;
    if (file == null || _downloading) return;
    setState(() {
      _downloading = true;
      _downloadError = null;
    });
    try {
      final path = await downloadVoiceNote(widget.message);
      if (!mounted) return;
      setState(() {
        _path = path;
        _downloading = false;
      });
    } catch (e) {
      DebugLogger.log('[Voice] Download failed | $e', type: 'ERROR');
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = e is FileTransferException ? e.message : 'download failed';
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_path.isEmpty) return;
    await voicePlayer.toggle(_id, _path);
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor;

    if (kIsWeb) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          'Voice notes are not available on web yet',
          style: TextStyle(color: color.withAlpha(180), fontSize: 14),
        ),
      );
    }

    return ValueListenableBuilder<VoicePlayerState>(
      valueListenable: voicePlayer.state,
      builder: (context, state, _) {
        final active = state.messageId == _id;
        final hasPath = _path.isNotEmpty;
        final failed = (active && state.error != null) || _downloadError != null;
        final total = (active && state.duration != null)
            ? state.duration!
            : Duration(seconds: widget.message.fileDurationSeconds ?? 0);
        final position = active ? state.position : Duration.zero;
        final playing = active && state.playing;

        double progress = 0;
        if (total.inMilliseconds > 0) {
          progress = (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        }

        final String label;
        if (!hasPath) {
          final size = _sizeLabel(widget.message.fileSize);
          final length = total.inSeconds > 0 ? DurationUtils.formatClock(total.inSeconds) : '';
          label = [length, size].where((e) => e.isNotEmpty).join('  ');
        } else if (active && (playing || position > Duration.zero)) {
          label = DurationUtils.formatClock(position.inSeconds);
        } else {
          label = total.inSeconds > 0 ? DurationUtils.formatClock(total.inSeconds) : '';
        }

        Widget button;
        if (_downloading) {
          button = SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
          );
        } else if (failed) {
          button = Icon(Icons.refresh_rounded, color: color, size: 26);
        } else if (!hasPath) {
          button = Icon(Icons.download_rounded, color: color, size: 26);
        } else {
          button = Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: color,
            size: 28,
          );
        }

        final VoidCallback? onPressed;
        if (_downloading) {
          onPressed = null;
        } else if (_downloadError != null || !hasPath) {
          onPressed = _download;
        } else {
          onPressed = _togglePlay;
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: 230,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: onPressed,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withAlpha(28),
                        ),
                        alignment: Alignment.center,
                        child: button,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: color,
                          inactiveTrackColor: color.withAlpha(60),
                          thumbColor: color,
                          disabledActiveTrackColor: color.withAlpha(90),
                          disabledInactiveTrackColor: color.withAlpha(60),
                          disabledThumbColor: color.withAlpha(90),
                        ),
                        child: Slider(
                          value: _dragValue ?? progress,
                          onChanged: (hasPath && active && !failed)
                              ? (v) => setState(() => _dragValue = v)
                              : null,
                          onChangeEnd: (v) {
                            setState(() => _dragValue = null);
                            voicePlayer.seek(
                              _id,
                              Duration(milliseconds: (v * total.inMilliseconds).round()),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          failed ? 'Tap to try again' : label,
                          style: TextStyle(color: color.withAlpha(153), fontSize: 11),
                        ),
                      ),
                      widget.footer,
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
