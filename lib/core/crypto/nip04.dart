// nip04.dart

import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'ecdh_engine.dart';
import 'crypto_utils.dart';

class Nip04 {
  /// Enkripsi plaintext sesuai standar NIP-04.
  ///
  /// [plaintext]  : pesan asli yang akan dienkripsi
  /// [myPriv]     : private key pengirim (hex, 32 byte)
  /// [peerPub]    : public key penerima (hex, 32 byte x-only atau 33 byte compressed)
  ///
  /// Returns string dengan format: "<ciphertext_base64>?iv=<iv_base64>"
  static String encrypt(String plaintext, String myPriv, String peerPub) {
    try {
      if (plaintext.isEmpty) throw Exception('Plaintext kosong');

      // 1. Hitung shared secret: koordinat x mentah (tanpa hash)
      final sharedX = ECDH.computeSharedSecretRaw(myPriv, peerPub);

      // 2. Generate IV random 16 byte (CBC membutuhkan block size 16)
      final ivBytes = CryptoUtils.generateSecureRandomBytes(16);

      // 3. Enkripsi dengan AES-256-CBC
      final key = encrypt_lib.Key(sharedX);
      final iv = encrypt_lib.IV(ivBytes);
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );

      final encrypted = encrypter.encrypt(plaintext, iv: iv);

      // 4. Format output NIP-04: "ciphertext?iv=ivBase64"
      final ivBase64 = base64.encode(ivBytes);
      return '${encrypted.base64}?iv=$ivBase64';
    } catch (e) {
      throw Exception('NIP-04 enkripsi gagal: $e');
    }
  }

  /// Dekripsi payload NIP-04.
  ///
  /// [payload]  : string format "<ciphertext_base64>?iv=<iv_base64>"
  /// [myPriv]   : private key penerima (hex)
  /// [peerPub]  : public key pengirim (hex)
  ///
  /// Returns plaintext asli.
  static String decrypt(String payload, String myPriv, String peerPub) {
    try {
      if (payload.isEmpty) throw Exception('Payload kosong');

      // 1. Parse format "ciphertext?iv=..."
      final parts = payload.split('?iv=');
      if (parts.length != 2) {
        throw Exception('Format NIP-04 tidak valid, harus "ciphertext?iv=..."');
      }

      final ciphertextBase64 = parts[0];
      final ivBase64 = parts[1];

      // 2. Hitung shared secret yang sama
      final sharedX = ECDH.computeSharedSecretRaw(myPriv, peerPub);

      // 3. Dekripsi AES-256-CBC
      final key = encrypt_lib.Key(sharedX);
      final iv = encrypt_lib.IV.fromBase64(ivBase64);
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );

      return encrypter.decrypt64(ciphertextBase64, iv: iv);
    } catch (e) {
      throw Exception('NIP-04 dekripsi gagal: $e');
    }
  }

  /// Cek apakah sebuah string adalah format NIP-04 yang valid.
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