// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'call_log.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CallLogAdapter extends TypeAdapter<CallLog> {
  @override
  final int typeId = 2;

  @override
  CallLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CallLog(
      id: fields[0] as String,
      peerPubkey: fields[1] as String,
      peerName: fields[2] as String,
      direction: fields[3] as String,
      mediaType: fields[4] as String,
      timestamp: fields[5] as int,
      durationSeconds: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CallLog obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.peerPubkey)
      ..writeByte(2)
      ..write(obj.peerName)
      ..writeByte(3)
      ..write(obj.direction)
      ..writeByte(4)
      ..write(obj.mediaType)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.durationSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
