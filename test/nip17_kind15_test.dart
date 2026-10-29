// nip17_kind15_test.dart

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17.dart';
import 'package:chatme/core/crypto/nip17_file.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  final alicePriv = _key(1);
  final bobPriv = _key(2);
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPub = bip340.getPublicKey(bobPriv);

  final file = FileMessage(
    url: 'https://blossom.example/${'c' * 64}.bin',
    mimeType: 'audio/mp4',
    key: 'a' * 64,
    nonce: 'b' * 32,
    hash: 'c' * 64,
    originalHash: 'd' * 64,
    size: 4096,
    durationSeconds: 12,
  );

  test('a kind 15 file message round trips through the gift wrap', () async {
    final wrapped = await Nip17.wrap(
      plaintext: file.url,
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkey: bobPub,
      kind: Nip17.kindFile,
      customTags: [
        ['p', bobPub],
        ...file.toTags(),
      ],
    );

    final result = await Nip17.unwrap(
      giftWrapEvent: wrapped.giftWrap,
      receiverPrivkey: bobPriv,
      receiverPubkey: bobPub,
    );

    expect(result.rumorKind, Nip17.kindFile);
    expect(result.senderPubkey, alicePub);
    expect(result.receiverPubkey, bobPub);

    final parsed = FileMessage.parse(content: result.plaintext, tags: result.rumorTags)!;
    expect(parsed.url, file.url);
    expect(parsed.key, file.key);
    expect(parsed.nonce, file.nonce);
    expect(parsed.hash, file.hash);
    expect(parsed.originalHash, file.originalHash);
    expect(parsed.durationSeconds, 12);
    expect(parsed.isAudio, isTrue);
  });

  test('the self copy of a file message is readable by the sender', () async {
    final wrapped = await Nip17.wrapMulti(
      plaintext: file.url,
      senderPrivkey: alicePriv,
      senderPubkey: alicePub,
      receiverPubkeys: [bobPub, alicePub],
      rumorReceiverPubkey: bobPub,
      kind: Nip17.kindFile,
      customTags: [
        ['p', bobPub],
        ...file.toTags(),
      ],
    );

    final mine = await Nip17.unwrap(
      giftWrapEvent: wrapped[1].giftWrap,
      receiverPrivkey: alicePriv,
      receiverPubkey: alicePub,
    );

    expect(mine.rumorKind, Nip17.kindFile);
    expect(mine.rumorId, wrapped[0].rumorId);
    expect(FileMessage.parse(content: mine.plaintext, tags: mine.rumorTags), isNotNull);
  });
}
