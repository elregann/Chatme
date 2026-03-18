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
}