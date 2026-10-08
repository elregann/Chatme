// chat_message.dart

import 'package:hive/hive.dart';
import '../services/app_settings.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 1)
class ChatMessage {
  /// Canonical message ID.
  ///
  /// For NIP-17 messages, this is the **Rumor ID** (kind 14), which is
  /// stable across both sender and receiver. For legacy NIP-04 messages,
  /// this is the kind-4 event ID. For temporary/offline messages, this is
  /// a local placeholder prefixed with `temp_` or `pending_`.
  @HiveField(0) final String id;

  @HiveField(1) final String senderPubkey;
  @HiveField(2) final String receiverPubkey;
  @HiveField(3) final String content;
  @HiveField(4) final String plaintext;
  @HiveField(5) final int timestamp;
  @HiveField(6) String status;
  @HiveField(7) final String chatKey;
  @HiveField(8) final String? replyToId;
  @HiveField(9) final String? replyToContent;
  @HiveField(10, defaultValue: {}) Map<String, String> reactions;
  @HiveField(11, defaultValue: '') final String? replyToSenderPubkey;

  /// The event ID of the outer NIP-17 Gift Wrap (kind 1059) that carried
  /// this message. It is used **only** to match `["OK", <id>, true]`
  /// acknowledgements from relays — the gift-wrap ID changes every time a
  /// message is re-sent with a fresh ephemeral key, so it must never be
  /// used as a stable identifier.
  ///
  /// Empty for legacy NIP-04 messages and for local pending messages that
  /// have not yet been wrapped.
  @HiveField(12, defaultValue: '') final String giftWrapId;

  @HiveField(13, defaultValue: {}) Map<String, String> pendingReactions;

  ChatMessage({
    required this.id,
    required this.senderPubkey,
    required this.receiverPubkey,
    required this.content,
    required this.plaintext,
    required this.timestamp,
    this.status = 'sent',
    required this.chatKey,
    this.replyToId,
    this.replyToContent,
    this.reactions = const {},
    this.replyToSenderPubkey,
    this.giftWrapId = '',
    this.pendingReactions = const {},
  });

  ChatMessage copyWithStatus(String newStatus) {
    return copyWith(status: newStatus);
  }

  ChatMessage copyWith({
    String? id,
    String? senderPubkey,
    String? receiverPubkey,
    String? content,
    String? plaintext,
    int? timestamp,
    String? status,
    String? chatKey,
    String? replyToId,
    String? replyToContent,
    Map<String, String>? reactions,
    String? replyToSenderPubkey,
    String? giftWrapId,
    Map<String, String>? pendingReactions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderPubkey: senderPubkey ?? this.senderPubkey,
      receiverPubkey: receiverPubkey ?? this.receiverPubkey,
      content: content ?? this.content,
      plaintext: plaintext ?? this.plaintext,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      chatKey: chatKey ?? this.chatKey,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      reactions: reactions ?? Map.from(this.reactions),
      replyToSenderPubkey: replyToSenderPubkey ?? this.replyToSenderPubkey,
      giftWrapId: giftWrapId ?? this.giftWrapId,
      pendingReactions: pendingReactions ?? Map.from(this.pendingReactions),
    );
  }

  void addReaction(String senderPubkey, String emoji) {
    reactions[senderPubkey] = emoji;
  }

  bool get isMe => senderPubkey == AppSettings.instance.myPubkey;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderPubkey': senderPubkey,
      'receiverPubkey': receiverPubkey,
      'content': content,
      'plaintext': plaintext,
      'timestamp': timestamp,
      'status': status,
      'chatKey': chatKey,
      'replyToId': replyToId,
      'replyToContent': replyToContent,
      'reactions': reactions,
      'replyToSenderPubkey': replyToSenderPubkey,
      'giftWrapId': giftWrapId,
      'pendingReactions': pendingReactions,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      senderPubkey: map['senderPubkey'],
      receiverPubkey: map['receiverPubkey'],
      content: map['content'],
      plaintext: map['plaintext'],
      timestamp: map['timestamp'],
      status: map['status'] ?? 'sent',
      chatKey: map['chatKey'],
      replyToId: map['replyToId'],
      replyToContent: map['replyToContent'],
      reactions: Map<String, String>.from(map['reactions'] ?? {}),
      replyToSenderPubkey: map['replyToSenderPubkey'],
      giftWrapId: map['giftWrapId'] ?? '',
      pendingReactions: Map<String, String>.from(map['pendingReactions'] ?? {}),
    );
  }
}