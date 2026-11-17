// aead_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chatme/core/crypto/aead.dart';
import 'package:chatme/core/crypto/stream_crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final nonce = Uint8List.fromList(
    const [1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0],
  );
  final aad = Uint8List.fromList(utf8.encode('chatme aead test'));
  final plain = Uint8List.fromList(
    utf8.encode('AES-256-GCM known answer test, 45 bytes long!!'),
  );

  test('dart engine matches a known AES-256-GCM answer', () async {
    // Made with OpenSSL, the same cipher Android uses:
    //   node -e 'crypto.createCipheriv("aes-256-gcm", ...)'
    const expected = '60108e7025a44e5cbca4da9bdbaed8199e3f3b9fa3d66c2168855c2c'
        '16bee42dd4f7addd925964d48b12b05632e346a4c1f25944d9457799dcc86dabf7ad';

    final sealed = await Aead.fallback.seal(
      key: key,
      nonce: nonce,
      aad: aad,
      plain: plain,
    );
    expect(HEX.encode(sealed), expected);

    final opened = await Aead.fallback.open(
      key: key,
      nonce: nonce,
      aad: aad,
      sealed: sealed,
    );
    expect(opened, plain);
  });

  test('dart engine agrees with the cryptography package on a big chunk',
      () async {
    final big = Uint8List.fromList(
      List<int>.generate(64 * 1024, (i) => (i * 31 + 7) % 256),
    );
    final box = await cryptography.AesGcm.with256bits().encrypt(
      big,
      secretKey: cryptography.SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final expected = Uint8List.fromList(
      [...box.cipherText, ...box.mac.bytes],
    );

    final sealed = await Aead.fallback.seal(
      key: key,
      nonce: nonce,
      aad: aad,
      plain: big,
    );

    expect(sealed, expected);
  });

  test('a changed tag is refused', () async {
    final sealed = await Aead.fallback.seal(
      key: key,
      nonce: nonce,
      aad: aad,
      plain: plain,
    );
    sealed[sealed.length - 1] ^= 0xff;

    await expectLater(
      Aead.fallback.open(
        key: key,
        nonce: nonce,
        aad: aad,
        sealed: sealed,
      ),
      throwsA(isA<InvalidCipherTextException>()),
    );
  });

  test('the stream uses the injected engine for every chunk', () async {
    final dir = Directory.systemTemp.createTempSync('chatme_aead');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File('${dir.path}/video.mp4')
      ..writeAsBytesSync(List<int>.generate(
          StreamKey.chunkSize * 2 + 10, (i) => (i * 17 + 3) % 256));

    final spy = _SpyAead();
    final streamKey = await StreamKey.prepare(source, aead: spy);
    final encrypted = BytesBuilder(copy: false);
    await for (final chunk in streamKey.openEncrypted(source, aead: spy)) {
      encrypted.add(chunk);
    }

    expect(spy.seals, streamKey.totalChunks * 2);
    expect(streamKey.totalChunks, 3);

    final target = File('${dir.path}/out.mp4');
    await StreamFileCrypto.decryptToFile(
      ciphertext: Stream.value(encrypted.takeBytes()),
      target: target,
      key: streamKey.keyHex,
      nonce: streamKey.nonceHex,
      hash: streamKey.ciphertextHash,
      originalHash: streamKey.plaintextHash,
      encryptedSize: streamKey.encryptedSize,
      aead: spy,
    );

    expect(spy.opens, streamKey.totalChunks);
    expect(target.readAsBytesSync(), source.readAsBytesSync());
  });
}

class _SpyAead implements Aead {
  int seals = 0;
  int opens = 0;

  @override
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plain,
  }) {
    seals++;
    return Aead.fallback.seal(key: key, nonce: nonce, aad: aad, plain: plain);
  }

  @override
  Future<Uint8List> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  }) {
    opens++;
    return Aead.fallback.open(
      key: key,
      nonce: nonce,
      aad: aad,
      sealed: sealed,
    );
  }
}
