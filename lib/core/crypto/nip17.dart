// nip17.dart

import 'dart:convert';
import 'package:hex/hex.dart';
import 'nip44.dart';
import 'ecdh_engine.dart';
import 'nostr_protocol.dart';
import 'crypto_utils.dart';

/// NIP-17 — Private Direct Messages using Gift Wraps and Seals.
///
/// NIP-17 provides metadata resistance by wrapping messages in multiple layers:
/// 1. Rumor: The actual message content (Kind 14).
/// 2. Seal: An encrypted event (Kind 13) containing the Rumor, signed by the sender.
/// 3. Gift Wrap: An encrypted event (Kind 1059) containing the Seal, signed by a random key.
class Nip17 {
  static const int kindGiftWrap = 1059;
  static const int kindSeal = 13;
  static const int kindDmRumor = 14;

  /// Creates a NIP-17 Gift Wrap event.
  ///
  /// [message]      : The plaintext message to send.
  /// [senderPriv]   : The sender's real private key (hex).
  /// [recipientPub] : The recipient's public key (hex).
  ///
  /// Returns a Map representing the Gift Wrap event (Kind 1059) ready to be broadcast.
  static Future<Map<String, dynamic>> createGiftWrap({
    required String message,
    required String senderPriv,
    required String recipientPub,
  }) async {
    final senderPub = ECDH.getPublicKey(senderPriv);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 1. Create the Rumor (The actual content)
    final rumor = {
      'content': message,
      'kind': kindDmRumor,
      'pubkey': senderPub,
      'created_at': now,
      'tags': [
        ['p', recipientPub]
      ],
    };

    // 2. Create the Seal (Kind 13)
    // The Seal is encrypted for the recipient using the sender's real key.
    final rumorJson = jsonEncode(rumor);
    final sealedContent = await Nip44.encrypt(rumorJson, senderPriv, recipientPub);

    final seal = {
      'content': sealedContent,
      'kind': kindSeal,
      'pubkey': senderPub,
      'created_at': now,
      'tags': [],
    };

    // Sign the Seal with sender's real private key using NostrSigner
    final sealId = NostrSigner.calculateEventId(seal);
    seal['id'] = sealId;
    seal['sig'] = NostrSigner.sign(sealId, senderPriv);

    // 3. Create the Gift Wrap (Kind 1059)
    // We generate a random "throwaway" keypair to sign the Gift Wrap using CryptoUtils.
    final throwawayPrivBytes = CryptoUtils.generateSecureRandomBytes(32);
    final throwawayPriv = HEX.encode(throwawayPrivBytes);
    final throwawayPub = ECDH.getPublicKey(throwawayPriv);

    final sealJson = jsonEncode(seal);
    final wrappedContent = await Nip44.encrypt(sealJson, throwawayPriv, recipientPub);

    final giftWrap = {
      'content': wrappedContent,
      'kind': kindGiftWrap,
      'pubkey': throwawayPub,
      'created_at': now,
      'tags': [
        ['p', recipientPub]
      ],
    };

    // Sign the Gift Wrap with the throwaway key using NostrSigner
    final giftWrapId = NostrSigner.calculateEventId(giftWrap);
    giftWrap['id'] = giftWrapId;
    giftWrap['sig'] = NostrSigner.sign(giftWrapId, throwawayPriv);

    return giftWrap;
  }

  /// Unwraps a NIP-17 Gift Wrap to reveal the original message.
  ///
  /// [giftWrap]    : The received Gift Wrap event map.
  /// [receiverPriv]: The recipient's private key (hex).
  ///
  /// Returns the original plaintext message.
  static Future<String> unwrapGiftWrap(
      Map<String, dynamic> giftWrap,
      String receiverPriv,
      ) async {
    try {
      if (giftWrap['kind'] != kindGiftWrap) {
        throw Exception('Not a Gift Wrap event');
      }

      // 1. Decrypt the Gift Wrap to get the Seal
      final wrappedContent = giftWrap['content'] as String;
      final senderPub = giftWrap['pubkey'] as String;

      final sealJson = await Nip44.decrypt(wrappedContent, receiverPriv, senderPub);
      final seal = jsonDecode(sealJson) as Map<String, dynamic>;

      if (seal['kind'] != kindSeal) {
        throw Exception('Invalid Seal inside Gift Wrap');
      }

      // 2. Decrypt the Seal to get the Rumor
      final sealedContent = seal['content'] as String;
      final realSenderPub = seal['pubkey'] as String;

      final rumorJson = await Nip44.decrypt(sealedContent, receiverPriv, realSenderPub);
      final rumor = jsonDecode(rumorJson) as Map<String, dynamic>;

      if (rumor['kind'] != kindDmRumor) {
        throw Exception('Invalid Rumor inside Seal');
      }

      return rumor['content'] as String;
    } catch (e) {
      throw Exception('Failed to unwrap NIP-17: $e');
    }
  }
}