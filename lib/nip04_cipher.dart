import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'encryption_secp256k1.dart';

class Nip04Cipher {
  static String encrypt({
    required String plaintext,
    required String myPrivateKey,
    required String peerPublicKey,
  }) {

    final shared = SimpleECDH.computeSharedSecret(
      myPrivateKey,
      peerPublicKey,
    );

    final key = encrypt_lib.Key(shared);

    final ivBytes = _generateIV();
    final iv = encrypt_lib.IV(ivBytes);

    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
    );

    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    return "${encrypted.base64}?iv=${base64.encode(ivBytes)}";
  }

  static String decrypt({
    required String payload,
    required String myPrivateKey,
    required String peerPublicKey,
  }) {

    final parts = payload.split("?iv=");

    if (parts.length != 2) {
      throw Exception("Invalid NIP04 format");
    }

    final ciphertext = parts[0];
    final iv = encrypt_lib.IV.fromBase64(parts[1]);

    final shared = SimpleECDH.computeSharedSecret(
      myPrivateKey,
      peerPublicKey,
    );

    final key = encrypt_lib.Key(shared);

    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
    );

    return encrypter.decrypt64(ciphertext, iv: iv);
  }

  static Uint8List _generateIV() {
    return encrypt_lib.IV.fromSecureRandom(16).bytes;
  }
}