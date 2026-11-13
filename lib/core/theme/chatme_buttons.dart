import 'package:flutter/material.dart';

import 'chatme_colors.dart';

/// Accent color used for text buttons and switches.
const Color chatmeAccent = ChatmeColors.accentPrimary;

final TextButtonThemeData chatmeTextButtonTheme = TextButtonThemeData(
  style: TextButton.styleFrom(foregroundColor: chatmeAccent),
);

final SwitchThemeData chatmeSwitchTheme = SwitchThemeData(
  trackColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? ChatmeColors.accentStrong
        : null,
  ),
  thumbColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? ChatmeColors.accentPrimary
        : null,
  ),
);

/// Shared shapes and colors for the custom buttons in the app.
class ChatmeButtonStyles {
  ChatmeButtonStyles._();

  static const double radius = 12;
  static const double chipRadius = 8;
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 14);

  static const Color primaryBackground = ChatmeColors.buttonPrimary;
  static const Color primaryForeground = ChatmeColors.buttonOnPrimary;
  static const Color dangerBackground = ChatmeColors.buttonDanger;
  static const Color dangerForeground = ChatmeColors.buttonOnDanger;
  static const Color neutralBackground = ChatmeColors.buttonNeutral;
  static const Color neutralForeground = ChatmeColors.buttonOnNeutral;
  static const Color neutralBorder = ChatmeColors.borderSubtle;

  static BoxDecoration primaryDecoration() => BoxDecoration(
        color: primaryBackground,
        borderRadius: BorderRadius.circular(radius),
      );

  static BoxDecoration dangerDecoration() => BoxDecoration(
        color: dangerBackground,
        borderRadius: BorderRadius.circular(radius),
      );

  static BoxDecoration neutralDecoration() => BoxDecoration(
        color: neutralBackground,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: neutralBorder, width: 0.5),
      );

  static BoxDecoration chipDecoration() => BoxDecoration(
        color: neutralBackground,
        borderRadius: BorderRadius.circular(chipRadius),
        border: Border.all(color: neutralBorder, width: 0.5),
      );
}
