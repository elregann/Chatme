// nip17_unwrap_test.dart

import 'dart:convert';
import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17.dart';
import 'package:chatme/core/crypto/nip44.dart';
import 'package:chatme/core/crypto/nostr_protocol.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

Future<Map<String, dynamic>> _buildWrap({
  required String senderPriv,
  required String senderPub,
  required String rumorPub,
  required String receiverPub,
  bool tamperSealSig = false,
}) async {
  final unsignedRumor = <String, dynamic>{
    'pubkey': rumorPub,
    'created_at': 1700000000,
    'kind': Nip17.kindRumor,
    'tags': [
      ['p', receiverPub],
    ],
    'content': 'hello',
  };
  final rumor = {
    ...unsignedRumor,
    'id': NostrSigner.calculateEventId(unsignedRumor),
  };

  final unsignedSeal = <String, dynamic>{
    'pubkey': senderPub,
    'created_at': 1700000000,
    'kind': Nip17.kindSeal,
    'tags': <List<String>>[],
    'content': await Nip44.encrypt(jsonEncode(rumor), senderPriv, receiverPub),
  };
  final sealId = NostrSigner.calculateEventId(unsignedSeal);
  var sealSig = NostrSigner.sign(sealId, senderPriv);
  if (tamperSealSig) {
    final last = sealSig[sealSig.length - 1];
    sealSig = sealSig.substring(0, sealSig.length - 1) + (last == '0' ? '1' : '0');
  }
  final seal = {...unsignedSeal, 'id': sealId, 'sig': sealSig};

  final wrapPriv = _key(99);
  final unsignedWrap = <String, dynamic>{
    'pubkey': bip340.getPublicKey(wrapPriv),
    'created_at': 1700000000,
    'kind': Nip17.kindGiftWrap,
    'tags': [
      ['p', receiverPub],
    ],
    'content': await Nip44.encrypt(jsonEncode(seal), wrapPriv, receiverPub),
  };
  final wrapId = NostrSigner.calculateEventId(unsignedWrap);
  return {...unsignedWrap, 'id': wrapId, 'sig': NostrSigner.sign(wrapId, wrapPriv)};
}

void main() {
  final alicePriv = _key(1);
  final bobPriv = _key(2);
  final evePriv = _key(3);
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPub = bip340.getPublicKey(bobPriv);
  final evePub = bip340.getPublicKey(evePriv);

  test('wrap then unwrap returns the original message and sender', () async {
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
    expect(result.plaintext, 'hello');
    expect(result.senderPubkey, alicePub);
  });

  test('accepts a well formed gift wrap built by hand', () async {
    final event = await _buildWrap(
      senderPriv: alicePriv,
      senderPub: alicePub,
      rumorPub: alicePub,
      receiverPub: bobPub,
    );
    final result = await Nip17.unwrap(
      giftWrapEvent: event,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );
    expect(result.plaintext, 'hello');
  });

  test('rejects a rumor whose pubkey differs from the seal pubkey', () async {
    final event = await _buildWrap(
      senderPriv: alicePriv,
      senderPub: alicePub,
      rumorPub: evePub,
      receiverPub: bobPub,
    );
    await expectLater(
      Nip17.unwrap(
        giftWrapEvent: event,
        receiverPrivkey: bobPriv,
        receiverPubkey: bobPub,
      ),
      throwsException,
    );
  });

  test('rejects a seal with an invalid signature', () async {
    final event = await _buildWrap(
      senderPriv: alicePriv,
      senderPub: alicePub,
      rumorPub: alicePub,
      receiverPub: bobPub,
      tamperSealSig: true,
    );
    await expectLater(
      Nip17.unwrap(
        giftWrapEvent: event,
        receiverPrivkey: bobPriv,
        receiverPubkey: bobPub,
      ),
      throwsException,
    );
  });
}