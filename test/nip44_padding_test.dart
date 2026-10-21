// nip44_padding_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip44.dart';

void main() {
  const priv = '0000000000000000000000000000000000000000000000000000000000000001';
  const pub = '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';

  // [unpadded length, padded length] from the official NIP-44 vectors.
  const vectors = [
    [16, 32], [32, 32], [33, 64], [37, 64], [45, 64], [49, 64], [64, 64],
    [65, 96], [100, 128], [111, 128], [200, 224], [250, 256], [320, 320],
    [383, 384], [384, 384], [400, 448], [500, 512], [512, 512], [515, 640],
    [700, 768],
  ];

  test('NIP-44 padding length matches the spec', () async {
    final mismatches = <String>[];
    for (final v in vectors) {
      final payload = base64.decode(await Nip44.encrypt('a' * v[0], priv, pub));
      // payload = version(1) + nonce(32) + padded buffer + mac(32)
      final paddedBuffer = payload.length - 65;
      if (paddedBuffer != v[1] + 2) {
        mismatches.add('len ${v[0]}: actual=$paddedBuffer, expected=${v[1] + 2}');
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });
}