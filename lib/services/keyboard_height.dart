// keyboard_height.dart

/// Rules for how tall the emoji panel is, so it takes the exact place of the
/// keyboard. The platform cannot report a keyboard that is not on screen, so
/// the last real height is remembered and a share of the screen is the guess
/// before any keyboard has been seen.
class KeyboardHeight {
  KeyboardHeight._();

  static const double minimum = 150;
  static const double maximum = 600;

  static double fallback(double screenHeight) {
    return (screenHeight * 0.42).clamp(260.0, 380.0).toDouble();
  }

  /// [value] when it can be a keyboard height, otherwise null.
  static double? valid(Object? value) {
    if (value is! num) return null;
    final height = value.toDouble();
    if (!height.isFinite || height < minimum || height > maximum) return null;
    return height;
  }

  static double forOpening({
    required double keyboardNow,
    required Object? stored,
    required double screenHeight,
  }) {
    return valid(keyboardNow) ?? valid(stored) ?? fallback(screenHeight);
  }

  static bool shouldSave(Object? stored, double now) {
    if (valid(now) == null) return false;
    final before = valid(stored);
    return before == null || (before - now).abs() > 1;
  }

  static String key({required bool landscape}) {
    return landscape ? 'keyboard_height_landscape' : 'keyboard_height_portrait';
  }

  /// How much of the panel should stay once the keyboard stopped moving, as a
  /// share of the panel height. 1 means the keyboard already covers it, so the
  /// panel can go without anything shifting.
  static double revealAfterSettle({required double keyboard, required double panel}) {
    if (panel <= 0 || keyboard <= 0) return 0.0;
    if (keyboard >= panel - 0.5) return 1.0;
    return (keyboard / panel).clamp(0.0, 1.0).toDouble();
  }
}
