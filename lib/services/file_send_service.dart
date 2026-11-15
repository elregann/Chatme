// file_send_service.dart

import 'dart:io';
import 'package:http/http.dart' as http;
import '../core/crypto/file_crypto.dart';
import '../core/crypto/nip17_file.dart';
import '../core/crypto/stream_crypto.dart';
import 'blossom_service.dart';

class FileSendService {
  static const String voiceMimeType = 'audio/mp4';

  /// Encrypts [source], uploads it to the first server that takes it and
  /// returns everything the receiver needs to open it.
  static Future<FileMessage> encryptAndUpload({
    required File source,
    required String mimeType,
    int? durationSeconds,
    int? width,
    int? height,
    List<String> servers = BlossomService.defaultServers,
    http.Client? client,
  }) async {
    final plain = await source.readAsBytes();
    final encrypted = FileCrypto.encrypt(plain);

    final blob = await BlossomService.uploadToAny(
      encrypted.bytes,
      servers: servers,
      client: client,
    );

    final uri = Uri.tryParse(blob.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const BlossomException('server gave an address that is not https');
    }

    return FileMessage(
      url: blob.url,
      mimeType: mimeType,
      key: encrypted.key,
      nonce: encrypted.nonce,
      hash: encrypted.hash,
      originalHash: encrypted.originalHash,
      size: encrypted.bytes.length,
      durationSeconds: durationSeconds,
      width: width,
      height: height,
    );
  }

  /// Encrypts [source] in chunks and uploads it while it is encrypted, for
  /// videos that are too large to hold in memory. The file is read twice: once
  /// to build the key, nonce and hashes, then again to encrypt and upload.
  static Future<FileMessage> encryptAndUploadStreaming({
    required File source,
    required String mimeType,
    int? durationSeconds,
    int? width,
    int? height,
    List<String> servers = BlossomService.defaultServers,
    http.Client? client,
  }) async {
    final key = await StreamKey.prepare(source);

    final blob = await BlossomService.uploadStreamToAny(
      open: () => key.openEncrypted(source),
      length: key.encryptedSize,
      hash: key.ciphertextHash,
      servers: servers,
      client: client,
    );

    final uri = Uri.tryParse(blob.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const BlossomException('server gave an address that is not https');
    }

    return FileMessage(
      url: blob.url,
      mimeType: mimeType,
      key: key.keyHex,
      nonce: key.nonceHex,
      hash: key.ciphertextHash,
      algorithm: FileMessage.chunkedAlgorithm,
      originalHash: key.plaintextHash,
      size: key.encryptedSize,
      plainSize: key.plainSize,
      durationSeconds: durationSeconds,
      width: width,
      height: height,
    );
  }

  /// Moves [source] into [directory] under [name]. Falls back to copy and
  /// delete when the two folders are on different storage.
  static Future<File> moveIntoFolder(File source, Directory directory, String name) async {
    await directory.create(recursive: true);
    final target = '${directory.path}${Platform.pathSeparator}$name';
    try {
      return await source.rename(target);
    } on FileSystemException {
      final copy = await source.copy(target);
      await source.delete();
      return copy;
    }
  }
}
