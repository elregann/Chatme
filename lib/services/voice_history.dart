// voice_history.dart

import '../core/utils/duration_utils.dart';
import '../models/chat_message.dart';

/// Voice notes of one chat, newest first.
List<ChatMessage> voiceNotesNewestFirst(Iterable<ChatMessage> messages) {
  return messages.where((m) => m.isVoiceNote).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Oct 08 at 1:45 AM"
String voiceDateLabel(DateTime time) {
  final day = time.day.toString().padLeft(2, '0');
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour < 12 ? 'AM' : 'PM';
  return '${_months[time.month - 1]} $day at $hour12:$minute $suffix';
}

/// "You • 00:14", or just the sender when the length is unknown.
String voiceSubtitle(String sender, int seconds) {
  if (seconds <= 0) return sender;
  return '$sender • ${DurationUtils.formatClock(seconds)}';
}
