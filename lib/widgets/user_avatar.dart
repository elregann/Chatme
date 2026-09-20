import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../relay_manager.dart';
import '../core/utils/ui_utils.dart';

class UserAvatar extends StatelessWidget {
  final String pubkey;
  final String? name; // For initials
  final double radius;
  final RelayManager relayManager;

  const UserAvatar({
    super.key,
    required this.pubkey,
    this.name,
    this.radius = 20.0,
    required this.relayManager,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: relayManager.fetchProfilePicture(pubkey),
      builder: (context, snapshot) {
        final photoUrl = snapshot.data;
        
        final fallbackAvatar = CircleAvatar(
          radius: radius,
          backgroundColor: UIUtils.getAvatarColor(pubkey),
          child: Text(
            UIUtils.getInitials(name ?? pubkey),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.7, // Skala font otomatis
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
      },
    );
  }
}
