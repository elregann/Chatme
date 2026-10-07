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
/// Conforms to NIP-17 and NIP-59. Three-layer wrapping:
///   1. Rumor  (kind 14)  — unsigned plaintext.
///   2. Seal   (kind 13)  — NIP-44 encrypted Rumor, signed by sender.
///   3. GiftWrap (kind 1059) — NIP-44 encrypted Seal, signed by ephemeral key.
///
/// Reference: https://github.com/nostr-protocol/nips/blob/master/17.md
class Nip17 {
  static const int kindRumor = 14;
  static const int kindSeal = 13;
  static const int kindGiftWrap = 1059;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Wraps a plaintext into a **single** Gift Wrap for [receiverPubkey].
  ///
  /// Convenience wrapper around [wrapMulti] for the common single-recipient
  /// case (e.g. read receipts and reactions that don't need a self-envelope).
  static Future<Nip17Wrapped> wrap({
    required String plaintext,
    required String senderPrivkey,
    required String senderPubkey,
    required String receiverPubkey,
    String? rumorReceiverPubkey,
    String? replyToId,
    int? forcedTimestampSec,
  }) async {
    final results = await wrapMulti(
      plaintext: plaintext,
      senderPrivkey: senderPrivkey,
      senderPubkey: senderPubkey,
      receiverPubkeys: [receiverPubkey],
      rumorReceiverPubkey: rumorReceiverPubkey,
      replyToId: replyToId,
      forcedTimestampSec: forcedTimestampSec,
    );
    return results.first;
  }

  /// Wraps a plaintext into **multiple** Gift Wraps that all share the SAME
  /// inner Rumor.
  ///
  /// This is the correct way to build a recipient envelope + a self-envelope
  /// for multi-device sync: the Rumor (and therefore its ID) is identical
  /// across both envelopes, so the sender's own devices can deduplicate by
  /// Rumor ID.
  ///
  /// [receiverPubkeys] is the list of pubkeys to encrypt to. Order is
  /// preserved in the returned list.
  ///
  /// [rumorReceiverPubkey] is the pubkey that appears in the Rumor's `p` tag.
  /// Defaults to `receiverPubkeys.first` if null.
  ///
  /// [forcedTimestampSec] pins the Rumor's `created_at`. Used on retries so
  /// the resulting Rumor ID is stable across re-sends.
  static Future<List<Nip17Wrapped>> wrapMulti({
    required String plaintext,
    required String senderPrivkey,
    required String senderPubkey,
    required List<String> receiverPubkeys,
    String? rumorReceiverPubkey,
    String? replyToId,
    int? forcedTimestampSec,
  }) async {
    try {
      if (receiverPubkeys.isEmpty) {
        throw Exception('wrapMulti requires at least one receiver');
      }

      // 1. Build ONE Rumor — shared across all envelopes.
      final rumor = _buildRumor(
        plaintext: plaintext,
        senderPubkey: senderPubkey,
        receiverPubkey: rumorReceiverPubkey ?? receiverPubkeys.first,
        replyToId: replyToId,
        forcedTimestampSec: forcedTimestampSec,
      );
      final rumorId = rumor['id'] as String;
      final rumorTimestamp = rumor['created_at'] as int;

      // 2. For each recipient, build a Seal + Gift Wrap around the SAME Rumor.
      final results = <Nip17Wrapped>[];
      for (final receiverPubkey in receiverPubkeys) {
        final seal = await _buildSeal(
          rumor: rumor,
          senderPrivkey: senderPrivkey,
          senderPubkey: senderPubkey,
          receiverPubkey: receiverPubkey,
        );
        final giftWrap = await _buildGiftWrap(
          seal: seal,
          receiverPubkey: receiverPubkey,
        );
        results.add(Nip17Wrapped(
          giftWrap: giftWrap,
          giftWrapId: giftWrap['id'] as String,
          rumorId: rumorId,
          rumorTimestamp: rumorTimestamp,
        ));
      }
      return results;
    } catch (e) {
      throw Exception('NIP-17 wrapMulti failed: $e');
    }
  }

