// blossom_service_test.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/core/crypto/nostr_protocol.dart';
import 'package:chatme/services/blossom_service.dart';

void main() {
  const privkey = '0000000000000000000000000000000000000000000000000000000000000003';
  final pubkey = bip340.getPublicKey(privkey);
  final bytes = Uint8List.fromList(List<int>.generate(300, (i) => i % 256));
  final hash = FileCrypto.sha256Hex(bytes);

  String descriptor({String? sha, int? size}) => jsonEncode({
    'url': 'https://blossom.example/$hash',
    'sha256': sha ?? hash,
    'size': size ?? bytes.length,
    'type': 'application/octet-stream',
    'uploaded': 1700000000,
  });

  group('auth event', () {
    test('has the upload tags and a valid signature', () {
      final event = BlossomService.buildAuthEvent(
        pubkey: pubkey,
        privkey: privkey,
        hash: hash,
        content: 'Upload voice note',
        now: 1700000000,
      );

      expect(event['kind'], 24242);
      expect(event['pubkey'], pubkey);
      expect(event['created_at'], 1699999990);
      expect(event['content'], 'Upload voice note');
      expect(event['tags'], [
        ['t', 'upload'],
        ['x', hash],
        ['expiration', '1700000300'],
      ]);

      final id = NostrSigner.calculateEventId(event);
      expect(event['id'], id);
      expect(NostrSigner.verify(id, event['sig'], pubkey), isTrue);
    });

    test('the header is Nostr plus the base64 event', () {
      final event = BlossomService.buildAuthEvent(
        pubkey: pubkey,
        privkey: privkey,
        hash: hash,
        now: 1700000000,
      );
      final header = BlossomService.authHeader(event);

      expect(header.startsWith('Nostr '), isTrue);
      final decoded = jsonDecode(utf8.decode(base64.decode(header.substring(6))));
      expect(decoded['id'], event['id']);
      expect(decoded['sig'], event['sig']);
    });
  });

  group('delete', () {
    final key = (privkey: privkey, pubkey: pubkey);

    String decodeHeader(String header) {
      final encoded = header.substring(6);
      return utf8.decode(base64Url.decode(encoded.padRight(
            (encoded.length + 3) ~/ 4 * 4,
            '=',
          )));
    }

    test('generateUploadKey makes a valid signing key', () {
      final generated = BlossomService.generateUploadKey();

      expect(generated.privkey, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(generated.pubkey, bip340.getPublicKey(generated.privkey));
    });

    test('buildDeleteAuthEvent limits the token to one action, hash and server',
        () {
      final event = BlossomService.buildDeleteAuthEvent(
        pubkey: pubkey,
        privkey: privkey,
        hash: hash.toUpperCase(),
        server: 'https://files.example/base',
        content: 'Delete old blobs',
        now: 1700000000,
      );

      expect(event['kind'], 24242);
      expect(event['content'], 'Delete old blobs');
      expect(event['created_at'], 1699999990);
      expect(event['tags'], [
        ['t', 'delete'],
        ['x', hash],
        ['server', 'files.example'],
        ['expiration', '1700000300'],
      ]);

      final id = NostrSigner.calculateEventId(event);
      expect(event['id'], id);
      expect(NostrSigner.verify(id, event['sig'], pubkey), isTrue);
    });

    test('delete header is unpadded base64url', () {
      final event = BlossomService.buildDeleteAuthEvent(
        pubkey: pubkey,
        privkey: privkey,
        hash: hash,
        server: 'https://files.example',
        now: 1700000000,
      );

      final header = BlossomService.deleteAuthHeader(event);
      final encoded = header.substring(6);

      expect(header, startsWith('Nostr '));
      expect(encoded, isNot(contains('=')));
      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
      expect(jsonDecode(decodeHeader(header))['id'], event['id']);
    });

    test('deletes the exact blob from the server in its url', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('', 204);
      });

      await BlossomService.delete(
        'https://files.example/$hash.enc',
        hash: hash,
        key: key,
        client: client,
      );

      expect(seen.method, 'DELETE');
      expect(seen.url.toString(), 'https://files.example/$hash');
      expect(seen.headers['User-Agent'], startsWith('Chatme'));

      final event = jsonDecode(decodeHeader(seen.headers['Authorization']!))
          as Map<String, dynamic>;
      expect(event['pubkey'], pubkey);
      expect(
            (event['tags'] as List).any(
              (t) => t[0] == 't' && t[1] == 'delete',
            ),
        isTrue,
      );
      expect(
            (event['tags'] as List).any(
              (t) => t[0] == 'x' && t[1] == hash,
            ),
        isTrue,
      );
      expect(
            (event['tags'] as List).any(
              (t) => t[0] == 'server' && t[1] == 'files.example',
            ),
        isTrue,
      );
      expect(NostrSigner.verify(event['id'], event['sig'], pubkey), isTrue);
    });

    test('a rejected delete becomes a BlossomException with the reason',
        () async {
      final client = MockClient(
            (_) async => http.Response('', 403, headers: {'x-reason': 'not owner'}),
      );

      await expectLater(
        BlossomService.delete(
          'https://files.example/$hash.enc',
          hash: hash,
          key: key,
          client: client,
        ),
        throwsA(
          isA<BlossomException>().having(
                (e) => e.message,
            'message',
            allOf(contains('403'), contains('not owner')),
          ),
        ),
      );
    });

    test('a bad hash or address is refused before any request', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 204);
      });

      for (final bad in ['http://files.example/$hash', 'not a url', '']) {
        await expectLater(
          BlossomService.delete(bad, hash: hash, key: key, client: client),
          throwsA(isA<BlossomException>()),
        );
      }
      for (final badHash in ['abc', 'z' * 64]) {
        await expectLater(
          BlossomService.delete(
            'https://files.example/$hash.enc',
            hash: badHash,
            key: key,
            client: client,
          ),
          throwsA(isA<BlossomException>()),
        );
      }
      expect(calls, 0);
    });
  });

  group('upload key', () {
    Map<String, dynamic> authEventOf(http.Request request) {
      final encoded = request.headers['Authorization']!.substring(6);
      return jsonDecode(utf8.decode(base64.decode(encoded))) as Map<String, dynamic>;
    }

    test('the upload is signed with a valid key made for it', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(descriptor(), 200);
      });
      await BlossomService.upload(bytes, client: client);

      final event = authEventOf(seen);
      expect(event['kind'], 24242);
      expect(event['pubkey'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(event['id'], NostrSigner.calculateEventId(event));
      expect(NostrSigner.verify(event['id'], event['sig'], event['pubkey']), isTrue);
    });

    test('two uploads never share a key', () async {
      final keys = <String>[];
      final client = MockClient((request) async {
        keys.add(authEventOf(request)['pubkey'] as String);
        return http.Response(descriptor(), 200);
      });
      await BlossomService.upload(bytes, client: client);
      await BlossomService.upload(bytes, client: client);

      expect(keys, hasLength(2));
      expect(keys[0], isNot(keys[1]));
    });

    test('every server that is tried gets its own key', () async {
      final keys = <String>[];
      final client = MockClient((request) async {
        keys.add(authEventOf(request)['pubkey'] as String);
        if (request.url.host == 'first.example') return http.Response('', 415);
        return http.Response(descriptor(), 200);
      });
      await BlossomService.uploadToAny(
        bytes,
        servers: ['https://first.example', 'https://second.example'],
        client: client,
      );

      expect(keys, hasLength(2));
      expect(keys[0], isNot(keys[1]));
    });
  });

  group('upload', () {
    test('sends a PUT to /upload and returns the descriptor', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(descriptor(), 200);
      });

      final blob = await BlossomService.upload(
        bytes,
        server: 'https://blossom.example/',
        client: client,
      );

      expect(seen.method, 'PUT');
      expect(seen.url.toString(), 'https://blossom.example/upload');
      expect(seen.headers['Content-Type'], startsWith('application/octet-stream'));
      expect(seen.headers['X-SHA-256'], hash);
      expect(seen.headers['Authorization'], startsWith('Nostr '));
      expect(seen.bodyBytes, bytes);

      expect(blob.url, 'https://blossom.example/$hash');
      expect(blob.sha256, hash);
      expect(blob.size, bytes.length);
    });

    test('the auth event in the request covers the file hash', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(descriptor(), 200);
      });
      await BlossomService.upload(bytes, client: client);

      final encoded = seen.headers['Authorization']!.substring(6);
      final event = jsonDecode(utf8.decode(base64.decode(encoded)));
      expect((event['tags'] as List).any((t) => t[0] == 'x' && t[1] == hash), isTrue);
    });

    test('sends a User-Agent, some servers refuse the default one', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(descriptor(), 200);
      });
      await BlossomService.upload(bytes, client: client);
      expect(seen.headers['User-Agent'], startsWith('Chatme'));
    });

    test('a server that stored another file is rejected', () async {
      final client = MockClient((_) async => http.Response(descriptor(sha: 'a' * 64), 200));
      expect(
            () => BlossomService.upload(bytes, client: client),
        throwsA(isA<BlossomException>()),
      );
    });

    test('an error status shows the server reason', () async {
      final client = MockClient(
            (_) async => http.Response('', 413, headers: {'x-reason': 'File too large'}),
      );
      await expectLater(
        BlossomService.upload(bytes, client: client),
        throwsA(
          isA<BlossomException>().having(
                (e) => e.message,
            'message',
            allOf(contains('413'), contains('File too large')),
          ),
        ),
      );
    });

    test('an answer that is not a descriptor is rejected', () async {
      for (final body in ['not json', '[]', '{"url": 1}', '{"url": "https://x"}']) {
        final client = MockClient((_) async => http.Response(body, 200));
        await expectLater(
          BlossomService.upload(bytes, client: client),
          throwsA(isA<BlossomException>()),
        );
      }
    });

    test('a network failure becomes a BlossomException', () async {
      final client = MockClient((_) async => throw http.ClientException('offline'));
      expect(
            () => BlossomService.upload(bytes, client: client),
        throwsA(isA<BlossomException>()),
      );
    });
  });

  group('uploadToAny', () {
    test('moves on to the next server when one refuses', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        if (request.url.host == 'first.example') {
          return http.Response('', 415, headers: {'x-reason': 'File type not allowed'});
        }
        return http.Response(descriptor(), 200);
      });

      final blob = await BlossomService.uploadToAny(
        bytes,
        servers: ['https://first.example', 'https://second.example'],
        client: client,
      );

      expect(hosts, ['first.example', 'second.example']);
      expect(blob.sha256, hash);
    });

    test('stops at the first server that works', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        return http.Response(descriptor(), 200);
      });

      await BlossomService.uploadToAny(
        bytes,
        servers: ['https://first.example', 'https://second.example'],
        client: client,
      );

      expect(hosts, ['first.example']);
    });

    test('fails with the last reason when every server refuses', () async {
      final client = MockClient((request) async {
        return http.Response('', 403, headers: {'x-reason': 'no from ${request.url.host}'});
      });

      await expectLater(
        BlossomService.uploadToAny(
          bytes,
          servers: ['https://first.example', 'https://second.example'],
          client: client,
        ),
        throwsA(
          isA<BlossomException>().having(
                (e) => e.message,
            'message',
            allOf(contains('second.example'), contains('403')),
          ),
        ),
      );
    });

    test('an empty server list is an error', () async {
      expect(
            () => BlossomService.uploadToAny(bytes, servers: []),
        throwsA(isA<BlossomException>()),
      );
    });
  });

  group('download', () {
    const url = 'https://blossom.example/file';

    test('returns the bytes when the hash matches', () async {
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      final out = await BlossomService.download(url, expectedHash: hash, client: client);
      expect(out, bytes);
    });

    test('download sends a User-Agent too', () async {
      late http.BaseRequest seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response.bytes(bytes, 200);
      });
      await BlossomService.download(url, client: client);
      expect(seen.headers['User-Agent'], startsWith('Chatme'));
    });

    test('accepts an uppercase expected hash', () async {
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      final out = await BlossomService.download(
        url,
        expectedHash: hash.toUpperCase(),
        client: client,
      );
      expect(out, bytes);
    });

    test('rejects a file with another hash', () async {
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      expect(
            () => BlossomService.download(url, expectedHash: 'b' * 64, client: client),
        throwsA(isA<BlossomException>()),
      );
    });

    test('rejects a missing file', () async {
      final client = MockClient((_) async => http.Response('', 404));
      expect(
            () => BlossomService.download(url, client: client),
        throwsA(isA<BlossomException>()),
      );
    });

    test('rejects addresses that are not https', () async {
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      for (final bad in ['http://blossom.example/file', 'ftp://x/y', 'file:///etc/passwd', 'not a url', '']) {
        await expectLater(
          BlossomService.download(bad, client: client),
          throwsA(isA<BlossomException>()),
        );
      }
    });

    test('rejects a file above the size limit', () async {
      final client = MockClient((_) async => http.Response.bytes(bytes, 200));
      expect(
            () => BlossomService.download(url, maxBytes: 100, client: client),
        throwsA(isA<BlossomException>()),
      );
    });
  });
}