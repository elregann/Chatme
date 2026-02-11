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

// bip32: ^2.0.0
// import 'package:bip39/bip39.dart' as bip39;
// import 'package:bip32/bip32.dart';
// import 'package:hex/hex.dart';
//
// class ChatMeVault {
//   static String generateNewMnemonic() {
//     return bip39.generateMnemonic();
//   }
//
//   static Future<String> deriveNostrPrivateKey(String mnemonic) async {
//     try {
//       final cleanMnemonic = mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
//
//       if (!bip39.validateMnemonic(cleanMnemonic)) {
//         throw "Mnemonic typo atau tidak valid";
//       }
//
//       final seed = bip39.mnemonicToSeed(cleanMnemonic);
//       final root = BIP32.fromSeed(seed);
//       final child = root.derivePath("m/44'/1237'/0'/0/0");
//
//       return HEX.encode(child.privateKey!);
//     } catch (e) {
//       rethrow;
//     }
//   }
// }