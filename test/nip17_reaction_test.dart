// nip17_reaction_test.dart

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  final alicePriv = _key(1);
  final bobPriv = _key(2);
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPub = bip340.getPublicKey(bobPriv);

  test('default wrap still produces a kind 14 rumor', () async {
    final wrapped = await Nip17.wrap(
      plaintext: 'hello',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
    );
    final result = await Nip17.unwrap(
      giftWrapEvent: wrapped.giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    expect(result.rumorKind, Nip17.kindRumor);
    expect(result.receiverPubkey, bobPub);
  });

  test('reaction to the peer message keeps kind, emoji and tags', () async {
    final wrapped = await Nip17.wrap(
      plaintext: '❤️',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      kind: Nip17.kindReaction,
      customTags: [
        ['e', 'abc'],
        ['p', bobPub],
        ['k', '14'],
      ],
    );
    final result = await Nip17.unwrap(
      giftWrapEvent: wrapped.giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    expect(result.rumorKind, Nip17.kindReaction);
    expect(result.plaintext, '❤️');
    expect(result.replyToId, 'abc');
    expect(result.senderPubkey, alicePub);
    expect(result.receiverPubkey, bobPub);
    expect(result.rumorTags, contains(equals(['k', '14'])));
  });

  test('reaction to my own message resolves the peer on both envelopes', () async {
    final multi = await Nip17.wrapMulti(
      plaintext: '👍',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkeys: [bobPub, alicePub],
      kind: Nip17.kindReaction,
      customTags: [
        ['e', 'abc'],
        ['p', alicePub],
        ['p', bobPub],
        ['k', '14'],
      ],
    );
    final forBob = await Nip17.unwrap(
      giftWrapEvent: multi[0].giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    final forAlice = await Nip17.unwrap(
      giftWrapEvent: multi[1].giftWrap,
      receiverPrivkey: alicePriv,
      receiverPubkey: alicePub,
    );
    expect(forBob.receiverPubkey, bobPub);
    expect(forAlice.senderPubkey, alicePub);
    expect(forAlice.receiverPubkey, bobPub);
    expect(forAlice.rumorId, forBob.rumorId);
  });

  test('unwrap rejects rumor kinds other than 14 and 7', () async {
    final wrapped = await Nip17.wrap(
      plaintext: 'nope',
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      kind: 1,
    );
    expect(
      Nip17.unwrap(
        giftWrapEvent: wrapped.giftWrap,
        receiverPrivkey: bobPriv,
        receiverPubkey: bobPub,
      ),
      throwsException,
    );
  });
}