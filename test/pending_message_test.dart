// pending_message_test.dart
//
// Contract tests for the ciphertext mailbox written by the FCM isolate and
// consumed by the main isolate. No plaintext is ever written here.

import 'dart:convert';
import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/core/crypto/nip17.dart';
import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  late Directory tempDir;

  final alicePriv = _key(1);
  final bobPriv = _key(2);
  final alicePub = bip340.getPublicKey(alicePriv);
  final bobPub = bip340.getPublicKey(bobPriv);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pending_message_test');
    BgInbox.baseDirectoryOverride = tempDir;
  });

  tearDown(() async {
    BgInbox.baseDirectoryOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<Nip17Wrapped> wrap(String text) => Nip17.wrap(
        plaintext: text,
        senderPrivkey: alicePriv,
        senderPubkey: alicePub,
        receiverPubkey: bobPub,
        forcedTimestampSec: 1700000000,
      );

  Future<File> writeRaw(String name, Object payload) async {
    final dir = Directory('${tempDir.path}/bg_inbox');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$name').writeAsString(jsonEncode(payload), flush: true);
  }

  group('BgInbox pending gift wraps', () {
    test('writes a valid payload and reads every field back', () async {
      final wrapped = await wrap('halo kapten');
      final ok = await BgInbox.writePendingMessage(
        eventId: wrapped.giftWrapId,
        ephemeralPubkey: wrapped.giftWrap['pubkey'] as String,
        ciphertext: wrapped.giftWrap['content'] as String,
        writtenAtMs: 1000,
      );

      expect(ok, isTrue);
      final items = await BgInbox.peekPendingMessages();
      expect(items, hasLength(1));
      expect(items.single.eventId, wrapped.giftWrapId);
      expect(items.single.ephemeralPubkey, wrapped.giftWrap['pubkey']);
      expect(items.single.ciphertext, wrapped.giftWrap['content']);
      expect(items.single.writtenAtMs, 1000);
      expect(
        items.single.file.path.endsWith('p_${wrapped.giftWrapId}.json'),
        isTrue,
      );
    });

    test('rejects traversal and malformed identifiers', () async {
      final wrapped = await wrap('x');
      final ephemeral = wrapped.giftWrap['pubkey'] as String;
      final ciphertext = wrapped.giftWrap['content'] as String;

      expect(
        await BgInbox.writePendingMessage(
          eventId: '../evil',
          ephemeralPubkey: ephemeral,
          ciphertext: ciphertext,
        ),
        isFalse,
      );
      expect(
        await BgInbox.writePendingMessage(
          eventId: wrapped.giftWrapId,
          ephemeralPubkey: 'not-a-pubkey',
          ciphertext: ciphertext,
        ),
        isFalse,
      );
      expect(
        await BgInbox.writePendingMessage(
          eventId: wrapped.giftWrapId,
          ephemeralPubkey: ephemeral,
          ciphertext: '',
        ),
        isFalse,
      );

      expect(await BgInbox.peekPendingMessages(), isEmpty);
    });

    test('a duplicate event id keeps only the first file', () async {
      final wrapped = await wrap('dup');
      Future<bool> writeAt(int ms) => BgInbox.writePendingMessage(
            eventId: wrapped.giftWrapId,
            ephemeralPubkey: wrapped.giftWrap['pubkey'] as String,
            ciphertext: wrapped.giftWrap['content'] as String,
            writtenAtMs: ms,
          );

      expect(await writeAt(1), isTrue);
      expect(await writeAt(2), isFalse);

      final items = await BgInbox.peekPendingMessages();
      expect(items, hasLength(1));
      expect(items.single.writtenAtMs, 1);
    });

    test('temporary files are ignored by the reader', () async {
      final wrapped = await wrap('temp');
      await writeRaw('tmp_p_${wrapped.giftWrapId}_abc.json', {
        'v': 1,
        'eventId': wrapped.giftWrapId,
        'ephemeralPubkey': wrapped.giftWrap['pubkey'],
        'ciphertext': wrapped.giftWrap['content'],
        'writtenAtMs': 1,
      });

      expect(await BgInbox.peekPendingMessages(), isEmpty);
    });

    test('malformed and oversized files are discarded on peek', () async {
      await writeRaw('p_bad.json', {'v': 1, 'eventId': 'x'});
      await writeRaw('p_huge.json', {
        'v': 1,
        'eventId': _key(9),
        'ephemeralPubkey': _key(10),
        'ciphertext': 'x' * (17 * 1024),
        'writtenAtMs': 1,
      });

      expect(await BgInbox.peekPendingMessages(), isEmpty);
      expect(await File('${tempDir.path}/bg_inbox/p_bad.json').exists(), isFalse);
      expect(await File('${tempDir.path}/bg_inbox/p_huge.json').exists(), isFalse);
    });

    test('returns structurally valid entries oldest first', () async {
      final wrapped = await wrap('order');
      await BgInbox.writePendingMessage(
        eventId: wrapped.giftWrapId,
        ephemeralPubkey: wrapped.giftWrap['pubkey'] as String,
        ciphertext: wrapped.giftWrap['content'] as String,
        writtenAtMs: 2000,
      );
      final olderId = _key(77);
      await BgInbox.writePendingMessage(
        eventId: olderId,
        ephemeralPubkey: wrapped.giftWrap['pubkey'] as String,
        ciphertext: wrapped.giftWrap['content'] as String,
        writtenAtMs: 1000,
      );

      final items = await BgInbox.peekPendingMessages();
      expect(items.map((e) => e.eventId), [olderId, wrapped.giftWrapId]);
    });

    test('consume deletes only the consumed file', () async {
      final wrapped = await wrap('consume');
      await BgInbox.writePendingMessage(
        eventId: wrapped.giftWrapId,
        ephemeralPubkey: wrapped.giftWrap['pubkey'] as String,
        ciphertext: wrapped.giftWrap['content'] as String,
      );
      final items = await BgInbox.peekPendingMessages();

      await BgInbox.consumePendingMessage(items.single.file);

      expect(await BgInbox.peekPendingMessages(), isEmpty);
    });

    test('prunes to the newest 50 files', () async {
      final wrapped = await wrap('prune');
      final ephemeral = wrapped.giftWrap['pubkey'] as String;
      final ciphertext = wrapped.giftWrap['content'] as String;

      for (var i = 0; i < 55; i++) {
        await BgInbox.writePendingMessage(
          eventId: _key(100 + i),
          ephemeralPubkey: ephemeral,
          ciphertext: ciphertext,
          writtenAtMs: i,
        );
      }

      final items = await BgInbox.peekPendingMessages();
      expect(items, hasLength(50));
      expect(items.first.eventId, _key(105));
      expect(items.last.eventId, _key(154));
    });

    test('peeked ciphertext still unwraps to the verified message', () async {
      final wrapped = await wrap('verify me');
      await BgInbox.writePendingMessage(
        eventId: wrapped.giftWrapId,
        ephemeralPubkey: wrapped.giftWrap['pubkey'] as String,
        ciphertext: wrapped.giftWrap['content'] as String,
      );
      final item = (await BgInbox.peekPendingMessages()).single;

      final result = await Nip17.unwrap(
        giftWrapEvent: {
          'pubkey': item.ephemeralPubkey,
          'content': item.ciphertext,
          'kind': 1059,
        },
        receiverPrivkey: bobPriv,
        receiverPubkey: bobPub,
      );

      expect(result.plaintext, 'verify me');
      expect(result.senderPubkey, alicePub);
      expect(result.rumorId, wrapped.rumorId);
      expect(result.timestamp, 1700000000 * 1000);
    });
  });
}
