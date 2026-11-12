// lib/core/utils/notification_entry.dart
//
// One message shown in a contact's chat notification. Stored as a small json
// file by [BgInbox], so every isolate builds the same notification.

class NotificationEntry {
  const NotificationEntry({
    required this.sender,
    required this.message,
    required this.timeMs,
  });

  factory NotificationEntry.fromJson(Map<String, dynamic> json) =>
      NotificationEntry(
        sender: json['sender'] as String,
        message: json['message'] as String,
        timeMs: json['time'] as int,
      );

  final String sender;
  final String message;
  final int timeMs;

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'message': message,
        'time': timeMs,
      };
}
