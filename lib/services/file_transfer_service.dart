// file_transfer_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/crypto/file_crypto.dart';
import '../core/crypto/nip17_file.dart';
import '../core/crypto/stream_crypto.dart';
import 'blossom_service.dart';
import 'storage_space.dart';

class FileTransferException implements Exception {
  final String message;
  const FileTransferException(this.message);

  @override
  String toString() => message;
}

/// Downloads a kind 15 file, checks it, decrypts it and saves it in the app folder.
class FileTransferService {
  static String extensionFor(String mimeType) {
    switch (mimeType.toLowerCase().split(';').first.trim()) {
      case 'audio/mp4':
      case 'audio/m4a':
      case 'audio/x-m4a':
      case 'audio/aac':
        return 'm4a';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/ogg':
        return 'ogg';
      case 'audio/webm':
        return 'webm';
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'video/mp4':
        return 'mp4';
      case 'video/quicktime':
        return 'mov';
      case 'video/webm':
        return 'webm';
      case 'video/x-matroska':
        return 'mkv';
      case 'video/3gpp':
        return '3gp';
      case 'video/ogg':
        return 'ogv';
      case 'video/x-msvideo':
        return 'avi';
      default:
        return 'bin';
    }
  }

  /// Returns the path of the saved file. The name comes from the file hash, never
  /// from anything the sender wrote, so a hostile message cannot pick a path.
  ///
  /// A chunked (video) file is written straight to a `.part` file while it is
  /// downloaded and only renamed when every check passed. A failure removes the
  /// partial file, so a broken download never looks like a real video.
  static Future<String> downloadAndSave(
    FileMessage file, {
    required Directory directory,
    http.Client? client,
    void Function(int received, int total)? onProgress,
  }) async {
    final name = (file.originalHash ?? file.hash).toLowerCase();
    final target = File('${directory.path}${Platform.pathSeparator}$name.${extensionFor(file.mimeType)}');
    if (await target.exists()) return target.path;

    await directory.create(recursive: true);

    if (file.isStreamed) {
      await _downloadStreamed(
        file,
        target,
        client: client,
        onProgress: onProgress,
      );
      return target.path;
    }

    final Uint8List encrypted;
    final Uint8List plain;
    try {
      encrypted = await BlossomService.download(
        file.url,
        expectedHash: file.hash,
        client: client,
      );
      plain = FileCrypto.decrypt(
        encrypted,
        key: file.key,
        nonce: file.nonce,
        hash: file.hash,
        originalHash: file.originalHash,
      );
    } on BlossomException catch (e) {
      throw FileTransferException('download failed: ${e.message}');
    } on FileCryptoException catch (e) {
      throw FileTransferException('file is not valid: ${e.message}');
    }

    final temp = File('${target.path}.part');
    await temp.writeAsBytes(plain, flush: true);
    await temp.rename(target.path);
    return target.path;
  }

  static Future<void> _downloadStreamed(
    FileMessage file,
    File target, {
    http.Client? client,
    void Function(int received, int total)? onProgress,
  }) async {
    final plainSize = file.plainSize;
    if (plainSize != null) {
      final free = await StorageSpace.freeBytes();
      if (free != null && free < StorageSpace.requiredFor(plainSize)) {
        throw const FileTransferException('Not enough space on the phone');
      }
    }

    final temp = File('${target.path}.part');
    try {
      await _deleteQuietly(temp);
      await StreamFileCrypto.decryptToFile(
        ciphertext: BlossomService.downloadStreamed(file.url, client: client),
        target: temp,
        key: file.key,
        nonce: file.nonce,
        hash: file.hash,
        originalHash: file.originalHash,
        encryptedSize: file.size,
        onProgress: onProgress,
      );
      if (await target.exists()) {
        // Two downloads of the same file finished at the same time.
        return;
      }
      await temp.rename(target.path);
    } on StreamCryptoException catch (e) {
      throw FileTransferException(_streamErrorMessage(e.message));
    } on BlossomException catch (e) {
      throw FileTransferException('download failed: ${e.message}');
    } on FileSystemException catch (e) {
      throw FileTransferException(_streamErrorMessage(e.message));
    } finally {
      await _deleteQuietly(temp);
    }
  }

  /// Turns the internal error into something the chat bubble can show without
  /// leaking a whole operating system stack trace.
  static String _streamErrorMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('no space') || lower.contains('enospc')) {
      return 'Not enough space on the phone';
    }
    if (message.startsWith('download failed')) return 'download failed';
    return 'file is not valid: $message';
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
