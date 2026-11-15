// lib/core/utils/notification_summary.dart
//
// Turns the newest message of each conversation into the lines shown in the
// grouped chat notification. Pure functions, so the inbox look can be tested
// without Android.

import 'notification_entry.dart';

class NotificationSummary {
  const NotificationSummary._();

  /// How many conversation lines the expanded inbox style may hold.
  static const int maxLines = 5;

  /// One line of the inbox: the sender, two spaces, then the message.
  ///
  /// Newlines and repeated whitespace are flattened so a multi-line message
  /// cannot break the list layout.
  static String lineFor(NotificationEntry entry) {
    final sender = _oneLine(entry.sender);
    final message = _oneLine(entry.message);
    if (sender.isEmpty) return message;
    if (message.isEmpty) return sender;
    return '$sender  $message';
  }

  /// The conversation lines of [newestFirst], at most [maxLines].
  ///
  /// When there are more conversations than fit, the last line becomes a
  /// count instead of a conversation, so the list keeps its maximum height.
  static List<String> linesFor(List<NotificationEntry> newestFirst) {
    if (newestFirst.isEmpty) return const [];

    if (newestFirst.length <= maxLines) {
      return [for (final entry in newestFirst) lineFor(entry)];
    }

    final shown = newestFirst.take(maxLines - 1).toList();
    return [
      for (final entry in shown) lineFor(entry),
      moreLabel(newestFirst.length - shown.length),
    ];
  }

  /// The collapsed form of the summary.
  ///
  /// Android shows the group header itself, so the title is the newest
  /// conversation line instead of an app name. The second line carries the
  /// next conversation and, when some do not fit, how many are left.
  static ({String title, String? body})? previewFor(
    List<NotificationEntry> newestFirst,
  ) {
    if (newestFirst.isEmpty) return null;

    final title = lineFor(newestFirst.first);
    if (newestFirst.length == 1) return (title: title, body: null);

    final hidden = newestFirst.length - 2;
    var body = lineFor(newestFirst[1]);
    if (hidden > 0) body = '$body  ·  +$hidden more';
    return (title: title, body: body);
  }

  /// A plural-aware label for conversations that did not fit.
  static String moreLabel(int hidden) =>
      '+$hidden more conversation${hidden == 1 ? '' : 's'}';

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
