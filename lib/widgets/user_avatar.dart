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

  /// In-memory cache of profile picture URLs. Only **non-null** entries
  /// are stored — a missing picture must not be cached, otherwise the
  /// widget would never retry and avatars would stay empty until the
  /// app is fully restarted.
  static final Map<String, String> _avatarMemCache = {};

  /// Bumped whenever [invalidate] or [invalidateAll] is called. Every
  /// live UserAvatar widget listens to this and rebuilds when it changes.
  static final ValueNotifier<int> _cacheVersion = ValueNotifier<int>(0);

  /// Clears the cached URL for [pubkey] and forces every visible
  /// UserAvatar to rebuild. Call this whenever a profile picture is
  /// updated — for the local user after `broadcastProfileKind0`, or
  /// for a peer when a Kind 0 metadata event arrives from a relay.
  static void invalidate(String pubkey) {
    _avatarMemCache.remove(pubkey);
    _cacheVersion.value++;
  }

  /// Clears the entire cache. Use sparingly (e.g. on account switch).
  static void invalidateAll() {
    _avatarMemCache.clear();
    _cacheVersion.value++;
  }

  const UserAvatar({
    super.key,
    required this.pubkey,
    this.name,
    this.radius = 20.0,
    required this.relayManager,
  });

  Widget _buildAvatar(BuildContext context, String? photoUrl) {
    final fallbackAvatar = CircleAvatar(
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

    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: photoUrl,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundColor: UIUtils.getAvatarColor(pubkey),
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => fallbackAvatar,
        errorWidget: (context, url, error) => fallbackAvatar,
      );
    }

    return fallbackAvatar;
  }

  Widget _buildContent(BuildContext context) {
    // Instant synchronous render if the URL is already cached.
    final cached = _avatarMemCache[pubkey];
    if (cached != null) {
      return _buildAvatar(context, cached);
    }

    return FutureBuilder<String?>(
      future: relayManager.fetchProfilePicture(pubkey),
      builder: (context, snapshot) {
        // Only cache successful, non-empty fetches. Caching null (or an
        // empty string) would permanently block future retries because
        // the cache lookup below only checks for presence, not validity.
        if (snapshot.hasData &&
            snapshot.data != null &&
            snapshot.data!.isNotEmpty) {
          _avatarMemCache[pubkey] = snapshot.data!;
        }

        return _buildAvatar(context, snapshot.data);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _cacheVersion,
      builder: (context, _, __) => _buildContent(context),
    );
  }
}