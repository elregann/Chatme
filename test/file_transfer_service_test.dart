// file_transfer_service_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatme/core/crypto/file_crypto.dart';
import 'package:chatme/core/crypto/nip17_file.dart';
import 'package:chatme/services/file_transfer_service.dart';

void main() {
  late Directory dir;
  late Uint8List plain;
  late EncryptedFile encrypted;
  late FileMessage file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chatme_transfer_test');
    plain = Uint8List.fromList(utf8.encode('pretend this is a voice note'));
    encrypted = FileCrypto.encrypt(plain);
    file = FileMessage(
      url: 'https://files.example/${encrypted.hash}.bin',
      mimeType: 'audio/mp4',
      key: encrypted.key,
      nonce: encrypted.nonce,
      hash: encrypted.hash,
      originalHash: encrypted.originalHash,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('downloads, decrypts and saves under the hash of the original', () async {
    final client = MockClient((_) async => http.Response.bytes(encrypted.bytes, 200));

    final path = await FileTransferService.downloadAndSave(file, directory: dir, client: client);

    expect(path, endsWith('${encrypted.originalHash}.m4a'));
    expect(File(path).readAsBytesSync(), plain);
    expect(dir.listSync().length, 1);
  });

  test('a file that is already saved is not downloaded again', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes(encrypted.bytes, 200);
    });

    await FileTransferService.downloadAndSave(file, directory: dir, client: client);
    await FileTransferService.downloadAndSave(file, directory: dir, client: client);

    expect(calls, 1);
  });

  test('creates the folder when it does not exist yet', () async {
    final client = MockClient((_) async => http.Response.bytes(encrypted.bytes, 200));
    final inner = Directory('${dir.path}/voice/notes');

    final path = await FileTransferService.downloadAndSave(file, directory: inner, client: client);

    expect(File(path).existsSync(), isTrue);
  });

  test('a server that returns another file is rejected and nothing is saved', () async {
    final other = FileCrypto.encrypt(Uint8List.fromList(utf8.encode('something else')));
    final client = MockClient((_) async => http.Response.bytes(other.bytes, 200));

    await expectLater(
      FileTransferService.downloadAndSave(file, directory: dir, client: client),
      throwsA(isA<FileTransferException>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('a wrong key is rejected and nothing is saved', () async {
    final wrongKey = FileMessage(
      url: file.url,
      mimeType: file.mimeType,
      key: FileCrypto.encrypt(plain).key,
      nonce: file.nonce,
      hash: file.hash,
      originalHash: file.originalHash,
    );
    final client = MockClient((_) async => http.Response.bytes(encrypted.bytes, 200));

    await expectLater(
      FileTransferService.downloadAndSave(wrongKey, directory: dir, client: client),
      throwsA(isA<FileTransferException>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('a server error becomes a transfer error', () async {
    final client = MockClient((_) async => http.Response('', 404));

    await expectLater(
      FileTransferService.downloadAndSave(file, directory: dir, client: client),
      throwsA(isA<FileTransferException>()),
    );
  });

  test('a plain http address is refused', () async {
    final insecure = FileMessage(
      url: 'http://files.example/a.bin',
      mimeType: file.mimeType,
      key: file.key,
      nonce: file.nonce,
      hash: file.hash,
      originalHash: file.originalHash,
    );
    final client = MockClient((_) async => http.Response.bytes(encrypted.bytes, 200));

    await expectLater(
      FileTransferService.downloadAndSave(insecure, directory: dir, client: client),
      throwsA(isA<FileTransferException>()),
    );
  });

  test('file types map to extensions', () {
    expect(FileTransferService.extensionFor('audio/mp4'), 'm4a');
    expect(FileTransferService.extensionFor('audio/mp4; codecs=mp4a.40.2'), 'm4a');
    expect(FileTransferService.extensionFor('image/jpeg'), 'jpg');
    expect(FileTransferService.extensionFor('application/x-weird'), 'bin');
  });
}
