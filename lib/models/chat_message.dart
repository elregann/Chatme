// chat_message.dart

import 'package:hive/hive.dart';
import '../services/app_settings.dart';

part 'chat_message.g.dart';

@HiveType(typeId: 1)
class ChatMessage {
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
    );
  }
}