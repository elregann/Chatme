import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:bip39/bip39.dart' as bip39;

class ChatMeVault {
  static String generateNewMnemonic() {
    return bip39.generateMnemonic();
  }

  static Future<String> deriveNostrPrivateKey(String mnemonic) async {
    try {
      final cleanMnemonic = mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

      if (!bip39.validateMnemonic(cleanMnemonic)) {
        throw "Mnemonic typo atau tidak valid";
      }

      var bytes = utf8.encode(cleanMnemonic);
      var digest = sha256.convert(bytes);

      return digest.toString();
    } catch (e) {
      rethrow;
    }
  }
}