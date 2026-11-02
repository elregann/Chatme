// emoji_utils.dart

import 'package:characters/characters.dart';

/// Base font size for a message made of a few emoji.
const double emojiLargeFontSize = 44.0;

/// Base font size for a message with more than three emoji, so a long run of
/// emoji does not fill the whole screen.
const double emojiSmallFontSize = 30.0;

/// The number of emoji in [text], or `null` when [text] contains anything
/// other than emoji and spaces.
///
/// Emoji sequences such as `👨‍👩‍👧`, `👍🏽`, `🇮🇩`, and `1️⃣` count as one
/// character, matching what the user sees.
int? emojiOnlyCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  var count = 0;
  for (final cluster in trimmed.characters) {
    if (cluster.trim().isEmpty) continue;
    if (!_isEmojiCluster(cluster)) return null;
    count++;
  }
  return count == 0 ? null : count;
}

/// Whether [text] is made only of emoji (and spaces between them).
bool isEmojiOnly(String text) => emojiOnlyCount(text) != null;

/// The un-scaled font size for an emoji-only message with [count] emoji.
double emojiFontSizeForCount(int count) =>
    count <= 3 ? emojiLargeFontSize : emojiSmallFontSize;

bool _isEmojiCluster(String cluster) {
  final runes = cluster.runes.toList();
  final isKeycap = runes.contains(0x20E3);
  var hasBase = false;

  for (final rune in runes) {
    if (_isEmojiModifier(rune)) continue;
    if (isKeycap && _isKeycapBase(rune)) {
      hasBase = true;
      continue;
    }
    if (_isEmojiBase(rune)) {
      hasBase = true;
      continue;
    }
    return false;
  }
  return hasBase;
}

/// Characters that only decorate an emoji: joiners, variation selectors,
/// skin tones, keycaps, and the tag characters used by subdivision flags.
bool _isEmojiModifier(int rune) {
  return rune == 0x200D || // zero-width joiner
      rune == 0xFE0E || // text presentation selector
      rune == 0xFE0F || // emoji presentation selector
      rune == 0x20E3 || // combining enclosing keycap
      (rune >= 0x1F3FB && rune <= 0x1F3FF) || // skin tones
      (rune >= 0xE0020 && rune <= 0xE007F); // flag tag characters
}

bool _isKeycapBase(int rune) {
  return rune == 0x23 || // #
      rune == 0x2A || // *
      (rune >= 0x30 && rune <= 0x39); // 0-9
}

bool _isEmojiBase(int rune) {
  for (final (start, end) in _emojiRanges) {
    if (rune >= start && rune <= end) return true;
  }
  return false;
}

/// Code point ranges that can start an emoji. This is intentionally broader
/// than the current Unicode emoji list: a symbol that renders as a picture is
/// still better treated as an emoji than as text.
const List<(int, int)> _emojiRanges = [
  (0x00A9, 0x00A9), // ©
  (0x00AE, 0x00AE), // ®
  (0x203C, 0x203C), // ‼
  (0x2049, 0x2049), // ⁉
  (0x2122, 0x2122), // ™
  (0x2139, 0x2139), // ℹ
  (0x2194, 0x2199),
  (0x21A9, 0x21AA),
  (0x231A, 0x231B),
  (0x2328, 0x2328),
  (0x23CF, 0x23CF),
  (0x23E9, 0x23F3),
  (0x23F8, 0x23FA),
  (0x24C2, 0x24C2),
  (0x25AA, 0x25AB),
  (0x25B6, 0x25B6),
  (0x25C0, 0x25C0),
  (0x25FB, 0x25FE),
  (0x2600, 0x27BF),
  (0x2934, 0x2935),
  (0x2B05, 0x2B07),
  (0x2B1B, 0x2B1C),
  (0x2B50, 0x2B50),
  (0x2B55, 0x2B55),
  (0x3030, 0x3030),
  (0x303D, 0x303D),
  (0x3297, 0x3297),
  (0x3299, 0x3299),
  (0x1F000, 0x1FAFF),
];
