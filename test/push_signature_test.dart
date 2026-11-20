// push_signature_test.dart

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/core/crypto/nostr_protocol.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final privkey = _key(1);
  final myPubkey = bip340.getPublicKey(privkey);
  const receiverPubkey = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const eventId = 'gw_test';
  final ts = DateTime.now().millisecondsSinceEpoch;
  const body = '{"receiverPubkey":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
      '"senderPubkey":"sender","eventId":"gw_test","senderName":"Chatme","ciphertext":"","ephemeralPubkey":"","type":"call"}';

  setUp(() {
    AppSettings.instance.myPrivkey = privkey;
    AppSettings.instance.myPubkey = myPubkey;
  });

  String challengeFor(String protocol, String bodyHash, String id) =>
      sha256.convert(utf8.encode(
        [protocol, receiverPubkey, myPubkey, id, ts, bodyHash].join('|'),
      )).toString();

  String legacyChallenge(String id) => sha256.convert(utf8.encode(
        ['chatme-push-v1', receiverPubkey, myPubkey, id, ts].join('|'),
      )).toString();

  test('push headers carry a signature bound to the exact request body', () {
    final headers = RelayManager().buildPushHeaders(
      receiverPubkey: receiverPubkey,
      senderPubkey: myPubkey,
      eventId: eventId,
      timestampMs: ts,
      body: body,
    );

    expect(headers.containsKey('X-Secret-Key'), isFalse);
    expect(headers['X-Nostr-Pubkey'], myPubkey);
    expect(headers['X-Nostr-Ts'], '$ts');

    final bodyHash = sha256.convert(utf8.encode(body)).toString();
    expect(
      NostrSigner.verify(
        challengeFor('chatme-push-v2', bodyHash, eventId),
        headers['X-Nostr-Sig'] ?? '',
        myPubkey,
      ),
      isTrue,
    );
  });

  test('signature rejects a changed event id or a changed body', () {
    final headers = RelayManager().buildPushHeaders(
      receiverPubkey: receiverPubkey,
      senderPubkey: myPubkey,
      eventId: eventId,
      timestampMs: ts,
      body: body,
    );
    final signature = headers['X-Nostr-Sig'] ?? '';
    final bodyHash = sha256.convert(utf8.encode(body)).toString();

    expect(
      NostrSigner.verify(
        challengeFor('chatme-push-v2', bodyHash, 'gw_other'),
        signature,
        myPubkey,
      ),
      isFalse,
    );

    final changedBody = body.replaceFirst('"type":"call"', '"type":"chat"');
    final changedHash = sha256.convert(utf8.encode(changedBody)).toString();
    expect(
      NostrSigner.verify(
        challengeFor('chatme-push-v2', changedHash, eventId),
        signature,
        myPubkey,
      ),
      isFalse,
    );

    // The old protocol is rejected even when the body is untouched.
    expect(
      NostrSigner.verify(
        legacyChallenge(eventId),
        signature,
        myPubkey,
      ),
      isFalse,
    );
  });
}
