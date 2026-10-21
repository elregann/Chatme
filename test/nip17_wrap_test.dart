// nip17_wrap_test.dart

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  final alicePriv = _key(1);
  final bobPriv = _key(2);

  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPub = bip340.getPublicKey(bobPriv);

  test('wrapMulti generates shared Rumor IDs for multi-envelopes', () async {
    final multi = await Nip17.wrapMulti(
      plaintext: 'multi-test',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkeys: [bobPub, alicePub],
      rumorReceiverPubkey: bobPub,
    );

    expect(multi.length, 2);
    expect(multi[0].rumorId, multi[1].rumorId);

    final result = await Nip17.unwrap(
      giftWrapEvent: multi[0].giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    expect(result.plaintext, 'multi-test');
  });

  test('forcedTimestampSec produces deterministic Rumor ID', () async {
    const pinnedTs = 1700000000;

    final a = await Nip17.wrap(
      plaintext: 'pinned',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      forcedTimestampSec: pinnedTs,
    );

    final b = await Nip17.wrap(
      plaintext: 'pinned',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      forcedTimestampSec: pinnedTs,
    );

    expect(a.rumorId, b.rumorId);
    expect(a.giftWrapId, isNot(b.giftWrapId));
  });
}