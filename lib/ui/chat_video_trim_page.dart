// chat_video_trim_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../core/theme/chatme_colors.dart';
import '../core/utils/debug_logger.dart';

class ChatVideoTrimPage extends StatefulWidget {
  final String videoPath;

  const ChatVideoTrimPage({
    super.key,
    required this.videoPath,
  });

  /// Returns the path to send, or null when the user cancelled. The original
  /// path comes back untouched when nothing was cut.
  static Future<String?> open(BuildContext context, String videoPath) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ChatVideoTrimPage(videoPath: videoPath),
      ),
    );
  }

  /// False when the selection is the whole video or cannot be a real cut, so
  /// the original file is sent without another encode.
  @visibleForTesting
  static bool needsTrim({
    required double start,
    required double end,
    required int totalMs,
  }) {
    if (totalMs <= 0 || end <= start) return false;
    return start > 0 || end < totalMs - 50;
  }

  @override
  State<ChatVideoTrimPage> createState() => _ChatVideoTrimPageState();
}

class _ChatVideoTrimPageState extends State<ChatVideoTrimPage> {
  final Trimmer _trimmer = Trimmer();

  StreamSubscription<TrimmerEvent>? _readySubscription;
  double _startValue = 0;
  double _endValue = 0;
  bool _isPlaying = false;
  bool _isReady = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _readySubscription = _trimmer.eventStream.listen((event) {
      if (event == TrimmerEvent.initialized && mounted) {
        setState(() => _isReady = true);
      }
    });
    _load();
  }

  Future<void> _load() async {
    try {
      await _trimmer.loadVideo(videoPath: widget.videoPath);
      if (!mounted) return;
      final totalMs =
          _trimmer.videoPlayerController?.value.duration.inMilliseconds ?? 0;
      setState(() {
        _isReady = _trimmer.isVideoInitialized;
        _endValue = totalMs.toDouble();
      });
    } catch (e) {
      DebugLogger.log('[Video] Trim load failed | $e', type: 'ERROR');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the video')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _readySubscription?.cancel();
    _trimmer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (!_isReady || _isSaving) return;
    try {
      final playing = await _trimmer.videoPlaybackControl(
        startValue: _startValue,
        endValue: _endValue,
      );
      if (!mounted) return;
      setState(() => _isPlaying = playing);
    } catch (e) {
      DebugLogger.log('[Video] Trim playback failed | $e', type: 'ERROR');
    }
  }

  Future<void> _save() async {
    if (!_isReady || _isSaving) return;

    final totalMs =
        _trimmer.videoPlayerController?.value.duration.inMilliseconds ?? 0;
    if (!ChatVideoTrimPage.needsTrim(
      start: _startValue,
      end: _endValue,
      totalMs: totalMs,
    )) {
      Navigator.of(context).pop(widget.videoPath);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        storageDir: StorageDir.temporaryDirectory,
        onSave: (outputPath) {
          if (!mounted) return;
          setState(() => _isSaving = false);
          if (outputPath == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not trim the video')),
            );
            return;
          }
          Navigator.of(context).pop(outputPath);
        },
      );
    } catch (e) {
      DebugLogger.log('[Video] Trim save failed | $e', type: 'ERROR');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not trim the video')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = ChatmeColors.accentPrimary;

    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        backgroundColor: ChatmeColors.backgroundPrimary,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _isReady
                      ? VideoViewer(trimmer: _trimmer)
                      : const Center(
                          child: CircularProgressIndicator(
                            color: ChatmeColors.textPrimary,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _isReady
                    ? TrimViewer(
                        trimmer: _trimmer,
                        viewerWidth: MediaQuery.sizeOf(context).width - 32,
                        viewerHeight: 56,
                        durationStyle: DurationStyle.FORMAT_MM_SS,
                        durationTextStyle: const TextStyle(
                          color: ChatmeColors.textPrimary,
                          fontSize: 12,
                        ),
                        onChangeStart: (value) => _startValue = value,
                        onChangeEnd: (value) => _endValue = value,
                        onChangePlaybackState: (playing) {
                          if (!mounted) return;
                          setState(() => _isPlaying = playing);
                        },
                        editorProperties: const TrimEditorProperties(
                          borderPaintColor: ChatmeColors.accentPrimary,
                          borderWidth: 2,
                          borderRadius: 4,
                          scrubberPaintColor: ChatmeColors.accentPrimary,
                          scrubberWidth: 2,
                          circlePaintColor: ChatmeColors.textPrimary,
                          handleStyle: TrimHandleStyle.line,
                          handleHeight: TrimHandleHeight.percent(50),
                        ),
                        areaProperties: const TrimAreaProperties(
                          blurEdges: true,
                          blurColor: ChatmeColors.backgroundPrimary,
                          borderRadius: 4,
                          thumbnailFit: BoxFit.cover,
                        ),
                      )
                    : const SizedBox(height: 56),
              ),
              if (_isSaving)
                const LinearProgressIndicator(
                  color: accent,
                  backgroundColor: ChatmeColors.scrim,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: accent, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      tooltip: _isPlaying ? 'Pause' : 'Play',
                      onPressed:
                          _isReady && !_isSaving ? _togglePlayback : null,
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: ChatmeColors.textPrimary,
                        size: 30,
                      ),
                    ),
                    TextButton(
                      onPressed: _isReady && !_isSaving ? _save : null,
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
      ),
    );
  }
}
