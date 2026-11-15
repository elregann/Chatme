// profile_search_service_test.dart

import 'dart:async';
import 'dart:convert';

import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatme/core/crypto/nostr_protocol.dart';
import 'package:chatme/core/utils/key_utils.dart';
import 'package:chatme/services/profile_search_service.dart';

String _key(int n) => n.toRadixString(16).padLeft(64, '0');

class FakeConnection implements SearchRelayConnection {
  final _controller = StreamController<dynamic>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }

  void emit(Object data) => _controller.add(data);

  List<dynamic> get request => jsonDecode(sent.single) as List<dynamic>;

  String get subscriptionId => request[1].toString();

  Map<String, dynamic> get filter => request[2] as Map<String, dynamic>;
}

class FakeRelays {
  final Map<String, FakeConnection> connections = {};

  SearchRelayConnection connect(Uri uri) {
    final connection = FakeConnection();
    connections[uri.toString()] = connection;
    return connection;
  }
}

Map<String, dynamic> _profile({
  required String privkey,
  required int createdAt,
  required Map<String, dynamic> content,
  int kind = 0,
}) {
  final unsigned = <String, dynamic>{
    'pubkey': bip340.getPublicKey(privkey),
    'created_at': createdAt,
    'kind': kind,
    'tags': <List<String>>[],
    'content': jsonEncode(content),
  };
  final id = NostrSigner.calculateEventId(unsigned);
  return {
    ...unsigned,
    'id': id,
    'sig': NostrSigner.sign(id, privkey),
  };
}

String _eventMessage(FakeConnection connection, Map<String, dynamic> event) {
  return jsonEncode(['EVENT', connection.subscriptionId, event]);
}

String _eose(FakeConnection connection) {
  return jsonEncode(['EOSE', connection.subscriptionId]);
}

