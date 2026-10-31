// keyboard_height_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/keyboard_height.dart';

void main() {
  group('fallback', () {
    test('is a share of the screen height', () {
      expect(KeyboardHeight.fallback(800), closeTo(336, 0.01));
    });

    test('stays between the smallest and the largest sensible keyboard', () {
      expect(KeyboardHeight.fallback(400), 260);
      expect(KeyboardHeight.fallback(2000), 380);
    });
  });

  group('valid', () {
    test('accepts a real keyboard height', () {
      expect(KeyboardHeight.valid(300), 300);
      expect(KeyboardHeight.valid(301.5), 301.5);
    });

    test('rejects a closed keyboard, junk and absurd values', () {
      expect(KeyboardHeight.valid(0), isNull);
      expect(KeyboardHeight.valid(120), isNull);
      expect(KeyboardHeight.valid(5000), isNull);
      expect(KeyboardHeight.valid(double.nan), isNull);
      expect(KeyboardHeight.valid(double.infinity), isNull);
      expect(KeyboardHeight.valid('300'), isNull);
      expect(KeyboardHeight.valid(null), isNull);
    });
  });

  group('forOpening', () {
    test('the keyboard on screen wins', () {
      expect(
        KeyboardHeight.forOpening(keyboardNow: 310, stored: 290, screenHeight: 800),
        310,
      );
    });

    test('without a keyboard the remembered height is used', () {
      expect(
        KeyboardHeight.forOpening(keyboardNow: 0, stored: 290, screenHeight: 800),
        290,
      );
    });

    test('with nothing known it falls back to the screen share', () {
      expect(
        KeyboardHeight.forOpening(keyboardNow: 0, stored: null, screenHeight: 800),
        KeyboardHeight.fallback(800),
      );
    });

    test('a damaged remembered value is ignored', () {
      expect(
        KeyboardHeight.forOpening(keyboardNow: 0, stored: 'abc', screenHeight: 800),
        KeyboardHeight.fallback(800),
      );
    });
  });

  group('shouldSave', () {
    test('saves the first real height', () {
      expect(KeyboardHeight.shouldSave(null, 300), isTrue);
    });

    test('saves a different height but not the same one', () {
      expect(KeyboardHeight.shouldSave(300, 320), isTrue);
      expect(KeyboardHeight.shouldSave(300, 300.4), isFalse);
    });

    test('never saves something that is not a keyboard', () {
      expect(KeyboardHeight.shouldSave(300, 0), isFalse);
      expect(KeyboardHeight.shouldSave(null, 80), isFalse);
    });
  });

  test('portrait and landscape are remembered apart', () {
    expect(
      KeyboardHeight.key(landscape: true),
      isNot(KeyboardHeight.key(landscape: false)),
    );
  });

  group('revealAfterSettle', () {
    test('a keyboard as tall as the panel needs no animation', () {
      expect(KeyboardHeight.revealAfterSettle(keyboard: 300, panel: 300), 1.0);
      expect(KeyboardHeight.revealAfterSettle(keyboard: 299.8, panel: 300), 1.0);
    });

    test('a taller keyboard needs no animation either', () {
      expect(KeyboardHeight.revealAfterSettle(keyboard: 340, panel: 300), 1.0);
    });

    test('a shorter keyboard shrinks the panel to its height', () {
      expect(KeyboardHeight.revealAfterSettle(keyboard: 270, panel: 300), closeTo(0.9, 0.0001));
    });

    test('no keyboard collapses the panel', () {
      expect(KeyboardHeight.revealAfterSettle(keyboard: 0, panel: 300), 0.0);
    });

    test('an empty panel never divides by zero', () {
      expect(KeyboardHeight.revealAfterSettle(keyboard: 300, panel: 0), 0.0);
    });
  });
}
