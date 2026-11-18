// chatme_menu.dart

import 'package:flutter/material.dart';

import '../core/theme/chatme_colors.dart';

class ChatmeMenu {
  ChatmeMenu._();

  static const double radius = 10;
  static const double itemHeight = 44;
  static const Color darkColor = Color(0xFF2C2C2C);
  static const Color lightColor = Colors.white;
}

class ChatmeMenuEntry<T> {
  final T value;

  /// Optional: an entry with only a label has no leading icon.
  final IconData? icon;
  final String label;

  /// Optional unread dot shown after the label, used by Calls History.
  final bool dot;

  const ChatmeMenuEntry({
    required this.value,
    this.icon,
    required this.label,
    this.dot = false,
  });
}

/// The small menu Chatme uses for a button with a few choices. The press
/// effect fills each row all the way to the edge of the menu.
class ChatmeMenuButton<T> extends StatelessWidget {
  final Widget icon;
  final List<ChatmeMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  /// Menu background. Follows the theme when null.
  final Color? color;

  /// Text and icon color of the rows. Follows the theme when null.
  final Color? textColor;

  final double splashRadius;

  /// Where the menu opens, relative to the button.
  final Offset offset;

  /// Set to false to leave focus where it is while the menu is open, so a
  /// text field that has the keyboard up keeps it. Null uses the default.
  final bool? requestFocus;

  const ChatmeMenuButton({
    super.key,
    required this.icon,
    required this.entries,
    required this.onSelected,
    this.color,
    this.textColor,
    this.splashRadius = 22,
    this.offset = Offset.zero,
    this.requestFocus,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rowColor = textColor ?? (dark ? Colors.white : Colors.black87);

    return PopupMenuButton<T>(
      tooltip: '',
      padding: EdgeInsets.zero,
      menuPadding: EdgeInsets.zero,
      splashRadius: splashRadius,
      offset: offset,
      requestFocus: requestFocus,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      icon: icon,
      color: color ?? (dark ? ChatmeMenu.darkColor : ChatmeMenu.lightColor),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChatmeMenu.radius)),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final entry in entries)
          PopupMenuItem<T>(
            value: entry.value,
            height: ChatmeMenu.itemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.icon != null) ...[
                  Icon(entry.icon, size: 20, color: rowColor),
                  const SizedBox(width: 12),
                ],
                Text(entry.label, style: TextStyle(fontSize: 14, color: rowColor)),
                if (entry.dot) ...[
                  const SizedBox(width: 8),
                  const DecoratedBox(
                    key: Key('chatme-menu-dot'),
                    decoration: BoxDecoration(
                      color: ChatmeColors.badgeDanger,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(width: 6, height: 6),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
