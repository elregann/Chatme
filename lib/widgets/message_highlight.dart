// message_highlight.dart

import 'package:flutter/material.dart';

/// A translucent band drawn over one message row to point at it after a jump.
/// It covers the row and extends [bleed] past both sides, so it reaches the
/// screen edges even though the list has side padding.
class MessageHighlight extends StatelessWidget {
  const MessageHighlight({
    super.key,
    required this.highlighted,
    required this.color,
    required this.child,
    this.bleed = 0,
    this.bottomInset = 0,
  });

  static const Duration fade = Duration(milliseconds: 300);

  final bool highlighted;
  final Color color;
  final double bleed;

  /// Space at the bottom of [child] that the band should leave uncovered.
  final double bottomInset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          left: -bleed,
          right: -bleed,
          bottom: bottomInset,
          child: IgnorePointer(
            child: AnimatedOpacity(
              key: const Key('message_highlight_fade'),
              opacity: highlighted ? 1.0 : 0.0,
              duration: fade,
              child: ColoredBox(
                key: const Key('message_highlight_band'),
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
