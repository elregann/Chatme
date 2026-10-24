// nip17_read_receipt_test.dart

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  final alicePriv = _key(1);
  final bobPriv = _key(2);
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPub = bip340.getPublicKey(bobPriv);

  test('read receipt round trip keeps kind, status and target id', () async {
    final wrapped = await Nip17.wrap(
      plaintext: 'read',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      kind: Nip17.kindReadReceipt,
      customTags: [
        ['e', 'abc'],
        ['p', bobPub],
      ],
    );
    final result = await Nip17.unwrap(
      giftWrapEvent: wrapped.giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    expect(result.rumorKind, 3329);
    expect(result.plaintext, 'read');
    expect(result.replyToId, 'abc');
    expect(result.senderPubkey, alicePub);
    expect(result.receiverPubkey, bobPub);
  });
}