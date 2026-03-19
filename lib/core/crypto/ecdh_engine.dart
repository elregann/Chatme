// ecdh_engine.dart

import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart' as ecc;

class Secp256k1Constants {
  static final BigInt p = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F', radix: 16);
  static final BigInt n = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141', radix: 16);
  static final BigInt b = BigInt.from(7);
}

class ECDH {
  static final _domainParams = ecc.ECDomainParameters('secp256k1');

  /// Shared secret untuk skema custom Chatme.
  /// Output: SHA-256(x) — lebih aman, dipakai di EncryptionManager.
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

      final curve = _domainParams.curve;
      final Q = curve.decodePoint(fullPubBytes);

      if (Q == null || Q.isInfinity) throw Exception('Invalid public key');
      if (!_isValidPoint(Q)) throw Exception('Point not on curve');

      final S = Q * d;
      final xBigInt = S!.x!.toBigInteger()!;
      final xBytes = Uint8List(32);
      final rawBytes = xBigInt.toRadixString(16).padLeft(64, '0');
      xBytes.setAll(0, HEX.decode(rawBytes));

      // Hash x untuk keamanan lebih baik
      return Uint8List.fromList(sha256.convert(xBytes).bytes);
    } catch (e) {
      rethrow;
    }
  }

  /// Shared secret untuk NIP-04 (standar Nostr).
  /// Output: x mentah (raw), TANPA di-hash — sesuai spesifikasi NIP-04.
  /// Gunakan ini hanya untuk interoperabilitas dengan client Nostr lain.
  static Uint8List computeSharedSecretRaw(String privateKeyHex, String publicKeyHex) {
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

      if (Q == null || Q.isInfinity) throw Exception('Invalid public key');
      if (!_isValidPoint(Q)) throw Exception('Point not on curve');

      final S = Q * d;
      final xBigInt = S!.x!.toBigInteger()!;
      final rawHex = xBigInt.toRadixString(16).padLeft(64, '0');

      // NIP-04: kembalikan x mentah, TANPA hash
      return Uint8List.fromList(HEX.decode(rawHex));
    } catch (e) {
      rethrow;
    }
  }

  static bool _isValidPoint(ecc.ECPoint point) {
    final x = point.x!.toBigInteger()!;
    final y = point.y!.toBigInteger()!;
    final left = (y * y) % Secp256k1Constants.p;
    final right = (x.modPow(BigInt.from(3), Secp256k1Constants.p) + Secp256k1Constants.b) % Secp256k1Constants.p;
    if (left != right) return false;
    return (point * Secp256k1Constants.n)!.isInfinity;
  }

  static bool _isValidHex(String hex) =>
      hex.isNotEmpty && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
}