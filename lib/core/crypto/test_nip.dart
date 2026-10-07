// test_nip.dart
//
// Standalone integration test for NIP-17 / NIP-44.
// Run with:  dart run lib/core/crypto/test_nip.dart
//
// Or (recommended) move this file to `tool/test_nip.dart` and run from there.

import 'package:hex/hex.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'nip44.dart';
import 'nip17.dart';
import 'crypto_utils.dart';

void main() async {
  print('\n========================================');
  print('NIP-17 & NIP-44 INTEGRATION TEST');
  print('========================================\n');

  // ---------------------------------------------------------------
  // Key generation
  // ---------------------------------------------------------------
  final alicePriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final bobPub = bip340.getPublicKey(bobPriv);

  const testMessage = "Hello Bob, this is a secret message!";

  print('Alice Pubkey: ${alicePub.substring(0, 16)}...');
  print('Bob Pubkey:   ${bobPub.substring(0, 16)}...');
  print('Test Message: "$testMessage"\n');

  // ---------------------------------------------------------------
  // TEST 1 — NIP-44 encrypt / decrypt
  // ---------------------------------------------------------------
  print('--- TEST 1: NIP-44 ---');
  try {
    final encrypted = await Nip44.encrypt(testMessage, alicePriv, bobPub);
    print('OK  Encrypted: ${encrypted.substring(0, 32)}...');

    final decrypted = await Nip44.decrypt(encrypted, bobPriv, alicePub);
    if (decrypted == testMessage) {
      print('OK  Decryption matches');
    } else {
      print('FAIL  Decryption mismatch');
      return;
    }
  } catch (e) {
    print('FAIL  NIP-44: $e');
    return;
  }

  // ---------------------------------------------------------------
  // TEST 2 — NIP-17 wrap / unwrap (single recipient)
  // ---------------------------------------------------------------
  print('\n--- TEST 2: NIP-17 Wrap / Unwrap ---');
  Nip17Wrapped wrapped;
  Nip17Result result;
  try {
    wrapped = await Nip17.wrap(
      plaintext: testMessage,
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
    );
    print('OK  Gift Wrap created (kind ${wrapped.giftWrap['kind']})');
    print('    Outer pubkey  : ${(wrapped.giftWrap['pubkey'] as String).substring(0, 16)}...');
    print('    Gift Wrap ID  : ${wrapped.giftWrapId.substring(0, 16)}...');
    print('    Rumor ID      : ${wrapped.rumorId.substring(0, 16)}...');

    result = await Nip17.unwrap(
      giftWrapEvent: wrapped.giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    print('OK  Unwrapped: "${result.plaintext}"');

    if (result.plaintext == testMessage &&
        result.senderPubkey == alicePub &&
        result.rumorId == wrapped.rumorId) {
      print('OK  Content, sender, and rumor ID verified');
    } else {
      print('FAIL  Unwrap verification failed');
      return;
    }
  } catch (e) {
    print('FAIL  NIP-17 wrap/unwrap: $e');
    return;
  }

  // ---------------------------------------------------------------
  // TEST 3 — Reply tracking (reply tag survives NIP-17 wrapping)
  // ---------------------------------------------------------------
  print('\n--- TEST 3: Reply ---');
  try {
    final replyWrap = await Nip17.wrap(
      plaintext: "Thanks Alice!",
      senderPrivkey: bobPriv,
      senderPubkey: bobPub,
      receiverPubkey: alicePub,
      replyToId: result.rumorId,
    );
    final replyResult = await Nip17.unwrap(
      giftWrapEvent: replyWrap.giftWrap,
      receiverPrivkey: alicePriv,
      receiverPubkey: alicePub,
    );
    if (replyResult.replyToId == result.rumorId) {
      print('OK  Reply tracking works (replyToId = ${result.rumorId.substring(0, 16)}...)');
    } else {
      print('FAIL  Reply tracking broken');
      return;
    }
  } catch (e) {
    print('FAIL  Reply test: $e');
    return;
  }

  // ---------------------------------------------------------------
  // TEST 4 — wrapMulti: shared Rumor across recipient + self envelopes
  // ---------------------------------------------------------------
  print('\n--- TEST 4: wrapMulti (shared Rumor) ---');
  try {
    final multi = await Nip17.wrapMulti(
      plaintext: "Multi-envelope test",
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkeys: [bobPub, alicePub],  // recipient + self
      rumorReceiverPubkey: bobPub,
    );

    if (multi.length != 2) {
      print('FAIL  Expected 2 envelopes, got ${multi.length}');
      return;
    }

    // Both envelopes MUST share the same Rumor ID
    if (multi[0].rumorId != multi[1].rumorId) {
      print('FAIL  Rumor IDs differ between envelopes');
      return;
    }
    print('OK  Both envelopes share Rumor ID: ${multi[0].rumorId.substring(0, 16)}...');

    // Recipient can unwrap the first envelope
    final bobResult = await Nip17.unwrap(
      giftWrapEvent: multi[0].giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    print('OK  Bob unwrapped: "${bobResult.plaintext}"');
    print('    Bob sees receiver p tag: ${bobResult.receiverPubkey.substring(0, 16)}...');

    // Sender's other device can unwrap the self envelope
    final selfResult = await Nip17.unwrap(
      giftWrapEvent: multi[1].giftWrap,
      receiverPrivkey: alicePriv,
      receiverPubkey: alicePub,
    );
    print('OK  Self envelope unwrapped: "${selfResult.plaintext}"');
    print('    Self envelope p tag (should be Bob): ${selfResult.receiverPubkey.substring(0, 16)}...');

    if (selfResult.receiverPubkey != bobPub) {
      print('FAIL  Self envelope should reference Bob in p tag');
      return;
    }
  } catch (e) {
    print('FAIL  wrapMulti test: $e');
    return;
  }

  // ---------------------------------------------------------------
  // TEST 5 — forcedTimestampSec produces deterministic Rumor ID
  // ---------------------------------------------------------------
  print('\n--- TEST 5: Deterministic Rumor ID ---');
  try {
    const pinnedTs = 1700000000; // arbitrary fixed timestamp

    final a = await Nip17.wrap(
      plaintext: "pinned",
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      forcedTimestampSec: pinnedTs,
    );
    final b = await Nip17.wrap(
      plaintext: "pinned",
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      forcedTimestampSec: pinnedTs,
    );

    if (a.rumorId == b.rumorId) {
      print('OK  Same plaintext + same timestamp = same Rumor ID');
      print('    Rumor ID: ${a.rumorId.substring(0, 16)}...');
    } else {
      print('FAIL  Rumor ID is not deterministic');
      return;
    }

    // Gift Wrap IDs should still differ (fresh ephemeral key each time)
    if (a.giftWrapId != b.giftWrapId) {
      print('OK  Gift Wrap IDs differ (fresh ephemeral key)');
    } else {
      print('FAIL  Gift Wrap IDs should be unique');
      return;
    }
  } catch (e) {
    print('FAIL  Deterministic test: $e');
    return;
  }

  // ---------------------------------------------------------------
  // TEST 6 — Wrong key must be rejected
  // ---------------------------------------------------------------
  print('\n--- TEST 6: Wrong key ---');
  final evePriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final evePub = bip340.getPublicKey(evePriv);
  try {
    await Nip17.unwrap(
      giftWrapEvent: wrapped.giftWrap,
      receiverPrivkey: evePriv,
      receiverPubkey: evePub,
    );
    print('FAIL  Wrong key should have failed');
    return;
  } catch (e) {
    print('OK  Wrong key correctly rejected');
  }

  // ---------------------------------------------------------------
  // TEST 7 — Ephemeral key uniqueness
  // ---------------------------------------------------------------
  print('\n--- TEST 7: Ephemeral keys ---');
  final Set<String> outerKeys = {};
  for (int i = 0; i < 3; i++) {
    final w = await Nip17.wrap(
      plaintext: "Message $i",
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
    );
    outerKeys.add(w.giftWrap['pubkey'] as String);
  }
  if (outerKeys.length == 3) {
    print('OK  All 3 messages used different outer pubkeys');
  } else {
    print('FAIL  Ephemeral keys not unique');
    return;
  }

  // ---------------------------------------------------------------
  print('\n========================================');
  print('ALL TESTS PASSED');
  print('========================================\n');
}