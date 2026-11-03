import 'package:flutter/material.dart';

/// The blue of the send button, used for every text button and popup action.
const Color chatmeAccent = Color(0xFF2196F3);

final TextButtonThemeData chatmeTextButtonTheme = TextButtonThemeData(
  style: TextButton.styleFrom(foregroundColor: chatmeAccent),
);

final SwitchThemeData chatmeSwitchTheme = SwitchThemeData(
  trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? chatmeAccent : null,
  ),
);