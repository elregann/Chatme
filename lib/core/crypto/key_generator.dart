// key_generator.dart

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:hex/hex.dart';

class ChatMeVault {
  static const String nostrDerivationPath = "m/44'/1237'/0'/0/0";

  static String generateNewMnemonic() {
    return bip39.generateMnemonic();
  }

  /// NIP-06: BIP-39 seed, then BIP-32 at m/44'/1237'/0'/0/0.
  static String deriveNostrPrivateKey(String mnemonic) {
    final cleanMnemonic = mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    if (!bip39.validateMnemonic(cleanMnemonic)) {
      throw 'Mnemonic typo or invalid';
    }

    final seed = bip39.mnemonicToSeed(cleanMnemonic);
    final node = bip32.BIP32.fromSeed(seed).derivePath(nostrDerivationPath);
    return HEX.encode(node.privateKey!);
  }
}
