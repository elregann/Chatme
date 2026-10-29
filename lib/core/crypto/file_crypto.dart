// file_crypto.dart

import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' show sha256;
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart'
    show AEADParameters, AESEngine, GCMBlockCipher, InvalidCipherTextException, KeyParameter;

class FileCryptoException implements Exception {
  final String message;
  const FileCryptoException(this.message);

  @override
  String toString() => 'FileCryptoException: $message';
}

class EncryptedFile {
  /// Ciphertext followed by the 16 byte GCM tag. This is what gets uploaded.
  final Uint8List bytes;

  /// NIP-17 decryption-key, 32 bytes as hex.
  final String key;

  /// NIP-17 decryption-nonce, 16 bytes as hex. Files from other clients may
  /// carry a 12 byte nonce, which decrypt() also accepts.
  final String nonce;

  /// NIP-94 x: sha256 of [bytes].
  final String hash;

  /// NIP-94 ox: sha256 of the original file.
  final String originalHash;

  const EncryptedFile({
    required this.bytes,
    required this.key,
    required this.nonce,
    required this.hash,
    required this.originalHash,
  });
}

/// File encryption for NIP-17 kind 15 messages: AES-256-GCM with a 16 byte
/// nonce, tag appended to the ciphertext. Same layout as Amethyst.
class FileCrypto {
  FileCrypto._();

  static const int keyLength = 32;
  static const int nonceLength = 16;
  static const int _tagBits = 128;

  static String sha256Hex(Uint8List data) => sha256.convert(data).toString();

  static Uint8List _randomBytes(int length, Random random) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _process(
    bool encrypt,
    Uint8List input,
    Uint8List key,
    Uint8List nonce,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    final out = Uint8List(cipher.getOutputSize(input.length));
    final written = cipher.processBytes(input, 0, input.length, out, 0);
    final total = written + cipher.doFinal(out, written);
    return Uint8List.sublistView(out, 0, total);
  }

  static Uint8List _decodeHex(String value, int length, String name) {
    final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(HEX.decode(value));
    } on FormatException {
      throw FileCryptoException('$name is not valid hex');
    }
    if (bytes.length != length) {
      throw FileCryptoException('$name must be $length bytes');
    }
    return bytes;
  }

  static Uint8List _decodeNonce(String value) {
    final length = value.length ~/ 2 == 12 ? 12 : nonceLength;
    return _decodeHex(value, length, 'nonce');
  }

  static EncryptedFile encrypt(Uint8List plain, {Random? random}) {
    final rng = random ?? Random.secure();
    return encryptWith(
      plain,
      key: HEX.encode(_randomBytes(keyLength, rng)),
      nonce: HEX.encode(_randomBytes(nonceLength, rng)),
    );
  }

  /// Encrypts with a known [key] and [nonce]. Never reuse a pair for two
  /// different files, use [encrypt] for that.
  static EncryptedFile encryptWith(
    Uint8List plain, {
    required String key,
    required String nonce,
  }) {
    final keyBytes = _decodeHex(key, keyLength, 'key');
    final nonceBytes = _decodeHex(nonce, nonceLength, 'nonce');
    final bytes = _process(true, plain, keyBytes, nonceBytes);

    return EncryptedFile(
      bytes: bytes,
      key: key.toLowerCase(),
      nonce: nonce.toLowerCase(),
      hash: sha256Hex(bytes),
      originalHash: sha256Hex(plain),
    );
  }

  /// Decrypts [bytes]. When [hash] or [originalHash] is given, it is checked
  /// before returning, so a tampered or swapped file is rejected.
  static Uint8List decrypt(
    Uint8List bytes, {
    required String key,
    required String nonce,
    String? hash,
    String? originalHash,
  }) {
    final keyBytes = _decodeHex(key, keyLength, 'key');
    final nonceBytes = _decodeNonce(nonce);

    if (hash != null && sha256Hex(bytes) != hash.toLowerCase()) {
      throw const FileCryptoException('encrypted file hash does not match');
    }
    if (bytes.length < _tagBits ~/ 8) {
      throw const FileCryptoException('encrypted file is too short');
    }

    final Uint8List plain;
    try {
      plain = _process(false, bytes, keyBytes, nonceBytes);
    } on InvalidCipherTextException {
      throw const FileCryptoException('authentication failed');
    }

    if (originalHash != null && sha256Hex(plain) != originalHash.toLowerCase()) {
      throw const FileCryptoException('original file hash does not match');
    }
    return plain;
  }
}
