import 'package:chatme/core/utils/emoji_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('emojiOnlyCount', () {
    test('counts single and multiple emoji', () {
      expect(emojiOnlyCount('😀'), 1);
      expect(emojiOnlyCount('😀😀😀'), 3);
      expect(emojiOnlyCount('😀 😀'), 2);
      expect(emojiOnlyCount('😀\n😀'), 2);
    });

    test('counts emoji sequences as one character', () {
      expect(emojiOnlyCount('👨‍👩‍👧'), 1);
      expect(emojiOnlyCount('👍🏽'), 1);
      expect(emojiOnlyCount('🇮🇩'), 1);
      expect(emojiOnlyCount('1️⃣'), 1);
      expect(emojiOnlyCount('#️⃣'), 1);
      expect(emojiOnlyCount('❤️'), 1);
      expect(emojiOnlyCount('©️'), 1);
    });

    test('rejects messages with text or punctuation', () {
      expect(emojiOnlyCount('hello 😀'), isNull);
      expect(emojiOnlyCount('😀!'), isNull);
      expect(emojiOnlyCount('123'), isNull);
      expect(emojiOnlyCount('!'), isNull);
      expect(emojiOnlyCount(''), isNull);
      expect(emojiOnlyCount('   '), isNull);
    });

    test('isEmojiOnly mirrors emojiOnlyCount', () {
      expect(isEmojiOnly('😀'), isTrue);
      expect(isEmojiOnly('😀 hello'), isFalse);
    });
  });

  test('font size grows only for a few emoji', () {
    expect(emojiFontSizeForCount(1), emojiLargeFontSize);
    expect(emojiFontSizeForCount(3), emojiLargeFontSize);
    expect(emojiFontSizeForCount(4), emojiSmallFontSize);
    expect(emojiFontSizeForCount(20), emojiSmallFontSize);
  });
}