  /// Unwraps a received NIP-17 Gift Wrap event to recover the original plaintext.
  static Future<Nip17Result> unwrap({
    required Map<String, dynamic> giftWrapEvent,
    required String receiverPrivkey,
    required String receiverPubkey,
  }) async {
    try {
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

      if (seal['kind'] != kindSeal) {
        throw Exception(
          'Inner event kind ${seal['kind']} is not a valid Seal (expected $kindSeal)',
        );
      }

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

      if (rumor['kind'] != kindRumor) {
        throw Exception(
          'Innermost event kind ${rumor['kind']} is not a valid Rumor (expected $kindRumor)',
        );
      }

      // Extract rumor tags — used by the caller to detect reply ('e'),
      // recipient ('p'), and any custom tags.
      String? replyToId;
      String receiverPubkey = '';
      final rumorTags = <List<String>>[];
      final tags = rumor['tags'] as List? ?? [];
      for (final tag in tags) {
        if (tag is List) {
          rumorTags.add(tag.map((e) => e.toString()).toList());
          if (tag.length > 1) {
            if (tag[0] == 'e') {
              replyToId = tag[1].toString();
            } else if (tag[0] == 'p') {
              receiverPubkey = tag[1].toString();
            }
          }
        }
      }

      return Nip17Result(
        plaintext: rumor['content']?.toString() ?? '',
        senderPubkey: senderPubkey,
        receiverPubkey: receiverPubkey,
        timestamp: (rumor['created_at'] as int? ?? 0) * 1000,
        rumorId: rumor['id']?.toString() ?? '',
        replyToId: replyToId,
        rumorTags: rumorTags,
      );
    } catch (e) {
      throw Exception('NIP-17 unwrap failed: $e');
    }
  }

  static bool isGiftWrap(Map<String, dynamic> event) {
    return event['kind'] == kindGiftWrap;
  }

  // ---------------------------------------------------------------------------
  // Layer Builders
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _buildRumor({
    required String plaintext,
    required String senderPubkey,
    required String receiverPubkey,
    String? replyToId,
    int? forcedTimestampSec,
  }) {
    final List<List<String>> tags = [['p', receiverPubkey]];

    if (replyToId != null && replyToId.isNotEmpty) {
      tags.add(['e', replyToId]);
    }

    final unsignedRumor = {
      'pubkey': senderPubkey,
      'created_at': forcedTimestampSec ?? _realTimestamp(),
      'kind': kindRumor,
      'tags': tags,
      'content': plaintext,
    };

    final id = _computeEventId(unsignedRumor);
    return {...unsignedRumor, 'id': id};
  }

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
      'tags': <List<String>>[],
      'content': encryptedRumor,
    };

    final id = _computeEventId(unsignedSeal);
    final sig = NostrSigner.sign(id, senderPrivkey);

    return {...unsignedSeal, 'id': id, 'sig': sig};
  }

  static Future<Map<String, dynamic>> _buildGiftWrap({
    required Map<String, dynamic> seal,
    required String receiverPubkey,
  }) async {
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
      'tags': [
        ['p', receiverPubkey]
      ],
      'content': encryptedSeal,
    };

    final id = _computeEventId(unsignedGiftWrap);
    final sig = NostrSigner.sign(id, ephemeralPrivkey);

    return {...unsignedGiftWrap, 'id': id, 'sig': sig};
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

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

  static int _realTimestamp() {
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// Returns a randomised timestamp within the **past** 2 days.
  ///
  /// MUST be in the past — relays reject events whose `created_at` is more
  /// than ~15 minutes ahead of real time.
  static int _randomisedTimestamp() {
    const twoDaysInSeconds = 172800;
    final rng = Random.secure();
    final offset = rng.nextInt(twoDaysInSeconds);
    return _realTimestamp() - offset;
  }

  static _EphemeralKeypair _generateEphemeralKeypair() {
    final rng = Random.secure();
    final privkeyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    final privkeyHex = privkeyBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final pubkeyHex = bip340.getPublicKey(privkeyHex);

    return _EphemeralKeypair(privkey: privkeyHex, pubkey: pubkeyHex);
  }
}

// ---------------------------------------------------------------------------
// Result and Internal Data Classes
// ---------------------------------------------------------------------------

class Nip17Result {
  final String plaintext;
  final String senderPubkey;
  final String receiverPubkey;
  final int timestamp;
  final String rumorId;
  final String? replyToId;

  /// The full tag list from the inner Rumor. Useful for callers that need
  /// to inspect custom tags beyond `p` and `e`.
  final List<List<String>> rumorTags;

  const Nip17Result({
    required this.plaintext,
    required this.senderPubkey,
    required this.receiverPubkey,
    required this.timestamp,
    required this.rumorId,
    this.replyToId,
    this.rumorTags = const [],
  });
}

class Nip17Wrapped {
  final Map<String, dynamic> giftWrap;
  final String giftWrapId;
  final String rumorId;
  final int rumorTimestamp;

  const Nip17Wrapped({
    required this.giftWrap,
    required this.giftWrapId,
    required this.rumorId,
    required this.rumorTimestamp,
  });
}

class _EphemeralKeypair {
  final String privkey;
  final String pubkey;

  const _EphemeralKeypair({required this.privkey, required this.pubkey});
}