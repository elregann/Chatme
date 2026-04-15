// nip17.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'nip44.dart';
import 'nostr_protocol.dart';
import 'package:bip340/bip340.dart' as bip340;

/// NIP-17 — Private Direct Messages via Gift Wrap.
///
/// This implementation conforms to the NIP-17 and NIP-59 specifications,
/// providing metadata-private direct messaging through a three-layer
/// wrapping scheme:
///
///   1. Rumor  (kind 14) — The unsigned plaintext chat message.
///   2. Seal   (kind 13) — The rumor encrypted with NIP-44, signed by the sender.
///   3. Gift Wrap (kind 1059) — The seal encrypted with NIP-44, signed by a
///                              single-use ephemeral keypair.
///
/// Privacy guarantees:
/// - Relay operators cannot determine the sender's identity from the outer event.
/// - Message timestamps are randomised within a 2-day window to prevent
///   timing correlation attacks.
/// - The actual event kind, tags, and content are hidden from the network.
///
/// Reference: https://github.com/nostr-protocol/nips/blob/master/17.md
class Nip17 {
  /// The Nostr event kind for a private chat message (Rumor).
  static const int kindRumor = 14;

  /// The Nostr event kind for a Seal — an encrypted, signed Rumor.
  static const int kindSeal = 13;

  /// The Nostr event kind for a Gift Wrap — an encrypted, signed Seal.
  static const int kindGiftWrap = 1059;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Wraps a plaintext [message] into a NIP-17 Gift Wrap event ready for relay.
  ///
  /// [plaintext]       : The UTF-8 chat message to send.
  /// [senderPrivkey]   : Sender's private key as a 64-character hex string.
  /// [senderPubkey]    : Sender's public key as a 64-character hex string.
  /// [receiverPubkey]  : Recipient's public key as a 64-character hex string.
  /// [replyToId]       : Optional event ID of the message being replied to.
  ///
  /// Returns a fully signed Gift Wrap event map ready to be published as:
  ///   `["EVENT", giftWrap]`
  ///
  /// Throws [Exception] if any layer of wrapping fails.
  static Future<Map<String, dynamic>> wrap({
    required String plaintext,
    required String senderPrivkey,
    required String senderPubkey,
    required String receiverPubkey,
    String? replyToId,
  }) async {
    try {
      // 1. Build the unsigned Rumor (kind 14) — the plaintext message layer.
      final rumor = _buildRumor(
        plaintext: plaintext,
        senderPubkey: senderPubkey,
        receiverPubkey: receiverPubkey,
        replyToId: replyToId,
      );

      // 2. Seal the Rumor: encrypt with NIP-44 and sign with the sender's key.
      final seal = await _buildSeal(
        rumor: rumor,
        senderPrivkey: senderPrivkey,
        senderPubkey: senderPubkey,
        receiverPubkey: receiverPubkey,
      );

      // 3. Gift-wrap the Seal: encrypt with NIP-44 and sign with an ephemeral key.
      final giftWrap = await _buildGiftWrap(
        seal: seal,
        receiverPubkey: receiverPubkey,
      );

      return giftWrap;
    } catch (e) {
      throw Exception('NIP-17 wrap failed: $e');
    }
  }

