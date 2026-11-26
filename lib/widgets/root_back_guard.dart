import 'package:flutter/material.dart';

/// Guards the root route against accidental double-back pops while a pushed
/// route is still animating back to root, while preserving [onMoveToBack]
/// when [allowExit] is false (for example during an active call).
class RootBackGuard extends StatelessWidget {
  final bool allowExit;
  final VoidCallback onMoveToBack;
  final Widget child;

  const RootBackGuard({
    super.key,
    required this.allowExit,
    required this.onMoveToBack,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryAnimation =
        ModalRoute.of(context)?.secondaryAnimation ?? kAlwaysDismissedAnimation;
    return AnimatedBuilder(
      animation: secondaryAnimation,
      builder: (context, guardedChild) {
        final returningToRoot =
            secondaryAnimation.status == AnimationStatus.reverse;
        return PopScope(
          canPop: allowExit && !returningToRoot,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !allowExit) {
              onMoveToBack();
            }
          },
          child: guardedChild!,
        );
      },
      child: child,
    );
  }
}
