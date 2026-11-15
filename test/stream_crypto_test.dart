// stream_crypto_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/core/crypto/stream_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chatme_stream_crypto');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File sourceOf(List<int> bytes) {
    final file = File('${dir.path}/source.mp4')..writeAsBytesSync(bytes);
    return file;
  }

  Uint8List bytesOf(int length, {int seed = 7}) {
    return Uint8List.fromList(
      List<int>.generate(length, (i) => (i * 31 + seed) % 256),
    );
  }

  Future<Uint8List> encryptedOf(File source, [StreamKey? prepared]) async {
    final key = prepared ?? await StreamKey.prepare(source);
    final out = BytesBuilder(copy: false);
    await for (final chunk in key.openEncrypted(source)) {
      out.add(chunk);
    }
    return out.takeBytes();
  }

  Future<void> decrypt(
    Uint8List encrypted, {
    required File target,
    required StreamKey key,
    int? encryptedSize,
  }) {
    return StreamFileCrypto.decryptToFile(
      ciphertext: Stream.value(encrypted),
      target: target,
      key: key.keyHex,
      nonce: key.nonceHex,
      hash: key.ciphertextHash,
      originalHash: key.plaintextHash,
      encryptedSize: encryptedSize,
    );
  }

  group('prepare', () {
    test('splits the file into chunks and knows the encrypted size', () async {
      final plain = bytesOf(StreamKey.chunkSize * 2 + 100);
      final key = await StreamKey.prepare(sourceOf(plain));

      expect(key.plainSize, plain.length);
      expect(key.totalChunks, 3);
      expect(
        key.encryptedSize,
        StreamKey.headerBytes +
            plain.length +
            3 * StreamKey.tagBytes,
      );
      expect(key.keyHex, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(key.nonceHex, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('an exact multiple of the chunk size has no empty last chunk',
        () async {
      final plain = bytesOf(StreamKey.chunkSize * 2);
      final key = await StreamKey.prepare(sourceOf(plain));

      expect(key.totalChunks, 2);
      expect(
        key.encryptedSize,
        StreamKey.headerBytes +
            plain.length +
            2 * StreamKey.tagBytes,
      );
    });

    test('hashes the original and the encrypted bytes', () async {
      final plain = bytesOf(700 * 1024);
      final source = sourceOf(plain);
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);

      expect(key.plaintextHash, FileCrypto.sha256Hex(plain));
      expect(key.ciphertextHash, FileCrypto.sha256Hex(encrypted));
    });

    test('two preparations never share a key or a nonce', () async {
      final source = sourceOf(bytesOf(4096));
      final a = await StreamKey.prepare(source);
      final b = await StreamKey.prepare(source);

      expect(a.keyHex, isNot(b.keyHex));
      expect(a.nonceHex, isNot(b.nonceHex));
      expect(a.ciphertextHash, isNot(b.ciphertextHash));
    });
  });

  group('openEncrypted', () {
    test('starts with the header and produces the announced size', () async {
      final source = sourceOf(bytesOf(600 * 1024));
      final key = await StreamKey.prepare(source);
      final out = BytesBuilder(copy: false);
      final progress = <int>[];

      await for (final chunk in key.openEncrypted(
        source,
        onProgress: (produced, total) {
          expect(total, key.encryptedSize);
          progress.add(produced);
        },
      )) {
        out.add(chunk);
      }

      final encrypted = out.takeBytes();
      expect(encrypted.length, key.encryptedSize);
      expect(encrypted.sublist(0, 4), [0x43, 0x4d, 0x53, 0x32]);
      expect(progress, isNotEmpty);
      expect(progress.last, key.encryptedSize);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThan(progress[i - 1]));
      }
    });
  });

  group('decryptToFile', () {
    test('restores a file of several chunks', () async {
      final plain = bytesOf(StreamKey.chunkSize * 3 + 5);
      final source = sourceOf(plain);
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/out.mp4.part');

      await decrypt(encrypted, target: target, key: key);

      expect(target.readAsBytesSync(), plain);
    });

    test('restores an empty file', () async {
      final source = sourceOf(const []);
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/empty.mp4.part');

      await decrypt(encrypted, target: target, key: key);

      expect(key.totalChunks, 0);
      expect(target.readAsBytesSync(), isEmpty);
    });

    test('accepts a stream that arrives in small pieces', () async {
      final plain = bytesOf(300 * 1024);
      final source = sourceOf(plain);
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/pieces.mp4.part');

      Stream<List<int>> pieces() async* {
        for (var i = 0; i < encrypted.length; i += 1000) {
          final end =
              i + 1000 > encrypted.length ? encrypted.length : i + 1000;
          yield encrypted.sublist(i, end);
        }
      }

      await StreamFileCrypto.decryptToFile(
        ciphertext: pieces(),
        target: target,
        key: key.keyHex,
        nonce: key.nonceHex,
        hash: key.ciphertextHash,
        originalHash: key.plaintextHash,
        encryptedSize: key.encryptedSize,
      );

      expect(target.readAsBytesSync(), plain);
    });

    test('reports progress up to the announced size', () async {
      final source = sourceOf(bytesOf(500 * 1024));
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/progress.mp4.part');
      final progress = <int>[];

      await StreamFileCrypto.decryptToFile(
        ciphertext: Stream.value(encrypted),
        target: target,
        key: key.keyHex,
        nonce: key.nonceHex,
        hash: key.ciphertextHash,
        originalHash: key.plaintextHash,
        encryptedSize: key.encryptedSize,
        onProgress: (received, total) {
          expect(total, key.encryptedSize);
          progress.add(received);
        },
      );

      expect(progress, isNotEmpty);
      expect(progress.last, key.encryptedSize);
    });

    test('a changed chunk is rejected and nothing is left behind', () async {
      final source = sourceOf(bytesOf(600 * 1024));
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      encrypted[StreamKey.headerBytes + 200] ^= 0xff;
      final target = File('${dir.path}/changed.mp4.part');

      await expectLater(
        decrypt(encrypted, target: target, key: key),
        throwsA(isA<StreamCryptoException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('a truncated file is rejected and nothing is left behind', () async {
      final source = sourceOf(bytesOf(600 * 1024));
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/cut.mp4.part');

      await expectLater(
        decrypt(encrypted.sublist(0, encrypted.length - 40),
            target: target, key: key),
        throwsA(isA<StreamCryptoException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('trailing bytes are rejected', () async {
      final source = sourceOf(bytesOf(100 * 1024));
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/long.mp4.part');

      await expectLater(
        decrypt(
          Uint8List.fromList([...encrypted, 1]),
          target: target,
          key: key,
        ),
        throwsA(isA<StreamCryptoException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('two swapped chunks are rejected', () async {
      final plain = bytesOf(StreamKey.chunkSize * 2);
      final source = sourceOf(plain);
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      const frame = StreamKey.chunkSize + StreamKey.tagBytes;

      final swapped = Uint8List.fromList(encrypted);
      final first = encrypted.sublist(
        StreamKey.headerBytes,
        StreamKey.headerBytes + frame,
      );
      final second = encrypted.sublist(
        StreamKey.headerBytes + frame,
        StreamKey.headerBytes + 2 * frame,
      );
      swapped.setRange(StreamKey.headerBytes, StreamKey.headerBytes + frame, second);
      swapped.setRange(
        StreamKey.headerBytes + frame,
        StreamKey.headerBytes + 2 * frame,
        first,
      );
      final target = File('${dir.path}/swap.mp4.part');

      await expectLater(
        decrypt(swapped, target: target, key: key),
        throwsA(isA<StreamCryptoException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('a wrong key is rejected', () async {
      final source = sourceOf(bytesOf(200 * 1024));
      final key = await StreamKey.prepare(source);
      final other = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/wrong.mp4.part');

      await expectLater(
        StreamFileCrypto.decryptToFile(
          ciphertext: Stream.value(encrypted),
          target: target,
          key: other.keyHex,
          nonce: key.nonceHex,
          hash: key.ciphertextHash,
          originalHash: key.plaintextHash,
          encryptedSize: key.encryptedSize,
        ),
        throwsA(isA<StreamCryptoException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('a file that is not a Chatme stream is rejected', () async {
      final target = File('${dir.path}/plain.mp4.part');
      final notStream = Uint8List(StreamKey.headerBytes + 100);

      await expectLater(
        StreamFileCrypto.decryptToFile(
          ciphertext: Stream.value(notStream),
          target: target,
          key: 'a' * 64,
          nonce: 'b' * 32,
          hash: 'c' * 64,
        ),
        throwsA(isA<StreamCryptoException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('a size that does not match the header is refused', () async {
      final source = sourceOf(bytesOf(100 * 1024));
      final key = await StreamKey.prepare(source);
      final encrypted = await encryptedOf(source, key);
      final target = File('${dir.path}/size.mp4.part');

      await expectLater(
        decrypt(
          encrypted,
          target: target,
          key: key,
          encryptedSize: key.encryptedSize + 1,
        ),
        throwsA(isA<StreamCryptoException>()),
      );
      expect(target.existsSync(), isFalse);
    });
  });
}
