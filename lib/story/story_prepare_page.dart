// story_prepare_page.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../core/theme/chatme_colors.dart';
import '../core/utils/trim_playback_geometry.dart';
import '../services/chatme_toast.dart';
import '../services/image_prepare.dart';
import '../ui/chat_image_crop_page.dart';

/// What the prepare screen hands back. Posting stays in the caller; this
/// screen never encrypts, uploads, or publishes anything.
class StoryPrepareResult {
  final File file;
  final String mimeType;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final int? trimStartMs;
  final int? trimEndMs;
  final String caption;

  const StoryPrepareResult({
    required this.file,
    required this.mimeType,
    this.width,
    this.height,
    this.durationSeconds,
    this.trimStartMs,
    this.trimEndMs,
    this.caption = '',
  });

  factory StoryPrepareResult.fromPreparedImage({
    required PreparedImage prepared,
    required File file,
    String caption = '',
  }) {
    return StoryPrepareResult(
      file: file,
      mimeType: 'image/jpeg',
      width: prepared.width,
      height: prepared.height,
      caption: caption.trim(),
    );
  }

  factory StoryPrepareResult.fromVideo({
    required String path,
    required Duration duration,
    Size? videoSize,
    int? trimStartMs,
    int? trimEndMs,
    String caption = '',
  }) {
    final seconds = duration.inMilliseconds > 0
        ? duration.inMilliseconds ~/ 1000
        : null;
    return StoryPrepareResult(
      file: File(path),
      mimeType: _mimeFromPath(path),
      width: videoSize?.width.round(),
      height: videoSize?.height.round(),
      durationSeconds: seconds,
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
      caption: caption.trim(),
    );
  }
}

String _mimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'video/mp4';
}

// Same trick as room chat: keep the caret without raising the keyboard until
// the user explicitly taps the field.
class _CaptionFocusNode extends FocusNode {
  bool _allowKeyboardOnNextFocus = false;

  void allowKeyboardOnNextFocus() {
    _allowKeyboardOnNextFocus = true;
  }

  @override
  bool consumeKeyboardToken() {
    final consumed = super.consumeKeyboardToken();
    final allowed = _allowKeyboardOnNextFocus;
    _allowKeyboardOnNextFocus = false;
    return consumed && allowed;
  }
}

class StoryPreparePage extends StatefulWidget {
  /// The selection box is capped, not the file size or the thumbnail strip.
  static const Duration maxVideoLength = Duration(seconds: 60);

  /// Picker mime types can be absent on some platforms, so the path is the
  /// fallback for choosing photo or video mode.
  static bool isVideoMedia(String path, String? mimeType) {
    if (mimeType != null && mimeType.startsWith('video/')) return true;
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  final String mediaPath;
  final bool isVideo;

  /// Seams for widget tests. Production callers leave every one null.
  final Future<Uint8List> Function(File file)? imageLoader;
  final Widget Function(Uint8List bytes)? imagePreviewBuilder;
  final Future<Uint8List?> Function(BuildContext context, Uint8List bytes,
      {double? aspectRatio})? cropOpener;
  final Future<PreparedImage> Function(Uint8List bytes,
      {int maxSide, int quality})? imagePreparer;
  final Future<File> Function(Uint8List bytes)? preparedFileWriter;
  final Widget Function(VoidCallback onToggle)? videoPreviewBuilder;
  final Widget Function(VoidCallback onTrim)? trimStripBuilder;
  final Duration? knownDuration;
  final Size? knownVideoSize;

  const StoryPreparePage({
    super.key,
    required this.mediaPath,
    required this.isVideo,
    this.imageLoader,
    this.imagePreviewBuilder,
    this.cropOpener,
    this.imagePreparer,
    this.preparedFileWriter,
    this.videoPreviewBuilder,
    this.trimStripBuilder,
    this.knownDuration,
    this.knownVideoSize,
  });

  @override
  State<StoryPreparePage> createState() => _StoryPreparePageState();
}

class _StoryPreparePageState extends State<StoryPreparePage> {
  final Trimmer _trimmer = Trimmer();
  final ValueNotifier<Duration> _playhead = ValueNotifier(Duration.zero);
  final TextEditingController _captionController = TextEditingController();
  final _CaptionFocusNode _captionFocusNode = _CaptionFocusNode();
  final List<File> _tempFiles = <File>[];

