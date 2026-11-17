// stream_crypto.dart
//
// AES-256-GCM for files that are too large to keep in memory.
//
// A file is split into fixed size chunks. Every chunk is sealed on its own, so
// it can be encrypted while it is read and decrypted while it is downloaded:
// memory stays small even for a video of hundreds of megabytes.
//
// Layout of the encrypted file (the bytes that are uploaded):
//
//   header        20 bytes
//     0  magic     "CMS2"
//     4  chunk     uint32 big endian
//     8  chunks    uint32 big endian
//    12  plain     uint64 big endian
//   chunk 0       ciphertext + 16 byte GCM tag
//   chunk 1       ...
//
// The nonce of a chunk is 4 random bytes followed by the 8 byte chunk number.
// The additional data covers the whole header and the chunk number, so a
// chunk that is moved, dropped or taken from another file is rejected.
//
// The `x` hash covers the header and every encrypted byte; `ox` covers the
// original file. Both are computed while streaming.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show Digest, sha256;
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;

import 'aead.dart';
import 'crypto_utils.dart';

class StreamCryptoException implements Exception {
  final String message;
  const StreamCryptoException(this.message);

  @override
  String toString() => message;
}

/// Everything the receiver needs, worked out before the upload starts.
class StreamKey {
  /// The encryption-algorithm tag sent with a streamed file.
  static const String algorithm = 'aes-gcm-chunked';

  /// 256 KiB keeps memory small and still makes the overhead tiny: 16 bytes
  /// per chunk is about 0.006% of a 256 KiB chunk.
  static const int chunkSize = 256 * 1024;
  static const int tagBytes = 16;
  static const int headerBytes = 20;
  static const int maxChunkSize = 4 * 1024 * 1024;
  static const List<int> magic = <int>[0x43, 0x4d, 0x53, 0x32]; // CMS2

  final Uint8List key;
  final Uint8List nonce;
  final int plainSize;
  final int totalChunks;
  final Uint8List header;

  /// NIP-17 `decryption-key`, 32 bytes as hex.
  final String keyHex;

  /// NIP-17 `decryption-nonce`, 16 bytes as hex.
  final String nonceHex;

  /// NIP-17 `x`: sha256 of the encrypted file.
  final String ciphertextHash;

  /// NIP-17 `ox`: sha256 of the original file.
  final String plaintextHash;

  StreamKey._({
    required this.key,
    required this.nonce,
    required this.plainSize,
    required this.totalChunks,
    required this.header,
    required this.keyHex,
    required this.nonceHex,
    required this.ciphertextHash,
    required this.plaintextHash,
  });

  /// Bytes of the encrypted file. Known before the upload so the receiver can
  /// show a size and the client can send a Content-Length.
  int get encryptedSize => headerBytes + plainSize + totalChunks * tagBytes;

  static int chunkCountFor(int plainSize, [int size = chunkSize]) {
    if (plainSize <= 0) return 0;
    return (plainSize + size - 1) ~/ size;
  }

  /// Reads [source] once to build the header, the key, the nonce and both
  /// hashes. The file itself is not kept; [openEncrypted] reads it again.
  ///
  /// [aead] is the cipher engine; Android uses its own AES by default, while a
  /// test can pass [Aead.fallback] so no platform channel is needed.
  static Future<StreamKey> prepare(File source, {Aead? aead}) async {
    final engine = aead ?? Aead.platform;
    final plainSize = await source.length();
    final totalChunks = chunkCountFor(plainSize);
    final key = CryptoUtils.generateSecureRandomBytes(32);
    final nonce = CryptoUtils.generateSecureRandomBytes(16);
    final header = _buildHeader(plainSize: plainSize, totalChunks: totalChunks);

    final cipherHash = _DigestBuilder()..add(header);
    final plainHash = _DigestBuilder();
    var index = 0;

    await for (final chunk in _readChunks(source, plainSize)) {
      plainHash.add(chunk);
      cipherHash.add(await _seal(chunk, index, key, nonce, header, engine));
      index++;
    }

    if (index != totalChunks) {
      throw const StreamCryptoException('the file changed while it was read');
    }

    return StreamKey._(
      key: key,
      nonce: nonce,
      plainSize: plainSize,
      totalChunks: totalChunks,
      header: header,
      keyHex: HEX.encode(key),
      nonceHex: HEX.encode(nonce),
      ciphertextHash: HEX.encode(cipherHash.close().bytes).toLowerCase(),
      plaintextHash: HEX.encode(plainHash.close().bytes).toLowerCase(),
    );
  }

