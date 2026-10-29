// chat_message_file_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17_file.dart';
import 'package:chatme/models/chat_message.dart';

void main() {
  final key = 'a' * 64;
  final nonce = 'b' * 32;
  final hash = 'c' * 64;

  final file = FileMessage(
    url: 'https://files.example/x.bin',
    mimeType: 'audio/mp4',
    key: key,
    nonce: nonce,
    hash: hash,
    originalHash: 'd' * 64,
    size: 1234,
    durationSeconds: 7,
  );

  ChatMessage build({Map<String, String> fileMap = const {}, String localPath = ''}) => ChatMessage(
        id: 'id1',
        senderPubkey: 'a',
        receiverPubkey: 'b',
        content: 'c',
        plaintext: 'Voice message',
        timestamp: 1,
        chatKey: 'k',
        file: fileMap,
        localPath: localPath,
      );

  test('FileMessage survives toMap and fromMap', () {
    final back = FileMessage.fromMap(file.toMap())!;
    expect(back.url, file.url);
    expect(back.mimeType, file.mimeType);
    expect(back.key, key);
    expect(back.nonce, nonce);
    expect(back.hash, hash);
    expect(back.originalHash, 'd' * 64);
    expect(back.size, 1234);
    expect(back.durationSeconds, 7);
  });

  test('fromMap returns null when a required value is missing', () {
    final map = file.toMap()..remove('key');
    expect(FileMessage.fromMap(map), isNull);
  });

  test('a text message has no file', () {
    final message = build();
    expect(message.hasFile, isFalse);
    expect(message.isVoiceNote, isFalse);
    expect(message.isDownloaded, isFalse);
    expect(message.fileMessage, isNull);
  });

  test('a voice note message knows it is a voice note', () {
    final message = build(fileMap: file.toMap());
    expect(message.hasFile, isTrue);
    expect(message.isVoiceNote, isTrue);
    expect(message.fileMessage!.durationSeconds, 7);
  });

  test('an image file is not a voice note', () {
    final image = FileMessage(
      url: file.url,
      mimeType: 'image/jpeg',
      key: key,
      nonce: nonce,
      hash: hash,
    );
    expect(build(fileMap: image.toMap()).isVoiceNote, isFalse);
  });

  test('copyWith keeps the file and can set the local path', () {
    final message = build(fileMap: file.toMap());
    final saved = message.copyWith(localPath: '/data/x.m4a');
    expect(saved.isDownloaded, isTrue);
    expect(saved.file, message.file);
    expect(message.copyWith(status: 'read').localPath, '');
  });

  test('toMap and fromMap keep the file fields', () {
    final message = build(fileMap: file.toMap(), localPath: '/data/x.m4a');
    final back = ChatMessage.fromMap(message.toMap());
    expect(back.file, message.file);
    expect(back.localPath, '/data/x.m4a');
  });

  test('old maps without file fields still load', () {
    final map = build().toMap()
      ..remove('file')
      ..remove('localPath');
    final back = ChatMessage.fromMap(map);
    expect(back.hasFile, isFalse);
    expect(back.localPath, '');
  });
}
