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

  /// A `name@chatme` handle, but only when the Chatme directory confirmed it.
  ///
  /// [globalId] is written exclusively from the directory, never from an
  /// arbitrary kind-0 `name`, so a Nostr profile called "0xChat" cannot
  /// pretend to be "0xChat@chatme". Placeholder values that leaked in from
  /// older app versions are rejected as well.
  String? get chatmeHandle {
    final handle = globalId?.trim() ?? '';
    if (handle.isEmpty || isPlaceholderName(handle, pubkey)) return null;
    return '$handle@chatme';
  }

  /// Builds a contact row from a global-search result.
  ///
  /// Only a row that came from the Chatme directory may carry a global ID.
  /// A NIP-50 result from the wider Nostr ecosystem has a profile `name`, not
  /// a Chatme username, so [globalId] stays null even when the names look
  /// alike.
  factory Contact.fromSearchResult({
    required String pubkey,
    required String name,
    required String source,
    bool isSaved = true,
  }) {
    final confirmed = source == 'Chatme' && !isPlaceholderName(name, pubkey);
    return Contact(
      pubkey: pubkey,
      name: name,
      isSaved: isSaved,
      globalId: confirmed ? name : null,
    );
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