// nip44_vectors_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip44.dart';

// Official vectors from https://github.com/paulmillr/nip44 (nip44.vectors.json).
Map<String, dynamic> _loadVectors() {
  final text = File('test/fixtures/nip44.vectors.json').readAsStringSync();
  return (jsonDecode(text) as Map<String, dynamic>)['v2'] as Map<String, dynamic>;
}

String _sha256(String text) => sha256.convert(utf8.encode(text)).toString();

Matcher _failsWith(String text) =>
    throwsA(predicate((e) => e.toString().contains(text)));

void main() {
  final vectors = _loadVectors();
  final valid = vectors['valid'] as Map<String, dynamic>;
  final invalid = vectors['invalid'] as Map<String, dynamic>;

  group('conversation key', () {
    test('matches every official vector', () {
      final list = valid['get_conversation_key'] as List;
      expect(list, isNotEmpty);
      for (final v in list) {
        expect(
          Nip44.conversationKeyHex(v['sec1'], v['pub2']),
          v['conversation_key'],
          reason: 'sec1 ${v['sec1']} pub2 ${v['pub2']}',
        );
      }
    });

    test('refuses every invalid key pair', () async {
      final list = invalid['get_conversation_key'] as List;
      expect(list, isNotEmpty);
      for (final v in list) {
        await expectLater(
          Nip44.encrypt('hello', v['sec1'], v['pub2']),
          throwsA(isA<Exception>()),
          reason: v['note'],
        );
      }
    });
  });

  group('message keys', () {
    test('match the official vectors', () {
      final section = valid['get_message_keys'] as Map<String, dynamic>;
      final conversationKey = section['conversation_key'] as String;
      for (final v in section['keys'] as List) {
        final keys = Nip44.messageKeysHex(conversationKey, v['nonce']);
        expect(keys['chacha_key'], v['chacha_key']);
        expect(keys['chacha_nonce'], v['chacha_nonce']);
        expect(keys['hmac_key'], v['hmac_key']);
      }
    });
  });

  group('padded length', () {
    test('matches every official pair', () {
      for (final pair in valid['calc_padded_len'] as List) {
        expect(
          Nip44.calcPaddedLength(pair[0] as int),
          pair[1],
          reason: 'length ${pair[0]}',
        );
      }
    });
  });

  group('official payloads', () {
    test('decrypt to the official plaintext, from either side', () async {
      final list = valid['encrypt_decrypt'] as List;
      expect(list, isNotEmpty);
      for (final v in list) {
        final pub1 = bip340.getPublicKey(v['sec1']);
        final pub2 = bip340.getPublicKey(v['sec2']);
        expect(await Nip44.decrypt(v['payload'], v['sec2'], pub1), v['plaintext']);
        expect(await Nip44.decrypt(v['payload'], v['sec1'], pub2), v['plaintext']);
      }
    });

    test('our own payloads have the official size', () async {
      for (final v in valid['encrypt_decrypt'] as List) {
        final pub2 = bip340.getPublicKey(v['sec2']);
        final ours = await Nip44.encrypt(v['plaintext'], v['sec1'], pub2);
        expect(base64.decode(ours).length, base64.decode(v['payload']).length);
        expect(await Nip44.decrypt(ours, v['sec2'], bip340.getPublicKey(v['sec1'])), v['plaintext']);
      }
    });

    test('long messages survive a round trip', () async {
      const sec1 = '0000000000000000000000000000000000000000000000000000000000000001';
      const sec2 = '0000000000000000000000000000000000000000000000000000000000000002';
      final pub2 = bip340.getPublicKey(sec2);
      final pub1 = bip340.getPublicKey(sec1);

      for (final v in valid['encrypt_decrypt_long_msg'] as List) {
        final text = (v['pattern'] as String) * (v['repeat'] as int);
        expect(_sha256(text), v['plaintext_sha256']);

        final payload = await Nip44.encrypt(text, sec1, pub2);
        final back = await Nip44.decrypt(payload, sec2, pub1);
        expect(_sha256(back), v['plaintext_sha256']);
      }
    });
  });

  group('message length limits', () {
    test('refuses the official invalid lengths', () async {
      const sec1 = '0000000000000000000000000000000000000000000000000000000000000001';
      final pub2 = bip340.getPublicKey(
        '0000000000000000000000000000000000000000000000000000000000000002',
      );
      for (final length in invalid['encrypt_msg_lengths'] as List) {
        await expectLater(
          Nip44.encrypt('a' * (length as int), sec1, pub2),
          throwsA(isA<Exception>()),
          reason: 'length $length',
        );
      }
    });
  });

  group('damaged payloads', () {
    const sec1 = '0000000000000000000000000000000000000000000000000000000000000001';
    const sec2 = '0000000000000000000000000000000000000000000000000000000000000002';
    final pub1 = bip340.getPublicKey(sec1);
    final pub2 = bip340.getPublicKey(sec2);

    Future<Uint8List> fresh() async =>
        base64.decode(await Nip44.encrypt('hello nip44', sec1, pub2));

    Future<String> open(Uint8List bytes) =>
        Nip44.decrypt(base64.encode(bytes), sec2, pub1);

    test('an untouched payload opens', () async {
      expect(await open(await fresh()), 'hello nip44');
    });

    test('a changed byte in the mac is refused', () async {
      final bytes = await fresh();
      bytes[bytes.length - 1] ^= 1;
      await expectLater(open(bytes), _failsWith('MAC'));
    });

    test('a changed byte in the ciphertext is refused', () async {
      final bytes = await fresh();
      bytes[40] ^= 1;
      await expectLater(open(bytes), _failsWith('MAC'));
    });

    test('a changed byte in the nonce is refused', () async {
      final bytes = await fresh();
      bytes[5] ^= 1;
      await expectLater(open(bytes), _failsWith('MAC'));
    });

    test('another version is refused', () async {
      for (final version in [0, 1, 3]) {
        final bytes = await fresh();
        bytes[0] = version;
        await expectLater(open(bytes), _failsWith('Unsupported'));
      }
    });

    test('a payload that is too short is refused', () async {
      final bytes = await fresh();
      await expectLater(open(Uint8List.sublistView(bytes, 0, bytes.length - 1)), _failsWith('too short'));
    });

    test('an empty payload is refused', () async {
      await expectLater(Nip44.decrypt('', sec2, pub1), _failsWith('empty'));
    });

    test('text that is not base64 is refused', () async {
      const notBase64 = '#Atqupco0WyaOW2IGDKcshwxI9xO8HgD/P8Ddt46CbxDbrhdG8VmJdU0MIDf06CUvEvdnr1cp1fiMtlM/GrE92xAc1K5odTpv3I';
      expect(Nip44.isValidPayload(notBase64), isFalse);
      await expectLater(Nip44.decrypt(notBase64, sec2, pub1), throwsA(isA<Exception>()));
    });

    test('the wrong key is refused', () async {
      final bytes = await fresh();
      final stranger = bip340.getPublicKey(
        '0000000000000000000000000000000000000000000000000000000000000003',
      );
      await expectLater(
        Nip44.decrypt(base64.encode(bytes), sec2, stranger),
        _failsWith('MAC'),
      );
    });
  });
}
