// aead.dart
//
// AES-256-GCM for one chunk of a file.
//
// Android has AES built into the system and runs it on a background thread, so
// sealing a 256 KiB chunk costs a few milliseconds instead of a quarter of a
// second. Everywhere else, and whenever the channel is not there, the Dart
// implementation below does the same work.
//
// Both engines produce the same bytes: ciphertext followed by the 16 byte tag.
// Without a tag match [open] throws `InvalidCipherTextException`, like the Dart
// implementation always did.

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:pointycastle/export.dart'
    show AEADParameters, AESEngine, GCMBlockCipher, KeyParameter;

abstract class Aead {
  const Aead();

  /// Encrypts [plain] and returns the ciphertext followed by the tag.
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plain,
  });

  /// Decrypts [sealed] (ciphertext followed by the tag).
  Future<Uint8List> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  });

  /// The engine the app uses: Android's own AES when it is available, the Dart
  /// implementation on every other platform.
  static final Aead platform = _PlatformAead();

  /// The Dart implementation. Also the fallback when the call to Android
  /// fails, so a file can always be sent and opened.
  static const Aead fallback = _DartAead();
}

class _PlatformAead implements Aead {
  static const MethodChannel _channel = MethodChannel('com.chatme.app/aes');

  /// Turned off for the rest of the process after the first
  /// [MissingPluginException]: a build without the channel should not pay for
  /// a failed platform call on every chunk.
  bool _native = Platform.isAndroid;

  @override
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plain,
  }) {
    return _run(
      'seal',
      key: key,
      nonce: nonce,
      aad: aad,
      data: plain,
    );
  }

  @override
  Future<Uint8List> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  }) {
    return _run(
      'open',
      key: key,
      nonce: nonce,
      aad: aad,
      data: sealed,
    );
  }

  Future<Uint8List> _run(
    String method, {
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List data,
  }) async {
    if (_native) {
      try {
        final out = await _channel.invokeMethod<Uint8List>(method, {
          'key': key,
          'nonce': nonce,
          'aad': aad,
          'data': data,
        });
        if (out != null) return out;
      } on MissingPluginException {
        _native = false;
      } on PlatformException {
        // Let the Dart engine repeat this chunk: it either succeeds or raises
        // the proper cipher error, and the next chunk can still use Android.
      }
    }

    const fallback = Aead.fallback;
    return method == 'seal'
        ? fallback.seal(key: key, nonce: nonce, aad: aad, plain: data)
        : fallback.open(key: key, nonce: nonce, aad: aad, sealed: data);
  }
}

class _DartAead implements Aead {
  const _DartAead();

  @override
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plain,
  }) async {
    return _process(true, plain, key, nonce, aad);
  }

  @override
  Future<Uint8List> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  }) async {
    return _process(false, sealed, key, nonce, aad);
  }

  Uint8List _process(
    bool encrypt,
    Uint8List input,
    Uint8List key,
    Uint8List nonce,
    Uint8List aad,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(KeyParameter(key), 128, nonce, aad),
      );
    final out = Uint8List(cipher.getOutputSize(input.length));
    final written = cipher.processBytes(input, 0, input.length, out, 0);
    final total = written + cipher.doFinal(out, written);
    return Uint8List.sublistView(out, 0, total);
  }
}
