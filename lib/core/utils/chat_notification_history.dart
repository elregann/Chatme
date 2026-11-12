// lib/core/utils/chat_notification_history.dart
//
// The messages stacked in one chat notification, per contact.
//
// The list belongs to the notification, not to the chat: once the
// notification is gone from the screen (read, replied, dismissed), the next
// message must start a fresh one. Every isolate keeps its own instance, so
// whether the previous notification is still shown is answered by the caller
// from the system and passed in, instead of guessed from state the isolates
// do not share.

class NotificationEntry {
  const NotificationEntry({
    required this.sender,
    required this.message,
    required this.timeMs,
  });

  final String sender;
  final String message;
  final int timeMs;
}

class ChatNotificationHistory {
  ChatNotificationHistory({this.maxPerContact = 10});

  /// Oldest entries are dropped beyond this many per contact.
  final int maxPerContact;

  final Map<String, List<NotificationEntry>> _byContact = {};

  /// Entries of [contactPubkey], oldest first.
  List<NotificationEntry> entriesFor(String contactPubkey) =>
      List.unmodifiable(_byContact[contactPubkey] ?? const <NotificationEntry>[]);

  int get contactCount => _byContact.length;

  int get messageCount =>
      _byContact.values.fold<int>(0, (sum, list) => sum + list.length);

  /// Adds [entry] to the stack of [contactPubkey]. When
  /// [previousStillShown] is false the earlier entries are no longer on
  /// screen, so the stack starts over with [entry] alone.
  void add(
    String contactPubkey,
    NotificationEntry entry, {
    required bool previousStillShown,
  }) {
    if (!previousStillShown) _byContact.remove(contactPubkey);

    final list = _byContact.putIfAbsent(contactPubkey, () => []);
    list.add(entry);
    while (list.length > maxPerContact) {
      list.removeAt(0);
    }
  }

  void clear(String contactPubkey) => _byContact.remove(contactPubkey);

  void clearAll() => _byContact.clear();
}
