// chat_reactions.dart

import 'package:flutter/material.dart';

/// One categorized set of emojis for message reactions.
class ChatReactionCategory {
  final String name;
  final IconData icon;
  final List<String> emojis;

  const ChatReactionCategory({
    required this.name,
    required this.icon,
    required this.emojis,
  });
}

/// Central catalog for message reaction emojis in Chatme.
class ChatReactions {
  ChatReactions._();

  /// Emojis displayed directly on the long-press reaction bar.
  static const List<String> defaultQuickReactions = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
  ];

  /// Categorized emoji catalog for the all-reactions picker.
  static const List<ChatReactionCategory> categories = [
    ChatReactionCategory(
      name: 'Popular',
      icon: Icons.star_rounded,
      emojis: [
        '👍', '❤️', '😂', '😮', '😢', '🙏',
        '🔥', '🎉', '👏', '✨', '💯', '🫡',
        '🥰', '🤝', '🙌', '💪', '🌹', '👀',
      ],
    ),
    ChatReactionCategory(
      name: 'Smileys',
      icon: Icons.sentiment_satisfied_alt_rounded,
      emojis: [
        '😀', '😃', '😄', '😁', '😆', '😅',
        '🤣', '😂', '🙂', '😉', '😊', '😇',
        '🥰', '😍', '🤩', '😘', '😋', '😜',
        '🤪', '😎', '🥳', '😏', '😒', '😞',
        '😔', '😟', '😕', '🙁', '🥺', '😢',
        '😭', '😤', '😡', '🤬', '🤯', '😳',
        '🥵', '🥶', '😱', '😨', '🤔', '🫣',
        '🤫', '🫠', '🫡', '🥱', '😴', '🤤',
      ],
    ),
    ChatReactionCategory(
      name: 'Hearts',
      icon: Icons.favorite_rounded,
      emojis: [
        '❤️', '🧡', '💛', '💚', '💙', '💜',
        '🖤', '🤍', '🤎', '💔', '❤️‍🔥', '❤️‍🩹',
        '💖', '💗', '💓', '💞', '💕', '💘',
        '💝', '💌', '🫶', '😻', '💋', '🫦',
      ],
    ),
    ChatReactionCategory(
      name: 'Gestures',
      icon: Icons.thumb_up_alt_rounded,
      emojis: [
        '👍', '👎', '👊', '✊', '🤛', '🤜',
        '👏', '🙌', '👐', '🤲', '🤝', '🙏',
        '✌️', '🤟', '🤘', '🤙', '👈', '👉',
        '👆', '👇', '☝️', '✋', '🤚', '🖐️',
        '🖖', '👋', '💪', '🦾', '🫰', '🫵',
      ],
    ),
    ChatReactionCategory(
      name: 'Celebration',
      icon: Icons.celebration_rounded,
      emojis: [
        '🎉', '🎊', '🎈', '🎂', '🎁', '🏆',
        '🥇', '🥈', '🥉', '⭐', '🌟', '✨',
        '⚡', '💥', '🔥', '💯', '💫', '☀️',
        '🌙', '🌈', '🍀', '🌹', '🌻', '🌸',
        '☕', '🍻', '🥂', '🍾', '🍕', '🍰',
      ],
    ),
    ChatReactionCategory(
      name: 'Symbols',
      icon: Icons.lightbulb_outline_rounded,
      emojis: [
        '✅', '✔️', '☑️', '❌', '❎', '❓',
        '❗', '❕', '⚠️', '🚫', '⛔', '🚀',
        '🎯', '💡', '🔔', '💬', '👀', '👁️',
        '💀', '👻', '🤖', '💩', '👑', '💎',
      ],
    ),
  ];
}
