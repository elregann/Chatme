// contact.dart

import 'package:hive/hive.dart';

part 'contact.g.dart';

@HiveType(typeId: 0)
class Contact {
  @HiveField(0) final String pubkey;
  @HiveField(1) String name;
  @HiveField(2) int lastChatTime;
  @HiveField(3) String lastMessage;
  @HiveField(4) int unreadCount;
  @HiveField(5) bool isSaved;

  Contact({
    required this.pubkey,
    required this.name,
    this.lastChatTime = 0,
    this.lastMessage = '',
    this.unreadCount = 0,
    this.isSaved = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'pubkey': pubkey,
      'name': name,
      'lastChatTime': lastChatTime,
      'lastMessage': lastMessage,
      'unreadCount': unreadCount,
    };
  }
}