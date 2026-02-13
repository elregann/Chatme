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
  static final _curve = _domainParams.curve; // Cache curve untuk performance

  static Uint8List computeSharedSecret(String privateKeyHex, String publicKeyHex) {
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

      final Q = _curve.decodePoint(fullPubBytes);

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

      // Ambil koordinat X sebagai shared secret
      final xBigInt = S.x!.toBigInteger()!;

      // Konversi ke 32 bytes
      final xBytes = Uint8List(32);
      final rawBytes = xBigInt.toRadixString(16).padLeft(64, '0');
      xBytes.setAll(0, HEX.decode(rawBytes));

      // Hash koordinat X untuk final shared secret
      final hashed = sha256.convert(xBytes).bytes;

      return Uint8List.fromList(hashed);
    } catch (e) {
      rethrow;
    }
  }

  static bool _isValidPoint(ecc.ECPoint point) {
    final x = point.x!.toBigInteger()!;
    final y = point.y!.toBigInteger()!;

    final left = (y * y) % Secp256k1Constants.p;
    final right = (x.modPow(BigInt.from(3), Secp256k1Constants.p) +
        Secp256k1Constants.b) %
        Secp256k1Constants.p;
    if (left != right) return false;

    final nQ = point * Secp256k1Constants.n;
    return nQ!.isInfinity;
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
// SYMMETRIC SALT DERIVATION
// =======================
Uint8List _deriveStaticSalt(String pubA, String pubB) {
  final keys = [pubA, pubB]..sort();
  return Uint8List.fromList(
    sha256.convert(utf8.encode(keys.join(':'))).bytes,
  );
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
// ENCRYPTION MANAGER - FIXED!
// =======================
class EncryptionManager {
  // =======================
  // ENCRYPT - RETURN TANPA "cm2:" PREFIX
  // =======================
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

      final randomSalt = _generateSecureRandomBytes(16);
      final staticSalt = _deriveStaticSalt(myPublicKey, peerPublicKey);
      final combinedSalt = Uint8List.fromList([...staticSalt, ...randomSalt]);

      final keyBytes = _hkdfSha256(
        sharedSecret,
        combinedSalt,
        utf8.encode('chatme-v2-aes-gcm'),
        32,
      );

      final key = encrypt_lib.Key(keyBytes);
      final ivBytes = _generateSecureRandomBytes(12);
      final iv = encrypt_lib.IV(ivBytes);

      final payload = jsonEncode({
        'v': 2,
        'msg': plaintext,
      });

      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
      );

      // AEAD: Mengunci identitas ke ciphertext
      final encrypted = encrypter.encrypt(
          payload,
          iv: iv,
          associatedData: staticSalt
      );

      final saltBase64 = base64.encode(randomSalt);
      final ivBase64 = base64.encode(ivBytes);
      final ciphertext = encrypted.base64;

      // ✅ FORMAT BERSIH: ciphertext?iv=xxx?salt=yyy
      // TANPA "cm2:" PREFIX!
      return '$ciphertext?iv=$ivBase64?salt=$saltBase64';

    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  // =======================
  // DECRYPT - AUTO BERSIHKAN "cm2:" PREFIX
  // =======================
  static String decrypt(
      String encrypted,
      String myPrivateKey,
      String myPublicKey,
      String peerPublicKey,
      ) {
    try {
      if (encrypted.isEmpty) return '[Empty message]';

      print('🔍 Decrypting: $encrypted'); // DEBUG

      // ============== 🚨 FIX UTAMA ==============
      // Hapus SEMUA "cm2:" prefix dari awal string
      String cleanInput = encrypted;
      while (cleanInput.startsWith('cm2:')) {
        cleanInput = cleanInput.substring(4);
      }
      // ===========================================

      // Parse format: ciphertext?iv=xxx?salt=yyy
      final parts = cleanInput.split('?');
      print('📦 Parts: $parts'); // DEBUG

      if (parts.length != 3) {
        return '[⚠️ Format pesan tidak valid - expected 3 parts, got ${parts.length}]';
      }

      final ciphertext = parts[0];
      final ivBase64 = parts[1].replaceFirst('iv=', '');
      final saltBase64 = parts[2].replaceFirst('salt=', '');

      print('📝 Ciphertext: $ciphertext'); // DEBUG
      print('🔑 IV: $ivBase64'); // DEBUG
      print('🧂 Salt: $saltBase64'); // DEBUG

      // Validasi komponen wajib
      if (ciphertext.isEmpty || ivBase64.isEmpty || saltBase64.isEmpty) {
        return '[⚠️ Komponen pesan tidak lengkap]';
      }

      // 1. Compute shared secret
      final sharedSecret = SimpleECDH.computeSharedSecret(
          myPrivateKey,
          peerPublicKey
      );
      print('🔐 Shared secret: ${base64.encode(sharedSecret)}'); // DEBUG

      // 2. Derive static salt dari identitas
      final staticSalt = _deriveStaticSalt(myPublicKey, peerPublicKey);
      print('🏠 Static salt: ${base64.encode(staticSalt)}'); // DEBUG

      // 3. Parse random salt
      Uint8List randomSalt;
      try {
        randomSalt = base64.decode(saltBase64);
        print('🎲 Random salt: ${base64.encode(randomSalt)}'); // DEBUG
      } catch (e) {
        print('❌ Salt decode error: $e'); // DEBUG
        return '[⚠️ Salt tidak valid: $e]';
      }

      // 4. Combine salts
      final combinedSalt = Uint8List.fromList([
        ...staticSalt,
        ...randomSalt
      ]);
      print('🧂 Combined salt: ${base64.encode(combinedSalt)}'); // DEBUG

      // 5. HKDF key derivation
      final keyBytes = _hkdfSha256(
        sharedSecret,
        combinedSalt,
        utf8.encode('chatme-v2-aes-gcm'),
        32,
      );
      print('🔑 Key bytes: ${base64.encode(keyBytes)}'); // DEBUG

      final key = encrypt_lib.Key(keyBytes);

      // 6. Parse IV
      final iv = encrypt_lib.IV.fromBase64(ivBase64);
      print('🎲 IV length: ${iv.bytes.length}'); // DEBUG

      if (iv.bytes.length != 12) {
        return '[⚠️ Panjang IV tidak valid: ${iv.bytes.length}]';
      }

      // 7. Decrypt dengan AEAD
      final encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.gcm),
      );

      print('🔓 Attempting decrypt...'); // DEBUG
      final decrypted = encrypter.decrypt64(
        ciphertext, // ✅ Sudah bersih dari "cm2:"
        iv: iv,
        associatedData: staticSalt,
      );
      print('📄 Decrypted JSON: $decrypted'); // DEBUG

      // 8. Parse payload
      final decoded = jsonDecode(decrypted);
      print('📦 Decoded: $decoded'); // DEBUG

      // 9. Validasi versi
      if (decoded['v'] != 2) {
        return '[⚠️ Versi protokol tidak didukung: ${decoded['v']}]';
      }

      final message = decoded['msg'];
      print('💬 Message: $message'); // DEBUG

      return message ?? '[Pesan kosong]';

    } catch (e, stacktrace) {
      print('❌ ERROR: $e'); // DEBUG
      print('📚 Stacktrace: $stacktrace'); // DEBUG
      return '[⚠️ Pesan rusak atau tidak diizinkan: $e]';
    }
  }

  // =======================
  // SIGNATURE (BIP-340)
  // =======================
  static String sign(String eventId, String privateKey) {
    try {
      final auxBytes = _generateSecureRandomBytes(32);
      final auxHex = HEX.encode(auxBytes);
      final signature = bip340.sign(privateKey, eventId, auxHex);

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
      if (signature.isEmpty || pubkey.isEmpty || eventId.isEmpty) {
        return false;
      }
      return bip340.verify(pubkey, eventId, signature);
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
    return sha256.convert(utf8.encode(serialized)).toString();
  }
}