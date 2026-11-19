// push_signature_test.dart

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/core/crypto/nostr_protocol.dart';
import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final privkey = _key(1);
  final myPubkey = bip340.getPublicKey(privkey);
  const receiverPubkey = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const eventId = 'gw_test';
  final ts = DateTime.now().millisecondsSinceEpoch;

  setUp(() {
    AppSettings.instance.myPrivkey = privkey;
    AppSettings.instance.myPubkey = myPubkey;
  });

  test('push headers carry a signature bound to the exact payload', () {
    final headers = RelayManager().buildPushHeaders(
      receiverPubkey: receiverPubkey,
      senderPubkey: myPubkey,
      eventId: eventId,
      timestampMs: ts,
    );

    expect(headers.containsKey('X-Secret-Key'), isFalse);
    expect(headers['X-Nostr-Pubkey'], myPubkey);
    expect(headers['X-Nostr-Ts'], '$ts');

    final canonical = ['chatme-push-v1', receiverPubkey, myPubkey, eventId, ts].join('|');
    final challenge = sha256.convert(canonical.codeUnits).toString();
    expect(
      NostrSigner.verify(challenge, headers['X-Nostr-Sig'] ?? '', myPubkey),
      isTrue,
    );

    final tampered = ['chatme-push-v1', receiverPubkey, myPubkey, 'gw_other', ts].join('|');
    final tamperedChallenge = sha256.convert(tampered.codeUnits).toString();
    expect(
      NostrSigner.verify(tamperedChallenge, headers['X-Nostr-Sig'] ?? '', myPubkey),
      isFalse,
    );
  });
}
