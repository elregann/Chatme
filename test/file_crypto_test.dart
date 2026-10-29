// file_crypto_test.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:chatme/core/crypto/file_crypto.dart';

void main() {
  // Reference values produced with OpenSSL (AES-256-GCM, 16 byte nonce).
  final key = HEX.encode(List<int>.generate(32, (i) => i));
  final nonce = HEX.encode(List<int>.generate(16, (i) => 0xa0 + i));
  final plain = Uint8List.fromList(utf8.encode('Chatme voice note test'));
  const expectedCipher =
      '69cb42c875a8ed00acf77cd4cd7ae2e4e765371c0d400fa935e543f59d17e580fd2db42654a4';
  const expectedHash =
      'b412dc916e62fcfaad073c7ed5bf3350d30e04468cb8ae38e1b25a9df51f3d5c';
  const expectedOriginalHash =
      '8cb9b985e053707d7226f9ee436358f25b7710c448d21c3ec33e89c37aad733e';

  Uint8List fixedCipher() => Uint8List.fromList(HEX.decode(expectedCipher));

  test('decrypts the OpenSSL reference ciphertext', () {
    final out = FileCrypto.decrypt(
      fixedCipher(),
      key: key,
      nonce: nonce,
      hash: expectedHash,
      originalHash: expectedOriginalHash,
    );
    expect(utf8.decode(out), 'Chatme voice note test');
  });

  test('hashes match the reference values', () {
    expect(FileCrypto.sha256Hex(fixedCipher()), expectedHash);
    expect(FileCrypto.sha256Hex(plain), expectedOriginalHash);
  });

  test('encrypting with the reference key matches OpenSSL', () {
    final enc = FileCrypto.encryptWith(plain, key: key, nonce: nonce);
    expect(HEX.encode(enc.bytes), expectedCipher);
    expect(enc.hash, expectedHash);
    expect(enc.originalHash, expectedOriginalHash);
  });

  test('a larger file matches the OpenSSL reference', () {
    final big = Uint8List.fromList(List<int>.generate(1000, (i) => i % 256));
    final enc = FileCrypto.encryptWith(big, key: key, nonce: nonce);
    expect(enc.bytes.length, 1016);
    expect(
      enc.hash,
      'ae26dbb13fb214b4429ea6501f0b64f379f4605f723045362d30694336c94199',
    );
    expect(
      enc.originalHash,
      'a8af099bf2e878609558dbf69d8f88f4a31040a8cf84b549a0cfa912f12ffc3f',
    );
    expect(HEX.encode(enc.bytes.sublist(0, 16)), '2aa221bf1cc8cb71cb9715bae119839f');
    expect(HEX.encode(enc.bytes.sublist(1000)), 'f744e672dac70dacd7a8f14729b519fd');
  });

  test('empty file is only the tag', () {
    final out = FileCrypto.decrypt(
      Uint8List.fromList(HEX.decode('022f841c702b66b0bec8111f67de221d')),
      key: key,
      nonce: nonce,
    );
    expect(out, isEmpty);
  });

  test('encrypt then decrypt returns the original', () {
    final big = Uint8List.fromList(List<int>.generate(100000, (i) => (i * 7) % 256));
    final enc = FileCrypto.encrypt(big);
    final out = FileCrypto.decrypt(
      enc.bytes,
      key: enc.key,
      nonce: enc.nonce,
      hash: enc.hash,
      originalHash: enc.originalHash,
    );
    expect(out, big);
  });

  test('sizes are 32 byte key, 16 byte nonce and a 16 byte tag', () {
    final enc = FileCrypto.encrypt(plain);
    expect(enc.key.length, 64);
    expect(enc.nonce.length, 32);
    expect(enc.bytes.length, plain.length + 16);
    expect(enc.hash, FileCrypto.sha256Hex(enc.bytes));
    expect(enc.originalHash, FileCrypto.sha256Hex(plain));
  });

  test('every file gets a new key and nonce', () {
    final a = FileCrypto.encrypt(plain);
    final b = FileCrypto.encrypt(plain);
    expect(a.key, isNot(b.key));
    expect(a.nonce, isNot(b.nonce));
    expect(a.bytes, isNot(b.bytes));
  });

  test('a seeded random gives a repeatable result', () {
    final a = FileCrypto.encrypt(plain, random: Random(1));
    final b = FileCrypto.encrypt(plain, random: Random(1));
    expect(a.bytes, b.bytes);
    expect(a.key, b.key);
  });

  test('a flipped byte is rejected', () {
    final enc = FileCrypto.encrypt(plain);
    final bad = Uint8List.fromList(enc.bytes)..[3] ^= 1;
    expect(
      () => FileCrypto.decrypt(bad, key: enc.key, nonce: enc.nonce),
      throwsA(isA<FileCryptoException>()),
    );
  });

  test('a flipped tag byte is rejected', () {
    final enc = FileCrypto.encrypt(plain);
    final bad = Uint8List.fromList(enc.bytes)..[enc.bytes.length - 1] ^= 1;
    expect(
      () => FileCrypto.decrypt(bad, key: enc.key, nonce: enc.nonce),
      throwsA(isA<FileCryptoException>()),
    );
  });

  test('the wrong key is rejected', () {
    final enc = FileCrypto.encrypt(plain);
    final other = FileCrypto.encrypt(plain);
    expect(
      () => FileCrypto.decrypt(enc.bytes, key: other.key, nonce: enc.nonce),
      throwsA(isA<FileCryptoException>()),
    );
  });

  test('a wrong hash is rejected before decrypting', () {
    final enc = FileCrypto.encrypt(plain);
    expect(
          () => FileCrypto.decrypt(enc.bytes, key: enc.key, nonce: enc.nonce, hash: expectedHash),
      throwsA(isA<FileCryptoException>()),
    );
    expect(
          () => FileCrypto.decrypt(enc.bytes, key: enc.key, nonce: enc.nonce, originalHash: expectedHash),
      throwsA(isA<FileCryptoException>()),
    );
  });

  test('uppercase hashes are accepted', () {
    final out = FileCrypto.decrypt(
      fixedCipher(),
      key: key,
      nonce: nonce,
      hash: expectedHash.toUpperCase(),
      originalHash: expectedOriginalHash.toUpperCase(),
    );
    expect(out, plain);
  });

  test('bad key, nonce and short input are rejected', () {
    final enc = FileCrypto.encrypt(plain);
    expect(
      () => FileCrypto.decrypt(enc.bytes, key: 'zz', nonce: enc.nonce),
      throwsA(isA<FileCryptoException>()),
    );
    expect(
      () => FileCrypto.decrypt(enc.bytes, key: enc.key.substring(2), nonce: enc.nonce),
      throwsA(isA<FileCryptoException>()),
    );
    expect(
      () => FileCrypto.decrypt(enc.bytes, key: enc.key, nonce: enc.nonce.substring(2)),
      throwsA(isA<FileCryptoException>()),
    );
    expect(
      () => FileCrypto.decrypt(Uint8List(5), key: enc.key, nonce: enc.nonce),
      throwsA(isA<FileCryptoException>()),
    );
  });
}
