import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'encryption_secp256k1.dart';

class Nip04 {

  static String encrypt(
      String plaintext,
      String myPrivkey,
      String peerPubkey,
      ) {

    final sharedSecret =
    SimpleECDH.computeSharedSecret(myPrivkey, peerPubkey);

    final key = encrypt_lib.Key(sharedSecret);

    final iv = encrypt_lib.IV.fromSecureRandom(16);

    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
    );

    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    return "${encrypted.base64}?iv=${iv.base64}";
  }

  static String decrypt(
      String encrypted,
      String myPrivkey,
      String peerPubkey,
      ) {

    final parts = encrypted.split('?iv=');

    if (parts.length != 2) {
      return '[invalid nip04]';
    }

    final sharedSecret =
    SimpleECDH.computeSharedSecret(myPrivkey, peerPubkey);

    final key = encrypt_lib.Key(sharedSecret);

    final iv = encrypt_lib.IV.fromBase64(parts[1]);

    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
    );

    return encrypter.decrypt64(parts[0], iv: iv);
  }
}