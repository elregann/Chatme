// file_transfer_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/crypto/file_crypto.dart';
import '../core/crypto/nip17_file.dart';
import 'blossom_service.dart';

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
      default:
        return 'bin';
    }
  }

  /// Returns the path of the saved file. The name comes from the file hash, never
  /// from anything the sender wrote, so a hostile message cannot pick a path.
  static Future<String> downloadAndSave(
    FileMessage file, {
    required Directory directory,
    http.Client? client,
  }) async {
    final name = (file.originalHash ?? file.hash).toLowerCase();
    final target = File('${directory.path}${Platform.pathSeparator}$name.${extensionFor(file.mimeType)}');
    if (await target.exists()) return target.path;

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

    await directory.create(recursive: true);
    final temp = File('${target.path}.part');
    await temp.writeAsBytes(plain, flush: true);
    await temp.rename(target.path);
    return target.path;
  }
}
