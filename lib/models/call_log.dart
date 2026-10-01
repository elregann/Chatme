// call_log.dart

import 'package:hive/hive.dart';

part 'call_log.g.dart';

@HiveType(typeId: 2)
class CallLog extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String peerPubkey;

  @HiveField(2)
  final String peerName;

  @HiveField(3)
  final String direction; // 'incoming', 'outgoing', 'missed'

  @HiveField(4)
  final String mediaType; // 'voice', 'video'

  @HiveField(5)
  final int timestamp; // epoch ms

  @HiveField(6)
  final int durationSeconds; // 0 if missed/declined

  CallLog({
    required this.id,
    required this.peerPubkey,
    required this.peerName,
    required this.direction,
    this.mediaType = 'voice',
    required this.timestamp,
    this.durationSeconds = 0,
  });

  bool get isMissed => direction == 'missed';
  bool get isIncoming => direction == 'incoming';
  bool get isOutgoing => direction == 'outgoing';

  String get formattedDuration {
    if (durationSeconds <= 0) return '';
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}
