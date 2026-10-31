// blossom_servers_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/services/blossom_service.dart';
import 'package:chatme/services/blossom_servers.dart';
import 'package:chatme/services/server_lists.dart';

void main() {
  group('BlossomLists.fromStored', () {
    test('nothing saved gives the defaults', () {
      expect(BlossomLists.fromStored(null), BlossomDefaults.servers);
    });

    test('keeps good servers in order and drops the rest', () {
      final list = BlossomLists.fromStored([
        'files.example.com',
        'http://insecure.example.com',
        42,
        'https://files.example.com/',
        'https://other.example.org',
      ]);
      expect(list, ['https://files.example.com', 'https://other.example.org']);
    });

    test('an empty or damaged list gives the defaults', () {
      expect(BlossomLists.fromStored(<String>[]), BlossomDefaults.servers);
      expect(BlossomLists.fromStored('nonsense'), BlossomDefaults.servers);
      expect(BlossomLists.fromStored(['localhost', 'http://x.example.com']), BlossomDefaults.servers);
    });

    test('never holds more than the limit', () {
      final many = List.generate(9, (i) => 'https://s$i.example.com');
      expect(BlossomLists.fromStored(many).length, ListLimits.blossomMax);
    });

    test('the service uses the same defaults', () {
      expect(BlossomService.defaultServers, BlossomDefaults.servers);
    });
  });

  group('addBlossomServer', () {
    const current = ['https://blossom.ditto.pub'];

    test('tests the server before adding it', () async {
      final tested = <String>[];
      final edit = await addBlossomServer(
        current,
        'files.example.com',
        probe: (url) async => tested.add(url),
      );
      expect(edit.change, ListChange.ok);
      expect(edit.list, ['https://blossom.ditto.pub', 'https://files.example.com']);
      expect(tested, ['https://files.example.com']);
    });

    test('a server that refuses the test file is not added', () async {
      final edit = await addBlossomServer(
        current,
        'files.example.com',
        probe: (_) async => throw const BlossomException('upload failed (415)'),
      );
      expect(edit.change, ListChange.unreachable);
      expect(edit.list, current);
    });

    test('a bad address, a duplicate or a full list never reach the server', () async {
      var calls = 0;
      Future<void> probe(String _) async => calls++;

      expect((await addBlossomServer(current, 'http://x.example.com', probe: probe)).change, ListChange.invalid);
      expect((await addBlossomServer(current, 'blossom.ditto.pub', probe: probe)).change, ListChange.duplicate);

      final full = List.generate(ListLimits.blossomMax, (i) => 'https://s$i.example.com');
      expect((await addBlossomServer(full, 'new.example.com', probe: probe)).change, ListChange.full);

      expect(calls, 0);
    });
  });

  group('removing', () {
    test('the last file server stays', () {
      final edit = ServerLists.remove(
        ['https://blossom.ditto.pub'],
        'https://blossom.ditto.pub',
        minimum: ListLimits.blossomMin,
      );
      expect(edit.change, ListChange.tooFew);
    });
  });

  group('BlossomService.testUpload', () {
    http.Response descriptorFor(http.Request request) {
      final hash = FileCrypto.sha256Hex(request.bodyBytes);
      return http.Response(
        jsonEncode({'url': 'https://files.example/$hash', 'sha256': hash, 'size': request.bodyBytes.length}),
        200,
      );
    }

    test('sends a small random file to that server', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return descriptorFor(request);
      });

      await BlossomService.testUpload('https://files.example', client: client);

      expect(seen.method, 'PUT');
      expect(seen.url.toString(), 'https://files.example/upload');
      expect(seen.bodyBytes.length, inInclusiveRange(16, 1024));
      expect(seen.headers['X-SHA-256'], FileCrypto.sha256Hex(seen.bodyBytes));
    });

    test('every test sends different bytes', () async {
      final bodies = <String>[];
      final client = MockClient((request) async {
        bodies.add(FileCrypto.sha256Hex(request.bodyBytes));
        return descriptorFor(request);
      });

      await BlossomService.testUpload('https://files.example', client: client);
      await BlossomService.testUpload('https://files.example', client: client);

      expect(bodies[0], isNot(bodies[1]));
    });

    test('a refusal is reported', () async {
      final client = MockClient((_) async => http.Response('', 403));
      expect(
        BlossomService.testUpload('https://files.example', client: client),
        throwsA(isA<BlossomException>()),
      );
    });
  });
}
