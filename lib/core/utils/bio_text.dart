// bio_text.dart

/// Rules for the plain-text bio that lives in the kind 0 `about` field.
///
/// Bios are user-authored text, but a bio received from a relay is untrusted
/// input from another client. Both paths go through [sanitize] so the UI only
/// ever renders clean, length-limited plain text: no markdown, no HTML, no
/// control characters.
class BioText {
  BioText._();

  /// Longest bio a person can write in Chatme, including line breaks.
  static const int maxUserLength = 500;

  /// Safety cap for a bio read from a relay. Other clients are free to
  /// publish longer text, but the app never renders an unbounded string.
  static const int maxRemoteLength = 2000;

  /// Normalizes and limits [raw].
  ///
  /// Line endings become `\n`, tabs become spaces, control characters are
  /// dropped, runs of blank lines collapse to one empty line, surrounding
  /// whitespace is trimmed and the result is cut at [maxLength] runes without
  /// splitting a character.
  static String sanitize(String? raw, {int maxLength = maxRemoteLength}) {
    if (raw == null || raw.isEmpty || maxLength <= 0) return '';

    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final buffer = StringBuffer();
    for (final rune in normalized.runes) {
      if (rune == 0x0A) {
        buffer.writeCharCode(rune);
      } else if (rune == 0x09) {
        buffer.writeCharCode(0x20);
      } else if (rune < 0x20 || rune == 0x7F) {
        continue;
      } else if (rune >= 0x80 && rune <= 0x9F) {
        continue;
      } else {
        buffer.writeCharCode(rune);
      }
    }

    var text = buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (text.runes.length > maxLength) {
      final cut = StringBuffer();
      var count = 0;
      for (final rune in text.runes) {
        if (count >= maxLength) break;
        cut.writeCharCode(rune);
        count++;
      }
      text = cut.toString().trimRight();
    }

    return text;
  }

  /// True when [raw] has no visible content after sanitizing.
  static bool isBlank(String? raw) => sanitize(raw).isEmpty;
}
