import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/utils/ui_utils.dart';
import '../relay_manager.dart';

class ProfilePhotoViewer extends StatefulWidget {
  final String pubkey;
  final String? name;
  final String? localPhotoPath;
  final String? photoUrl;
  final RelayManager relayManager;

  const ProfilePhotoViewer({
    super.key,
    required this.pubkey,
    required this.name,
    this.localPhotoPath,
    this.photoUrl,
    required this.relayManager,
  });

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer> {
  String? _photoUrl;

  bool get _hasLocalPhoto =>
      !kIsWeb &&
      widget.localPhotoPath != null &&
      widget.localPhotoPath!.isNotEmpty;

  @override
  void initState() {
    super.initState();

    if (widget.photoUrl != null && widget.photoUrl!.isNotEmpty) {
      _photoUrl = widget.photoUrl;
      return;
    }

    if (_hasLocalPhoto) return;

    final cachedUrl = widget.relayManager.getProfilePictureSync(widget.pubkey);
    if (cachedUrl != null) {
      _photoUrl = cachedUrl;
    } else {
      _loadPhoto();
    }
  }

  Future<void> _loadPhoto() async {
    try {
      final url = await widget.relayManager.fetchProfilePicture(widget.pubkey);
      if (!mounted) return;
      setState(() => _photoUrl = url ?? '');
    } catch (_) {
      if (mounted) setState(() => _photoUrl = '');
    }
  }

  Widget _buildFallback(double side) {
    return Container(
      color: UIUtils.getAvatarColor(widget.pubkey),
      alignment: Alignment.center,
      child: Text(
        UIUtils.getInitials(widget.name ?? widget.pubkey),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: side * 0.42,
        ),
      ),
    );
  }

  Widget _buildPhoto(double side) {
    if (_hasLocalPhoto) {
      return Image.file(
        File(widget.localPhotoPath!),
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null ? _buildFallback(side) : child,
        errorBuilder: (_, __, ___) => _buildFallback(side),
      );
    }

    final url = _photoUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null ? _buildFallback(side) : child,
        errorBuilder: (_, __, ___) => _buildFallback(side),
      );
    }

    return _buildFallback(side);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final side = math.min(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ).toDouble();
                    return SizedBox.square(
                      dimension: side,
                      child: _buildPhoto(side),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
