// time_utils.dart

import 'package:intl/intl.dart';

class TimeUtils {
  static String formatTimeHumanized(int timestamp) {
    if (timestamp == 0) return '';
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final aWeekAgo = today.subtract(const Duration(days: 7));
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == today) return DateFormat.jm().format(date);
    if (targetDate == yesterday) return 'Yesterday';
    if (targetDate.isAfter(aWeekAgo)) return DateFormat('EEEE').format(date);
    return date.year == now.year ? DateFormat('d MMM').format(date) : DateFormat('d MMM yyyy').format(date);
  }

  /// Day label plus clock time, matching the format used by Calls and Chatme
  /// bubbles. The 24-hour choice comes from the caller (normally
  /// `MediaQuery.alwaysUse24HourFormatOf`), so no in-app setting can drift.
  static String formatDayAndTime(
    int timestamp, {
    required bool alwaysUse24Hour,
  }) {
    if (timestamp == 0) return '';

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final minute = date.minute.toString().padLeft(2, '0');
    final hour = alwaysUse24Hour
        ? date.hour.toString().padLeft(2, '0')
        : (date.hour % 12 == 0 ? 12 : date.hour % 12).toString();
    final time = alwaysUse24Hour
        ? '$hour:$minute'
        : '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';

    if (_isSameDay(date, now)) return 'Today, $time';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday, $time';
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}, $time';
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
