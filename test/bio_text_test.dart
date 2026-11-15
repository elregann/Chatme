// bio_text_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/utils/bio_text.dart';

void main() {
  group('BioText.sanitize', () {
    test('null and whitespace-only values become empty', () {
      expect(BioText.sanitize(null), '');
      expect(BioText.sanitize('   \n\t  '), '');
    });

    test('trims surrounding whitespace', () {
      expect(BioText.sanitize('  hello there \n'), 'hello there');
    });

    test('normalizes CRLF and bare CR to LF', () {
      expect(BioText.sanitize('one\r\ntwo\rthree'), 'one\ntwo\nthree');
    });

    test('removes control characters but keeps newlines', () {
      expect(
        BioText.sanitize('hello\u0000\u0007\nworld\u007f'),
        'hello\nworld',
      );
    });

    test('collapses long runs of blank lines to one empty line', () {
      expect(BioText.sanitize('one\n\n\n\n\ntwo'), 'one\n\ntwo');
    });

    test('keeps text below the remote cap untouched', () {
      const text = 'short bio';
      expect(BioText.sanitize(text), text);
    });

    test('truncates remote text at the remote cap without splitting a rune',
        () {
      final text = '😀' * (BioText.maxRemoteLength + 10);

      final result = BioText.sanitize(text);

      expect(result.runes.length, BioText.maxRemoteLength);
      expect(result.endsWith('😀'), isTrue);
    });

    test('honors a custom cap', () {
      final text = 'a' * (BioText.maxUserLength + 25);

      final result = BioText.sanitize(text, maxLength: BioText.maxUserLength);

      expect(result.length, BioText.maxUserLength);
    });

    test('truncation does not leave trailing whitespace', () {
      final text = '${'a' * BioText.maxUserLength}   tail';

      final result = BioText.sanitize(text, maxLength: BioText.maxUserLength);

      expect(result.endsWith(' '), isFalse);
      expect(result, 'a' * BioText.maxUserLength);
    });
  });

  group('BioText.isBlank', () {
    test('treats null, empty and whitespace as blank', () {
      expect(BioText.isBlank(null), isTrue);
      expect(BioText.isBlank(''), isTrue);
      expect(BioText.isBlank('  \n '), isTrue);
    });

    test('treats real text as not blank', () {
      expect(BioText.isBlank('hello'), isFalse);
    });
  });
}
