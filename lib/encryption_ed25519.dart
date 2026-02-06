import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:cryptography/cryptography.dart' as crypto_pkg;
import 'package:encrypt/encrypt.dart' as encrypt_lib;

// =======================
// ED25519 & X25519 ECDH
// =======================
class Curve25519ECDH {
  static Future<Uint8List> computeSharedSecret(String privateKeyHex, String publicKeyHex) async {
    try {
      if (!_isValidHex(privateKeyHex) || !_isValidHex(publicKeyHex)) {
        throw Exception('Invalid hex format');
      }

      final algorithm = crypto_pkg.X25519();
      final privBytes = HEX.decode(privateKeyHex);
      final pubBytes = HEX.decode(publicKeyHex);

      // Membuat KeyPair dari private key kita (seed)
      final keyPair = await algorithm.newKeyPairFromSeed(privBytes);

      final remotePublicKey = crypto_pkg.SimplePublicKey(
        pubBytes,
        type: crypto_pkg.KeyPairType.x25519,
      );

      // Kalkulasi shared secret
      final sharedSecret = await algorithm.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: remotePublicKey,
      );

      final secretBytes = await sharedSecret.extractBytes();

      final hashed = sha256.convert(secretBytes).bytes;

      return Uint8List.fromList(hashed);
    } catch (e) {
      throw Exception('ECDH Failed: $e');
    }
  }

  static bool _isValidHex(String hex) {
    return hex.isNotEmpty && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
  }
}

// =======================
// HKDF SHA-256
// =======================
Uint8List _hkdfSha256(Uint8List ikm, Uint8List salt, Uint8List info, int length) {
  final prk = Hmac(sha256, salt).convert(ikm).bytes;
  Uint8List t = Uint8List(0);
  final out = BytesBuilder();
  int counter = 1;

  while (out.length < length) {
    final hmac = Hmac(sha256, prk);
    t = Uint8List.fromList(hmac.convert([...t, ...info, counter]).bytes);
    out.add(t);
    counter++;
  }
  return out.takeBytes().sublist(0, length);
}

Uint8List _deriveStaticSalt(String pubA, String pubB) {
  final keys = [pubA, pubB]..sort();
  return Uint8List.fromList(sha256.convert(utf8.encode(keys.join(':'))).bytes);
}

Uint8List _generateSecureRandomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

// =======================
// ENCRYPTION MANAGER
// =======================
class EncryptionManager {
  static Future<String> encrypt(
      String plaintext,
      String myPrivateKey,
      String myPublicKey,
      String peerPublicKey,
      ) async {
    try {
      if (plaintext.isEmpty) return '';

      final sharedSecret = await Curve25519ECDH.computeSharedSecret(myPrivateKey, peerPublicKey);
      final randomSalt = _generateSecureRandomBytes(16);
      final staticSalt = _deriveStaticSalt(myPublicKey, peerPublicKey);
      final combinedSalt = Uint8List.fromList([...staticSalt, ...randomSalt]);

      final keyBytes = _hkdfSha256(
        sharedSecret,
        combinedSalt,
        utf8.encode('ed25519-aes-gcm-v2'),
        32,
      );

      final key = encrypt_lib.Key(keyBytes);
      final ivBytes = _generateSecureRandomBytes(12);
      final iv = encrypt_lib.IV(ivBytes);

      final payload = jsonEncode({'v': 2, 'msg': plaintext});

      final keys = [myPublicKey, peerPublicKey]..sort();
      final aadString = keys.join(':');
      final aadBytes = Uint8List.fromList(utf8.encode(aadString));

      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm));
      final encrypted = encrypter.encrypt(
          payload,
          iv: iv,
          associatedData: aadBytes
      );

      return '${encrypted.base64}?iv=${base64.encode(ivBytes)}?salt=${base64.encode(randomSalt)}';
    } catch (e) {
      return '[⚠️ Encryption Failed]';
    }
  }

  static Future<String> decrypt(
      String encrypted,
      String myPrivateKey,
      String myPublicKey,
      String peerPublicKey,
      ) async {
    try {
      if (encrypted.isEmpty) return '[Empty message]';

      final parts = encrypted.split('?');
      if (parts.length != 3) return '[⚠️ Invalid format]';

      final ciphertext = parts[0];
      final ivBase64 = parts[1].replaceFirst('iv=', '');
      final saltBase64 = parts[2].replaceFirst('salt=', '');

      final sharedSecret = await Curve25519ECDH.computeSharedSecret(myPrivateKey, peerPublicKey);
      final randomSalt = base64.decode(saltBase64);
      final staticSalt = _deriveStaticSalt(myPublicKey, peerPublicKey);
      final combinedSalt = Uint8List.fromList([...staticSalt, ...randomSalt]);

      final keyBytes = _hkdfSha256(
        sharedSecret,
        combinedSalt,
        utf8.encode('ed25519-aes-gcm-v2'),
        32,
      );

      final key = encrypt_lib.Key(keyBytes);
      final iv = encrypt_lib.IV.fromBase64(ivBase64);

      final keys = [myPublicKey, peerPublicKey]..sort();
      final aadString = keys.join(':');
      final aadBytes = Uint8List.fromList(utf8.encode(aadString));

      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm));
      final decrypted = encrypter.decrypt64(
          ciphertext,
          iv: iv,
          associatedData: aadBytes
      );

      final decoded = jsonDecode(decrypted);

      return decoded['msg'];
    } catch (e) {
      return '[⚠️ Decryption failed]';
    }
  }

  static Future<String> sign(String eventId, String privateKey) async {
    try {
      final algorithm = crypto_pkg.Ed25519();
      final privBytes = HEX.decode(privateKey);
      final keyPair = await algorithm.newKeyPairFromSeed(privBytes);

      final signature = await algorithm.sign(
        utf8.encode(eventId),
        keyPair: keyPair,
      );

      return HEX.encode(signature.bytes);
    } catch (e) {
      throw Exception('Signing failed: $e');
    }
  }

  static Future<bool> verify(String eventId, String signature, String pubkey) async {
    try {
      if (signature.isEmpty || pubkey.isEmpty) return false;

      final algorithm = crypto_pkg.Ed25519();
      final sigBytes = HEX.decode(signature);
      final pubBytes = HEX.decode(pubkey);

      final verified = await algorithm.verify(
        utf8.encode(eventId),
        signature: crypto_pkg.Signature(
            sigBytes,
            publicKey: crypto_pkg.SimplePublicKey(pubBytes, type: crypto_pkg.KeyPairType.ed25519)
        ),
      );

      return verified;
    } catch (e) {
      return false;
    }
  }

  static String calculateEventId(Map<String, dynamic> event) {
    final List data = [
      0,
      event['pubkey'],
      event['created_at'],
      event['kind'],
      event['tags'],
      event['content'],
    ];

    final serialized = jsonEncode(data);
    final bytes = utf8.encode(serialized);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}