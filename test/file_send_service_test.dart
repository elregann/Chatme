// file_send_service_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/core/crypto/nip17_file.dart';
import 'package:chatme/services/blossom_service.dart';
import 'package:chatme/services/file_send_service.dart';

void main() {
  const privkey = '0000000000000000000000000000000000000000000000000000000000000003';
  final pubkey = bip340.getPublicKey(privkey);

  late Directory dir;
  late File recorded;
  late Uint8List plain;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chatme_send_test');
    plain = Uint8List.fromList(utf8.encode('pretend this is a recorded voice note'));
    recorded = File('${dir.path}/rec.m4a')..writeAsBytesSync(plain);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  http.Response stored200(http.Request request, {String urlScheme = 'https'}) {
    final hash = FileCrypto.sha256Hex(request.bodyBytes);
    return http.Response(
      jsonEncode({
        'url': '$urlScheme://files.example/$hash.bin',
        'sha256': hash,
        'size': request.bodyBytes.length,
        'type': 'application/octet-stream',
        'uploaded': 1700000000,
      }),
      200,
    );
  }

  MockClient storingServer({String urlScheme = 'https', List<Uint8List>? stored}) {
    return MockClient((request) async {
      stored?.add(request.bodyBytes);
      return stored200(request, urlScheme: urlScheme);
    });
  }

  group('encryptAndUpload', () {
    test('uploads an encrypted copy that the receiver can open', () async {
      final stored = <Uint8List>[];

      final file = await FileSendService.encryptAndUpload(
        source: recorded,
        mimeType: 'audio/mp4',
        durationSeconds: 9,
        pubkey: pubkey,
        privkey: privkey,
        servers: ['https://files.example'],
        client: storingServer(stored: stored),
      );

      expect(stored, hasLength(1));
      expect(stored.single, isNot(plain));

      final opened = FileCrypto.decrypt(
        stored.single,
        key: file.key,
        nonce: file.nonce,
        hash: file.hash,
        originalHash: file.originalHash,
      );
      expect(opened, plain);

      expect(file.url, startsWith('https://files.example/'));
      expect(file.mimeType, 'audio/mp4');
      expect(file.durationSeconds, 9);
      expect(file.size, stored.single.length);
      expect(file.isAudio, isTrue);
    });

    test('every upload uses a fresh key', () async {
      Future<FileMessage> run() => FileSendService.encryptAndUpload(
            source: recorded,
            mimeType: 'audio/mp4',
            pubkey: pubkey,
            privkey: privkey,
            servers: ['https://files.example'],
            client: storingServer(),
          );

      final a = await run();
      final b = await run();

      expect(a.key, isNot(b.key));
      expect(a.nonce, isNot(b.nonce));
    });

    test('moves on to the next server when the first refuses', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.host == 'first.example') return http.Response('', 415);
        return stored200(request);
      });

      final file = await FileSendService.encryptAndUpload(
        source: recorded,
        mimeType: 'audio/mp4',
        pubkey: pubkey,
        privkey: privkey,
        servers: ['https://first.example', 'https://second.example'],
        client: client,
      );

      expect(hosts, ['first.example', 'second.example']);
      expect(file.url, startsWith('https://files.example/'));
    });

    test('fails when every server refuses', () async {
      final client = MockClient((_) async => http.Response('', 403));

      await expectLater(
        FileSendService.encryptAndUpload(
          source: recorded,
          mimeType: 'audio/mp4',
          pubkey: pubkey,
          privkey: privkey,
          servers: ['https://first.example'],
          client: client,
        ),
        throwsA(isA<BlossomException>()),
      );
    });

    test('an address that is not https is refused', () async {
      await expectLater(
        FileSendService.encryptAndUpload(
          source: recorded,
          mimeType: 'audio/mp4',
          pubkey: pubkey,
          privkey: privkey,
          servers: ['https://files.example'],
          client: storingServer(urlScheme: 'http'),
        ),
        throwsA(isA<BlossomException>()),
      );
    });
  });

  group('moveIntoFolder', () {
    test('moves the file and creates the folder', () async {
      final target = Directory('${dir.path}/voice');

      final moved = await FileSendService.moveIntoFolder(recorded, target, 'out_1.m4a');

      expect(moved.path, endsWith('out_1.m4a'));
      expect(moved.readAsBytesSync(), plain);
      expect(recorded.existsSync(), isFalse);
    });
  });
}
