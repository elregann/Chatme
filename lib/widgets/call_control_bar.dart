import 'package:flutter/material.dart';

/// The capsule under the call timer: mute, speaker and hangup, or accept and
/// hangup for an incoming call. All positions come from the constants below.
class CallControlBar extends StatelessWidget {
  static const double buttonSize = 64;
  static const double iconSize = 28;
  static const double height = 80;
  static const double edgeGap = 8;
  static const double buttonGap = 24;
  static const double borderWidth = 1.2;
  static const double collapsedWidth = height;
  static const double expandedWidth = edgeGap * 2 + buttonSize * 3 + buttonGap * 2;

  static const Key capsuleKey = ValueKey('call-capsule');
  static const Key muteKey = ValueKey('call-mute');
  static const Key speakerKey = ValueKey('call-speaker');
  static const Key acceptKey = ValueKey('call-accept');
  static const Key hangupKey = ValueKey('call-hangup');

  final bool isDark;
  final bool expanded;
  final bool showControls;
  final bool showAccept;
  final bool isMuted;
  final bool isSpeakerOn;
  final VoidCallback onMute;
  final VoidCallback onSpeaker;
  final VoidCallback onAccept;
  final VoidCallback onHangup;

  const CallControlBar({
    super.key,
    required this.isDark,
    required this.expanded,
    required this.showControls,
    required this.showAccept,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onMute,
    required this.onSpeaker,
    required this.onAccept,
    required this.onHangup,
  });

  static const double _speakerLeft = (expandedWidth - buttonSize) / 2;
  static const double _hangupAlignX = 1 - 2 * edgeGap / (expandedWidth - buttonSize);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: capsuleKey,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
      width: expanded ? expandedWidth : collapsedWidth,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        color: isDark ? Colors.white.withAlpha(5) : Colors.black.withAlpha(5),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
          width: borderWidth,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: showControls ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !showControls,
              child: Stack(
                children: [
                  Positioned(
                    left: edgeGap,
                    top: edgeGap,
                    child: CallControlButton(
                      key: muteKey,
                      icon: isMuted ? Icons.mic_off : Icons.mic,
                      isActive: isMuted,
                      onTap: onMute,
                      isDark: isDark,
                    ),
                  ),
                  Positioned(
                    left: _speakerLeft,
                    top: edgeGap,
                    child: CallControlButton(
                      key: speakerKey,
                      icon: isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                      isActive: isSpeakerOn,
                      onTap: onSpeaker,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showAccept)
            Positioned(
              left: edgeGap,
              top: edgeGap,
              child: CallControlButton(
                key: acceptKey,
                icon: Icons.call,
                color: Colors.green,
                onTap: onAccept,
                isDark: isDark,
              ),
            ),
          AnimatedAlign(
            duration: const Duration(milliseconds: 400),
            curve: Curves.fastOutSlowIn,
            alignment: expanded ? const Alignment(_hangupAlignX, 0) : Alignment.center,
            child: CallControlButton(
              key: hangupKey,
              icon: Icons.call_end,
              isHangup: true,
              onTap: onHangup,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

class CallControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isHangup;
  final Color? color;
  final VoidCallback onTap;
  final bool isDark;

  const CallControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.isActive = false,
    this.isHangup = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final filled = isActive || isHangup || color != null;
    final background = color ??
        (isHangup
            ? Colors.redAccent.withAlpha(229)
            : (isActive
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(13))));
    final foreground = filled
        ? (isDark && !isHangup && color == null ? Colors.black : Colors.white)
        : (isDark ? Colors.white : Colors.black);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: CallControlBar.buttonSize,
        height: CallControlBar.buttonSize,
        decoration: BoxDecoration(shape: BoxShape.circle, color: background),
        child: Icon(icon, color: foreground, size: CallControlBar.iconSize),
      ),
    );
  }
}
