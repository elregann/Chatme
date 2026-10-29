// nip19_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/utils/key_utils.dart';

const _npub = 'npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg';
const _npubHex = '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';

const _nprofile =
    'nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p';
const _nprofileHex = '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';

const _pubkeyOnly = 'nprofile1qqs8ul5ug253hlh3n75jne0a5xmjur4urfxpzst88cnegg6ds6ka7nsz6vqwn';
const _unknownTlv =
    'nprofile1q5pszqsrqqs8ul5ug253hlh3n75jne0a5xmjur4urfxpzst88cnegg6ds6ka7nspzamhxue69uhhyetvv9ujuetcv9khqmr99e3k7mgc7dm4w';
const _lengthOverrun = 'nprofile1qqs8ul5ug253hlh3n75jne0a5xmjur4urfxpzst88cnegg6ds6ka7nspxfmhxue69uhkz9fnqle';
const _shortPubkey = 'nprofile1qq0hul5ug253hlh3n75jne0a5xmjur4urfxpzst88cnegg6ds6ka7tflntw';
const _noPubkey = 'nprofile1qythwumn8ghj7un9d3shjtn90psk6urvv5hxxmmdcxc3h6';

void main() {
  group('decodeNprofile', () {
    test('official NIP-19 vector', () {
      final profile = KeyUtils.decodeNprofile(_nprofile);
      expect(profile, isNotNull);
      expect(profile!.pubkey, _nprofileHex);
      expect(profile.relays, ['wss://r.x.com', 'wss://djbas.sadkb.com']);
    });

    test('pubkey only, no relays', () {
      final profile = KeyUtils.decodeNprofile(_pubkeyOnly);
      expect(profile!.pubkey, _npubHex);
      expect(profile.relays, isEmpty);
    });

    test('unknown TLV types are ignored', () {
      final profile = KeyUtils.decodeNprofile(_unknownTlv);
      expect(profile!.pubkey, _npubHex);
      expect(profile.relays, ['wss://relay.example.com']);
    });

    test('nostr: prefix and upper case are accepted', () {
      expect(KeyUtils.decodeNprofile('nostr:$_nprofile')!.pubkey, _nprofileHex);
      expect(KeyUtils.decodeNprofile('NOSTR:${_nprofile.toUpperCase()}')!.pubkey, _nprofileHex);
      expect(KeyUtils.decodeNprofile('  $_nprofile  ')!.pubkey, _nprofileHex);
    });

    test('broken input returns null', () {
      expect(KeyUtils.decodeNprofile(''), isNull);
      expect(KeyUtils.decodeNprofile(_npub), isNull);
      expect(KeyUtils.decodeNprofile('${_nprofile.substring(0, _nprofile.length - 1)}q'), isNull);
      expect(KeyUtils.decodeNprofile(_nprofile.substring(0, 60)), isNull);
      expect(KeyUtils.decodeNprofile(_lengthOverrun), isNull);
      expect(KeyUtils.decodeNprofile(_shortPubkey), isNull);
      expect(KeyUtils.decodeNprofile(_noPubkey), isNull);
    });
  });

  group('toNprofile', () {
    test('rebuilds the official NIP-19 vector', () {
      expect(
        KeyUtils.toNprofile(_nprofileHex, relays: ['wss://r.x.com', 'wss://djbas.sadkb.com']),
        _nprofile,
      );
    });

    test('pubkey only matches the vector without relays', () {
      expect(KeyUtils.toNprofile(_npubHex), _pubkeyOnly);
    });

    test('round trip keeps pubkey and relays', () {
      final text = KeyUtils.toNprofile(_npubHex, relays: ['wss://auth.nostr1.com', 'wss://nos.lol']);
      final profile = KeyUtils.decodeNprofile(text);
      expect(profile!.pubkey, _npubHex);
      expect(profile.relays, ['wss://auth.nostr1.com', 'wss://nos.lol']);
      expect(KeyUtils.normalizeToHex(text), _npubHex);
    });

    test('invalid pubkey is returned unchanged', () {
      expect(KeyUtils.toNprofile('abc'), 'abc');
      expect(KeyUtils.toNprofile('zz' * 32), 'zz' * 32);
    });
  });

  group('normalizeToHex', () {
    test('npub, nprofile and hex all give the pubkey hex', () {
      expect(KeyUtils.normalizeToHex(_npub), _npubHex);
      expect(KeyUtils.normalizeToHex(_nprofile), _nprofileHex);
      expect(KeyUtils.normalizeToHex(_npubHex), _npubHex);
    });

    test('nostr: prefix, spaces and upper case are accepted', () {
      expect(KeyUtils.normalizeToHex('nostr:$_npub'), _npubHex);
      expect(KeyUtils.normalizeToHex('nostr:$_nprofile'), _nprofileHex);
      expect(KeyUtils.normalizeToHex('  ${_npub.toUpperCase()}  '), _npubHex);
    });

    test('invalid input is not turned into a 64 character key', () {
      expect(KeyUtils.normalizeToHex('hello').length, isNot(64));
      expect(KeyUtils.normalizeToHex(_lengthOverrun).length, isNot(64));
      expect(KeyUtils.normalizeToHex(_noPubkey).length, isNot(64));
    });
  });
}
