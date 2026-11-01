// image_message_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17_file.dart';
import 'package:chatme/models/chat_message.dart';

void main() {
  final key = 'a' * 64;
  final nonce = 'b' * 32;
  final hash = 'c' * 64;

  FileMessage image({int? width = 1600, int? height = 1200}) => FileMessage(
        url: 'https://files.example/x.bin',
        mimeType: 'image/jpeg',
        key: key,
        nonce: nonce,
        hash: hash,
        originalHash: 'd' * 64,
        size: 2048,
        width: width,
        height: height,
      );

  ChatMessage message(Map<String, String> file) => ChatMessage(
        id: 'id1',
        senderPubkey: 'a',
        receiverPubkey: 'b',
        content: 'c',
        plaintext: 'Photo',
        timestamp: 1,
        chatKey: 'k',
        file: file,
      );

  group('dim tag', () {
    test('is written as widthxheight', () {
      expect(image().toTags(), contains(['dim', '1600x1200']));
    });

    test('is left out when the size is unknown', () {
      expect(image(width: null, height: null).toTags().where((t) => t[0] == 'dim'), isEmpty);
    });

    test('survives toMap and fromMap', () {
      final back = FileMessage.fromMap(image().toMap())!;
      expect((back.width, back.height), (1600, 1200));
    });

    test('survives a rumor round trip', () {
      final tags = image().rumorTags(receiver: 'f' * 64);
      final back = FileMessage.parse(content: image().url, tags: tags)!;
      expect((back.width, back.height), (1600, 1200));
      expect(back.isImage, isTrue);
    });

    test('a damaged or absurd value is ignored, the file still opens', () {
      for (final bad in ['abc', '0x0', '-5x10', '99999999x10', '10x', 'x10', '10 x 10']) {
        final tags = [
          ...image(width: null, height: null).rumorTags(receiver: 'f' * 64),
          ['dim', bad],
        ];
        final back = FileMessage.parse(content: image().url, tags: tags);
        expect(back, isNotNull, reason: bad);
        expect(back!.width, isNull, reason: bad);
      }
    });
  });

  group('labels', () {
    test('tell a photo, a voice note and another file apart', () {
      expect(image().previewLabel, 'Photo');
      expect(
        FileMessage(url: 'https://a.example/x', mimeType: 'audio/mp4', key: key, nonce: nonce, hash: hash).previewLabel,
        'Voice message',
      );
      expect(
        FileMessage(url: 'https://a.example/x', mimeType: 'application/pdf', key: key, nonce: nonce, hash: hash).previewLabel,
        'File',
      );
    });
  });

  group('ChatMessage', () {
    test('knows it holds an image', () {
      expect(message(image().toMap()).isImage, isTrue);
      expect(message(image().toMap()).isVoiceNote, isFalse);
      expect(message(const {}).isImage, isFalse);
    });

    test('gives the aspect ratio from the size', () {
      expect(message(image().toMap()).imageAspectRatio, closeTo(4 / 3, 0.0001));
    });

    test('keeps the ratio inside a sensible range', () {
      expect(message(image(width: 4000, height: 100).toMap()).imageAspectRatio, 2.5);
      expect(message(image(width: 100, height: 4000).toMap()).imageAspectRatio, 0.4);
    });

    test('falls back to a square when the size is unknown', () {
      expect(message(image(width: null, height: null).toMap()).imageAspectRatio, 1.0);
    });
  });
}
