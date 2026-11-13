import 'package:flutter/material.dart';

/// Central color palette for the Chatme app.
class ChatmeColors {
  ChatmeColors._();

  // Backgrounds and surfaces
  static const Color backgroundPrimary = Color(0xFF04060C);
  static const Color surfaceBase = Color(0xFF0A0D16);
  static const Color surfaceRaised = Color(0xFF121622);
  static const Color surfaceOverlay = Color(0xFF1A1F2E);
  static const Color surfaceMenu = Color(0xFF132020);
  static const Color surfaceAction = Color(0xFF0E3333);

  // Accent mint
  static const Color accentPrimary = Color(0xFF97FCE4);
  static const Color accentStrong = Color(0xFF50D2C1);
  static const Color accentDeep = Color(0xFF2FA89A);
  static const Color onAccent = Color(0xFF04060C);

  // Status
  static const Color statusPositive = Color(0xFF3FD68B);
  static const Color statusDanger = Color(0xFFFF5470);
  static const Color statusWarning = Color(0xFFFFD25F);

  // Text on dark surfaces
  static const Color textPrimary = Color(0xEBFFFFFF);
  static const Color textSecondary = Color(0xC7FFFFFF);
  static const Color textMuted = Color(0x99FFFFFF);
  static const Color textSubtle = Color(0x73FFFFFF);

  // Chat bubbles
  static const Color bubbleOutgoing = Color(0xFF0E3333);
  static const Color bubbleIncoming = Color(0xFF121622);

  // Call actions
  static const Color callAccept = statusPositive;
  static const Color callEnd = statusDanger;

  // Call UI surfaces
  static const Color callControlSurface = Color(0x14FFFFFF);
  static const Color callControlSurfaceActive = Color(0x33FFFFFF);
  static const Color callControlBorder = Color(0x1FFFFFFF);
  static const Color callControlIcon = Color(0xEBFFFFFF);
  static const Color callControlIconOnActive = Color(0xFF04060C);

  // Dividers and borders
  static const Color dividerSubtle = Color(0x1FFFFFFF);
  static const Color borderSubtle = Color(0x1FFFFFFF);

  // Message status and indicators
  static const Color readReceipt = accentStrong;
  static const Color notificationAccent = accentStrong;

  // Misc
  static const Color scrim = Color(0x99000000);
  static const Color scrimStrong = Color(0xCC000000);
  static const Color floatingBarBackground = Color(0xFF121622);
  static const Color badgeDanger = statusDanger;
  static const Color badgeOnDanger = Color(0xEBFFFFFF);
  static const Color navIndicator = Color(0xFF1A1F2E);
}