  /// The encrypted bytes, header first. Reading is streamed, so the caller can
  /// feed this straight into an HTTP request without a temporary file.
  ///
  /// [onProgress] receives (bytes produced, total encrypted bytes).
  Stream<List<int>> openEncrypted(
    File source, {
    void Function(int produced, int total)? onProgress,
    Aead? aead,
  }) async* {
    final engine = aead ?? Aead.platform;
    final cipherHash = _DigestBuilder()..add(header);
    var produced = headerBytes;
    yield header;

    var index = 0;
    await for (final chunk in _readChunks(source, plainSize)) {
      final sealed = await _seal(chunk, index, key, nonce, header, engine);
      index++;
      cipherHash.add(sealed);
      produced += sealed.length;
      onProgress?.call(produced, encryptedSize);
      yield sealed;
    }

    if (index != totalChunks ||
        HEX.encode(cipherHash.close().bytes).toLowerCase() != ciphertextHash) {
      throw const StreamCryptoException('the file changed while it was sent');
    }
  }

  static Uint8List _buildHeader({
    required int plainSize,
    required int totalChunks,
  }) {
    final header = Uint8List(headerBytes);
    header.setRange(0, magic.length, magic);
    final view = ByteData.sublistView(header);
    view.setUint32(4, chunkSize);
    view.setUint32(8, totalChunks);
    view.setUint64(12, plainSize);
    return header;
  }

  static Stream<Uint8List> _readChunks(File source, int plainSize) async* {
    final raf = await source.open();
    try {
      var remaining = plainSize;
      while (remaining > 0) {
        final want = remaining < chunkSize ? remaining : chunkSize;
        final chunk = Uint8List(want);
        final read = await raf.readInto(chunk, 0, want);
        if (read != want) {
          throw const StreamCryptoException('the file changed while it was read');
        }
        remaining -= read;
        yield chunk;
      }
    } finally {
      await raf.close();
    }
  }

  static Future<Uint8List> _seal(
    Uint8List plain,
    int index,
    Uint8List key,
    Uint8List nonce,
    Uint8List header,
    Aead engine,
  ) {
    return engine.seal(
      key: key,
      nonce: _nonceFor(nonce, index),
      aad: _aadFor(header, index),
      plain: plain,
    );
  }

  static Uint8List _nonceFor(Uint8List base, int index) {
    final nonce = Uint8List(12);
    nonce.setRange(0, 4, base);
    ByteData.sublistView(nonce).setUint64(4, index);
    return nonce;
  }

  static Uint8List _aadFor(Uint8List header, int index) {
    final aad = Uint8List(header.length + 4);
    aad.setRange(0, header.length, header);
    ByteData.sublistView(aad).setUint32(header.length, index);
    return aad;
  }
}

/// Reads a chunked file and writes the plaintext to [target].
///
/// Every check happens while the bytes arrive, so nothing is ever kept in
/// memory as a whole. On any failure [target] is deleted: a half written or
/// tampered file must never look like a real video.
class StreamFileCrypto {
  StreamFileCrypto._();

  /// [encryptedSize] is the size the sender announced. When it is set, a
  /// longer or shorter stream is refused before it can fill the phone. [aead]
  /// selects the cipher engine, like in [StreamKey.prepare].
  static Future<void> decryptToFile({
    required Stream<List<int>> ciphertext,
    required File target,
    required String key,
    required String nonce,
    required String hash,
    String? originalHash,
    int? encryptedSize,
    void Function(int received, int total)? onProgress,
    Aead? aead,
  }) async {
    final engine = aead ?? Aead.platform;
    final keyBytes = _decodeHex(key, 32, 'key');
    final nonceBytes = _decodeHex(nonce, 16, 'nonce');
    final reader = _FrameReader(ciphertext);
    RandomAccessFile? out;
    var finished = false;

    try {
      final header = await reader.read(StreamKey.headerBytes);
      final parsed = _parseHeader(header);
      final expected =
          StreamKey.headerBytes + parsed.plainSize + parsed.totalChunks * StreamKey.tagBytes;

      if (encryptedSize != null && encryptedSize != expected) {
        throw const StreamCryptoException('the file size does not match');
      }

      final cipherHash = _DigestBuilder()..add(header);
      final plainHash = _DigestBuilder();
      out = await target.open(mode: FileMode.write);

      var written = 0;
      var received = StreamKey.headerBytes;

      for (var index = 0; index < parsed.totalChunks; index++) {
        final plainLength = _plainLengthFor(
          parsed.plainSize,
          parsed.chunkSize,
          index,
        );
        final sealed = await reader.read(plainLength + StreamKey.tagBytes);
        cipherHash.add(sealed);
        received += sealed.length;

        final plain = await _open(
          sealed,
          index,
          keyBytes,
          nonceBytes,
          header,
          engine,
        );
        plainHash.add(plain);
        await out.writeFrom(plain);
        written += plain.length;
        onProgress?.call(received, expected);
      }

      if (written != parsed.plainSize) {
        throw const StreamCryptoException('the file is not complete');
      }
      if (await reader.hasMore()) {
        throw const StreamCryptoException('the file is longer than it claims');
      }
      if (HEX.encode(cipherHash.close().bytes).toLowerCase() !=
          hash.toLowerCase()) {
        throw const StreamCryptoException('the file was changed on the way');
      }
      if (originalHash != null &&
          HEX.encode(plainHash.close().bytes).toLowerCase() !=
              originalHash.toLowerCase()) {
        throw const StreamCryptoException('the file was changed on the way');
      }

      await out.flush();
      await out.close();
      out = null;
      finished = true;
    } on StreamCryptoException {
      rethrow;
    } on InvalidCipherTextException {
      throw const StreamCryptoException('the file is damaged or was changed');
    } catch (e) {
      throw StreamCryptoException('download failed: $e');
    } finally {
      await out?.close();
      if (!finished) {
        try {
          await target.delete();
        } catch (_) {}
      }
      // Stop reading as soon as a check fails, so a bad file does not keep the
      // connection busy until the whole download is done.
      await reader.cancel();
    }
  }

