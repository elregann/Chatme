// contact.dart

import 'package:hive/hive.dart';
import '../core/utils/key_utils.dart';

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

  String get displayName {
    if (name.isEmpty) return KeyUtils.formatDisplayName(pubkey);
    if (name.startsWith('npub1')) return KeyUtils.formatDisplayName(pubkey);
    if (name.startsWith('User ')) return KeyUtils.formatDisplayName(pubkey);
    if (name == pubkey) return KeyUtils.formatDisplayName(pubkey);
    return name;
  }

  bool get hasGlobalId {
    if (name.isEmpty) return false;
    if (name.startsWith('npub1')) return false;
    if (name.startsWith('User ')) return false;
    if (name == pubkey) return false;
    return true;
  }

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