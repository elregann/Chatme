import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:chatme/widgets/call_control_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({required bool isMuted, required bool isSpeakerOn}) {
  return MaterialApp(
    home: Scaffold(
      body: CallControlBar(
        isDark: true,
        expanded: true,
        showControls: true,
        showAccept: false,
        isMuted: isMuted,
        isSpeakerOn: isSpeakerOn,
        onMute: () {},
        onSpeaker: () {},
        onAccept: () {},
        onHangup: () {},
      ),
    ),
  );
}

Color _background(WidgetTester tester, Finder button) {
  final container = tester.widget<Container>(
    find.descendant(of: button, matching: find.byType(Container)).first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

Color _iconColor(WidgetTester tester, Finder button) {
  return tester.widget<Icon>(
    find.descendant(of: button, matching: find.byType(Icon)),
  ).color!;
}

void main() {
  group('CallControlBar button colors', () {
    testWidgets('inactive mute uses translucent surface and white icon', (tester) async {
      await tester.pumpWidget(_bar(isMuted: false, isSpeakerOn: false));
      final mute = find.byKey(CallControlBar.muteKey);

      expect(_background(tester, mute), ChatmeColors.callControlSurface);
      expect(_iconColor(tester, mute), ChatmeColors.callControlIcon);
    });

    testWidgets('inactive speaker uses translucent surface and white icon', (tester) async {
      await tester.pumpWidget(_bar(isMuted: false, isSpeakerOn: false));
      final speaker = find.byKey(CallControlBar.speakerKey);

      expect(_background(tester, speaker), ChatmeColors.callControlSurface);
      expect(_iconColor(tester, speaker), ChatmeColors.callControlIcon);
    });

    testWidgets('active speaker uses solid white surface and dark icon', (tester) async {
      await tester.pumpWidget(_bar(isMuted: false, isSpeakerOn: true));
      final speaker = find.byKey(CallControlBar.speakerKey);

      expect(_background(tester, speaker), ChatmeColors.callControlSurfaceActiveSolid);
      expect(_iconColor(tester, speaker), ChatmeColors.callControlIconOnActive);
    });

    testWidgets('active mute uses solid white surface and red icon', (tester) async {
      await tester.pumpWidget(_bar(isMuted: true, isSpeakerOn: true));
      final mute = find.byKey(CallControlBar.muteKey);

      expect(_background(tester, mute), ChatmeColors.callControlSurfaceActiveSolid);
      expect(_iconColor(tester, mute), ChatmeColors.callControlMuteIconOnActive);
    });

    testWidgets('hangup button keeps its original colors', (tester) async {
      await tester.pumpWidget(_bar(isMuted: false, isSpeakerOn: false));
      final hangup = find.byKey(CallControlBar.hangupKey);

      expect(_background(tester, hangup), ChatmeColors.callEnd);
      expect(_iconColor(tester, hangup), ChatmeColors.textPrimary);
    });

    test('overlay active surface token stays translucent', () {
      expect(ChatmeColors.callControlSurfaceActive.a, lessThan(1.0));
      expect(ChatmeColors.callControlSurfaceActive, isNot(ChatmeColors.callControlSurfaceActiveSolid));
    });
  });
}
