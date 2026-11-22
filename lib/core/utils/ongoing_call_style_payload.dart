import 'dart:typed_data';

/// Contract between Dart and the small Android shim that turns the active-call
/// notification into Android's own `CallStyle`. Only a connected call gets the
/// platform call chip, and only then does the notification have a stable start
/// time to feed the system chronometer.
class OngoingCallStylePayload {
  const OngoingCallStylePayload({
    required this.channelId,
    required this.notificationId,
    required this.title,
    required this.peerPubkey,
    required this.startedAtMs,
    required this.accentArgb,
    required this.endActionId,
    this.avatar,
  });

  final String channelId;
  final int notificationId;
  final String title;
  final String peerPubkey;
  final int startedAtMs;
  final int accentArgb;
  final String endActionId;
  final Uint8List? avatar;

  /// The call screen owns the session name, so it wins over a locally resolved
  /// profile name. The profile name is only a fallback for an unnamed session.
  static String displayName({
    required String sessionName,
    required String fallbackName,
  }) {
    return sessionName.trim().isEmpty ? fallbackName : sessionName;
  }

  /// Returns `null` for every non-active state so the existing notification
  /// stays untouched until the call is really connected.
  static OngoingCallStylePayload? forActiveCall({
    required String channelId,
    required int notificationId,
    required String endActionId,
    required int accentArgb,
    required String? status,
    required String title,
    required String peerPubkey,
    required int startedAtMs,
    Uint8List? avatar,
  }) {
    if (status != null) return null;
    if (title.trim().isEmpty) return null;
    if (startedAtMs <= 0) return null;

    return OngoingCallStylePayload(
      channelId: channelId,
      notificationId: notificationId,
      title: title,
      peerPubkey: peerPubkey,
      startedAtMs: startedAtMs,
      accentArgb: accentArgb,
      endActionId: endActionId,
      avatar: avatar,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'channelId': channelId,
        'notificationId': notificationId,
        'title': title,
        'peerPubkey': peerPubkey,
        'startedAtMs': startedAtMs,
        'accentArgb': accentArgb,
        'endActionId': endActionId,
        'avatar': avatar,
      };
}
