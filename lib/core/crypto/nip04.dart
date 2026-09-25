// nip04.dart

import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'ecdh_engine.dart';
import 'crypto_utils.dart';

class Nip04 {
  /// Encrypt plaintext per NIP-04 spec.
  ///
  /// [plaintext] : message to encrypt
  /// [myPriv]    : sender private key (hex, 32 bytes)
  /// [peerPub]   : recipient public key (hex, 32-byte x-only or 33-byte compressed)
  ///
  /// Returns "<ciphertext_base64>?iv=<iv_base64>".
  static String encrypt(String plaintext, String myPriv, String peerPub) {
    try {
      if (plaintext.isEmpty) throw Exception('Empty plaintext');

      // 1. Compute shared secret: raw x coordinate (no hash)
      final sharedX = ECDH.computeSharedSecretRaw(myPriv, peerPub);

      // 2. Generate random 16-byte IV (CBC block size)
      final ivBytes = CryptoUtils.generateSecureRandomBytes(16);

      // 3. Encrypt with AES-256-CBC
      final key = encrypt_lib.Key(sharedX);
      final iv = encrypt_lib.IV(ivBytes);
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );

      final encrypted = encrypter.encrypt(plaintext, iv: iv);

      // 4. Format NIP-04 output: "ciphertext?iv=ivBase64"
      final ivBase64 = base64.encode(ivBytes);
      return '${encrypted.base64}?iv=$ivBase64';
    } catch (e) {
      throw Exception('NIP-04 encrypt failed: $e');
    }
  }

  /// Decrypt NIP-04 payload.
  ///
  /// [payload] : string in "<ciphertext_base64>?iv=<iv_base64>" format
  /// [myPriv]  : recipient private key (hex)
  /// [peerPub] : sender public key (hex)
  ///
  /// Returns the original plaintext.
  static String decrypt(String payload, String myPriv, String peerPub) {
    try {
      if (payload.isEmpty) throw Exception('Empty payload');

      // 1. Parse "ciphertext?iv=..." format
      final parts = payload.split('?iv=');
      if (parts.length != 2) {
        throw Exception('Invalid NIP-04 format, expected "ciphertext?iv=..."');
      }

      final ciphertextBase64 = parts[0];
      final ivBase64 = parts[1];

      // 2. Compute the same shared secret
      final sharedX = ECDH.computeSharedSecretRaw(myPriv, peerPub);

      // 3. Decrypt with AES-256-CBC
      final key = encrypt_lib.Key(sharedX);
      final iv = encrypt_lib.IV.fromBase64(ivBase64);
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );

      return encrypter.decrypt64(ciphertextBase64, iv: iv);
    } catch (e) {
      throw Exception('NIP-04 decrypt failed: $e');
    }
  }

  /// Check if a string is a valid NIP-04 payload format.
  static bool isValidPayload(String payload) {
    final parts = payload.split('?iv=');
    if (parts.length != 2) return false;
    try {
      base64.decode(parts[0]);
      base64.decode(parts[1]);
      return true;
    } catch (_) {
      return false;
    }
  }
}