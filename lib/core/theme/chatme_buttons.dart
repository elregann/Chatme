import 'package:flutter/material.dart';

import 'chatme_colors.dart';

/// Accent color used for text buttons and switches.
const Color chatmeAccent = ChatmeColors.accentPrimary;

final TextButtonThemeData chatmeTextButtonTheme = TextButtonThemeData(
  style: TextButton.styleFrom(foregroundColor: chatmeAccent),
);

final SwitchThemeData chatmeSwitchTheme = SwitchThemeData(
  trackColor: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.selected) ? ChatmeColors.accentStrong : null,
  ),
  thumbColor: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.selected) ? ChatmeColors.accentPrimary : null,
  ),
);