  VideoPlayerController? _listenedController;
  Uint8List? _imageBytes;
  String? _videoPath;
  double _startValue = 0;
  double _endValue = 0;
  double _totalMs = 0;
  bool _isVideoReady = false;
  bool _isPlaying = false;
  bool _playCommandInFlight = false;
  bool _isSeeking = false;
  bool _nextBusy = false;
  bool _closing = false;

  VideoPlayerController? get _controller => _trimmer.videoPlayerController;

  Duration get _duration =>
      widget.knownDuration ??
      _controller?.value.duration ??
      Duration.zero;

  @override
  void initState() {
    super.initState();
    _sourceFile = File(widget.mediaPath);
    // A valid selection keeps EditableText from calling requestKeyboard()
    // while repairing an invalid one on the first quiet focus.
    _captionController.selection = const TextSelection.collapsed(offset: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _captionFocusNode.requestFocus();
    });
    if (widget.isVideo) {
      _videoPath = widget.mediaPath;
      _loadVideo();
    } else {
      _loadImage();
    }
  }

  late final File _sourceFile;

  @override
  void dispose() {
    _unbindController();
    _captionFocusNode.dispose();
    _captionController.dispose();
    _playhead.dispose();
    _trimmer.dispose();
    super.dispose();
  }

  void _bindController(VideoPlayerController controller) {
    _unbindController();
    _listenedController = controller;
    controller.addListener(_onControllerTick);
  }

  void _unbindController() {
    _listenedController?.removeListener(_onControllerTick);
    _listenedController = null;
  }

  void _onControllerTick() {
    final controller = _listenedController;
    if (controller == null || !controller.value.isInitialized) return;

    final start = Duration(milliseconds: _startValue.round());
    final end = Duration(milliseconds: _endValue.round());
    final position = controller.value.position;

    if (controller.value.isPlaying &&
        !_isSeeking &&
        end > start &&
        position >= end) {
      _isSeeking = true;
      _playhead.value = start;
      controller.seekTo(start).whenComplete(() => _isSeeking = false);
      return;
    }

    if (position != _playhead.value) _playhead.value = position;
    if (mounted && controller.value.isPlaying != _isPlaying) {
      setState(() => _isPlaying = controller.value.isPlaying);
    }
  }

  bool _needsTrim({
    required double start,
    required double end,
    required int totalMs,
  }) {
    if (totalMs <= 0 || end <= start) return false;
    return start > 0 || end < totalMs - 50;
  }

  double _boundedEnd(double value, {required double start}) {
    final bounded = value > _totalMs ? _totalMs : value;
    if (bounded < start) return start;
    final cap = StoryPreparePage.maxVideoLength.inMilliseconds.toDouble();
    if (bounded - start > cap) return start + cap;
    return bounded;
  }

  void _clampPlayhead() {
    final controller = _controller;
    final start = Duration(milliseconds: _startValue.round());
    final end = Duration(milliseconds: _endValue.round());
    var position = controller?.value.position ?? Duration.zero;
    if (position < start) position = start;
    if (position > end) position = end;
    _playhead.value = position;

    if (controller != null &&
        controller.value.isPlaying &&
        end > start &&
        position >= end) {
      controller.seekTo(start);
    }
  }

