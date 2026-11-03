import 'package:chatme/core/theme/cyber_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('the accent is the Amethyst purple', () {
    expect(CyberColors.accent, const Color(0xFFBB86FC));
  });

  test('text on the accent is easy to read', () {
    expect(contrast(CyberColors.onAccent, CyberColors.accent), greaterThanOrEqualTo(4.5));
    expect(contrast(CyberColors.replyNameOnAccent, CyberColors.accent), greaterThanOrEqualTo(4.5));
  });

  test('the read tick stays visible on the accent', () {
    expect(contrast(CyberColors.readTickOnAccent, CyberColors.accent), greaterThanOrEqualTo(3.0));
  });

  test('the accent is easy to read on the dark theme surfaces', () {
    for (final surface in const [Color(0xFF130F1A), Color(0xFF1B1425), Color(0xFF251C33)]) {
      expect(contrast(CyberColors.accent, surface), greaterThanOrEqualTo(4.5), reason: '$surface');
    }
  });
}
