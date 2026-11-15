import 'package:chatme/core/utils/notification_entry.dart';
import 'package:chatme/core/utils/notification_summary.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationEntry entry(
  String sender,
  String message, {
  int timeMs = 0,
}) =>
    NotificationEntry(sender: sender, message: message, timeMs: timeMs);

void main() {
  group('lineFor', () {
    test('puts exactly two spaces between sender and message', () {
      expect(
        NotificationSummary.lineFor(entry('Bob', 'Halo, apa kabar?')),
        'Bob  Halo, apa kabar?',
      );
    });

    test('flattens newlines and repeated whitespace', () {
      expect(
        NotificationSummary.lineFor(entry(' Bob ', 'Halo\n\napa\tkabar?  ')),
        'Bob  Halo apa kabar?',
      );
    });

    test('keeps a message that arrives without a sender', () {
      expect(NotificationSummary.lineFor(entry('', 'hello')), 'hello');
    });

    test('keeps a sender that arrives without a message', () {
      expect(NotificationSummary.lineFor(entry('Bob', '  ')), 'Bob');
    });
  });

  group('linesFor', () {
    test('keeps the newest-first order and one line per conversation', () {
      final lines = NotificationSummary.linesFor([
        entry('Bob', 'Halo', timeMs: 30),
        entry('Alice', 'Sudah makan?', timeMs: 20),
      ]);

      expect(lines, ['Bob  Halo', 'Alice  Sudah makan?']);
    });

    test('shows every conversation when five fit', () {
      final entries = [
        for (var i = 0; i < NotificationSummary.maxLines; i++)
          entry('Person $i', 'message $i', timeMs: 100 - i),
      ];

      final lines = NotificationSummary.linesFor(entries);

      expect(lines.length, NotificationSummary.maxLines);
      expect(lines.last, 'Person 4  message 4');
    });

    test('replaces the last line with a count when more do not fit', () {
      final entries = [
        for (var i = 0; i < 7; i++)
          entry('Person $i', 'message $i', timeMs: 100 - i),
      ];

      final lines = NotificationSummary.linesFor(entries);

      // Four conversations keep their line, the other three become the count.
      expect(lines.length, NotificationSummary.maxLines);
      expect(lines.last, '+3 more conversations');
    });

    test('uses the singular when one conversation does not fit', () {
      expect(NotificationSummary.moreLabel(1), '+1 more conversation');
      expect(NotificationSummary.moreLabel(2), '+2 more conversations');
    });

    test('returns no lines without conversations', () {
      expect(NotificationSummary.linesFor(const []), isEmpty);
    });
  });

  group('previewFor', () {
    test('shows the two newest conversations without a suffix', () {
      final preview = NotificationSummary.previewFor([
        entry('Bob', 'Halo', timeMs: 30),
        entry('Alice', 'Sudah makan?', timeMs: 20),
      ]);

      expect(preview?.title, 'Bob  Halo');
      expect(preview?.body, 'Alice  Sudah makan?');
    });

    test('adds the hidden count to the second line', () {
      final preview = NotificationSummary.previewFor([
        for (var i = 0; i < 4; i++)
          entry('Person $i', 'message $i', timeMs: 100 - i),
      ]);

      expect(preview?.title, 'Person 0  message 0');
      expect(preview?.body, 'Person 1  message 1  ·  +2 more');
    });

    test('uses a single line for one conversation', () {
      final preview = NotificationSummary.previewFor([
        entry('Bob', 'Halo'),
      ]);

      expect(preview?.title, 'Bob  Halo');
      expect(preview?.body, isNull);
    });

    test('has no preview without conversations', () {
      expect(NotificationSummary.previewFor(const []), isNull);
    });
  });
}
