import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'package:pointycastle/export.dart' as ecc;
import 'package:encrypt/encrypt.dart' as encrypt_lib;

// =======================
// SECP256K1 CONSTANTS
// =======================
class Secp256k1Constants {
  static final BigInt p = BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
      radix: 16);
  static final BigInt n = BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
      radix: 16);
  static final BigInt b = BigInt.from(7);
}

// =======================
// SIMPLE ECDH
// =======================
class SimpleECDH {
  static final _domainParams = ecc.ECDomainParameters('secp256k1');

  static Uint8List computeSharedSecret(
      String privateKeyHex, String publicKeyHex) {
    Uint8List? secretBytes;
    try {
      if (!_isValidHex(privateKeyHex) || !_isValidHex(publicKeyHex)) {
        throw Exception('Invalid hex format');
      }

      final d = BigInt.parse(privateKeyHex, radix: 16);
      if (d <= BigInt.zero || d >= Secp256k1Constants.n) {
        throw Exception('Invalid private key range');
      }

      final pubBytes = Uint8List.fromList(HEX.decode(publicKeyHex));
      final fullPubBytes = pubBytes.length == 32
          ? Uint8List.fromList([0x02, ...pubBytes])
          : pubBytes;

      final curve = _domainParams.curve;
      final Q = curve.decodePoint(fullPubBytes);

      if (Q == null || Q.isInfinity) {
        throw Exception('Invalid public key');
      }

      if (!_isValidPoint(Q)) {
        throw Exception('Point not on curve');
      }

      final S = Q * d;
      if (S == null || S.isInfinity) {
        throw Exception('Invalid shared secret');
      }

      final x = S.x!.toBigInteger()!;
      secretBytes = Uint8List.fromList(
        HEX.decode(x.toRadixString(16).padLeft(64, '0')),
      );

      final hashed = sha256.convert(secretBytes).bytes;
      _wipeUint8List(secretBytes);
      return Uint8List.fromList(hashed);
    } catch (e) {
      if (secretBytes != null) _wipeUint8List(secretBytes);
      rethrow;
    }
  }

  static bool _isValidPoint(ecc.ECPoint point) {
    final x = point.x!.toBigInteger()!;
    final y = point.y!.toBigInteger()!;
    final left = (y * y) % Secp256k1Constants.p;
    final right =
        (x.modPow(BigInt.from(3), Secp256k1Constants.p) +
            Secp256k1Constants.b) %
            Secp256k1Constants.p;
    return left == right;
  }

  static void _wipeUint8List(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  static bool _isValidHex(String hex) {
    return hex.isNotEmpty &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
  }
}

// =======================
// HKDF SHA-256
// =======================
Uint8List _hkdfSha256(
    Uint8List ikm,
    Uint8List salt,
    Uint8List info,
    int length,
    ) {
  final prk = Hmac(sha256, salt).convert(ikm).bytes;
  Uint8List t = Uint8List(0);
  final out = BytesBuilder();
  int counter = 1;

  while (out.length < length) {
    final hmac = Hmac(sha256, prk);
    t = Uint8List.fromList(
      hmac.convert([...t, ...info, counter]).bytes,
    );
    out.add(t);
    counter++;
  }

  return out.takeBytes().sublist(0, length);
}

// =======================
// SYMMETRIC SALT DERIVATION (FIX)
// =======================
Uint8List _deriveSalt(String pubA, String pubB) {
  final keys = [pubA, pubB]..sort();
  return Uint8List.fromList(
    sha256.convert(utf8.encode(keys.join(':'))).bytes,
  );
}

// =======================
// ENCRYPTION MANAGER
// =======================
class EncryptionManager {
  static String encrypt(
      String plaintext,
      String myPrivateKey,
      String myPublicKey,
      String peerPublicKey,
      ) {
    try {
      if (plaintext.isEmpty) return '';

      final sharedSecret =
      SimpleECDH.computeSharedSecret(myPrivateKey, peerPublicKey);

      final salt = _deriveSalt(myPublicKey, peerPublicKey);
      final keyBytes = _hkdfSha256(
        sharedSecret,
        salt,
        utf8.encode('aes-gcm-chat-v1'),
        32,
      );

      final key = encrypt_lib.Key(keyBytes);
      final iv = encrypt_lib.IV.fromSecureRandom(12);

      final payload = jsonEncode({
        'v': 1,
        'msg': plaintext,
      });

      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
      );

      final encrypted = encrypter.encrypt(payload, iv: iv);
      return '${encrypted.base64}?iv=${iv.base64}';
    } catch (e) {
      return base64.encode(utf8.encode(plaintext));
    }
  }

  static String decrypt(
      String encrypted,
      String myPrivateKey,
      String myPublicKey,
      String peerPublicKey,
      ) {
    try {
      if (encrypted.isEmpty) return '[Empty message]';

      final parts = encrypted.split('?iv=');
      if (parts.length != 2) {
        return utf8.decode(base64.decode(encrypted));
      }

      final sharedSecret =
      SimpleECDH.computeSharedSecret(myPrivateKey, peerPublicKey);

      final salt = _deriveSalt(myPublicKey, peerPublicKey);
      final keyBytes = _hkdfSha256(
        sharedSecret,
        salt,
        utf8.encode('aes-gcm-chat-v1'),
        32,
      );

      final key = encrypt_lib.Key(keyBytes);
      final iv = encrypt_lib.IV.fromBase64(parts[1]);

      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
      );

      final decrypted = encrypter.decrypt64(parts[0], iv: iv);
      final decoded = jsonDecode(decrypted);
      return decoded['msg'];
    } catch (e) {
      return '[⚠️ Damaged or tampered message]';
    }
  }

  // =======================
  // SIGNATURE (BIP-340)
  // =======================
  static String sign(String eventId, String privateKey) {
    try {
      final random = Random.secure();
      final aux = HEX.encode(
        Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
      );
      return bip340.sign(privateKey, eventId, aux);
    } catch (_) {
      return '';
    }
  }

  static bool verify(
      String eventId, String signature, String pubkey) {
    try {
      return bip340.verify(pubkey, eventId, signature);
    } catch (_) {
      return false;
    }
  }
}