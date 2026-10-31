// contact_qr_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/utils/key_utils.dart';
import 'package:chatme/services/contact_qr.dart';

void main() {
  const pubkey = '7e7e9c42a91bfef19fa929e59fda7b3c4ba0d1c8f7c4c2f0e1d5b6a7c8d9e0f1';
  final other = 'a' * 64;
  const relays = ['wss://auth.nostr1.com', 'wss://nos.lol'];

  group('contactQrPayload', () {
    test('is a nostr: uri with an nprofile', () {
      expect(contactQrPayload(pubkey, relays: relays), startsWith('nostr:nprofile1'));
    });

    test('carries the pubkey and the relay hints', () {
      final payload = contactQrPayload(pubkey, relays: relays);
      final pointer = KeyUtils.decodeNprofile(payload)!;
      expect(pointer.pubkey, pubkey);
      expect(pointer.relays, relays);
    });

    test('keeps at most two relays so the code stays easy to scan', () {
      final payload = contactQrPayload(pubkey, relays: [...relays, 'wss://relay.damus.io']);
      expect(KeyUtils.decodeNprofile(payload)!.relays, relays);
    });

    test('works without relays', () {
      final payload = contactQrPayload(pubkey);
      expect(KeyUtils.decodeNprofile(payload)!.pubkey, pubkey);
    });
  });

  group('contactFromScan accepts', () {
    test('what we put in our own code', () {
      expect(contactFromScan(contactQrPayload(pubkey, relays: relays)), pubkey);
    });

    test('a bare nprofile', () {
      final bare = KeyUtils.toNprofile(pubkey, relays: relays);
      expect(contactFromScan(bare), pubkey);
    });

    test('an npub, with and without the nostr: prefix', () {
      final npub = KeyUtils.toNpub(pubkey);
      expect(contactFromScan(npub), pubkey);
      expect(contactFromScan('nostr:$npub'), pubkey);
    });

    test('a 64 character hex key in any case', () {
      expect(contactFromScan(pubkey), pubkey);
      expect(contactFromScan(other.toUpperCase()), other);
    });

    test('extra spaces and a prefix in capitals', () {
      expect(contactFromScan('  NOSTR:${KeyUtils.toNpub(pubkey)}  \n'), pubkey);
    });
  });

  group('contactFromScan rejects', () {
    test('empty and random text', () {
      expect(contactFromScan(''), isNull);
      expect(contactFromScan('hello world'), isNull);
      expect(contactFromScan('https://example.com/abc'), isNull);
    });

    test('hex of the wrong length', () {
      expect(contactFromScan('abcd'), isNull);
      expect(contactFromScan('a' * 63), isNull);
      expect(contactFromScan('a' * 65), isNull);
    });

    test('64 characters that are not hex', () {
      expect(contactFromScan('g' * 64), isNull);
    });

    test('a broken npub', () {
      final npub = KeyUtils.toNpub(pubkey);
      expect(contactFromScan('${npub.substring(0, npub.length - 3)}xyz'), isNull);
    });

    test('a secret key, so it never becomes a contact', () {
      final nsec = KeyUtils.toNsec(other);
      expect(contactFromScan(nsec), isNull);
      expect(contactFromScan('nostr:$nsec'), isNull);
    });
  });
}
