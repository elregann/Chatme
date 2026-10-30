// voice_history_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/models/chat_message.dart';
import 'package:chatme/services/voice_history.dart';

void main() {
  ChatMessage msg(String id, int ts, {Map<String, String> file = const {}}) => ChatMessage(
        id: id,
        senderPubkey: 'a',
        receiverPubkey: 'b',
        content: 'c',
        plaintext: 'p',
        timestamp: ts,
        chatKey: 'k',
        file: file,
      );

  const voice = {'type': 'audio/mp4', 'duration': '10'};
  const image = {'type': 'image/jpeg'};

  group('voiceNotesNewestFirst', () {
    test('keeps only voice notes', () {
      final out = voiceNotesNewestFirst([
        msg('text', 1),
        msg('img', 2, file: image),
        msg('vn', 3, file: voice),
      ]);
      expect(out.map((m) => m.id), ['vn']);
    });

    test('puts the newest first', () {
      final out = voiceNotesNewestFirst([
        msg('old', 100, file: voice),
        msg('new', 300, file: voice),
        msg('mid', 200, file: voice),
      ]);
      expect(out.map((m) => m.id), ['new', 'mid', 'old']);
    });

    test('empty input gives empty output', () {
      expect(voiceNotesNewestFirst(const []), isEmpty);
    });

    test('does not change the input list', () {
      final input = [msg('a', 1, file: voice), msg('b', 2, file: voice)];
      voiceNotesNewestFirst(input);
      expect(input.map((m) => m.id), ['a', 'b']);
    });
  });

  group('voiceDateLabel', () {
    test('morning', () {
      expect(voiceDateLabel(DateTime(2026, 10, 8, 1, 45)), 'Oct 08 at 1:45 AM');
    });

    test('evening', () {
      expect(voiceDateLabel(DateTime(2026, 9, 12, 20, 9)), 'Sep 12 at 8:09 PM');
    });

    test('midnight and noon', () {
      expect(voiceDateLabel(DateTime(2026, 1, 3, 0, 5)), 'Jan 03 at 12:05 AM');
      expect(voiceDateLabel(DateTime(2026, 12, 31, 12, 0)), 'Dec 31 at 12:00 PM');
    });
  });

  group('voiceSubtitle', () {
    test('sender and duration', () {
      expect(voiceSubtitle('You', 14), 'You • 00:14');
    });

    test('long duration uses minutes', () {
      expect(voiceSubtitle('Dina', 95), 'Dina • 01:35');
    });

    test('unknown duration shows only the sender', () {
      expect(voiceSubtitle('You', 0), 'You');
    });
  });
}