  /// Unwraps a received NIP-17 Gift Wrap event to recover the original plaintext.
  ///
  /// [giftWrapEvent]  : The raw kind-1059 event map received from a relay.
  /// [receiverPrivkey]: Recipient's private key as a 64-character hex string.
  /// [receiverPubkey] : Recipient's public key as a 64-character hex string.
  ///
  /// Returns an [Nip17Result] containing the plaintext message, the verified
  /// sender public key, the original timestamp, and any reply metadata.
  ///
  /// Throws [Exception] if any layer fails to decrypt or validate.
  static Future<Nip17Result> unwrap({
    required Map<String, dynamic> giftWrapEvent,
    required String receiverPrivkey,
    required String receiverPubkey,
  }) async {
    try {
      // 1. Decrypt the Gift Wrap to recover the Seal.
      //    The Gift Wrap is signed by an ephemeral key — its pubkey is the
      //    ephemeral public key used to encrypt the Seal content.
      final ephemeralPubkey = giftWrapEvent['pubkey']?.toString() ?? '';
      if (ephemeralPubkey.isEmpty) {
        throw Exception('Gift Wrap event is missing the ephemeral pubkey field');
      }

      final sealJson = await Nip44.decrypt(
        giftWrapEvent['content']?.toString() ?? '',
        receiverPrivkey,
        ephemeralPubkey,
      );

      final seal = jsonDecode(sealJson) as Map<String, dynamic>;

      // 2. Validate that the Seal is of the expected kind.
      if (seal['kind'] != kindSeal) {
        throw Exception(
          'Inner event kind ${seal['kind']} is not a valid Seal (expected $kindSeal)',
        );
      }

      // 3. Decrypt the Seal to recover the Rumor.
      //    The Seal is signed by the actual sender — its pubkey is the sender's
      //    real public key, used as the peer key for NIP-44 decryption.
      final senderPubkey = seal['pubkey']?.toString() ?? '';
      if (senderPubkey.isEmpty) {
        throw Exception('Seal event is missing the sender pubkey field');
      }

      final rumorJson = await Nip44.decrypt(
        seal['content']?.toString() ?? '',
        receiverPrivkey,
        senderPubkey,
      );

      final rumor = jsonDecode(rumorJson) as Map<String, dynamic>;

      // 4. Validate that the Rumor is of the expected kind.
      if (rumor['kind'] != kindRumor) {
        throw Exception(
          'Innermost event kind ${rumor['kind']} is not a valid Rumor (expected $kindRumor)',
        );
      }

      // 5. Extract reply metadata from the Rumor's tags, if present.
      String? replyToId;
      final tags = rumor['tags'] as List? ?? [];
      for (final tag in tags) {
        if (tag is List && tag.length > 1 && tag[0] == 'e') {
          replyToId = tag[1].toString();
          break;
        }
      }

      return Nip17Result(
        plaintext: rumor['content']?.toString() ?? '',
        senderPubkey: senderPubkey,
        timestamp: (rumor['created_at'] as int? ?? 0) * 1000,
        rumorId: rumor['id']?.toString() ?? '',
        replyToId: replyToId,
      );
    } catch (e) {
      throw Exception('NIP-17 unwrap failed: $e');
    }
  }

  /// Returns [true] if [event] is a Gift Wrap event (kind 1059).
  ///
  /// Use this to filter incoming relay events before calling [unwrap].
  static bool isGiftWrap(Map<String, dynamic> event) {
    return event['kind'] == kindGiftWrap;
  }

  // ---------------------------------------------------------------------------
  // Layer Builders
  // ---------------------------------------------------------------------------

  /// Constructs an unsigned Rumor event (kind 14).
  ///
  /// The Rumor is intentionally left unsigned — its ID is computed for
  /// reference but no signature is attached. This ensures that the
  /// plaintext message is never directly attributable on the network.
  static Map<String, dynamic> _buildRumor({
    required String plaintext,
    required String senderPubkey,
    required String receiverPubkey,
    String? replyToId,
  }) {
    final List<List<String>> tags = [['p', receiverPubkey]];

    if (replyToId != null && replyToId.isNotEmpty) {
      tags.add(['e', replyToId]);
    }

    final unsignedRumor = {
      'pubkey': senderPubkey,
      'created_at': _realTimestamp(),
      'kind': kindRumor,
      'tags': tags,
      'content': plaintext,
    };

    // Compute the event ID so the Rumor can be referenced by reply tags,
    // but deliberately omit the 'sig' field to mark it as unsigned.
    final id = _computeEventId(unsignedRumor);
    return {...unsignedRumor, 'id': id};
  }

  /// Constructs a signed Seal event (kind 13).
  ///
  /// The Rumor is serialised to JSON, encrypted with NIP-44 addressed to
  /// the [receiverPubkey], and the resulting ciphertext is signed by the
  /// sender's actual private key.
  ///
  /// The Seal's timestamp is randomised within ±2 days to prevent
  /// timing correlation between the Seal and the Gift Wrap.
  static Future<Map<String, dynamic>> _buildSeal({
    required Map<String, dynamic> rumor,
    required String senderPrivkey,
    required String senderPubkey,
    required String receiverPubkey,
  }) async {
    final rumorJson = jsonEncode(rumor);

    final encryptedRumor = await Nip44.encrypt(
      rumorJson,
      senderPrivkey,
      receiverPubkey,
    );

    final unsignedSeal = {
      'pubkey': senderPubkey,
      'created_at': _randomisedTimestamp(),
      'kind': kindSeal,
      'tags': <List<String>>[],  // Seals carry no tags per the specification.
      'content': encryptedRumor,
    };

    final id = _computeEventId(unsignedSeal);
    final sig = NostrSigner.sign(id, senderPrivkey);

    return {...unsignedSeal, 'id': id, 'sig': sig};
  }

