// nip17_call_signal_test.dart

import 'dart:convert';
import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  final alicePriv = _key(1);
  final bobPriv = _key(2);
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPub = bip340.getPublicKey(bobPriv);

  test('call signal round trip keeps kind and the full signal payload', () async {
    final signal = {'type': 'offer', 'data': 'v=0\r\n' * 200};
    final wrapped = await Nip17.wrap(
      plaintext: jsonEncode(signal),
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      kind: Nip17.kindCallSignal,
      customTags: [
        ['p', bobPub],
      ],
    );
    final result = await Nip17.unwrap(
      giftWrapEvent: wrapped.giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    expect(result.rumorKind, 3330);
    expect(jsonDecode(result.plaintext), signal);
    expect(result.senderPubkey, alicePub);
    expect(result.receiverPubkey, bobPub);
  });
}