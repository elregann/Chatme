// blossom_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:bip340/bip340.dart' as bip340;
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;
import '../core/crypto/crypto_utils.dart';
import '../core/crypto/file_crypto.dart';
import '../core/crypto/nostr_protocol.dart';
import 'server_lists.dart';

class BlossomException implements Exception {
  final String message;
  const BlossomException(this.message);

  @override
  String toString() => 'BlossomException: $message';
}

class BlossomBlob {
  final String url;
  final String sha256;
  final int? size;
  final String? type;

  const BlossomBlob({
    required this.url,
    required this.sha256,
    this.size,
    this.type,
  });
}

class BlossomService {
  BlossomService._();

  static const String defaultServer = 'https://blossom.ditto.pub';
  static const List<String> defaultServers = BlossomDefaults.servers;
  static const int maxDownloadBytes = 32 * 1024 * 1024;
  static const Duration _timeout = Duration(minutes: 2);
  static const Duration _testTimeout = Duration(seconds: 20);

  /// A big video may be sent over a slow phone connection; the body can take
  /// far longer than the normal timeout, so only the answer has a sane limit.
  static const Duration _streamUploadTimeout = Duration(minutes: 30);

  /// A video download may take minutes, but it should not wait forever for a
  /// connection that stopped sending bytes.
  static const Duration _streamIdleTimeout = Duration(seconds: 60);
  static const int _authTtlSeconds = 300;
  static const int _authBackdateSeconds = 10;

  /// Signed kind 24242 event that authorizes one upload of the blob [hash].
  static Map<String, dynamic> buildAuthEvent({
    required String pubkey,
    required String privkey,
    required String hash,
    String content = 'Upload file',
    int? now,
  }) {
    final seconds = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final unsigned = <String, dynamic>{
      'kind': 24242,
      'pubkey': pubkey,
      'created_at': seconds - _authBackdateSeconds,
      'tags': [
        ['t', 'upload'],
        ['x', hash],
        ['expiration', '${seconds + _authTtlSeconds}'],
      ],
      'content': content,
    };
    final id = NostrSigner.calculateEventId(unsigned);
    return {...unsigned, 'id': id, 'sig': NostrSigner.sign(id, privkey)};
  }

  /// A key made for one upload and then forgotten, so the server never sees
  /// the account key and cannot link uploads to a person or to each other.
  static ({String privkey, String pubkey}) _throwawayKey() {
    final privkey = HEX.encode(CryptoUtils.generateSecureRandomBytes(32));
    return (privkey: privkey, pubkey: bip340.getPublicKey(privkey));
  }

  /// A one-use upload key that the caller keeps when it needs to delete the
  /// blob later. Chat uses [_throwawayKey] instead and forgets the key.
  static ({String privkey, String pubkey}) generateUploadKey() => _throwawayKey();

  /// Signed kind 24242 event authorizing one delete on one server. BUD-11
  /// server scoping keeps a leaked token useless anywhere else.
  static Map<String, dynamic> buildDeleteAuthEvent({
    required String pubkey,
    required String privkey,
    required String hash,
    required String server,
    String content = 'Delete file',
    int? now,
  }) {
    final serverHost = Uri.tryParse(server)?.host ?? '';
    if (serverHost.isEmpty) {
      throw const BlossomException('delete server must be a URL');
    }
    final seconds = now ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final unsigned = <String, dynamic>{
      'kind': 24242,
      'pubkey': pubkey,
      'created_at': seconds - _authBackdateSeconds,
      'tags': [
        ['t', 'delete'],
        ['x', hash.toLowerCase()],
        ['server', serverHost],
        ['expiration', '${seconds + _authTtlSeconds}'],
      ],
      'content': content,
    };
    final id = NostrSigner.calculateEventId(unsigned);
    return {...unsigned, 'id': id, 'sig': NostrSigner.sign(id, privkey)};
  }

  static String authHeader(Map<String, dynamic> event) {
    return 'Nostr ${base64.encode(utf8.encode(jsonEncode(event)))}';
  }

