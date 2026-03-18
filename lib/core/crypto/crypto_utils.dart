// crypto_utils.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class CryptoUtils {
  static Uint8List hkdfSha256(Uint8List ikm, Uint8List salt, Uint8List info, int length) {
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

  static Uint8List deriveStaticSalt(String pubA, String pubB) {
    final keys = [pubA, pubB]..sort();
    return Uint8List.fromList(sha256.convert(utf8.encode(keys.join(':'))).bytes);
  }

  static Uint8List generateSecureRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}