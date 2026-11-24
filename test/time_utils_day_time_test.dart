import 'package:chatme/core/utils/time_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 15, 45);
  final yesterday = DateTime(now.year, now.month, now.day - 1, 9, 10);
  final older = DateTime(now.year, now.month, now.day - 5, 18, 20);
  final midnight = DateTime(now.year, now.month, now.day, 0, 5);
  final noon = DateTime(now.year, now.month, now.day, 12, 0);

  int ms(DateTime value) => value.millisecondsSinceEpoch;

  group('TimeUtils.formatDayAndTime', () {
    test('uses Today and Yesterday with 12 hour time', () {
      expect(
        TimeUtils.formatDayAndTime(ms(today), alwaysUse24Hour: false),
        'Today, 3:45 PM',
      );
      expect(
        TimeUtils.formatDayAndTime(ms(yesterday), alwaysUse24Hour: false),
        'Yesterday, 9:10 AM',
      );
    });

    test('uses a short date for older days with 12 hour time', () {
      expect(
        TimeUtils.formatDayAndTime(ms(older), alwaysUse24Hour: false),
        '${DateFormat('d MMM').format(older)}, 6:20 PM',
      );
    });

    test('uses 24 hour time when the device asks for it', () {
      expect(
        TimeUtils.formatDayAndTime(ms(today), alwaysUse24Hour: true),
        'Today, 15:45',
      );
      expect(
        TimeUtils.formatDayAndTime(ms(yesterday), alwaysUse24Hour: true),
        'Yesterday, 09:10',
      );
      expect(
        TimeUtils.formatDayAndTime(ms(older), alwaysUse24Hour: true),
        '${DateFormat('d MMM').format(older)}, 18:20',
      );
    });

    test('midnight and noon stay 12 and 12 in 12 hour mode', () {
      expect(
        TimeUtils.formatDayAndTime(ms(midnight), alwaysUse24Hour: false),
        'Today, 12:05 AM',
      );
      expect(
        TimeUtils.formatDayAndTime(ms(noon), alwaysUse24Hour: false),
        'Today, 12:00 PM',
      );
    });

    test('an empty timestamp has no label', () {
      expect(TimeUtils.formatDayAndTime(0, alwaysUse24Hour: false), isEmpty);
    });
  });
}