  Future<void> _loadImage() async {
    try {
      final loader = widget.imageLoader ?? _readImage;
      final bytes = await loader(_sourceFile);
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ChatmeToast.show('Could not open the photo');
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadVideo() async {
    if (widget.videoPreviewBuilder != null) {
      final totalMs = widget.knownDuration?.inMilliseconds.toDouble() ?? 0;
      if (!mounted) return;
      setState(() {
        _totalMs = totalMs;
        _startValue = 0;
        _endValue = _boundedEnd(totalMs, start: 0);
        _isVideoReady = true;
      });
      return;
    }

    try {
      await _trimmer.loadVideo(videoPath: _videoPath!);
      if (!mounted) return;
      final controller = _controller;
      if (controller == null) throw const FileSystemException('no video');

      final totalMs = controller.value.duration.inMilliseconds.toDouble();
      _bindController(controller);
      await controller.setLooping(true);
      await controller.setVolume(1.0);
      if (!mounted) return;
      setState(() {
        _totalMs = totalMs;
        _startValue = 0;
        _endValue = _boundedEnd(totalMs, start: 0);
        _isVideoReady = true;
      });
      await controller.play();
    } catch (_) {
      _unbindController();
      if (!mounted) return;
      ChatmeToast.show('Could not open the video');
      Navigator.of(context).pop();
    }
  }

  static Future<Uint8List> _readImage(File file) => file.readAsBytes();

  static Future<Uint8List?> _openCrop(
    BuildContext context,
    Uint8List bytes, {
    double? aspectRatio,
  }) {
    return ChatImageCropPage.open(context, bytes, aspectRatio: aspectRatio);
  }

  Future<void> _cropImage() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    final opener = widget.cropOpener ?? _openCrop;
    final cropped = await opener(context, bytes);
    if (cropped != null && mounted) {
      setState(() => _imageBytes = cropped);
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !_isVideoReady || _playCommandInFlight) return;
    _playCommandInFlight = true;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
        return;
      }
      final start = Duration(milliseconds: _startValue.round());
      final end = Duration(milliseconds: _endValue.round());
      if (end > start &&
          (controller.value.position < start ||
              controller.value.position >= end)) {
        _playhead.value = start;
        await controller.seekTo(start);
      }
      await controller.play();
    } catch (_) {
      // A platform failure leaves the preview paused; Next still works.
    } finally {
      _playCommandInFlight = false;
    }
  }

  Future<String> _saveTrimIfNeeded() async {
    final original = _videoPath ?? widget.mediaPath;
    final needsTrim = _needsTrim(
      start: _startValue,
      end: _endValue,
      totalMs: _totalMs.round(),
    );
    if (!needsTrim) return original;

    final completer = Completer<String?>();
    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      storageDir: StorageDir.temporaryDirectory,
      onSave: (outputPath) {
        if (!completer.isCompleted) completer.complete(outputPath);
      },
    );
    final output = await completer.future;
    if (output == null || output.isEmpty) {
      throw const FileSystemException('could not trim the video');
    }
    if (output != original && output != widget.mediaPath) {
      _tempFiles.add(File(output));
    }
    return output;
  }

  Future<File> _writePreparedImage(Uint8List bytes) async {
    final name = 'story_prepare_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final file =
        File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _next() async {
    if (_nextBusy) return;
    final caption = _captionController.text.trim();
    _nextBusy = true;
    setState(() {});
    try {
      if (!widget.isVideo) {
        final bytes = _imageBytes;
        if (bytes == null) return;
        final preparer = widget.imagePreparer ?? prepareImage;
        final prepared = await preparer(bytes);
        final writer = widget.preparedFileWriter ?? _writePreparedImage;
        final file = await writer(prepared.bytes);
        if (!mounted) {
          await _safeDelete(file);
          return;
        }
        Navigator.of(context).pop(StoryPrepareResult.fromPreparedImage(
          prepared: prepared,
          file: file,
          caption: caption,
        ));
        return;
      }

      if (!mounted) return;
      await _controller?.pause();
      final needsTrim = _needsTrim(
        start: _startValue,
        end: _endValue,
        totalMs: _totalMs.round(),
      );
      final savedPath = await _saveTrimIfNeeded();
      if (!mounted) return;
      final duration = needsTrim
          ? Duration(milliseconds: (_endValue - _startValue).round())
          : _duration;
      Navigator.of(context).pop(StoryPrepareResult.fromVideo(
        path: savedPath,
        duration: duration,
        videoSize: _controller?.value.size ?? widget.knownVideoSize,
        trimStartMs: needsTrim ? _startValue.round() : null,
        trimEndMs: needsTrim ? _endValue.round() : null,
        caption: caption,
      ));
    } catch (_) {
      if (!mounted) return;
      ChatmeToast.show('Could not prepare the story');
    } finally {
      if (mounted) {
        setState(() => _nextBusy = false);
      }
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _cleanupTempFiles() async {
    for (final file in _tempFiles) {
      await _safeDelete(file);
    }
    _tempFiles.clear();
  }

  void _back() {
    if (_closing) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    const accent = ChatmeColors.accentPrimary;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _closing = true;
          if (result == null) unawaited(_cleanupTempFiles());
        }
      },
      child: Scaffold(
        backgroundColor: ChatmeColors.backgroundPrimary,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded,
                              color: ChatmeColors.textPrimary,
                              size: 18),
                          onPressed: _nextBusy ? null : _back,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'New Story',
                          style: TextStyle(
                            color: ChatmeColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (!widget.isVideo)
                          IconButton(
                            icon: const Icon(Icons.crop_rounded,
                                color: ChatmeColors.textPrimary,
                            ),
                            onPressed: _imageBytes == null ? null : _cropImage,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: widget.isVideo
                        ? _buildVideoPreview(accent)
                        : _buildPhotoPreview(accent),
                  ),
                  if (widget.isVideo) _buildTrimStrip(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      12,
                      kIsWeb ? 20 : 6,
                      12,
                      kIsWeb ? 20 : 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(
                              minHeight: 48,
                              maxHeight: 180,
                            ),
                            decoration: BoxDecoration(
                              color: ChatmeColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(30),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 48,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  alignment: Alignment.center,
                                  child: TextField(
                                    controller: _captionController,
                                    focusNode: _captionFocusNode,
                                    enabled: !_nextBusy,
                                    onTap: () {
                                      if (!_captionFocusNode.hasFocus) {
                                        _captionFocusNode
                                            .allowKeyboardOnNextFocus();
                                      }
                                    },
                                    maxLength: 200,
                                    maxLengthEnforcement:
                                        MaxLengthEnforcement.enforced,
                                    minLines: 1,
                                    maxLines: 3,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.25,
                                      color: ChatmeColors.textPrimary,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Add a caption...',
                                      hintStyle: TextStyle(
                                        fontSize: 16,
                                        height: 1.25,
                                        color: ChatmeColors.textSubtle,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 8,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      counterText: '',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: 'Next',
                          child: GestureDetector(
                            onTap: _nextBusy ? null : _next,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: ChatmeColors.accentPrimary,
                              ),
                              child: const Icon(
                                Icons.chevron_right_rounded,
                                color: ChatmeColors.backgroundPrimary,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_nextBusy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: ChatmeColors.scrim,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: ChatmeColors.accentPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(Color accent) {
    final bytes = _imageBytes;
    if (bytes == null) {
      return Center(child: CircularProgressIndicator(color: accent));
    }
    final preview =
        widget.imagePreviewBuilder?.call(bytes) ?? Image.memory(bytes);
    return Center(child: preview);
  }

  Widget _buildVideoPreview(Color accent) {
    if (widget.videoPreviewBuilder != null) {
      return SizedBox.expand(
        child: widget.videoPreviewBuilder!(_togglePlayback),
      );
    }
    final controller = _controller;
    if (!_isVideoReady || controller == null) {
      return Center(child: CircularProgressIndicator(color: accent));
    }
    final ratio =
        controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    return Center(
      child: GestureDetector(
        onTap: _togglePlayback,
        child: AspectRatio(
          aspectRatio: ratio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildTrimStrip() {
    final child = widget.trimStripBuilder != null
        ? widget.trimStripBuilder!(_onControllerTick)
        : _buildRealTrimStrip();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Tooltip(message: 'Trim video', child: child),
    );
  }

  Widget _buildRealTrimStrip() {
    if (!_isVideoReady) return const SizedBox(height: trimViewerHeight);
    const labelStyle = TextStyle(color: ChatmeColors.textPrimary, fontSize: 12);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return const SizedBox(height: trimViewerHeight);
        }
        final stripWidth = trimStripWidth(constraints.maxWidth);
        if (stripWidth <= 0) return const SizedBox(height: trimViewerHeight);

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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _format(Duration(milliseconds: _startValue.round())),
                      style: labelStyle,
                    ),
                    ValueListenableBuilder<Duration>(
                      valueListenable: _playhead,
                      builder: (_, position, __) =>
                          Text(_format(position), style: labelStyle),
                    ),
                    Text(
                      _format(Duration(milliseconds: _endValue.round())),
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
                    maxVideoLength: StoryPreparePage.maxVideoLength,
                    type: ViewerType.fixed,
                    viewerWidth: stripWidth,
                    viewerHeight: trimViewerHeight,
                    showDuration: false,
                    onChangeStart: (value) {
                      if (!mounted) return;
                      final bounded =
                          value > _endValue ? _endValue : value;
                      setState(() => _startValue = bounded);
                      _clampPlayhead();
                    },
                    onChangeEnd: (value) {
                      if (!mounted) return;
                      setState(() => _endValue = _boundedEnd(
                            value,
                            start: _startValue,
                          ));
                      _clampPlayhead();
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
                          valueListenable: _playhead,
                          builder: (_, position, __) {
                            final left = trimPlayheadLeft(
                              startX: 0,
                              endX: endX - startX,
                              startMs: _startValue,
                              endMs: _endValue,
                              positionMs: position.inMilliseconds.toDouble(),
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
                                    color: ChatmeColors.accentPrimary,
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
    );
  }
}