void main() {
  final alicePriv = _key(1);
  final bobPriv = _key(2);
  final alicePub = bip340.getPublicKey(alicePriv);

  late FakeRelays relays;
  late ProfileSearchService service;

  setUp(() {
    relays = FakeRelays();
    service = ProfileSearchService(
      relays: () => ['wss://a.example.com', 'wss://b.example.com'],
      connect: relays.connect,
      timeout: const Duration(milliseconds: 200),
    );
  });

  Future<List<ProfileSearchResult>> start(String query) {
    final future = service.search(query);
    // The sockets and REQ messages are created before the first await.
    return future;
  }

  group('results', () {
    test('reads the profile fields and uses name as the label', () async {
      final future = start('alice');
      final connection = relays.connections['wss://a.example.com']!;
      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: alicePriv,
          createdAt: 1700000000,
          content: {
            'name': 'Alice',
            'display_name': 'Alice A',
            'nip05': 'alice@example.com',
            'picture': 'https://example.com/alice.png',
            'about': 'hello',
          },
        ),
      ));
      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));

      final results = await future;
      expect(results, hasLength(1));
      final alice = results.single;
      expect(alice.pubkey, alicePub);
      expect(alice.name, 'Alice');
      expect(alice.displayName, 'Alice A');
      expect(alice.nip05, 'alice@example.com');
      expect(alice.picture, 'https://example.com/alice.png');
      expect(alice.about, 'hello');
      expect(alice.label, 'Alice');
    });

    test('falls back from name to display name to nip05 to npub', () async {
      final future = start('someone');
      final connection = relays.connections['wss://a.example.com']!;

      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: _key(3),
          createdAt: 1,
          content: {'display_name': 'Display Only'},
        ),
      ));
      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: _key(4),
          createdAt: 2,
          content: {'nip05': 'handle@example.com'},
        ),
      ));
      connection.emit(_eventMessage(
        connection,
        _profile(privkey: _key(5), createdAt: 3, content: {}),
      ));
      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));

      final labels = (await future).map((r) => r.label).toSet();
      expect(labels, containsAll(['Display Only', 'handle']));
      expect(labels.any((label) => label.startsWith('npub1')), isTrue);
    });

    test('keeps the newest kind 0 for the same pubkey', () async {
      final future = start('alice');
      final a = relays.connections['wss://a.example.com']!;
      final b = relays.connections['wss://b.example.com']!;

      a.emit(_eventMessage(
        a,
        _profile(
          privkey: alicePriv,
          createdAt: 100,
          content: {'name': 'Old Alice'},
        ),
      ));
      b.emit(_eventMessage(
        b,
        _profile(
          privkey: alicePriv,
          createdAt: 200,
          content: {'name': 'New Alice'},
        ),
      ));
      a.emit(_eose(a));
      b.emit(_eose(b));

      final results = await future;
      expect(results, hasLength(1));
      expect(results.single.name, 'New Alice');
      expect(results.single.relay, 'wss://b.example.com');
    });

    test('puts an exact name match before a partial one', () async {
      final future = start('alice');
      final a = relays.connections['wss://a.example.com']!;
      final b = relays.connections['wss://b.example.com']!;

      a.emit(_eventMessage(
        a,
        _profile(
          privkey: bobPriv,
          createdAt: 500,
          content: {'name': 'Alice Cooper'},
        ),
      ));
      b.emit(_eventMessage(
        b,
        _profile(
          privkey: alicePriv,
          createdAt: 100,
          content: {'name': 'alice'},
        ),
      ));
      a.emit(_eose(a));
      b.emit(_eose(b));

      final results = await future;
      expect(results.map((r) => r.name), ['alice', 'Alice Cooper']);
    });
  });

  group('rejects', () {
    test('an event with a bad signature', () async {
      final future = start('alice');
      final connection = relays.connections['wss://a.example.com']!;
      final event = _profile(
        privkey: alicePriv,
        createdAt: 100,
        content: {'name': 'Alice'},
      );
      final signature = event['sig'] as String;
      event['sig'] = signature.substring(0, signature.length - 1) +
          (signature.endsWith('0') ? '1' : '0');

      connection.emit(_eventMessage(connection, event));
      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));

      expect(await future, isEmpty);
    });

    test('an event whose content was changed after signing', () async {
      final future = start('alice');
      final connection = relays.connections['wss://a.example.com']!;
      final event = _profile(
        privkey: alicePriv,
        createdAt: 100,
        content: {'name': 'Alice'},
      );
      event['content'] = jsonEncode({'name': 'Mallory'});

      connection.emit(_eventMessage(connection, event));
      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));

      expect(await future, isEmpty);
    });

    test('anything that is not a usable kind 0', () async {
      final future = start('alice');
      final connection = relays.connections['wss://a.example.com']!;

      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: alicePriv,
          createdAt: 100,
          content: {'name': 'Alice'},
          kind: 1,
        ),
      ));
      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: alicePriv,
          createdAt: 101,
          content: {'name': 'Alice'},
        )..['content'] = 'not json',
      ));
      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: alicePriv,
          createdAt: 102,
          content: {},
        )..['content'] = '',
      ));
      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: alicePriv,
          createdAt: 103,
          content: {'name': 'Alice'},
        )..['content'] = '[]',
      ));
      connection.emit(jsonEncode(['NOTICE', 'ignored']));
      connection.emit(jsonEncode([
        'EVENT',
        'another-sub',
        _profile(
          privkey: alicePriv,
          createdAt: 104,
          content: {'name': 'Alice'},
        ),
      ]));
      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));

      expect(await future, isEmpty);
    });
  });

  group('queries', () {
    test('an npub looks the profile up by author, not by text', () async {
      final future = start(KeyUtils.toNpub(alicePub));
      final connection = relays.connections['wss://a.example.com']!;

      expect(connection.filter['authors'], [alicePub]);
      expect(connection.filter.containsKey('search'), isFalse);
      expect(connection.filter['kinds'], [0]);

      connection.emit(_eventMessage(
        connection,
        _profile(
          privkey: alicePriv,
          createdAt: 100,
          content: {'name': 'Alice'},
        ),
      ));
      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));

      final results = await future;
      expect(results, hasLength(1));
      expect(results.single.pubkey, alicePub);
    });

    test('a hex pubkey also uses the author filter', () async {
      final future = start(alicePub);
      final connection = relays.connections['wss://a.example.com']!;

      expect(connection.filter['authors'], [alicePub]);
      expect(connection.filter.containsKey('search'), isFalse);

      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));
      await future;
    });

    test('a name uses a NIP-50 search filter with a limit', () async {
      final future = start('alice');
      final connection = relays.connections['wss://a.example.com']!;

      expect(connection.filter['search'], 'alice');
      expect(connection.filter['kinds'], [0]);
      expect(connection.filter['limit'], 20);
      expect(connection.filter.containsKey('authors'), isFalse);

      connection.emit(_eose(connection));
      relays.connections['wss://b.example.com']!
          .emit(_eose(relays.connections['wss://b.example.com']!));
      await future;
    });

    test('too short a query does nothing', () async {
      expect(await service.search('a'), isEmpty);
      expect(await service.search('  '), isEmpty);
      expect(relays.connections, isEmpty);
    });

    test('no search relays means no connection at all', () async {
      final empty = ProfileSearchService(
        relays: () => const [],
        connect: relays.connect,
      );
      expect(await empty.search('alice'), isEmpty);
      expect(relays.connections, isEmpty);
    });

    test('a secret key is never sent to any relay', () async {
      final nsec = KeyUtils.toNsec(alicePriv);
      expect(await service.search(nsec), isEmpty);
      expect(await service.search('nostr:$nsec'), isEmpty);
      expect(relays.connections, isEmpty);
    });
  });

  group('lifecycle', () {
    test('EOSE finishes the query and closes every socket', () async {
      final future = start('alice');
      final a = relays.connections['wss://a.example.com']!;
      final b = relays.connections['wss://b.example.com']!;

      a.emit(_eose(a));
      expect(a.closed, isFalse);
      b.emit(_eose(b));
      await future;

      expect(a.closed, isTrue);
      expect(b.closed, isTrue);
    });

    test('a timeout keeps the partial results and closes the sockets',
        () async {
      final quick = ProfileSearchService(
        relays: () => ['wss://a.example.com', 'wss://b.example.com'],
        connect: relays.connect,
        timeout: const Duration(milliseconds: 30),
      );
      final future = quick.search('alice');
      final a = relays.connections['wss://a.example.com']!;

      a.emit(_eventMessage(
        a,
        _profile(
          privkey: alicePriv,
          createdAt: 100,
          content: {'name': 'Alice'},
        ),
      ));
      // No EOSE from either relay.

      final results = await future;
      expect(results, hasLength(1));
      expect(results.single.name, 'Alice');
      expect(a.closed, isTrue);
      expect(relays.connections['wss://b.example.com']!.closed, isTrue);
    });

    test('cancel drops the results of the query that was running', () async {
      final future = start('alice');
      final a = relays.connections['wss://a.example.com']!;

      a.emit(_eventMessage(
        a,
        _profile(
          privkey: alicePriv,
          createdAt: 100,
          content: {'name': 'Alice'},
        ),
      ));
      service.cancel();

      expect(await future, isEmpty);
      expect(a.closed, isTrue);
    });
  });
}