  /// Constructs a signed Gift Wrap event (kind 1059).
  ///
  /// The Seal is serialised to JSON, encrypted with NIP-44 addressed to
  /// the [receiverPubkey], and the resulting ciphertext is signed by a
  /// freshly generated single-use ephemeral keypair.
  ///
  /// The ephemeral key is discarded after signing — this prevents relay
  /// operators from linking the Gift Wrap to the sender's identity.
  ///
  /// The Gift Wrap's timestamp is also randomised to prevent timing attacks.
  static Future<Map<String, dynamic>> _buildGiftWrap({
    required Map<String, dynamic> seal,
    required String receiverPubkey,
  }) async {
    // Generate a single-use ephemeral keypair for this Gift Wrap only.
    final ephemeral = _generateEphemeralKeypair();
    final ephemeralPrivkey = ephemeral.privkey;
    final ephemeralPubkey = ephemeral.pubkey;

    final sealJson = jsonEncode(seal);

    final encryptedSeal = await Nip44.encrypt(
      sealJson,
      ephemeralPrivkey,
      receiverPubkey,
    );

    final unsignedGiftWrap = {
      'pubkey': ephemeralPubkey,
      'created_at': _randomisedTimestamp(),
      'kind': kindGiftWrap,
      'tags': [['p', receiverPubkey]],  // Only the recipient tag is exposed.
      'content': encryptedSeal,
    };

    final id = _computeEventId(unsignedGiftWrap);
    final sig = NostrSigner.sign(id, ephemeralPrivkey);

    return {...unsignedGiftWrap, 'id': id, 'sig': sig};
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Computes the canonical Nostr event ID for [event].
  ///
  /// Per NIP-01: SHA-256 of the UTF-8 JSON serialisation of
  /// [0, pubkey, created_at, kind, tags, content].
  static String _computeEventId(Map<String, dynamic> event) {
    final serialized = jsonEncode([
      0,
      event['pubkey'],
      event['created_at'],
      event['kind'],
      event['tags'],
      event['content'],
    ]);
    return sha256.convert(utf8.encode(serialized)).toString();
  }

  /// Returns the current Unix timestamp in seconds.
  static int _realTimestamp() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// Returns a randomised Unix timestamp within ±2 days of the current time.
  ///
  /// Per the NIP-17 specification, timestamps on Seals and Gift Wraps must be
  /// randomised to prevent timing-based correlation of wrapped messages.
  static int _randomisedTimestamp() {
    const twoDaysInSeconds = 172800;
    final rng = Random.secure();
    final offset = rng.nextInt(twoDaysInSeconds * 2) - twoDaysInSeconds;
    return _realTimestamp() + offset;
  }

  /// Generates a single-use ephemeral secp256k1 keypair.
  ///
  /// The private key is 32 cryptographically random bytes encoded as hex.
  /// The public key is derived via the same scalar multiplication used
  /// throughout the Nostr protocol.
  static _EphemeralKeypair _generateEphemeralKeypair() {
    final rng = Random.secure();
    final privkeyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    final privkeyHex = privkeyBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // Derive the corresponding public key from the ephemeral private key.
    final pubkeyHex = bip340.getPublicKey(privkeyHex);

    return _EphemeralKeypair(privkey: privkeyHex, pubkey: pubkeyHex);
  }
}

// ---------------------------------------------------------------------------
// Result and Internal Data Classes
// ---------------------------------------------------------------------------

/// The result of successfully unwrapping a NIP-17 Gift Wrap event.
class Nip17Result {
  /// The decrypted plaintext message content.
  final String plaintext;

  /// The verified public key of the actual message sender.
  final String senderPubkey;

  /// The original message timestamp in milliseconds since epoch.
  final int timestamp;

  /// The event ID of the innermost Rumor event.
  final String rumorId;

  /// The event ID of the message being replied to, if any.
  final String? replyToId;

  const Nip17Result({
    required this.plaintext,
    required this.senderPubkey,
    required this.timestamp,
    required this.rumorId,
    this.replyToId,
  });
}

/// Holds a single-use ephemeral secp256k1 keypair.
class _EphemeralKeypair {
  /// Private key as a 64-character lowercase hex string.
  final String privkey;

  /// Public key as a 64-character lowercase hex string (x-only).
  final String pubkey;

  const _EphemeralKeypair({required this.privkey, required this.pubkey});
}