  /// BUD-11 asks for unpadded base64url, unlike the older header [authHeader].
  static String deleteAuthHeader(Map<String, dynamic> event) {
    final encoded = base64Url.encode(utf8.encode(jsonEncode(event)));
    return 'Nostr ${encoded.replaceAll('=', '')}';
  }

  static const String _userAgent = 'Chatme/1.0 (Flutter)';

  static String _base(String server) {
    return server.endsWith('/') ? server.substring(0, server.length - 1) : server;
  }

  /// Uploads [bytes] (normally an encrypted file, so the content type is
  /// generic) and returns what the server says it stored.
  static Future<BlossomBlob> upload(
      Uint8List bytes, {
        String contentType = 'application/octet-stream',
        String server = defaultServer,
        String description = 'Upload file',
        http.Client? client,
      }) async {
    final hash = FileCrypto.sha256Hex(bytes);
    final key = _throwawayKey();
    final event = buildAuthEvent(
      pubkey: key.pubkey,
      privkey: key.privkey,
      hash: hash,
      content: description,
    );
    final http.Client httpClient = client ?? http.Client();

    try {
      final response = await httpClient
          .put(
        Uri.parse('${_base(server)}/upload'),
        headers: {
          'Authorization': authHeader(event),
          'Content-Type': contentType,
          'X-SHA-256': hash,
          if (!kIsWeb) 'User-Agent': _userAgent,
        },
        body: bytes,
      )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason = response.headers['x-reason'];
        throw BlossomException(
          'upload failed (${response.statusCode})${reason == null ? '' : ': $reason'}',
        );
      }

      return _storedBlob(response.body, hash);
    } on BlossomException {
      rethrow;
    } catch (e) {
      throw BlossomException('upload failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Same upload as [upload], but with a caller-owned key so the caller can
  /// sign a delete later. Normal chat uploads keep using [upload].
  static Future<BlossomBlob> uploadWithKey(
    Uint8List bytes, {
    required ({String privkey, String pubkey}) key,
    String contentType = 'application/octet-stream',
    String server = defaultServer,
    String description = 'Upload file',
    http.Client? client,
  }) async {
    final hash = FileCrypto.sha256Hex(bytes);
    final event = buildAuthEvent(
      pubkey: key.pubkey,
      privkey: key.privkey,
      hash: hash,
      content: description,
    );
    final http.Client httpClient = client ?? http.Client();

    try {
      final response = await httpClient
          .put(
        Uri.parse('${_base(server)}/upload'),
        headers: {
          'Authorization': authHeader(event),
          'Content-Type': contentType,
          'X-SHA-256': hash,
          if (!kIsWeb) 'User-Agent': _userAgent,
        },
        body: bytes,
      )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason = response.headers['x-reason'];
        throw BlossomException(
          'upload failed (${response.statusCode})${reason == null ? '' : ': $reason'}',
        );
      }

      return _storedBlob(response.body, hash);
    } on BlossomException {
      rethrow;
    } catch (e) {
      throw BlossomException('upload failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Reads the answer of a successful upload and checks that the server kept
  /// the exact bytes we sent.
  static BlossomBlob _storedBlob(String body, String hash) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const BlossomException('server sent an invalid answer');
    }
    if (decoded is! Map || decoded['url'] is! String || decoded['sha256'] is! String) {
      throw const BlossomException('server sent an invalid answer');
    }

    final storedHash = (decoded['sha256'] as String).toLowerCase();
    if (storedHash != hash) {
      throw const BlossomException('server stored a different file');
    }

    return BlossomBlob(
      url: decoded['url'] as String,
      sha256: storedHash,
      size: decoded['size'] is int ? decoded['size'] as int : null,
      type: decoded['type'] is String ? decoded['type'] as String : null,
    );
  }

  /// Uploads a stream whose length and sha256 are already known. This is the
  /// path for videos: the encrypted file is never kept in memory and never
  /// written to a temporary file.
  ///
  /// [open] is called for every attempt, so a fallback server gets a fresh
  /// stream from the start of the file.
  static Future<BlossomBlob> uploadStream({
    required Stream<List<int>> Function() open,
    required int length,
    required String hash,
    String contentType = 'application/octet-stream',
    String server = defaultServer,
    String description = 'Upload file',
    http.Client? client,
  }) async {
    final key = _throwawayKey();
    final event = buildAuthEvent(
      pubkey: key.pubkey,
      privkey: key.privkey,
      hash: hash,
      content: description,
    );
    final http.Client httpClient = client ?? http.Client();

    try {
      final request = _StreamPutRequest(
        Uri.parse('${_base(server)}/upload'),
        open(),
        length: length,
        headers: {
          'Authorization': authHeader(event),
          'Content-Type': contentType,
          'X-SHA-256': hash,
          if (!kIsWeb) 'User-Agent': _userAgent,
        },
      );

      final streamed = await httpClient.send(request).timeout(_streamUploadTimeout);
      final body = await streamed.stream.bytesToString().timeout(_timeout);

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final reason = streamed.headers['x-reason'];
        throw BlossomException(
          'upload failed (${streamed.statusCode})${reason == null ? '' : ': $reason'}',
        );
      }

      return _storedBlob(body, hash);
    } on BlossomException {
      rethrow;
    } catch (e) {
      throw BlossomException('upload failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Tries [servers] in order with the same streamed file. [open] must start
  /// again from the first byte every time it is called.
  static Future<BlossomBlob> uploadStreamToAny({
    required Stream<List<int>> Function() open,
    required int length,
    required String hash,
    List<String> servers = defaultServers,
    String description = 'Upload file',
    http.Client? client,
  }) async {
    BlossomException? last;
    for (final server in servers) {
      try {
        return await uploadStream(
          open: open,
          length: length,
          hash: hash,
          server: server,
          description: description,
          client: client,
        );
      } on BlossomException catch (e) {
        last = BlossomException('${Uri.tryParse(server)?.host ?? server}: ${e.message}');
      }
    }
    throw last ?? const BlossomException('no upload server configured');
  }

  /// Uploads a few random bytes to [server] to see that it takes files from us.
  /// The bytes are not a real file and are different every time.
  static Future<void> testUpload(String server, {http.Client? client}) async {
    final bytes = CryptoUtils.generateSecureRandomBytes(64);
    try {
      await upload(
        bytes,
        server: server,
        description: 'Test upload',
        client: client,
      ).timeout(_testTimeout);
    } on TimeoutException {
      throw const BlossomException('server did not answer in time');
    }
  }

  /// Tries [servers] in order and returns the first upload that works. Some
  /// servers refuse files that are not real media, which every encrypted file is.
  static Future<BlossomBlob> uploadToAny(
      Uint8List bytes, {
        List<String> servers = defaultServers,
        String description = 'Upload file',
        http.Client? client,
      }) async {
    BlossomException? last;
    for (final server in servers) {
      try {
        return await upload(
          bytes,
          server: server,
          description: description,
          client: client,
        );
      } on BlossomException catch (e) {
        last = BlossomException('${Uri.tryParse(server)?.host ?? server}: ${e.message}');
      }
    }
    throw last ?? const BlossomException('no upload server configured');
  }

  /// Tries [servers] in order with one caller-owned upload key, for uploads
  /// whose blob may have to be deleted later.
  static Future<BlossomBlob> uploadToAnyWithKey(
    Uint8List bytes, {
    required ({String privkey, String pubkey}) key,
    List<String> servers = defaultServers,
    String description = 'Upload file',
    http.Client? client,
  }) async {
    BlossomException? last;
    for (final server in servers) {
      try {
        return await uploadWithKey(
          bytes,
          key: key,
          server: server,
          description: description,
          client: client,
        );
      } on BlossomException catch (e) {
        last = BlossomException('${Uri.tryParse(server)?.host ?? server}: ${e.message}');
      }
    }
    throw last ?? const BlossomException('no upload server configured');
  }

  /// Asks the server named in [url] to delete the blob [hash]. The signed key
  /// must be the one that uploaded it. This best-effort call only removes the
  /// server's record; mirrors and events already on relays are untouched.
  static Future<void> delete(
    String url, {
    required String hash,
    required ({String privkey, String pubkey}) key,
    http.Client? client,
  }) async {
    final blobHash = hash.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(blobHash)) {
      throw const BlossomException('invalid blob hash');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const BlossomException('file address must be https');
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    final origin = '${uri.scheme}://${uri.host}$port';
    final event = buildDeleteAuthEvent(
      pubkey: key.pubkey,
      privkey: key.privkey,
      hash: blobHash,
      server: origin,
      content: 'Delete story blob',
    );
    final http.Client httpClient = client ?? http.Client();

    try {
      final response = await httpClient
          .delete(
        Uri.parse('${_base(origin)}/$blobHash'),
        headers: {
          'Authorization': deleteAuthHeader(event),
          if (!kIsWeb) 'User-Agent': _userAgent,
        },
      )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason = response.headers['x-reason'];
        throw BlossomException(
          'delete failed (${response.statusCode})${reason == null ? '' : ': $reason'}',
        );
      }
    } on BlossomException {
      rethrow;
    } catch (e) {
      throw BlossomException('delete failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Downloads [url]. The address comes from the sender, so only https is
  /// accepted and the size is capped. With [expectedHash] the bytes are
  /// checked before they are returned.
  static Future<Uint8List> download(
      String url, {
        String? expectedHash,
        int maxBytes = maxDownloadBytes,
        http.Client? client,
      }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const BlossomException('file address must be https');
    }
    final http.Client httpClient = client ?? http.Client();

    try {
      return await () async {
        final request = http.Request('GET', uri);
        if (!kIsWeb) request.headers['User-Agent'] = _userAgent;
        final streamed = await httpClient.send(request);
        if (streamed.statusCode != 200) {
          throw BlossomException('download failed (${streamed.statusCode})');
        }
        final length = streamed.contentLength;
        if (length != null && length > maxBytes) {
          throw const BlossomException('file is too large');
        }

        final builder = BytesBuilder(copy: false);
        await for (final chunk in streamed.stream) {
          builder.add(chunk);
          if (builder.length > maxBytes) {
            throw const BlossomException('file is too large');
          }
        }
        final bytes = builder.takeBytes();

        if (expectedHash != null &&
            FileCrypto.sha256Hex(bytes) != expectedHash.toLowerCase()) {
          throw const BlossomException('downloaded file hash does not match');
        }
        return bytes;
      }()
          .timeout(_timeout);
    } on BlossomException {
      rethrow;
    } catch (e) {
      throw BlossomException('download failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Streams [url] without keeping it in memory, for the chunked (video) path.
  /// Only https is accepted and the caller checks what arrives. The stream
  /// reports an error when the connection stops for a minute.
  static Stream<List<int>> downloadStreamed(String url, {http.Client? client}) async* {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const BlossomException('file address must be https');
    }
    final http.Client httpClient = client ?? http.Client();

    try {
      final request = http.Request('GET', uri);
      if (!kIsWeb) request.headers['User-Agent'] = _userAgent;
      final streamed = await httpClient.send(request).timeout(_timeout);
      if (streamed.statusCode != 200) {
        throw BlossomException('download failed (${streamed.statusCode})');
      }
      yield* streamed.stream.timeout(_streamIdleTimeout);
    } on BlossomException {
      rethrow;
    } on TimeoutException {
      throw const BlossomException('download stopped answering');
    } catch (e) {
      throw BlossomException('download failed: $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }
}

/// A PUT whose body is read from a stream, with the length known up front.
/// The normal [http.Request] would need the whole file as a byte list.
class _StreamPutRequest extends http.BaseRequest {
  final Stream<List<int>> _body;

  _StreamPutRequest(
    Uri url,
    this._body, {
    required int length,
    required Map<String, String> headers,
  }) : super('PUT', url) {
    contentLength = length;
    this.headers.addAll(headers);
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}
