// image_viewer.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../services/chat_reply.dart';
import '../../services/gallery_save.dart';
import '../../services/media_history.dart';
import '../../widgets/chatme_menu.dart';

/// Full screen pictures. Swipe to change, pinch to zoom.
class ImageViewerPage extends StatefulWidget {
  final List<String> paths;
  final int initialIndex;

  /// The messages shown in [paths], in the same order. Used for Reply.
  final List<ChatMessage> messages;

  /// Replies to the picture on screen. No Reply item is shown without it.
  final ValueChanged<ChatMessage>? onReply;

  final String? _single;

  /// Saves a picture to the gallery. Replaceable for tests.
  final Future<void> Function(String path) saveToGallery;

  const ImageViewerPage({
    super.key,
    required this.paths,
    this.initialIndex = 0,
    this.messages = const [],
    this.onReply,
    this.saveToGallery = GallerySaver.save,
  }) : _single = null;

  const ImageViewerPage.single({
    super.key,
    required String path,
    this.messages = const [],
    this.onReply,
    this.saveToGallery = GallerySaver.save,
  })  : paths = const [],
        initialIndex = 0,
        _single = path;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final List<String> _paths;
  late final PageController _controller;
  late int _index;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _paths = widget._single != null ? [widget._single!] : widget.paths;
    _index = _paths.isEmpty ? 0 : widget.initialIndex.clamp(0, _paths.length - 1);
    _controller = PageController(initialPage: _index);
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
      await widget.saveToGallery(_paths[_index]);
      text = 'Saved to the Chatme album';
    } on GallerySaveException catch (e) {
      text = e.message;
    } catch (_) {
      text = 'Could not save the photo';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _setZoomed(bool zoomed) {
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  ChatMessage? get _currentMessage =>
      _index < widget.messages.length ? widget.messages[_index] : null;

  void _reply() {
    final message = _currentMessage;
    if (message == null || !canReplyTo(message)) return;
    widget.onReply?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentMessage;
    final canReply =
        current != null && widget.onReply != null && canReplyTo(current);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: _paths.length > 1
            ? Text(
              viewerCounter(_index, _paths.length),
              style: const TextStyle(fontSize: 15, color: Colors.white),
            )
            : null,
        actions: [
          ChatmeMenuButton<int>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            entries: [
              const ChatmeMenuEntry(value: 0, icon: Icons.save_alt_rounded, label: 'Save to Gallery'),
              if (canReply)
                const ChatmeMenuEntry(value: 1, icon: Icons.reply, label: 'Reply'),
            ],
            onSelected: (value) => value == 0 ? _save() : _reply(),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: _paths.length,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        onPageChanged: (i) => setState(() {
          _index = i;
          _zoomed = false;
        }),
        itemBuilder: (_, i) => _ZoomablePage(
          key: ValueKey(_paths[i]),
          path: _paths[i],
          onZoomChanged: _setZoomed,
        ),
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  final String path;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePage({super.key, required this.path, required this.onZoomChanged});

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 5,
      panEnabled: _zoomed,
      child: SizedBox.expand(
        child: Image.file(
          File(widget.path),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
          ),
        ),
      ),
    );
  }
}
