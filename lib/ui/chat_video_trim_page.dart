// chat_video_trim_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../core/theme/chatme_colors.dart';
import '../core/utils/debug_logger.dart';
import '../core/utils/trim_playback_clock.dart';
import '../core/utils/trim_playback_geometry.dart';
import '../core/utils/trim_playback_guard.dart';
import '../services/chatme_toast.dart';

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
  final TrimPlaybackClock _clock = TrimPlaybackClock();
  final ValueNotifier<Duration> _scrubPosition = ValueNotifier(Duration.zero);

  Timer? _scrubTicker;
  double _startValue = 0;
  double _endValue = 0;
  double _totalMs = 0;
  bool _isPlaying = false;
  bool _isReady = false;
  bool _isSaving = false;
  bool _reachedEnd = false;
  bool _playCommandInFlight = false;
  bool _nextPlaySettles = true;

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
      _clock.reset();
      _publishScrubPosition();
      setState(() {
        _isReady = _trimmer.isVideoInitialized;
        _totalMs = totalMs.toDouble();
        _startValue = 0;
        _endValue = totalMs.toDouble();
      });
    } catch (e) {
      DebugLogger.log('[Video] Trim load failed | $e', type: 'ERROR');
      if (!mounted) return;
      ChatmeToast.show('Could not open the video');
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _readySubscription?.cancel();
    _scrubTicker?.cancel();
    _scrubPosition.dispose();
    _trimmer.dispose();
    super.dispose();
  }

  void _publishScrubPosition() {
    final position = _clock.position;
    if (position != _scrubPosition.value) _scrubPosition.value = position;
  }

  void _startScrubTicker() {
    _scrubTicker?.cancel();
    _publishScrubPosition();
    _scrubTicker = Timer.periodic(TrimPlaybackClock.tickInterval, (_) {
      _publishScrubPosition();
    });
  }

  void _stopScrubTicker() {
    _scrubTicker?.cancel();
    _scrubTicker = null;
    _publishScrubPosition();
  }

  void _clampClockToRange() {
    if (_clock.running) return;
    final start = Duration(milliseconds: _startValue.round());
    final end = Duration(milliseconds: _endValue.round());
    final position = _clock.position;
    if (position < start) {
      _clock.seek(start);
    } else if (position > end) {
      _clock.seek(end);
    } else {
      return;
    }
    _publishScrubPosition();
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _togglePlayback() async {
    if (!_isReady || _isSaving || _playCommandInFlight) return;
    final controller = _trimmer.videoPlayerController;
    if (controller == null) return;

    // Ignore a second tap while pause()/seek()/play() is still in flight. The
    // controller would otherwise report the old isPlaying value and interpret
    // the tap as the opposite command.
    _playCommandInFlight = true;
    try {
      if (controller.value.isPlaying) {
        // Freeze the line before native pause can report a stale position.
        _clock.pause();
        _stopScrubTicker();
        await controller.pause();
        if (!mounted) return;
        setState(() => _isPlaying = false);
        return;
      }

      final shouldRestart = _reachedEnd ||
          shouldRestartTrimPlayback(
            value: controller.value,
            startValue: _startValue,
            endValue: _endValue,
          );
      if (shouldRestart) {
        final start = Duration(milliseconds: _startValue.round());
        _clock.seek(start);
        _publishScrubPosition();
        _nextPlaySettles = true;
        await controller.seekTo(start);
        _reachedEnd = false;
      } else {
        _nextPlaySettles = false;
      }

      await controller.play();
      if (!mounted) return;
      // onChangePlaybackState normally starts the clock. This covers engines
      // that do not emit that callback for a play() they already reported.
      if (!_clock.running) {
        _clock.start(_clock.position, withSettle: _nextPlaySettles);
        _startScrubTicker();
      }
      _nextPlaySettles = false;
      setState(() => _isPlaying = true);
    } catch (e) {
      _clock.pause();
      _stopScrubTicker();
      DebugLogger.log('[Video] Trim playback failed | $e', type: 'ERROR');
    } finally {
      _playCommandInFlight = false;
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
            ChatmeToast.show('Could not trim the video');
            return;
          }
          Navigator.of(context).pop(outputPath);
        },
      );
    } catch (e) {
      DebugLogger.log('[Video] Trim save failed | $e', type: 'ERROR');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ChatmeToast.show('Could not trim the video');
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = ChatmeColors.accentPrimary;
    const labelStyle = TextStyle(color: ChatmeColors.textPrimary, fontSize: 12);

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
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          if (!constraints.hasBoundedWidth) {
                            return const SizedBox(height: trimViewerHeight);
                          }
                          final requestedWidth = constraints.maxWidth;
                          final stripWidth = trimStripWidth(requestedWidth);
                          if (stripWidth <= 0) {
                            return const SizedBox(
                              height: trimViewerHeight,
                            );
                          }

                          final startX = trimHandleX(
                            stripWidth: stripWidth,
                            positionMs: _startValue,
                            totalMs: _totalMs,
                          );
                          final endX = trimHandleX(
                            stripWidth: stripWidth,
                            positionMs: _endValue,
                            totalMs: _totalMs,
                          );

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: stripWidth,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _format(Duration(
                                          milliseconds: _startValue.round(),
                                        )),
                                        style: labelStyle,
                                      ),
                                      ValueListenableBuilder<Duration>(
                                        valueListenable: _scrubPosition,
                                        builder: (_, position, __) => Text(
                                          _format(position),
                                          style: labelStyle,
                                        ),
                                      ),
                                      Text(
                                        _format(Duration(
                                          milliseconds: _endValue.round(),
                                        )),
                                        style: labelStyle,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: stripWidth,
                                height: trimViewerHeight,
                                child: Stack(
                                  children: [
                                    TrimViewer(
                                      trimmer: _trimmer,
                                      viewerWidth: stripWidth,
                                      viewerHeight: trimViewerHeight,
                                      showDuration: false,
                                      onChangeStart: (value) {
                                        if (!mounted) return;
                                        setState(() {
                                          _startValue = value;
                                          _reachedEnd = false;
                                        });
                                        _clampClockToRange();
                                      },
                                      onChangeEnd: (value) {
                                        if (!mounted) return;
                                        setState(() {
                                          _endValue = value;
                                          _reachedEnd = false;
                                        });
                                        _clampClockToRange();
                                      },
                                      onChangePlaybackState: (playing) {
                                        if (!mounted) return;
                                        if (playing) {
                                          // A resume must not restart the
                                          // settle delay; a fresh play or seek
                                          // may.
                                          if (!_clock.running) {
                                            _clock.start(
                                              _clock.position,
                                              withSettle: _nextPlaySettles,
                                            );
                                            _startScrubTicker();
                                          }
                                          _nextPlaySettles = false;
                                          setState(() {
                                            _isPlaying = true;
                                            _reachedEnd = false;
                                          });
                                          return;
                                        }

                                        // The package pauses up to 120 ms
                                        // before the video's last frame. Snap
                                        // the app-owned line to the visible
                                        // end so it reaches the boundary.
                                        if (_clock.running) {
                                          final nearEnd =
                                              shouldSnapTrimPlaybackToEnd(
                                            position: _clock.position,
                                            startValue: _startValue,
                                            endValue: _endValue,
                                          );
                                          if (nearEnd) {
                                            _clock.snapTo(Duration(
                                              milliseconds: _endValue.round(),
                                            ));
                                            _reachedEnd = true;
                                          } else {
                                            _clock.pause();
                                          }
                                          _stopScrubTicker();
                                        }
                                        setState(() => _isPlaying = false);
                                      },
                                      editorProperties: const TrimEditorProperties(
                                        borderPaintColor: ChatmeColors.accentPrimary,
                                        borderWidth: 2,
                                        borderRadius: 0,
                                        scrubberPaintColor: Colors.transparent,
                                        scrubberWidth: trimPlayheadWidth,
                                        circlePaintColor: ChatmeColors.textPrimary,
                                        handleStyle: TrimHandleStyle.line,
                                        handleHeight: TrimHandleHeight.percent(50),
                                      ),
                                      areaProperties: const TrimAreaProperties(
                                        blurEdges: true,
                                        blurColor: ChatmeColors.backgroundPrimary,
                                        borderRadius: 0,
                                        thumbnailFit: BoxFit.cover,
                                      ),
                                    ),
                                    if (endX > startX)
                                      Positioned(
                                        left: startX,
                                        top: 0,
                                        width: endX - startX,
                                        height: trimViewerHeight,
                                        child: ClipRect(
                                          child: ValueListenableBuilder<Duration>(
                                            valueListenable: _scrubPosition,
                                            builder: (_, position, __) {
                                              final left = trimPlayheadLeft(
                                                startX: 0,
                                                endX: endX - startX,
                                                startMs: _startValue,
                                                endMs: _endValue,
                                                positionMs:
                                                    position.inMilliseconds
                                                        .toDouble(),
                                              );
                                              return Stack(
                                                children: [
                                                  const SizedBox.expand(),
                                                  Positioned(
                                                    left: left,
                                                    top: 0,
                                                    width: trimPlayheadWidth,
                                                    height: trimViewerHeight,
                                                    child: Container(
                                                      color: accent,
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : const SizedBox(height: trimViewerHeight),
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
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
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
