import 'package:chatme/core/theme/chatme_buttons.dart';
import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('switch track is accent when on and default when off', () {
    final track = chatmeSwitchTheme.trackColor!;
    expect(track.resolve({WidgetState.selected}), ChatmeColors.accentStrong);
    expect(track.resolve({}), isNull);
  });
}