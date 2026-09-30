import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../relay_manager.dart';
import '../core/utils/ui_utils.dart';

class UserAvatar extends StatelessWidget {
  final String pubkey;
  final String? name; // For initials
  final double radius;
  final RelayManager relayManager;

  // Static in-memory cache to prevent FutureBuilder flicker & re-execution during scrolling
  static final Map<String, String?> _avatarMemCache = {};

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

  @override
  Widget build(BuildContext context) {
    // Instant synchronous render if photo URL is already in memory cache
    if (_avatarMemCache.containsKey(pubkey)) {
      return _buildAvatar(context, _avatarMemCache[pubkey]);
    }

    return FutureBuilder<String?>(
      future: relayManager.fetchProfilePicture(pubkey),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done || snapshot.hasData) {
          _avatarMemCache[pubkey] = snapshot.data;
        }
        final photoUrl = snapshot.data ?? _avatarMemCache[pubkey];
        return _buildAvatar(context, photoUrl);
      },
    );
  }
}
