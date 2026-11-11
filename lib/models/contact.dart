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

  /// The contact's claimed global ID handle (e.g. "edwards" in
  /// "edwards@chatme"). This is the contact's remote identity and is kept
  /// separate from [name] — which holds the local, possibly renamed,
  /// nickname — so renaming a contact never clobbers it.
  ///
  /// Nullable so records written before this field existed (which lack
  /// Hive field 6) still deserialize cleanly.
  @HiveField(6) String? globalId;

  Contact({
    required this.pubkey,
    required this.name,
    this.lastChatTime = 0,
    this.lastMessage = '',
    this.unreadCount = 0,
    this.isSaved = false,
    this.globalId,
  });

  /// True when [name] is not a real, user-authored name but a placeholder
  /// (empty, an npub stub, a "User ..." stub, or the raw pubkey). Placeholder
  /// values must never be published as identity or stored on a contact row.
  static bool isPlaceholderName(String name, String pubkey) {
    if (name.isEmpty) return true;
    if (name.startsWith('npub1')) return true;
    if (name.startsWith('User ')) return true;
    if (name == pubkey) return true;
    return false;
  }

  String get displayName {
    if (isPlaceholderName(name, pubkey)) return KeyUtils.formatDisplayName(pubkey);
    return name;
  }

  /// Non-null view of [globalId], handy for display ("edwards@chatme").
  String get globalHandle => globalId ?? '';

  bool get hasGlobalId {
    return globalHandle.isNotEmpty;
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