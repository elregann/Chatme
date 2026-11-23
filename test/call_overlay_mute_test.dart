import 'package:chatme/call_overlay.dart';
import 'package:chatme/core/theme/chatme_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallFloatingBar mute colors', () {
    test('unmuted mute uses translucent surface and white icon', () {
      final colors = CallFloatingBar.muteColors(isMuted: false);

      expect(colors.surface, ChatmeColors.callControlSurface);
      expect(colors.icon, ChatmeColors.callControlIcon);
    });

    test('muted mute uses solid surface and red icon', () {
      final colors = CallFloatingBar.muteColors(isMuted: true);

      expect(colors.surface, ChatmeColors.callControlSurfaceActiveSolid);
      expect(colors.icon, ChatmeColors.callControlMuteIconOnActive);
    });
  });
}