  static ({int plainSize, int chunkSize, int totalChunks}) _parseHeader(
    Uint8List header,
  ) {
    if (header.length != StreamKey.headerBytes) {
      throw const StreamCryptoException('the file is not complete');
    }
    for (var i = 0; i < StreamKey.magic.length; i++) {
      if (header[i] != StreamKey.magic[i]) {
        throw const StreamCryptoException('not a Chatme file');
      }
    }

    final view = ByteData.sublistView(header);
    final chunkSize = view.getUint32(4);
    final totalChunks = view.getUint32(8);
    final plainSize = view.getUint64(12);

    if (chunkSize < 4096 || chunkSize > StreamKey.maxChunkSize) {
      throw const StreamCryptoException('the file header is not valid');
    }
    // A negative value means the sender set the top bit of the 64 bit size.
    if (plainSize < 0 || plainSize > (1 << 42)) {
      throw const StreamCryptoException('the file is too large');
    }
    if (totalChunks != StreamKey.chunkCountFor(plainSize, chunkSize)) {
      throw const StreamCryptoException('the file header is not valid');
    }

    return (
      plainSize: plainSize,
      chunkSize: chunkSize,
      totalChunks: totalChunks,
    );
  }

  static int _plainLengthFor(int plainSize, int chunkSize, int index) {
    final left = plainSize - index * chunkSize;
    return left < chunkSize ? left : chunkSize;
  }

  static Future<Uint8List> _open(
    Uint8List sealed,
    int index,
    Uint8List key,
    Uint8List nonce,
    Uint8List header,
    Aead engine,
  ) {
    return engine.open(
      key: key,
      nonce: StreamKey._nonceFor(nonce, index),
      aad: StreamKey._aadFor(header, index),
      sealed: sealed,
    );
  }

  static Uint8List _decodeHex(String value, int length, String name) {
    final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(HEX.decode(value));
    } on FormatException {
      throw StreamCryptoException('$name is not valid hex');
    }
    if (bytes.length != length) {
      throw StreamCryptoException('$name must be $length bytes');
    }
    return bytes;
  }
}

/// Reads exact frames out of a stream that arrives in arbitrary pieces.
class _FrameReader {
  _FrameReader(Stream<List<int>> source) : _iterator = StreamIterator(source);

  final StreamIterator<List<int>> _iterator;
  List<int>? _current;
  int _offset = 0;

  Future<Uint8List> read(int count) async {
    final out = Uint8List(count);
    var filled = 0;

    while (filled < count) {
      final chunk = _current;
      if (chunk == null || _offset >= chunk.length) {
        if (!await _iterator.moveNext()) {
          throw const StreamCryptoException('the download stopped too early');
        }
        _current = _iterator.current;
        _offset = 0;
        continue;
      }

      final take = min(count - filled, chunk.length - _offset);
      out.setRange(filled, filled + take, chunk, _offset);
      _offset += take;
      filled += take;
    }

    return out;
  }

  Future<bool> hasMore() async {
    final chunk = _current;
    if (chunk != null && _offset < chunk.length) return true;
    return _iterator.moveNext();
  }

  /// Releases the source stream without reading the rest of it.
  Future<void> cancel() async {
    try {
      await _iterator.cancel();
    } catch (_) {}
  }
}

class _DigestBuilder {
  final _DigestSink _sink = _DigestSink();
  late final ByteConversionSink _input = sha256.startChunkedConversion(_sink);

  void add(List<int> bytes) => _input.add(bytes);

  Digest close() {
    _input.close();
    final digest = _sink.value;
    if (digest == null) {
      throw const StreamCryptoException('the file could not be checked');
    }
    return digest;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
