import 'package:flutter/material.dart';

/// Colours of the Nostr Cyber / Amethyst room chat theme.
class CyberColors {
  CyberColors._();

  /// The purple of the send button, your bubbles, and the accent text.
  static const Color accent = Color(0xFFBB86FC);

  /// Text and icons drawn on top of [accent]. White is too faint on it.
  static const Color onAccent = Color(0xFF130F1A);

  /// Reply name inside your own bubble.
  static const Color replyNameOnAccent = Color(0xFF3C096C);

  /// Blue double tick on your own bubble.
  static const Color readTickOnAccent = Color(0xFF0D47A1);
}
