import 'package:chatme/widgets/call_control_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    bool expanded = true,
    bool showControls = true,
    bool showAccept = false,
    bool isMuted = false,
    bool isSpeakerOn = false,
    VoidCallback? onMute,
    VoidCallback? onSpeaker,
    VoidCallback? onAccept,
    VoidCallback? onHangup,
    bool isDark = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: CallControlBar(
            isDark: isDark,
            expanded: expanded,
            showControls: showControls,
            showAccept: showAccept,
            isMuted: isMuted,
            isSpeakerOn: isSpeakerOn,
            onMute: onMute ?? () {},
            onSpeaker: onSpeaker ?? () {},
            onAccept: onAccept ?? () {},
            onHangup: onHangup ?? () {},
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

  void expectClose(double actual, double expected) {
    expect(actual, closeTo(expected, 0.01));
  }

  testWidgets('capsule and buttons use the planned sizes', (tester) async {
    await tester.pumpWidget(host());
    final capsule = rectOf(tester, CallControlBar.capsuleKey);

    expectClose(capsule.width, 256);
    expectClose(capsule.height, 80);
    for (final key in [CallControlBar.muteKey, CallControlBar.speakerKey, CallControlBar.hangupKey]) {
      final r = rectOf(tester, key);
      expectClose(r.width, 64);
      expectClose(r.height, 64);
    }
  });

  testWidgets('three buttons sit on the vertical center with equal gaps', (tester) async {
    await tester.pumpWidget(host());
    final capsule = rectOf(tester, CallControlBar.capsuleKey);
    final mute = rectOf(tester, CallControlBar.muteKey);
    final speaker = rectOf(tester, CallControlBar.speakerKey);
    final hangup = rectOf(tester, CallControlBar.hangupKey);

    for (final r in [mute, speaker, hangup]) {
      expectClose(r.center.dy, capsule.center.dy);
    }
    expectClose(mute.left - capsule.left, 8);
    expectClose(capsule.right - hangup.right, 8);
    expectClose(speaker.left - mute.right, 24);
    expectClose(hangup.left - speaker.right, 24);
    expectClose(speaker.center.dx, capsule.center.dx);
  });

  testWidgets('incoming call has accept and hangup mirrored at the edges', (tester) async {
    await tester.pumpWidget(host(showControls: false, showAccept: true));
    final capsule = rectOf(tester, CallControlBar.capsuleKey);
    final accept = rectOf(tester, CallControlBar.acceptKey);
    final hangup = rectOf(tester, CallControlBar.hangupKey);

    expectClose(accept.left - capsule.left, 8);
    expectClose(capsule.right - hangup.right, 8);
    expectClose(accept.center.dy, capsule.center.dy);
    expectClose(hangup.center.dy, capsule.center.dy);
  });

  testWidgets('collapsed capsule is a circle with hangup in the middle', (tester) async {
    await tester.pumpWidget(host(expanded: false, showControls: false));
    final capsule = rectOf(tester, CallControlBar.capsuleKey);
    final hangup = rectOf(tester, CallControlBar.hangupKey);

    expectClose(capsule.width, 80);
    expectClose(capsule.height, 80);
    expectClose(hangup.center.dx, capsule.center.dx);
    expectClose(hangup.center.dy, capsule.center.dy);
  });

  testWidgets('icons follow mute and speaker state', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.volume_down), findsOneWidget);

    await tester.pumpWidget(host(isMuted: true, isSpeakerOn: true));
    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('every tap reaches its callback, also when tapped fast', (tester) async {
    var mute = 0, speaker = 0, hangup = 0;
    await tester.pumpWidget(host(
      onMute: () => mute++,
      onSpeaker: () => speaker++,
      onHangup: () => hangup++,
    ));

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(CallControlBar.muteKey));
      await tester.tap(find.byKey(CallControlBar.speakerKey));
    }
    await tester.tap(find.byKey(CallControlBar.hangupKey));

    expect(mute, 5);
    expect(speaker, 5);
    expect(hangup, 1);
  });

  testWidgets('mute and speaker ignore taps while controls are hidden', (tester) async {
    var mute = 0, speaker = 0;
    await tester.pumpWidget(host(
      showControls: false,
      onMute: () => mute++,
      onSpeaker: () => speaker++,
    ));

    await tester.tap(find.byKey(CallControlBar.muteKey), warnIfMissed: false);
    await tester.tap(find.byKey(CallControlBar.speakerKey), warnIfMissed: false);

    expect(mute, 0);
    expect(speaker, 0);
  });

  testWidgets('the accept button only exists for an incoming call', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byKey(CallControlBar.acceptKey), findsNothing);

    await tester.pumpWidget(host(showAccept: true));
    expect(find.byKey(CallControlBar.acceptKey), findsOneWidget);
  });
}
