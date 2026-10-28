import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The single signal every ambient surface in the app listens to.
///
/// A screen pushes raw scroll deltas in — vertical from the page,
/// lateral from the rows of reels and moments along the bottom — and
/// the backdrop reads back three smoothed numbers:
///
///   depth   how far the page has travelled, in px, eased
///   drift   how far the rows have travelled sideways, in px, eased
///   energy  0..1, how much the surface is moving *right now*
///
/// Nothing here decides what movement looks like; it only decides that
/// the sky knows the page moved. Depth and drift are what make the
/// layers separate — each one reads them at its own rate, so the far
/// ones lag the near ones and the whole thing gains a distance it
/// never had. Energy is the flare: a flick brightens the veils and
/// leans the motes over, and then it bleeds away slower than it
/// arrived, so the sky settles instead of snapping back.
///
/// Deltas are pushed rather than pulled from a controller so one
/// listener at the top of a screen can feed every scrollable under it,
/// however many rows it grows later.
class AmbientMotion extends ChangeNotifier {
  /// Eased vertical travel, in logical pixels.
  double get depth => _depth;
  double _depth = 0;

  /// Eased lateral travel, in logical pixels — a push rather than a
  /// position. See [settle] for why it comes back to nothing.
  double get drift => _drift;
  double _drift = 0;

  /// How alive the surface is, 0..1. Fast to rise, slow to fall.
  double get energy => _energy;
  double _energy = 0;

  /// Seconds since the surface appeared — the clock every idle drift
  /// is phased against.
  double get time => _time;
  double _time = 0;

  double _depthTarget = 0;
  double _driftTarget = 0;

  /// How far either axis is allowed to move the sky.
  ///
  /// Without these the two would grow without limit — a page a few
  /// thousand pixels long, or an afternoon of flicking rows, and every
  /// wash of light would have been carried clean off the screen and
  /// the sky would be a flat gradient with nothing in it. Past the
  /// limit the parallax simply saturates, which nobody can see,
  /// because by then whatever was casting it is long out of frame.
  static const _depthLimit = 1100.0;
  static const _driftLimit = 340.0;

  /// Distance travelled since the last settle, weighted; converted to
  /// a rate the moment we know how long the frame took.
  double _travelled = 0;

  /// Seconds stepped since the last repaint was asked for; see [settle].
  double _held = 0;

  bool _disposed = false;

  /// Below this the surface is at rest: nothing is scrolling, and the
  /// only movement left is the idle drift, which is slow enough that 30
  /// repaints a second can't be told from one every frame.
  static const _restEnergy = 0.015;

  /// The longest a resting surface holds a repaint back: just under the
  /// ambient beat, so on a frame drawn at the beat it always repaints.
  static const _restGap = 1 / 31;

  void pushVertical(double delta) {
    _depthTarget = (_depthTarget + delta).clamp(-_depthLimit, _depthLimit);
    _travelled += delta.abs();
  }

  /// Lateral travel counts for more than vertical: a row of reels is a
  /// smaller gesture than a page scroll, and should still be felt.
  void pushLateral(double delta) {
    _driftTarget = (_driftTarget + delta).clamp(-_driftLimit, _driftLimit);
    _travelled += delta.abs() * 1.6;
  }

  /// Advances the eased values by [dt] seconds. Called once per frame
  /// by whichever backdrop is on screen — the ticker lives there, so a
  /// screen with no backdrop costs nothing.
  void settle(double dt) {
    if (_disposed) return;
    // Frame times spike on the first frame after a route push and
    // whenever the raster thread stalls; a clamp keeps one long frame
    // from teleporting the sky.
    final step = dt.clamp(0.0, 1 / 24);
    _time += step;

    final follow = 1 - math.exp(-step * 6.5);
    _depth += (_depthTarget - _depth) * follow;
    _drift += (_driftTarget - _drift) * follow;

    // Vertical travel is a position — scroll back up and the sky comes
    // back with you. Lateral travel is not: a row of reels has no
    // relationship to where the night is, so pushing one leans the sky
    // over and then it rights itself over a couple of seconds. That
    // return is most of what makes flicking a row feel like moving
    // something rather than setting it.
    _driftTarget *= math.exp(-step * 0.42);

    final rate = step > 0 ? _travelled / step : 0.0;
    _travelled = 0;
    final target = (rate / 2400).clamp(0.0, 1.0);
    // Asymmetric: the flare arrives with the flick, and drains over
    // about a second. Equal rates read as a flicker.
    final k = target > _energy
        ? 1 - math.exp(-step * 14)
        : 1 - math.exp(-step * 2.4);
    _energy += (target - _energy) * k;

    // At rest the sky and the hero's air repaint at most 30 times a
    // second. Every listener is a full-surface painter — the veils, the
    // stars, the rays, the haze — and while nothing is being scrolled
    // they are drawing a drift measured in pixels a second. The clock
    // keeps AmbientPace, so a still page draws 30 frames a second; on
    // the faster frames something else is drawing (a spinner, a page
    // sliding in), the sky holds its picture between beats, and the
    // moment a finger moves the surface is back to every frame.
    final resting = _energy < _restEnergy &&
        (_depthTarget - _depth).abs() < 0.5 &&
        (_driftTarget - _drift).abs() < 0.5;
    _held += step;
    if (resting && _held < _restGap) return;
    _held = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Hands the screen's [AmbientMotion] to anything drawn under it.
///
/// A plain [InheritedWidget] rather than an [InheritedNotifier]: the
/// instance never changes, and the values inside it change every
/// frame. Rebuilding the subtree at 60 Hz is exactly what we are
/// trying not to do — the painters take it as a repaint [Listenable]
/// instead, which repaints without ever rebuilding a widget.
class AmbientScope extends InheritedWidget {
  final AmbientMotion motion;

  const AmbientScope({
    super.key,
    required this.motion,
    required super.child,
  });

  static AmbientMotion? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AmbientScope>()
      ?.motion;

  @override
  bool updateShouldNotify(AmbientScope old) => old.motion != motion;
}

/// Feeds every scrollable beneath it into [motion].
///
/// One of these at the root of a screen covers the page and all of its
/// rows, including rows added later — which is the point. Scrolling
/// the reels along the bottom has to move the sky just as the page
/// does, and neither should have to be wired up by hand.
class AmbientScrollSensor extends StatelessWidget {
  final AmbientMotion motion;
  final Widget child;

  const AmbientScrollSensor({
    super.key,
    required this.motion,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        final d = n.scrollDelta;
        // Depth 0 is the page itself; anything nested is a row.
        if (d != null && d != 0) {
          if (n.metrics.axis == Axis.vertical) {
            motion.pushVertical(d);
          } else {
            motion.pushLateral(d);
          }
        }
        return false; // let it keep bubbling; we are only eavesdropping
      },
      child: child,
    );
  }
}
