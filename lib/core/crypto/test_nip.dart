// test_nip.dart

import 'package:hex/hex.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'nip44.dart';
import 'nip17.dart';
import 'crypto_utils.dart';

void main() async {
  print('\n========================================');
  print('NIP-17 & NIP-44 INTEGRATION TEST');
  print('========================================\n');

  // Generate keys
  final alicePriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final bobPub = bip340.getPublicKey(bobPriv);
  const testMessage = "Hello Bob, this is a secret message!";

  print('Alice Pubkey: ${alicePub.substring(0, 16)}...');
  print('Bob Pubkey:   ${bobPub.substring(0, 16)}...');
  print('Test Message: "$testMessage"\n');

  // TEST 1: NIP-44
  print('--- TEST 1: NIP-44 ---');
  try {
    final encrypted = await Nip44.encrypt(testMessage, alicePriv, bobPub);
    print('✓ Encrypted: ${encrypted.substring(0, 32)}...');
    final decrypted = await Nip44.decrypt(encrypted, bobPriv, alicePub);
    if (decrypted == testMessage) {
      print('✓ Decryption matches');
    } else {
      print('❌ Decryption mismatch');
      return;
    }
  } catch (e) {
    print('❌ NIP-44 failed: $e');
    return;
  }

  // TEST 2: NIP-17 wrap/unwrap
  print('\n--- TEST 2: NIP-17 Wrap/Unwrap ---');
  Map<String, dynamic> giftWrap;
  Nip17Result result;
  try {
    giftWrap = await Nip17.wrap(
      plaintext: testMessage,
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
    );
    print('✓ Gift Wrap created (kind ${giftWrap['kind']})');
    print('  Outer pubkey: ${giftWrap['pubkey'].substring(0, 16)}...');
    result = await Nip17.unwrap(
      giftWrapEvent: giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    print('✓ Unwrapped: "${result.plaintext}"');
    if (result.plaintext == testMessage && result.senderPubkey == alicePub) {
      print('✓ Content and sender verified');
    } else {
      print('❌ Unwrap verification failed');
      return;
    }
  } catch (e) {
    print('❌ NIP-17 wrap/unwrap failed: $e');
    return;
  }

  // TEST 3: Reply
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
      giftWrapEvent: replyWrap,
      receiverPrivkey: alicePriv,
      receiverPubkey: alicePub,
    );
    if (replyResult.replyToId == result.rumorId) {
      print('✓ Reply tracking OK (replyToId matches)');
    } else {
      print('❌ Reply tracking failed');
      return;
    }
  } catch (e) {
    print('❌ Reply test failed: $e');
    return;
  }

  // TEST 4: Wrong key
  print('\n--- TEST 4: Wrong key ---');
  final evePriv = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
  final evePub = bip340.getPublicKey(evePriv);
  try {
    await Nip17.unwrap(
      giftWrapEvent: giftWrap,
      receiverPrivkey: evePriv,
      receiverPubkey: evePub,
    );
    print('❌ Wrong key should have failed');
    return;
  } catch (e) {
    print('✓ Correctly rejected wrong key: ${e.toString().substring(0, 60)}...');
  }

  // TEST 5: Ephemeral uniqueness
  print('\n--- TEST 5: Ephemeral keys ---');
  final Set<String> outerKeys = {};
  for (int i = 0; i < 3; i++) {
    final w = await Nip17.wrap(
      plaintext: "Message $i",
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
    );
    outerKeys.add(w['pubkey'] as String);
  }
  if (outerKeys.length == 3) {
    print('✓ All 3 messages used different outer pubkeys');
  } else {
    print('❌ Ephemeral keys not unique');
    return;
  }

  print('\n========================================');
  print('✅ ALL TESTS PASSED');
  print('========================================');
}