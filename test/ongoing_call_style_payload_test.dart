import 'package:chatme/core/utils/ongoing_call_style_channel.dart';
import 'package:chatme/core/utils/ongoing_call_style_payload.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

OngoingCallStylePayload? payloadFor({
  String? status,
  String title = 'Rina',
  String peerPubkey = 'npub1rina',
  int startedAtMs = 1700000000000,
  Uint8List? avatar,
}) {
  return OngoingCallStylePayload.forActiveCall(
    channelId: 'chatme_active_call_channel',
    notificationId: 888889,
    endActionId: 'END_CALL_ACTION',
    accentArgb: 0xFF50D2C1,
    status: status,
    title: title,
    peerPubkey: peerPubkey,
    startedAtMs: startedAtMs,
    avatar: avatar,
  );
}

void main() {
  group('OngoingCallStylePayload.forActiveCall', () {
    test('builds a payload for a connected call with its start time', () {
      final payload = payloadFor();

      expect(payload, isNotNull);
      expect(payload!.title, 'Rina');
      expect(payload.peerPubkey, 'npub1rina');
      expect(payload.startedAtMs, 1700000000000);
      expect(payload.notificationId, 888889);
    });

    test('does not build a payload while the call is still connecting', () {
      expect(payloadFor(status: 'Connecting'), isNull);
      expect(payloadFor(status: 'Calling'), isNull);
      expect(payloadFor(status: 'Incoming call'), isNull);
    });

    test('does not build a payload without a stable call start time', () {
      expect(payloadFor(startedAtMs: 0), isNull);
      expect(payloadFor(startedAtMs: -1), isNull);
    });

    test('does not build a payload without a display name', () {
      expect(payloadFor(title: ''), isNull);
      expect(payloadFor(title: '   '), isNull);
    });
  });

  group('OngoingCallStylePayload.toMap', () {
    test('uses the exact platform channel keys', () {
      final map = payloadFor()!.toMap();

      expect(map, {
        'channelId': 'chatme_active_call_channel',
        'notificationId': 888889,
        'title': 'Rina',
        'peerPubkey': 'npub1rina',
        'startedAtMs': 1700000000000,
        'accentArgb': 0xFF50D2C1,
        'endActionId': 'END_CALL_ACTION',
        'avatar': null,
      });
    });

    test('sends the avatar bytes unchanged to the native shim', () {
      final avatar = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);

      final map = payloadFor(avatar: avatar)!.toMap();

      expect(map['avatar'], same(avatar));
      expect(map['avatar'], isA<Uint8List>());
    });

    test('keeps an empty peer key because it is only an identity hint', () {
      final map = payloadFor(peerPubkey: '')!.toMap();

      expect(map['peerPubkey'], '');
    });
  });

  group('OngoingCallStylePayload.displayName', () {
    test('uses the call screen session name when there is one', () {
      expect(
        OngoingCallStylePayload.displayName(
          sessionName: 'Rina',
          fallbackName: 'npub1abc...xyz',
        ),
        'Rina',
      );
    });

    test('falls back to the profile name when the session has no name', () {
      expect(
        OngoingCallStylePayload.displayName(
          sessionName: '',
          fallbackName: 'npub1abc...xyz',
        ),
        'npub1abc...xyz',
      );
      expect(
        OngoingCallStylePayload.displayName(
          sessionName: '   ',
          fallbackName: 'npub1abc...xyz',
        ),
        'npub1abc...xyz',
      );
    });
  });

  group('OngoingCallStyleChannel', () {
    late MethodChannel channel;
    late List<MethodCall> calls;

    setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

    setUp(() {
      calls = <MethodCall>[];
      channel = const MethodChannel(OngoingCallStyleChannel.channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('uses the channel name shared with the Kotlin shim', () {
      expect(
        OngoingCallStyleChannel.channelName,
        'com.chatme.app/ongoing_call_style',
      );
    });

    test('applies the payload with the shared method name', () async {
      final applied = await OngoingCallStyleChannel.apply(payloadFor()!);

      expect(applied, isTrue);
      expect(calls.single.method, 'applyCallStyle');
      expect(calls.single.arguments, payloadFor()!.toMap());
    });

    test('clears only the active call notification id', () async {
      await OngoingCallStyleChannel.clear(notificationId: 888889);

      expect(calls.single.method, 'clearCallStyle');
      expect(calls.single.arguments, <String, Object?>{'notificationId': 888889});
    });
  });
}
