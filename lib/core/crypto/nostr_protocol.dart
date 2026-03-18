// nostr_protocol.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'crypto_utils.dart';

class NostrSigner {
  static String sign(String eventId, String privateKey) {
    try {
      final auxBytes = CryptoUtils.generateSecureRandomBytes(32);
      final auxHex = HEX.encode(auxBytes);
      final signature = bip340.sign(privateKey, eventId, auxHex);
      if (signature.isEmpty) throw Exception('Signature generation failed');
      return signature;
    } catch (e) {
      throw Exception('Signing failed: $e');
    }
  }

  static bool verify(String eventId, String signature, String pubkey) {
    try {
      if (signature.isEmpty || pubkey.isEmpty || eventId.isEmpty) return false;
      return bip340.verify(pubkey, eventId, signature);
    } catch (e) {
      return false;
    }
  }

  static String calculateEventId(Map<String, dynamic> event) {
    final List data = [0, event['pubkey'], event['created_at'], event['kind'], event['tags'], event['content']];
    return sha256.convert(utf8.encode(jsonEncode(data))).toString();
  }
}