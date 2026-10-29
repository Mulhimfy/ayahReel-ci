import 'package:flutter/material.dart';

/// A one-time entrance: the child rises into place from a little below,
/// swinging up out of depth as it comes, and fades in — after [delay].
///
/// For things that are made, shown on a shelf: a card, a deck, a page
/// of verses. Each arrives as an object rather than appearing as a
/// picture. With the platform asking for less motion it is simply there.
class Arrive extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far back it starts, in radians about its foot.
  final double depth;

  /// How far below it starts.
  final double rise;

  const Arrive({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 640),
    this.depth = 0.45,
    this.rise = 26,
  });

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) return child;
    final total = delay + duration;
    final start = total.inMicroseconds == 0
        ? 0.0
        : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..translateByDouble(0, rise * (1 - v), 0, 1)
            ..rotateX(depth * (1 - v)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
