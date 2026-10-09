// user_avatar.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../relay_manager.dart';
import '../core/utils/ui_utils.dart';

class UserAvatar extends StatelessWidget {
  final String pubkey;
  final String? name;
  final double radius;
  final RelayManager relayManager;

  /// In-memory cache of profile picture URLs.
  /// Standard URLs are stored as non-empty strings.
  /// Users without a picture are stored as `""` (negative caching) to prevent
  /// infinite network re-fetch loops on every build/scroll pass.
  static final Map<String, String> _avatarMemCache = {};

  /// In-memory cache of resolved ImageProviders for zero-flicker instant rendering.
  static final Map<String, ImageProvider?> _imageProviderCache = {};

  /// Per-pubkey notifiers to ensure invalidating one user's avatar only
  /// triggers a rebuild for widgets representing that specific user.
  static final Map<String, ValueNotifier<int>> _pubkeyNotifiers = {};

  static ValueNotifier<int> _getNotifier(String pubkey) {
    return _pubkeyNotifiers.putIfAbsent(pubkey, () => ValueNotifier<int>(0));
  }

  /// Pre-caches an ImageProvider into RAM memory for instant zero-flicker renders.
  static void precacheProvider(String pubkey, String url) {
    if (url.isEmpty) {
      _avatarMemCache[pubkey] = '';
      _imageProviderCache[pubkey] = null;
      return;
    }
    _avatarMemCache[pubkey] = url;
    _imageProviderCache[pubkey] = CachedNetworkImageProvider(url);
  }

  /// Clears the cached URL & ImageProvider for [pubkey] and forces only the visible
  /// UserAvatars for that pubkey to rebuild. Call this whenever a profile
  /// picture is updated — for the local user after `broadcastProfileKind0`,
  /// or for a peer when a Kind 0 metadata event arrives from a relay with a new URL.
  static void invalidate(String pubkey) {
    _avatarMemCache.remove(pubkey);
    _imageProviderCache.remove(pubkey);
    if (_pubkeyNotifiers.containsKey(pubkey)) {
      _pubkeyNotifiers[pubkey]!.value++;
    }
  }

  /// Clears the entire cache and triggers rebuild for all registered avatars.
  /// Use sparingly (e.g. on account switch).
  static void invalidateAll() {
    _avatarMemCache.clear();
    _imageProviderCache.clear();
    for (final notifier in _pubkeyNotifiers.values) {
      notifier.value++;
    }
  }

  const UserAvatar({
    super.key,
    required this.pubkey,
    this.name,
    this.radius = 20.0,
    required this.relayManager,
  });

  Widget _buildFallback() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: UIUtils.getAvatarColor(pubkey),
      child: Text(
        UIUtils.getInitials(name ?? pubkey),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String? photoUrl) {
    // 1. Instant zero-flicker render if ImageProvider is already resolved in RAM
    final cachedProvider = _imageProviderCache[pubkey];
    if (cachedProvider != null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: UIUtils.getAvatarColor(pubkey),
        backgroundImage: cachedProvider,
      );
    }

    // 2. Photo URL exists but provider not yet in RAM cache -> render with CachedNetworkImage
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: photoUrl,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        imageBuilder: (context, imageProvider) {
          _imageProviderCache[pubkey] = imageProvider;
          return CircleAvatar(
            radius: radius,
            backgroundColor: UIUtils.getAvatarColor(pubkey),
            backgroundImage: imageProvider,
          );
        },
        placeholder: (context, url) => _buildFallback(),
        errorWidget: (context, url, error) {
          _avatarMemCache[pubkey] = '';
          _imageProviderCache[pubkey] = null;
          return _buildFallback();
        },
      );
    }

    return _buildFallback();
  }

  Widget _buildContent(BuildContext context) {
    // 1. Instant synchronous render if RAM cache contains result (URL or negative empty string)
    final cachedMem = _avatarMemCache[pubkey];
    if (cachedMem != null) {
      return _buildAvatar(context, cachedMem.isEmpty ? null : cachedMem);
    }

    // 2. Instant synchronous render if available in local Hive cache
    final cachedHive = relayManager.getProfilePictureSync(pubkey);
    if (cachedHive != null) {
      if (cachedHive.isNotEmpty) {
        precacheProvider(pubkey, cachedHive);
        return _buildAvatar(context, cachedHive);
      } else {
        _avatarMemCache[pubkey] = '';
        _imageProviderCache[pubkey] = null;
        return _buildFallback();
      }
    }

    // 3. Fallback to async fetch if not found in RAM or Hive
    return FutureBuilder<String?>(
      future: relayManager.fetchProfilePicture(pubkey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          final url = snapshot.data ?? '';
          if (url.isNotEmpty) {
            precacheProvider(pubkey, url);
          } else {
            _avatarMemCache[pubkey] = '';
            _imageProviderCache[pubkey] = null;
          }
        }

        return _buildAvatar(context, snapshot.data);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _getNotifier(pubkey),
      builder: (context, _, __) => _buildContent(context),
    );
  }
}