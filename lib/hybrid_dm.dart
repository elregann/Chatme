import 'encryption_secp256k1.dart';
import 'nip04_cipher.dart';

class HybridDM {
  // =========================
  // ENCRYPT ROUTER - FIXED!
  // =========================
  static String encryptMessage({
    required String plaintext,
    required String myPrivateKey,
    required String myPublicKey,
    required String peerPublicKey,
    required bool peerSupportsChatMe,
  }) {
    if (peerSupportsChatMe) {
      final encrypted = EncryptionManager.encrypt(
        plaintext,
        myPrivateKey,
        myPublicKey,
        peerPublicKey,
      );

      // ✅ TAMBAH "cm2:" PREFIX HANYA SEKALI DI SINI!
      // EncryptionManager.encrypt() return TANPA "cm2:"
      return "cm2:$encrypted";
    }

    // NIP04 fallback - tetap sama
    return Nip04Cipher.encrypt(
      plaintext: plaintext,
      myPrivateKey: myPrivateKey,
      peerPublicKey: peerPublicKey,
    );
  }

  // =========================
  // DECRYPT ROUTER - FIXED!
  // =========================
  static String decryptMessage({
    required String payload,
    required String myPrivateKey,
    required String myPublicKey,
    required String peerPublicKey,
  }) {
    try {
      String cleanPayload = payload;

      // ============== 🚨 FIX UTAMA ==============
      // Hapus SEMUA "cm2:" prefix dari awal string
      // Loop while untuk jaga-jaga kalo ada double prefix
      while (cleanPayload.startsWith('cm2:')) {
        cleanPayload = cleanPayload.substring(4);
      }
      // ===========================================

      // Cek apakah ini ChatMe format (punya salt)
      if (cleanPayload.contains('?iv=') && cleanPayload.contains('?salt=')) {
        return EncryptionManager.decrypt(
          cleanPayload, // ✅ Sudah bersih total!
          myPrivateKey,
          myPublicKey,
          peerPublicKey,
        );
      }

      // NIP04 fallback (hanya punya iv, tanpa salt)
      if (cleanPayload.contains('?iv=')) {
        return Nip04Cipher.decrypt(
          payload: cleanPayload,
          myPrivateKey: myPrivateKey,
          peerPublicKey: peerPublicKey,
        );
      }

      return "[Unknown encryption format]";

    } catch (e) {
      print('❌ HybridDM decrypt error: $e');
      return "[⚠️ Decryption failed]";
    }
  }
}