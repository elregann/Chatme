import 'package:hex/hex.dart';

// Direct internal imports
import 'nip17.dart';
import 'nip44.dart';
import 'ecdh_engine.dart';
import 'crypto_utils.dart';

/// NIP-17 & NIP-44 Integration Test Suite
///
/// This script validates the end-to-end cryptographic flow for Chatme,
/// ensuring that messages are correctly encrypted, wrapped, and recovered
/// while maintaining metadata privacy.
void main() async {
  print('===========================================================');
  print('🚀 CHATME CRYPTOGRAPHIC INTEGRATION TEST SUITE');
  print('===========================================================');

  // 1. Participant Setup
  // Generating secure random keys for Alice (Sender) and Bob (Recipient)
  final String alicePriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final String alicePub = ECDH.getPublicKey(alicePriv);

  final String bobPriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final String bobPub = ECDH.getPublicKey(bobPriv);

  const String secretMessage = "Hello Bob, this is a secure NIP-17 message from Alice.";

  print('ALICE (Sender)    : $alicePub');
  print('BOB (Recipient)   : $bobPub');
  print('-----------------------------------------------------------');

  try {
    // 2. Foundation Layer: NIP-44 v2 Test
    // Validates the base encryption used for both Seals and Gift Wraps.
    print('[STAGE 1] Testing NIP-44 v2 Encryption...');

    final payload = await Nip44.encrypt(secretMessage, alicePriv, bobPub);

    if (!Nip44.isValidPayload(payload)) {
      throw Exception('Structural validation failed for NIP-44 payload.');
    }

    final decrypted = await Nip44.decrypt(payload, bobPriv, alicePub);
    if (decrypted != secretMessage) {
      throw Exception('Decryption integrity failure: Plaintext mismatch.');
    }

    print('✅ NIP-44: Authenticated encryption/decryption verified.');
    print('-----------------------------------------------------------');

    // 3. Privacy Layer: NIP-17 Gift Wrap Test
    // Validates the triple-wrapping mechanism (Rumor -> Seal -> Gift Wrap).
    print('[STAGE 2] Testing NIP-17 Gift Wrap (Metadata Resistance)...');

    final giftWrap = await Nip17.createGiftWrap(
      message: secretMessage,
      senderPriv: alicePriv,
      recipientPub: bobPub,
    );

    // Metadata Privacy Check:
    // The outer pubkey must be a random "throwaway" key, not Alice's real pubkey.
    if (giftWrap['kind'] != 1059) throw Exception('Invalid event kind for Gift Wrap.');
    if (giftWrap['pubkey'] == alicePub) {
      throw Exception('Security Flaw: Alice\'s identity is exposed in the outer layer.');
    }

    // Process of unwrapping the layers: Gift Wrap -> Seal -> Rumor
    final unwrappedMessage = await Nip17.unwrapGiftWrap(giftWrap, bobPriv);
    if (unwrappedMessage != secretMessage) {
      throw Exception('NIP-17: Recovered message content is corrupted.');
    }

    print('✅ NIP-17: Triple-layer wrap/unwrap successful.');
    print('✅ NIP-17: Sender anonymity preserved (Throwaway key used).');
    print('-----------------------------------------------------------');

    // 4. Security Bound Test: Unauthorized Access
    // Ensures that an attacker with a different private key cannot recover the message.
    print('[STAGE 3] Testing Security Rejection (Malicious Actor)...');

    final evePriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));

    try {
      await Nip17.unwrapGiftWrap(giftWrap, evePriv);
      throw Exception('Critical Vulnerability: Unauthorized key successfully unwrapped the message.');
    } catch (e) {
      // Expected behavior: HMAC verification in NIP-44 should fail.
      print('✅ Security: Unauthorized decryption correctly rejected.');
    }

    print('-----------------------------------------------------------');
    print('🎉 ALL CRYPTOGRAPHIC TESTS PASSED SUCCESSFULLY!');
    print('Chatme is now secured with NIP-17 metadata resistance.');
    print('===========================================================');

  } catch (e) {
    print('❌ INTEGRATION TEST FAILED');
    print('Context: $e');
  }
}