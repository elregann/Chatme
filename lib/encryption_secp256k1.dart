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

    // Validasi titik berada di kurva
    final left = (y * y) % Secp256k1Constants.p;
    final right = (x.modPow(BigInt.from(3), Secp256k1Constants.p) +
        Secp256k1Constants.b) %
        Secp256k1Constants.p;
    if (left != right) return false;

    // Validasi titik berada di subgroup yang benar
    final nQ = point * Secp256k1Constants.n;
    return nQ!.isInfinity;
  }

  static void _wipeUint8List(Uint8List data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  static bool _isValidHex(String hex) {
    return hex.isNotEmpty && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
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
// SYMMETRIC SALT DERIVATION (WITH RANDOM SALT)
// =======================
Uint8List _deriveStaticSalt(String pubA, String pubB) {
  final keys = [pubA, pubB]..sort();
  return Uint8List.fromList(
    sha256.convert(utf8.encode(keys.join(':'))).bytes,
  );
}

// Helper untuk menghasilkan byte acak dengan aman
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

      // Generate random salt untuk sesi ini (16 bytes)
      final randomSalt = _generateSecureRandomBytes(16);

      // Gabungkan static salt dengan random salt
      final staticSalt = _deriveStaticSalt(myPublicKey, peerPublicKey);
      final combinedSalt = Uint8List.fromList([...staticSalt, ...randomSalt]);

      final keyBytes = _hkdfSha256(
        sharedSecret,
        combinedSalt,
        utf8.encode('aes-gcm-chat-v2'), // Versi ditingkatkan
        32,
      );

      final key = encrypt_lib.Key(keyBytes);

      // Generate IV dengan validasi (12 bytes untuk AES-GCM)
      final ivBytes = _generateSecureRandomBytes(12);
      final iv = encrypt_lib.IV(ivBytes);

      // Pastikan IV benar-benar 12 bytes
      if (ivBytes.length != 12) {
        throw Exception('Invalid IV length');
      }

      final payload = jsonEncode({
        'v': 2, // Versi protokol ditingkatkan
        'msg': plaintext,
      });

      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
      );

      final encrypted = encrypter.encrypt(payload, iv: iv);

      // Format baru: ciphertext?iv=...?salt=...
      final saltBase64 = base64.encode(randomSalt);
      final ivBase64 = base64.encode(ivBytes);
      final ciphertext = encrypted.base64;

      return '$ciphertext?iv=$ivBase64?salt=$saltBase64';
    } catch (e) {
      throw Exception('Encryption failed: $e');
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

      // Parsing format baru (v2)
      final parts = encrypted.split('?');
      String ciphertext;
      String ivBase64;
      String saltBase64;

      if (parts.length == 3) {
        // Format baru: ciphertext?iv=...?salt=...
        ciphertext = parts[0];
        ivBase64 = parts[1].replaceFirst('iv=', '');
        saltBase64 = parts[2].replaceFirst('salt=', '');
      } else if (encrypted.contains('?iv=') && parts.length == 2) {
        // Format lama (v1) untuk backward compatibility
        final oldParts = encrypted.split('?iv=');
        ciphertext = oldParts[0];
        ivBase64 = oldParts[1];
        saltBase64 = ''; // Tidak ada salt di v1
      } else {
        try {
          return utf8.decode(base64.decode(encrypted));
        } catch (e) {
          return '[⚠️ Format pesan tidak valid]';
        }
      }

      final sharedSecret =
      SimpleECDH.computeSharedSecret(myPrivateKey, peerPublicKey);

      Uint8List combinedSalt;
      Uint8List info;
      int version;

      if (saltBase64.isNotEmpty) {
        // Format v2 dengan random salt
        try {
          final randomSalt = base64.decode(saltBase64);
          final staticSalt = _deriveStaticSalt(myPublicKey, peerPublicKey);
          combinedSalt = Uint8List.fromList([...staticSalt, ...randomSalt]);
          info = utf8.encode('aes-gcm-chat-v2');
          version = 2;
        } catch (e) {
          return '[⚠️ Salt tidak valid]';
        }
      } else {
        // Format v1 tanpa random salt
        combinedSalt = _deriveStaticSalt(myPublicKey, peerPublicKey);
        info = utf8.encode('aes-gcm-chat-v1');
        version = 1;
      }

      final keyBytes = _hkdfSha256(
        sharedSecret,
        combinedSalt,
        info,
        32,
      );

      final key = encrypt_lib.Key(keyBytes);
      final iv = encrypt_lib.IV.fromBase64(ivBase64);

      // Validasi IV
      if (iv.bytes.length != 12) {
        return '[⚠️ Panjang IV tidak valid]';
      }

      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
      );

      final decrypted = encrypter.decrypt64(ciphertext, iv: iv);
      final decoded = jsonDecode(decrypted);

      // Validasi versi
      if (decoded['v'] != version) {
        return '[⚠️ Versi protokol tidak cocok]';
      }

      return decoded['msg'];
    } catch (e) {
      return '[⚠️ Pesan rusak atau telah diubah]';
    }
  }

  // =======================
  // SIGNATURE (BIP-340)
  // =======================
  static String sign(String eventId, String privateKey) {
    try {
      // Generate aux dengan CSPRNG
      final auxBytes = _generateSecureRandomBytes(32);
      final auxHex = HEX.encode(auxBytes);

      final signature = bip340.sign(privateKey, eventId, auxHex);

      // Validasi signature tidak kosong
      if (signature.isEmpty) {
        throw Exception('Signature generation failed');
      }

      return signature;
    } catch (e) {
      throw Exception('Signing failed: $e');
    }
  }

  static bool verify(
      String eventId,
      String signature,
      String pubkey,
      ) {
    try {
      // Validasi input
      if (signature.isEmpty || pubkey.isEmpty || eventId.isEmpty) {
        return false;
      }

      return bip340.verify(pubkey, eventId, signature);
    } catch (e) {
      return false;
    }
  }

  static String calculateEventId(Map<String, dynamic> event) {
    // Standar Nostr: ID adalah SHA256 hash dari [0, pubkey, created_at, kind, tags, content]
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