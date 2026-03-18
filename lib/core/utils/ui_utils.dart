// ui_utils.dart

import 'package:flutter/material.dart';

class UIUtils {
  static Color getAvatarColor(String pubkey) {
    if (pubkey.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(pubkey.substring(0, 8), radix: 16) | 0xFF000000);
    } catch (e) {
      return Colors.blueGrey;
    }
  }

  static String getInitials(String name) {
    if (name.trim().isEmpty) return "?";
    return name.trim().substring(0, 1).toUpperCase();
  }
}