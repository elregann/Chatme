import 'dart:async';

import 'package:chatme/services/call_speaker_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('during a call only WebRTC owns the speaker route', () async {
    final webrtc = <bool>[];
    final native = <bool>[];
    final router = CallSpeakerRouter(
      viaWebRtc: (on) async => webrtc.add(on),
      viaNative: (on) async => native.add(on),
      isWeb: () => false,
    );

    await router.setDuringCall(true);
    await router.setDuringCall(false);

    expect(webrtc, [true, false]);
    expect(native, isEmpty,
        reason: 'a second native owner can leave the speaker stuck on');
  });

  test('web calls do not touch native audio routing', () async {
    final webrtc = <bool>[];
    final native = <bool>[];
    final router = CallSpeakerRouter(
      viaWebRtc: (on) async => webrtc.add(on),
      viaNative: (on) async => native.add(on),
      isWeb: () => true,
    );

    await router.setDuringCall(true);
    await router.resetAfterCall();

    expect(webrtc, isEmpty);
    expect(native, isEmpty);
  });

  test('teardown clears both WebRTC and the native override', () async {
    final calls = <String>[];
    final router = CallSpeakerRouter(
      viaWebRtc: (on) async => calls.add('webrtc:$on'),
      viaNative: (on) async => calls.add('native:$on'),
      isWeb: () => false,
    );

    await router.resetAfterCall();

    expect(calls, ['webrtc:false', 'native:false']);
  });

  test('teardown still clears the native override when WebRTC fails',
      () async {
    final native = <bool>[];
    final router = CallSpeakerRouter(
      viaWebRtc: (_) async => throw StateError('plugin failure'),
      viaNative: (on) async => native.add(on),
      isWeb: () => false,
    );

    await router.resetAfterCall();
    expect(native, [false]);
  });

  test('teardown waits for an in-flight speaker change', () async {
    final calls = <String>[];
    final gate = Completer<void>();
    final router = CallSpeakerRouter(
      viaWebRtc: (on) async {
        if (on) await gate.future;
        calls.add('webrtc:$on');
      },
      viaNative: (on) async => calls.add('native:$on'),
      isWeb: () => false,
    );

    final pending = router.setDuringCall(true);
    final reset = router.resetAfterCall();
    gate.complete();
    await Future.wait([pending, reset]);

    expect(calls, ['webrtc:true', 'webrtc:false', 'native:false']);
  });

  test('a failed WebRTC change never falls back to the native owner', () async {
    final native = <bool>[];
    final router = CallSpeakerRouter(
      viaWebRtc: (_) async => throw StateError('plugin failure'),
      viaNative: (on) async => native.add(on),
      isWeb: () => false,
    );

    await expectLater(
      router.setDuringCall(true),
      throwsA(isA<StateError>()),
    );
    expect(native, isEmpty);
  });
}
