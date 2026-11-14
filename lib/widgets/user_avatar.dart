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

  /// URL that each cached provider belongs to, so a provider is only reused
  /// when it still matches the current profile picture.
  static final Map<String, String> _imageProviderUrlCache = {};

  /// Per-pubkey notifiers to ensure invalidating one user's avatar only
  /// triggers a rebuild for widgets representing that specific user.
  static final Map<String, ValueNotifier<int>> _pubkeyNotifiers = {};

  static ValueNotifier<int> _getNotifier(String pubkey) {
    return _pubkeyNotifiers.putIfAbsent(pubkey, () => ValueNotifier<int>(0));
  }

  /// Seeds the RAM caches for [pubkey]. A resolved provider from an older URL
  /// is kept so it can act as the placeholder until the new URL loads.
  static void precacheProvider(String pubkey, String url) {
    if (url.isEmpty) {
      _avatarMemCache[pubkey] = '';
      _imageProviderCache[pubkey] = null;
      _imageProviderUrlCache[pubkey] = '';
      return;
    }
    _avatarMemCache[pubkey] = url;
    // Keep the last resolved provider around. It is reused as the placeholder
    // while a newly announced URL loads, so the avatar never falls back to the
    // initials circle in between two photos.
    if (_imageProviderCache[pubkey] != null) return;
    _imageProviderCache[pubkey] = CachedNetworkImageProvider(url);
    _imageProviderUrlCache[pubkey] = url;
  }

  /// Stores an already-resolved provider for [url], replacing any older one.
  /// Used after a local upload has been preloaded so the switch from the
  /// temporary file to the permanent URL happens in a single frame.
  static void setResolvedProvider(
    String pubkey,
    String url,
    ImageProvider provider,
  ) {
    _avatarMemCache[pubkey] = url;
    _imageProviderCache[pubkey] = provider;
    _imageProviderUrlCache[pubkey] = url;
  }

  /// Clears the cached URL for [pubkey] and forces only the visible
  /// UserAvatars for that pubkey to rebuild. Call this whenever a profile
  /// picture is updated - for the local user after `broadcastProfileKind0`,
  /// or for a peer when a Kind 0 metadata event arrives from a relay with a new URL.
  ///
  /// The resolved ImageProvider is intentionally kept so the previous avatar
  /// stays visible until the new URL has loaded.
  static void invalidate(String pubkey) {
    _avatarMemCache.remove(pubkey);
    if (_pubkeyNotifiers.containsKey(pubkey)) {
      _pubkeyNotifiers[pubkey]!.value++;
    }
  }

  /// Clears the entire cache and triggers rebuild for all registered avatars.
  /// Use sparingly (e.g. on account switch).
  static void invalidateAll() {
    _avatarMemCache.clear();
    _imageProviderCache.clear();
    _imageProviderUrlCache.clear();
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

  Widget _buildProviderAvatar(ImageProvider provider) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: UIUtils.getAvatarColor(pubkey),
      backgroundImage: provider,
    );
  }

  Widget _buildAvatar(BuildContext context, String? photoUrl) {
    final hasPhotoUrl = photoUrl != null && photoUrl.isNotEmpty;
    final cachedProvider = _imageProviderCache[pubkey];

    // 1. Instant zero-flicker render if the resolved provider matches the URL.
    if (hasPhotoUrl &&
        cachedProvider != null &&
        _imageProviderUrlCache[pubkey] == photoUrl) {
      return _buildProviderAvatar(cachedProvider);
    }

    // 2. Photo URL exists but its provider is not ready yet -> load it while
    // keeping the last successful avatar visible as the placeholder.
    if (hasPhotoUrl) {
      final placeholderProvider = cachedProvider;

      return CachedNetworkImage(
        imageUrl: photoUrl,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        imageBuilder: (context, imageProvider) {
          _imageProviderCache[pubkey] = imageProvider;
          _imageProviderUrlCache[pubkey] = photoUrl;
          return _buildProviderAvatar(imageProvider);
        },
        placeholder: (context, url) => placeholderProvider != null
            ? _buildProviderAvatar(placeholderProvider)
            : _buildFallback(),
        errorWidget: (context, url, error) {
          _avatarMemCache[pubkey] = '';
          _imageProviderCache[pubkey] = null;
          _imageProviderUrlCache[pubkey] = '';
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
        _imageProviderUrlCache[pubkey] = '';
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
            _imageProviderUrlCache[pubkey] = '';
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
