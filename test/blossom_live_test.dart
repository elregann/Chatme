// blossom_live_test.dart
//
// Talks to real servers. Run it by hand:
//   flutter test test/blossom_live_test.dart --dart-define=LIVE=true
// Add --dart-define=SIZES=true to also probe file sizes on one server:
//   --dart-define=SERVER=https://blossom.ditto.pub

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/services/blossom_service.dart';

const _servers = [
  'https://blossom.ditto.pub',
  'https://nostr.download',
  'https://blossom.primal.net',
  'https://blossom.nostr.build',
  'https://blossom.band',
];

void main() {
  const live = bool.fromEnvironment('LIVE');
  const sizes = bool.fromEnvironment('SIZES');
  const probeServer = String.fromEnvironment(
    'SERVER',
    defaultValue: BlossomService.defaultServer,
  );

  test('which servers take an encrypted file', () async {
    final random = Random.secure();
    final plain = Uint8List.fromList(
      utf8.encode('Chatme live test ${DateTime.now().toIso8601String()} ${random.nextInt(1 << 30)}'),
    );
    final encrypted = FileCrypto.encrypt(plain);
    final accepted = <String>[];

    for (final server in _servers) {
      try {
        final blob = await BlossomService.upload(
          encrypted.bytes,
          server: server,
          description: 'Chatme live test',
        );
        final downloaded = await BlossomService.download(
          blob.url,
          expectedHash: encrypted.hash,
        );
        final decrypted = FileCrypto.decrypt(
          downloaded,
          key: encrypted.key,
          nonce: encrypted.nonce,
          originalHash: encrypted.originalHash,
        );
        expect(decrypted, plain);
        accepted.add(server);
        // ignore: avoid_print
        print('[OK]   $server -> ${blob.url}');
      } on BlossomException catch (e) {
        // ignore: avoid_print
        print('[FAIL] $server -> ${e.message}');
      }
    }

    expect(accepted, isNotEmpty);
  }, skip: live ? false : 'add --dart-define=LIVE=true to run', timeout: const Timeout(Duration(minutes: 5)));

  test('how big a file the server takes', () async {
    final random = Random.secure();
    for (final mib in [1, 8]) {
      final plain = Uint8List.fromList(
        List<int>.generate(mib * 1024 * 1024, (_) => random.nextInt(256)),
      );
      final encrypted = FileCrypto.encrypt(plain);
      try {
        await BlossomService.upload(
          encrypted.bytes,
          server: probeServer,
          description: 'Chatme size test',
        );
        // ignore: avoid_print
        print('[OK]   $mib MiB on $probeServer');
      } on BlossomException catch (e) {
        // ignore: avoid_print
        print('[FAIL] $mib MiB on $probeServer -> ${e.message}');
      }
    }
  }, skip: (live && sizes) ? false : 'add --dart-define=LIVE=true --dart-define=SIZES=true', timeout: const Timeout(Duration(minutes: 10)));
}