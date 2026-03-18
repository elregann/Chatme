// encryption.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'ecdh_engine.dart';
import 'crypto_utils.dart';

class EncryptionManager {
  static String encrypt(String plaintext, String myPriv, String myPub, String peerPub) {
    try {
      if (plaintext.isEmpty) return '';
      final sharedSecret = ECDH.computeSharedSecret(myPriv, peerPub);
      final randomSalt = CryptoUtils.generateSecureRandomBytes(16);
      final staticSalt = CryptoUtils.deriveStaticSalt(myPub, peerPub);
      final keyBytes = CryptoUtils.hkdfSha256(sharedSecret, Uint8List.fromList([...staticSalt, ...randomSalt]), utf8.encode('chatme-v2-aes-gcm'), 32);

      final key = encrypt_lib.Key(keyBytes);
      final ivBytes = CryptoUtils.generateSecureRandomBytes(12);
      final iv = encrypt_lib.IV(ivBytes);
      final payload = jsonEncode({'v': 2, 'msg': plaintext});
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm));

      final encrypted = encrypter.encrypt(payload, iv: iv, associatedData: staticSalt);
      return '${encrypted.base64}?iv=${base64.encode(ivBytes)}?salt=${base64.encode(randomSalt)}';
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  static String decrypt(String encrypted, String myPriv, String myPub, String peerPub) {
    try {
      if (encrypted.isEmpty) return '[Empty message]';
      final parts = encrypted.split('?');
      if (parts.length < 2) return '[⚠️ Format invalid]';

      final ciphertext = parts[0];
      final ivBase64 = parts[1].replaceFirst('iv=', '');
      final saltBase64 = parts.length == 3 ? parts[2].replaceFirst('salt=', '') : '';

      final sharedSecret = ECDH.computeSharedSecret(myPriv, peerPub);
      final staticSalt = CryptoUtils.deriveStaticSalt(myPub, peerPub);

      Uint8List combinedSalt = saltBase64.isNotEmpty
          ? Uint8List.fromList([...staticSalt, ...base64.decode(saltBase64)])
          : staticSalt;

      final keyBytes = CryptoUtils.hkdfSha256(sharedSecret, combinedSalt, utf8.encode(saltBase64.isNotEmpty ? 'chatme-v2-aes-gcm' : 'aes-gcm-chat-v1'), 32);
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(encrypt_lib.Key(keyBytes), mode: encrypt_lib.AESMode.gcm));

      final decrypted = encrypter.decrypt64(ciphertext, iv: encrypt_lib.IV.fromBase64(ivBase64), associatedData: staticSalt);
      final decoded = jsonDecode(decrypted);
      return decoded['msg'];
    } catch (e) {
      return '[⚠️ Message corrupted/not allowed]';
    }
  }
}