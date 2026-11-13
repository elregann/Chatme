import 'package:flutter/material.dart';

import '../core/theme/chatme_colors.dart';

/// A neutral card for information and warnings, matching the menu cards.
class ChatmeNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color iconColor;
  final Color textColor;

  const ChatmeNotice({
    super.key,
    required this.icon,
    required this.message,
    this.iconColor = ChatmeColors.accentPrimary,
    this.textColor = ChatmeColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ChatmeColors.surfaceMenu,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChatmeColors.borderSubtle, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, height: 1.5, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
