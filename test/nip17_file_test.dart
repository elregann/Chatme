// nip17_file_test.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/core/crypto/nip17_file.dart';

void main() {
  final key = 'a' * 64;
  final nonce = 'b' * 32;
  final hash = 'c' * 64;
  final originalHash = 'd' * 64;
  const url = 'https://blossom.example/abc';

  List<List<String>> baseTags() => [
        ['file-type', 'audio/mp4'],
        ['encryption-algorithm', 'aes-gcm'],
        ['decryption-key', key],
        ['decryption-nonce', nonce],
        ['x', hash],
        ['ox', originalHash],
      ];

  group('FileMessage tags', () {
    test('toTags lists the NIP-17 tags in order', () {
      final message = FileMessage(
        url: url,
        mimeType: 'audio/mp4',
        key: key,
        nonce: nonce,
        hash: hash,
        originalHash: originalHash,
        size: 4096,
        durationSeconds: 12,
      );
      expect(message.toTags(), [
        ...baseTags(),
        ['size', '4096'],
        ['duration', '12'],
      ]);
    });

    test('optional tags are left out when missing', () {
      final message = FileMessage(
        url: url,
        mimeType: 'audio/mp4',
        key: key,
        nonce: nonce,
        hash: hash,
      );
      expect(message.toTags().map((t) => t[0]), [
        'file-type',
        'encryption-algorithm',
        'decryption-key',
        'decryption-nonce',
        'x',
      ]);
    });

    test('parse reads what toTags wrote', () {
      final message = FileMessage(
        url: url,
        mimeType: 'audio/mp4',
        key: key,
        nonce: nonce,
        hash: hash,
        originalHash: originalHash,
        size: 4096,
        durationSeconds: 12,
      );
      final parsed = FileMessage.parse(content: url, tags: message.toTags())!;
      expect(parsed.url, url);
      expect(parsed.mimeType, 'audio/mp4');
      expect(parsed.key, key);
      expect(parsed.nonce, nonce);
      expect(parsed.hash, hash);
      expect(parsed.originalHash, originalHash);
      expect(parsed.size, 4096);
      expect(parsed.durationSeconds, 12);
      expect(parsed.isAudio, isTrue);
    });
  });

  group('FileMessage.parse', () {
    FileMessage? parse(List tags, {String content = url}) =>
        FileMessage.parse(content: content, tags: tags);

    test('ignores other tags, bad entries and repeats', () {
      final tags = [
        ['p', 'someone'],
        'text',
        ['e'],
        [1, 2],
        ...baseTags(),
        ['file-type', 'image/png'],
      ];
      final parsed = parse(tags)!;
      expect(parsed.mimeType, 'audio/mp4');
    });

    test('ox is optional', () {
      final tags = baseTags()..removeWhere((t) => t[0] == 'ox');
      expect(parse(tags)!.originalHash, isNull);
    });

    test('accepts uppercase hex and a 12 byte nonce', () {
      final tags = baseTags()
        ..removeWhere((t) => t[0] == 'decryption-nonce' || t[0] == 'x')
        ..add(['decryption-nonce', 'B' * 24])
        ..add(['x', 'C' * 64]);
      final parsed = parse(tags)!;
      expect(parsed.nonce, 'b' * 24);
      expect(parsed.hash, hash);
    });

    test('returns null when a required tag is missing', () {
      for (final name in ['file-type', 'encryption-algorithm', 'decryption-key', 'decryption-nonce', 'x']) {
        final tags = baseTags()..removeWhere((t) => t[0] == name);
        expect(parse(tags), isNull, reason: name);
      }
    });

    test('returns null for another algorithm', () {
      final tags = baseTags()..removeWhere((t) => t[0] == 'encryption-algorithm')
        ..add(['encryption-algorithm', 'chacha20']);
      expect(parse(tags), isNull);
    });

    test('returns null for badly formed key, nonce and hashes', () {
      for (final entry in {
        'decryption-key': 'a' * 63,
        'decryption-nonce': 'b' * 20,
        'x': 'zz' * 32,
        'ox': 'd' * 10,
      }.entries) {
        final tags = baseTags()..removeWhere((t) => t[0] == entry.key)
          ..add([entry.key, entry.value]);
        expect(parse(tags), isNull, reason: entry.key);
      }
    });

    test('returns null unless the address is https', () {
      for (final bad in ['http://blossom.example/abc', 'file:///x', 'blossom.example/abc', '']) {
        expect(parse(baseTags(), content: bad), isNull, reason: bad);
      }
    });

    test('a bad size or duration is dropped, not fatal', () {
      final tags = [
        ...baseTags(),
        ['size', 'big'],
        ['duration', '-3'],
      ];
      final parsed = parse(tags)!;
      expect(parsed.size, isNull);
      expect(parsed.durationSeconds, isNull);
    });
  });

  group('12 byte nonce from other clients', () {
    test('decrypts the OpenSSL reference', () {
      final out = FileCrypto.decrypt(
        Uint8List.fromList(HEX.decode(
          'da3d3bdf81a89b292891f4c7ed33e7b6e11c3db7665a6170fabee2e7a2fbc958cab34618a455',
        )),
        key: HEX.encode(List<int>.generate(32, (i) => i)),
        nonce: 'b0b1b2b3b4b5b6b7b8b9babb',
      );
      expect(utf8.decode(out), 'Chatme voice note test');
    });
  });
}
