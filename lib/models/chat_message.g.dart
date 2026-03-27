// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 1;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      senderPubkey: fields[1] as String,
      receiverPubkey: fields[2] as String,
      content: fields[3] as String,
      plaintext: fields[4] as String,
      timestamp: fields[5] as int,
      status: fields[6] as String,
      chatKey: fields[7] as String,
      replyToId: fields[8] as String?,
      replyToContent: fields[9] as String?,
      reactions:
          fields[10] == null ? {} : (fields[10] as Map).cast<String, String>(),
      replyToSenderPubkey: fields[11] == null ? '' : fields[11] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.senderPubkey)
      ..writeByte(2)
      ..write(obj.receiverPubkey)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.plaintext)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.chatKey)
      ..writeByte(8)
      ..write(obj.replyToId)
      ..writeByte(9)
      ..write(obj.replyToContent)
      ..writeByte(10)
      ..write(obj.reactions)
      ..writeByte(11)
      ..write(obj.replyToSenderPubkey);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
