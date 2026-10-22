/// Glass on a tile: the picture under a pane of glass that answers a
/// finger.
///
/// The scenery picker was a wall of flat posters. Here every poster is
/// behind a pane of glass:
///
///   touch      the pane leans toward the finger (at most 9° of yaw and
///              7° of pitch) and lifts a hair, a burst of light runs
///              across it and sparkles catch at its corners
///   hold       still for 0.12 s, then slide, and every tile under the
///              finger leans after it with a tick of the selection
///              haptic — the grid holds still meanwhile; a plain drag
///              still scrolls it
///   let go     everything eases home
///   at rest    the light drifts slowly over all the panes at once, so
///              they still read as glass with nothing touching them
///
/// It behaves like hover: a tap still does exactly what it did before,
/// because the glass never claims a tap. It only takes the touch for
/// itself once a slide after the hold has made it plainly not one.
///
/// The motion is the Glass Gifts concept's (tgdesign, design 5), which
/// is Telegram's TON wallet card: the angles follow their targets with
/// 1 − e^(−8 dt), the lift with 1 − e^(−12 dt), the targets decay by
/// e^(−4 dt) once the finger has gone, and the perspective is
/// m34 = −1/650. The concept moves the light with the phone's tilt;
/// this app reads no motion sensor, so a slow light of its own stands
/// in — one light for a whole grid, wandering, which each pane catches
/// according to where it is on the screen, so scrolling the grid moves
/// the light across it as tilting a sheet of glass would.
///
/// Cost, for a grid of forty tiles on a slow phone:
///
///   * one ticker per touched tile, and none at rest — a tile's ticker
///     stops as soon as it is home;
///   * one light for the whole grid, stepped about 24 times a second
///     from a timer rather than a ticker, so the slow drift never asks
///     for a frame it does not need (and a settled test settles);
///   * the lean is a transform over a retained layer, and nothing is
///     rebuilt for any of it: the painters listen, the widgets don't.
///
/// With the platform asking for less motion the panes never lean, lift
/// or drift; the light still follows the finger.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The numbers. Those that are not the app's own are the concept's
/// (glass-gifts.js `GiftLook`, profile-page.js), which are Telegram's.
abstract final class GlassLook {
  /// Degrees. The wallet card turns up to 17.2° on a 361 pt card; a
  /// tile a third of a phone wide wants about half of that.
  static const maxYaw = 9.0;
  static const maxPitch = 7.0;

  /// The lift while touched.
  static const held = 1.01;

  /// m34 = −1 / [perspective].
  static const perspective = 650.0;

  /// Telegram's context-gesture threshold: still this long, a slide
  /// belongs to the tiles rather than to the grid.
  static const hold = Duration(milliseconds: 120);

  /// A move past this before the hold is a scroll, and the glass lets
  /// the touch go.
  static const scrollSlop = 8.0;

  /// The hold counts within this; a slide this long after it starts
  /// following the finger across the tiles.
  static const holdSlop = 10.0;

  /// Points per millisecond along the grid's scroll above which the
  /// slide that ends a hold is a flick, and the grid's to scroll. A
  /// finger rested on a grid a moment before throwing it is common,
  /// and a grid that would not scroll for it would read as stuck.
  static const flingSpeed = 0.6;

  /// The burst waits this long for the finger to show it is not a
  /// scroll. Under the tenth of a second a touch reads as answered in,
  /// and a grid that flashed at the start of every scroll would be a
  /// grid that never stopped flashing.
  static const burstDelay = Duration(milliseconds: 60);

  /// A finger that has moved further than this by [burstDelay] is
  /// starting a scroll: no burst.
  static const stillSlop = 4.0;

  /// The burst's own clock: the shards run in this, the sparkles a
  /// little after.
  static const burstSeconds = 0.55;

  /// The picture sits behind the glass, so while the pane leans it
  /// shifts a little against it — this many points per degree — and
  /// comes a little closer to fill the room the shift needs.
  static const slide = 0.24;
  static const zoom = 0.04;

  /// The run of light round a tile's edge when it is chosen. It waits
  /// for the touch's own burst to have mostly run, so the two never
  /// land at once, and then takes its time.
  static const ringDelay = 0.16;
  static const ringSeconds = 1.05;

  /// How far the slow light leans the light, at most, in the degrees
  /// of the concept's phone tilt (±20 is the whole effect there).
  static const ambient = 5.0;

  /// How often the slow light moves. Slow enough that a step is under
  /// a pixel; often enough that it never looks stepped.
  static const ambientStep = Duration(milliseconds: 42);
}

/// One light fragment running across the glass during a burst.
@immutable
class GlassShard {
  /// 0..1.
  final double opacity;

  /// How far along it is, in percent of its own width (−130 → 130).
  final double translation;

  /// Degrees.
  final double rotation;

  const GlassShard(this.opacity, this.translation, this.rotation);
}

/// One sparkle at a corner of the glass during a burst.
@immutable
class GlassSparkle {
  final double opacity;
  final double scale;

  /// Degrees.
  final double rotation;

  const GlassSparkle(this.opacity, this.scale, this.rotation);
}

/// Everything one frame of the glass shows: the concept's
/// `GlassTileState`, in the concept's units — angles in degrees, the
/// light's positions in percent of their own boxes, offsets in points.
@immutable
class GlassPose {
  /// Whether anything is still moving: the lean, the lift, a burst.
  final bool isActive;

  /// The pane: perspective, translate, scale, then rotate X, Y and Z.
  final double yaw;
  final double pitch;
  final double scale;
  final Offset translation;
  final double roll;

  /// The specular sheen, a soft light in a box 170 % of the tile:
  /// its shift (percent of that box) and strength.
  final Offset sheen;
  final double sheenOpacity;

  /// The faint prismatic streak: its background position (percent)
  /// and strength.
  final Offset holo;
  final double holoOpacity;

  /// Where the lit edge faces, as a CSS gradient angle (0 = up,
  /// clockwise).
  final double rimAngle;

  /// The picture's shift behind the glass, in points.
  final Offset slide;

  /// The soft shadow under a leaning pane.
  final Offset shadowOffset;
  final double shadowScale;
  final double shadowOpacity;

  /// Only while a burst runs.
  final List<GlassShard>? shards;
  final List<GlassSparkle>? sparkles;

  const GlassPose({
    this.isActive = false,
    this.yaw = 0,
    this.pitch = 0,
    this.scale = 1,
    this.translation = Offset.zero,
    this.roll = 0,
    this.sheen = Offset.zero,
    this.sheenOpacity = 0.3,
    this.holo = const Offset(50, 50),
    this.holoOpacity = 0.06,
    this.rimAngle = 135,
    this.slide = Offset.zero,
    this.shadowOffset = const Offset(0, 2),
    this.shadowScale = 0.96,
    this.shadowOpacity = 0.32,
    this.shards,
    this.sparkles,
  });

  /// A pane nobody is touching, under a light straight ahead.
  static const rest = GlassPose();
}

double _clamp(double x, [double lo = 0, double hi = 1]) =>
    x < lo ? lo : (x > hi ? hi : x);

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

/// One pane's lean, lift and light: the concept's `GlassTile`, as plain
/// Dart, frame by frame.
class GlassMotion {
  double _yaw = 0;
  double _pitch = 0;
  double _scale = 1;
  double _targetYaw = 0;
  double _targetPitch = 0;
  double _targetScale = 1;
  bool _touching = false;
  double? _burstStart;

  bool get isTouching => _touching;
  bool get isBursting => _burstStart != null;

  /// The finger at ([u], [v]) in the tile, −1..1 each way, (0, 0) the
  /// centre. Past the edge counts as the edge.
  void aim(double u, double v) {
    _touching = true;
    _targetYaw = _clamp(u, -1, 1) * GlassLook.maxYaw;
    _targetPitch = -_clamp(v, -1, 1) * GlassLook.maxPitch;
    _targetScale = GlassLook.held;
  }

  /// The finger has gone: the pane eases home.
  void release() {
    _touching = false;
    _targetScale = 1;
  }

  /// A burst of light starting at [now], on the same clock as [update].
  void burst(double now) => _burstStart = now;

  /// One frame [dt] seconds after the last, at [now]. [light] is the
  /// tilt the light comes from, in degrees (±20 is the whole effect);
  /// [motionLean] is how many degrees of lean it may add.
  GlassPose update(
    double now,
    double dt, {
    Offset light = Offset.zero,
    double motionLean = 0,
  }) {
    if (!_touching) {
      // The pan's offset decays after release.
      final k = math.exp(-4 * dt);
      _targetYaw *= k;
      _targetPitch *= k;
    }
    final a = 1 - math.exp(-8 * dt);
    final b = 1 - math.exp(-12 * dt);
    _yaw += (_targetYaw - _yaw) * a;
    _pitch += (_targetPitch - _pitch) * a;
    _scale += (_targetScale - _scale) * b;

    final lx = light.dx;
    final ly = light.dy;
    final yaw = _yaw + _clamp(lx / 20, -1, 1) * motionLean;
    final pitch = _pitch - _clamp(ly / 20, -1, 1) * motionLean;
    final moving = (_targetYaw - _yaw).abs() > 0.01 ||
        (_targetPitch - _pitch).abs() > 0.01 ||
        (_targetScale - _scale).abs() > 1e-4 ||
        _targetYaw.abs() > 0.01 ||
        _targetPitch.abs() > 0.01;

    // The light: the pane's lean plus the light's own tilt, ×0.9 for
    // the surface.
    final sx = yaw + lx * 0.9;
    final sy = pitch - ly * 0.9;
    final tilt = math.min(1.0, _hypot(sx, sy) / 12);

    List<GlassShard>? shards;
    List<GlassSparkle>? sparkles;
    var bursting = false;
    final start = _burstStart;
    if (start != null) {
      final u = (now - start) / GlassLook.burstSeconds;
      shards = List<GlassShard>.generate(3, (i) {
        final v = _clamp(u * 1.25 - i * 0.12);
        return GlassShard(
          v > 0 && v < 1 ? math.sin(math.pi * v) * 0.8 : 0.0,
          -130 + 260 * v,
          -28.0 + i * 7,
        );
      });
      sparkles = List<GlassSparkle>.generate(4, (i) {
        final v = _clamp(u * 1.4 - 0.15 - i * 0.08);
        final k = v > 0 && v < 1 ? math.sin(math.pi * v) : 0.0;
        return GlassSparkle(k, 0.3 + k, v * 120);
      });
      if (u >= 1.3) _burstStart = null;
      bursting = true;
    }

    return GlassPose(
      isActive: moving || bursting,
      yaw: yaw,
      pitch: pitch,
      scale: _scale,
      translation: Offset(-yaw * 0.06, pitch * 0.05),
      roll: yaw * 0.05,
      sheen: Offset(_clamp(sx * 2.2, -40, 40), _clamp(-sy * 2.2, -40, 40)),
      sheenOpacity: 0.3 + 0.7 * tilt,
      holo: Offset(50 + sx * 5, 50 - sy * 5),
      holoOpacity: 0.06 + 0.3 * tilt,
      rimAngle: 135 + sx * 6 - sy * 6,
      // Behind the glass rather than floating on it, the picture moves
      // against the lean: toward the side that comes nearer.
      slide: Offset(-yaw * GlassLook.slide, pitch * GlassLook.slide),
      shadowOffset: Offset(-yaw * 0.45, pitch * 0.45 + 2),
      shadowScale: 0.96 + (_scale - 1) * 2,
      shadowOpacity: 0.32 + 0.4 * math.min(1.0, _hypot(yaw, pitch) / 9),
      shards: shards,
      sparkles: sparkles,
    );
  }
}

/// What is under the glass, which decides how strong its light is.
enum GlassSurface {
  /// A photograph: the light is kept low, so the picture stays the
  /// picture a user is choosing between.
  picture,

  /// A flat panel — a tile with only a glyph on it — which takes the
  /// glass's light in full.
  flat,
}

/// A tile under glass. See the library comment for what it does.
///
/// It adds nothing to what a screen reader hears and takes no tap: put
/// the tile's own [GestureDetector] and semantics around it, as
/// before. Inside, wrap the picture in a [GlassDepth] to set it behind
/// the glass.
///
/// Tiles inside the same [Scrollable] share their light and their
/// hold-and-slide; nothing has to be put around the grid for that.
class GlassTile extends StatefulWidget {
  final Widget child;

  /// The tile's corner radius, which the light is cut to.
  final double radius;

  /// A run of light goes once round the edge when this turns on.
  final bool selected;

  final GlassSurface surface;

  const GlassTile({
    super.key,
    required this.child,
    this.radius = 14,
    this.selected = false,
    this.surface = GlassSurface.picture,
  });

  @override
  State<GlassTile> createState() => GlassTileState();
}

/// Public for tests: [debugPose], [debugDepth], [debugStill].
class GlassTileState extends State<GlassTile>
    with SingleTickerProviderStateMixin {
  final _motion = GlassMotion();
  final _frame = _GlassFrame();
  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// The tile's own clock, seconds: advanced only while its ticker runs.
  double _time = 0;

  /// 0 at rest … 1 awake: how much of the perspective, the lift of the
  /// picture and the shadow are showing. Fades in as the glass wakes
  /// and out once it is home, so a tile at rest is exactly the tile.
  double _depth = 0;

  double? _ringStart;

  /// The slow light where this tile is, in degrees of tilt.
  Offset _ambient = Offset.zero;

  bool _still = false;
  bool _tickerOn = true;
  bool _active = true;
  _GlassGroup? _group;

  @visibleForTesting
  GlassPose get debugPose => _frame.pose;

  @visibleForTesting
  double get debugDepth => _frame.depth;

  @visibleForTesting
  bool get debugStill => _frame.still;

  /// Whether the slow light should run for this tile.
  bool get _lit => _active && _tickerOn && !_still;

  bool get _usable => mounted && _active;

  RenderBox? get _box {
    if (!_usable) return null;
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerOn = TickerMode.valuesOf(context).enabled;
    if (_still) _ambient = Offset.zero;
    final Object scope = Scrollable.maybeOf(context) ?? this;
    if (!identical(_group?.scope, scope)) {
      _group?.remove(this);
      _group = _GlassGroup.of(scope)..add(this);
    } else {
      _group?.changed();
    }
    _publish();
  }

  @override
  void didUpdateWidget(covariant GlassTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected && !_still) {
      _ringStart = _time;
      _wake();
    }
  }

  @override
  void deactivate() {
    // Out of the tree, if only for a moment: out of the grid's light
    // and out of reach of a finger sliding over it.
    _active = false;
    _group?.remove(this);
    _group = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    // didChangeDependencies follows and finds the grid again.
  }

  @override
  void dispose() {
    _active = false;
    _group?.remove(this);
    _group = null;
    _ticker?.dispose();
    _frame.dispose();
    super.dispose();
  }

  // ---- the finger (from _GlassRecognizer) --------------------------

  void _aim(Offset global) {
    final box = _box;
    if (box == null) return;
    final p = box.globalToLocal(global);
    final s = box.size;
    if (s.isEmpty) return;
    _motion.aim(p.dx / s.width * 2 - 1, p.dy / s.height * 2 - 1);
    _wake();
  }

  void _release() {
    if (!_usable) return;
    _motion.release();
    _wake();
  }

  void _flash() {
    if (!_usable) return;
    _motion.burst(_time);
    _wake();
  }

  bool _contains(Offset global) {
    final box = _box;
    return box != null &&
        (Offset.zero & box.size).contains(box.globalToLocal(global));
  }

  // ---- frames -------------------------------------------------------

  void _wake() {
    if (!_usable) return;
    final ticker = _ticker ??= createTicker(_tick);
    if (!ticker.isActive) {
      _last = Duration.zero;
      ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    // The concept's frame step: 0..50 ms, so a stalled frame never
    // throws the glass.
    final dt = _clamp((elapsed - _last).inMicroseconds / 1e6, 0, 0.05);
    _last = elapsed;
    _time += dt;
    final pose = _motion.update(_time, dt, light: _ambient);
    final awake = pose.isActive || _motion.isTouching;
    final target = awake && !_still ? 1.0 : 0.0;
    _depth += (target - _depth) * (1 - math.exp(-12 * dt));
    if ((target - _depth).abs() < 0.001) _depth = target;
    final ring = _ring();
    _frame.set(pose, depth: _depth, ring: ring, still: _still);
    if (!awake && _depth == target && ring == null) _ticker?.stop();
  }

  /// A frame without moving the clock: the light moved, or the tile
  /// was just built.
  void _publish() {
    if (_ticker?.isActive ?? false) return;
    final pose = _motion.update(_time, 0, light: _ambient);
    _frame.set(pose, depth: _still ? 0 : _depth, ring: null, still: _still);
  }

  double? _ring() {
    final start = _ringStart;
    if (start == null) return null;
    final p =
        (_time - start - GlassLook.ringDelay) / GlassLook.ringSeconds;
    if (p >= 1) {
      _ringStart = null;
      return null;
    }
    // Negative while it waits: the ticker keeps running for it.
    return p;
  }

  /// The grid's slow light has moved on.
  void _ambientTick(double time, double strength) {
    if (!_lit) return;
    final box = _box;
    if (box == null) return;
    final centre = box.localToGlobal(box.size.center(Offset.zero));
    final light = _GlassGroup.lightAt(time, centre) * strength;
    if ((light - _ambient).distance < 0.015) return;
    _ambient = light;
    _publish();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      gestures: <Type, GestureRecognizerFactory>{
        _GlassRecognizer:
            GestureRecognizerFactoryWithHandlers<_GlassRecognizer>(
          () => _GlassRecognizer(debugOwner: this),
          (r) => r.tile = this,
        ),
      },
      child: _GlassBody(
        frame: _frame,
        radius: widget.radius,
        child: RepaintBoundary(
          child: CustomPaint(
            foregroundPainter: _GlassLightPainter(
              frame: _frame,
              radius: widget.radius,
              surface: widget.surface,
            ),
            child: _GlassScope(frame: _frame, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// The picture under the glass. Inside a [GlassTile] it moves a little
/// against the pane while it leans, as something behind a window does;
/// anywhere else it is just its child.
///
/// Put it inside the tile's clip: it comes a few percent closer while
/// the pane is awake, so its edges stay out of sight as it shifts.
class GlassDepth extends StatelessWidget {
  final Widget child;
  const GlassDepth({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final frame =
        context.dependOnInheritedWidgetOfExactType<_GlassScope>()?.frame;
    if (frame == null) return child;
    return _GlassDepthBox(frame: frame, child: child);
  }
}

// ---------------------------------------------------------------------
// The frame every part listens to
// ---------------------------------------------------------------------

/// One tile's current frame. The transform, the picture behind the
/// glass and the light all listen to it and repaint; nothing rebuilds.
class _GlassFrame extends ChangeNotifier {
  GlassPose pose = GlassPose.rest;
  double depth = 0;
  double? ring;
  bool still = false;

  void set(
    GlassPose pose, {
    required double depth,
    required double? ring,
    required bool still,
  }) {
    this.pose = pose;
    this.depth = depth;
    this.ring = ring;
    this.still = still;
    notifyListeners();
  }
}

class _GlassScope extends InheritedWidget {
  final _GlassFrame frame;
  const _GlassScope({required this.frame, required super.child});

  @override
  bool updateShouldNotify(_GlassScope old) => old.frame != frame;
}

const _deg = math.pi / 180;

// ---------------------------------------------------------------------
// The lean and the shadow
// ---------------------------------------------------------------------

class _GlassBody extends SingleChildRenderObjectWidget {
  final _GlassFrame frame;
  final double radius;

  const _GlassBody({
    required this.frame,
    required this.radius,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassBody(frame, radius);

  @override
  void updateRenderObject(BuildContext context, _RenderGlassBody body) {
    body
      ..frame = frame
      ..radius = radius;
  }
}

/// Leans its child as the frame says, about its centre, with the
/// shadow flat under it. Taps are not leaned with it: a tile answers
/// where it stands, so a finger sliding over a leaning pane never sees
/// its edge move away from under it.
class _RenderGlassBody extends RenderProxyBox {
  _RenderGlassBody(this._frame, this._radius);

  _GlassFrame _frame;
  set frame(_GlassFrame value) {
    if (identical(value, _frame)) return;
    if (attached) {
      _frame.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _frame = value;
    markNeedsPaint();
  }

  double _radius;
  set radius(double value) {
    if (value == _radius) return;
    _radius = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _frame.removeListener(markNeedsPaint);
    super.detach();
  }

  /// The wallet card's transform: perspective, a small translate with
  /// the angles, the lift, X / Y rotation and a touch of Z — about the
  /// centre, with the perspective as strong as the glass is awake.
  static Matrix4 lean(Size size, GlassPose p, double depth) {
    final c = size.center(Offset.zero);
    final m = Matrix4.identity()
      ..setEntry(3, 2, -depth / GlassLook.perspective)
      ..translateByDouble(p.translation.dx, p.translation.dy, 0, 1)
      ..scaleByDouble(p.scale, p.scale, 1, 1)
      ..rotateX(p.pitch * _deg)
      ..rotateY(p.yaw * _deg)
      ..rotateZ(p.roll * _deg);
    return Matrix4.translationValues(c.dx, c.dy, 0)
      ..multiply(m)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final f = _frame;
    final k = f.still ? 0.0 : f.depth;
    if (k <= 0) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final p = f.pose;
    // The shadow: flat on the page under the pane, away from the
    // finger, darker the further the pane leans.
    final alpha = 0.55 * p.shadowOpacity * k;
    if (alpha > 0.004) {
      // The concept's: in by 8 at the sides and 10 at the top, 4 out
      // at the foot, a little rounder than the tile.
      final box = Rect.fromLTRB(8, 10, size.width - 8, size.height + 4);
      final r = math.min(_radius + 4, box.shortestSide / 2);
      final grown = Rect.fromCenter(
        center: box.center + p.shadowOffset,
        width: box.width * p.shadowScale,
        height: box.height * p.shadowScale,
      );
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(grown.shift(offset), Radius.circular(r)),
        Paint()
          ..color = Colors.black.withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    final m = lean(size, p, k);
    final det = m.determinant();
    if (det == 0 || !det.isFinite) {
      layer = null;
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      m,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }
}

// ---------------------------------------------------------------------
// The picture behind the glass
// ---------------------------------------------------------------------

class _GlassDepthBox extends SingleChildRenderObjectWidget {
  final _GlassFrame frame;
  const _GlassDepthBox({required this.frame, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassDepth(frame);

  @override
  void updateRenderObject(BuildContext context, _RenderGlassDepth box) {
    box.frame = frame;
  }
}

class _RenderGlassDepth extends RenderProxyBox {
  _RenderGlassDepth(this._frame);

  _GlassFrame _frame;
  set frame(_GlassFrame value) {
    if (identical(value, _frame)) return;
    if (attached) {
      _frame.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _frame = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _frame.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final f = _frame;
    final k = f.still ? 0.0 : f.depth;
    if (k <= 0) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final c = size.center(Offset.zero);
    final s = 1 + GlassLook.zoom * k;
    final slide = f.pose.slide * k;
    final m = Matrix4.translationValues(c.dx + slide.dx, c.dy + slide.dy, 0)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    layer = context.pushTransform(
      needsCompositing,
      offset,
      m,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }
}

// ---------------------------------------------------------------------
// The light
// ---------------------------------------------------------------------

/// How strongly each part of the light shows on a surface.
///
/// The concept's numbers are for a flat grey tile with a sticker on
/// it. Over a photograph the same light washes the picture out — the
/// colour streak reads as a cast on the sky, a full-strength burst as
/// grey paint across it — so a picture takes less of each, and the
/// sparkles come a little smaller and warmer.
class _Gain {
  final double glazeTop;
  final double glazeFoot;
  final double holo;
  final double sheen;
  final double rim;
  final double shard;
  final double sparkle;
  final Color sparkleColour;

  const _Gain({
    required this.glazeTop,
    required this.glazeFoot,
    required this.holo,
    required this.sheen,
    required this.rim,
    required this.shard,
    required this.sparkle,
    required this.sparkleColour,
  });

  static const picture = _Gain(
    glazeTop: 0.06,
    glazeFoot: 0,
    holo: 0.42,
    sheen: 0.62,
    rim: 0.85,
    shard: 0.62,
    sparkle: 0.82,
    sparkleColour: Color(0xFFFFF8EA),
  );
  static const flat = _Gain(
    glazeTop: 0.09,
    glazeFoot: 0.02,
    holo: 1,
    sheen: 1,
    rim: 1,
    shard: 1,
    sparkle: 1,
    sparkleColour: Color(0xFFFFFFFF),
  );

  static _Gain of(GlassSurface s) =>
      s == GlassSurface.flat ? flat : picture;
}

Color _white(double alpha) =>
    Color.from(alpha: _clamp(alpha), red: 1, green: 1, blue: 1);

/// The two ends of a CSS `linear-gradient(<angle>)` over a box: 0deg
/// points up, 90deg right, and the line is long enough that the corners
/// get the first and the last colour.
(Offset, Offset) _cssLine(double degrees, Size size) {
  final a = degrees * _deg;
  final dx = math.sin(a);
  final dy = -math.cos(a);
  final length =
      (size.width * math.sin(a)).abs() + (size.height * math.cos(a)).abs();
  final c = size.center(Offset.zero);
  final half = Offset(dx, dy) * (length / 2);
  return (c - half, c + half);
}

/// The glass's sparkle — the concept's four-pointed star, with a soft
/// glow round it — at [centre]: ten points across at [scale] 1, turned
/// [rotation] degrees. Shared, so everything in the app that catches
/// the light catches it the same way.
void paintSparkle(
  Canvas canvas,
  Offset centre, {
  required double opacity,
  double scale = 1,
  double rotation = 0,
  Color color = const Color(0xFFFFFFFF),
  double glow = 0.5,
}) {
  if (opacity <= 0.004 || scale <= 0) return;
  canvas.save();
  canvas.translate(centre.dx, centre.dy);
  canvas.rotate(rotation * _deg);
  canvas.scale(scale);
  if (glow > 0) {
    canvas.drawCircle(
      Offset.zero,
      6,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          6,
          [
            color.withValues(alpha: _clamp(glow * opacity)),
            color.withValues(alpha: 0),
          ],
        ),
    );
  }
  canvas.drawPath(
    _sparkle,
    Paint()..color = color.withValues(alpha: _clamp(opacity)),
  );
  canvas.restore();
}

/// The concept's four-pointed sparkle, ten points across, centred.
final Path _sparkle = () {
  const points = [
    (0.5, 0.0),
    (0.62, 0.38),
    (1.0, 0.5),
    (0.62, 0.62),
    (0.5, 1.0),
    (0.38, 0.62),
    (0.0, 0.5),
    (0.38, 0.38),
  ];
  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final x = (points[i].$1 - 0.5) * 10;
    final y = (points[i].$2 - 0.5) * 10;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path..close();
}();

class _GlassLightPainter extends CustomPainter {
  final _GlassFrame frame;
  final double radius;
  final GlassSurface surface;

  _GlassLightPainter({
    required this.frame,
    required this.radius,
    required this.surface,
  }) : super(repaint: frame);

  static const _pink = Color(0xFFFF40A0);
  static const _gold = Color(0xFFFFD246);
  static const _mint = Color(0xFF46FFC8);
  static const _blue = Color(0xFF5096FF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = frame.pose;
    final g = _Gain.of(surface);
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.save();
    canvas.clipRRect(rrect);

    // The glaze: the pane's own faint reflection, brightest at the top
    // corner.
    final glaze = _cssLine(160, size);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          glaze.$1,
          glaze.$2,
          [_white(g.glazeTop), _white(g.glazeFoot)],
          const [0, 0.55],
        ),
    );

    // The prismatic streak: a band of colour in a box three times the
    // tile's size, which slides with the light.
    final holoAlpha = 0.55 * p.holoOpacity * g.holo;
    if (holoAlpha > 0.02) {
      final box = Size(w * 3, h * 3);
      final origin = Offset(
        (w - box.width) * p.holo.dx / 100,
        (h - box.height) * p.holo.dy / 100,
      );
      final line = _cssLine(115, box);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            line.$1 + origin,
            line.$2 + origin,
            [
              _pink.withValues(alpha: 0),
              _pink.withValues(alpha: holoAlpha),
              _gold.withValues(alpha: holoAlpha),
              _mint.withValues(alpha: holoAlpha),
              _blue.withValues(alpha: holoAlpha),
              _blue.withValues(alpha: 0),
            ],
            const [0.30, 0.40, 0.46, 0.52, 0.58, 0.68],
          ),
      );
    }

    // The sheen: a soft light in a box 170 % of the tile, its circle at
    // (50 %, 38 %) of the box, sliding against the lean.
    final sheenAlpha = p.sheenOpacity * g.sheen;
    if (sheenAlpha > 0.01) {
      final bw = w * 1.7;
      final bh = h * 1.7;
      final o = Offset((w - bw) / 2 + p.sheen.dx / 100 * bw,
          (h - bh) / 2 + p.sheen.dy / 100 * bh);
      final centre = o + Offset(bw * 0.5, bh * 0.38);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            centre,
            _hypot(bw * 0.5, bh * 0.62),
            [_white(0.34 * sheenAlpha), _white(0.08 * sheenAlpha), _white(0)],
            const [0, 0.28, 0.5],
          ),
      );
    }

    // The burst: fragments of light crossing the glass.
    final shards = p.shards;
    if (shards != null) {
      final sw = w * 0.34;
      final sh = h * 2.2;
      for (var i = 0; i < shards.length; i++) {
        final s = shards[i];
        if (s.opacity <= 0.004) continue;
        final top = h * (-0.6 + 0.28 * i);
        canvas.save();
        canvas.translate(sw / 2 + s.translation / 100 * sw, top + sh / 2);
        canvas.rotate(s.rotation * _deg);
        final band = Rect.fromCenter(center: Offset.zero, width: sw, height: sh);
        // The concept's white band, with its light gathered toward the
        // middle: a fragment of light rather than a stripe of white.
        final a = 0.7 * s.opacity * g.shard;
        canvas.drawRect(
          band,
          Paint()
            ..shader = ui.Gradient.linear(
              band.centerLeft,
              band.centerRight,
              [_white(0), _white(0.4 * a), _white(a), _white(0.4 * a), _white(0)],
              const [0, 0.3, 0.5, 0.7, 1],
            ),
        );
        canvas.restore();
      }
    }

    // The edge: a hairline, brighter where it faces the light.
    final rim = _cssLine(p.rimAngle, size);
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rim.$1,
          rim.$2,
          [
            _white(0.7 * g.rim),
            _white(0.1 * g.rim),
            _white(0.06 * g.rim),
            _white(0.45 * g.rim),
          ],
          const [0, 0.32, 0.68, 1],
        ),
    );

    // Chosen: a run of gold light once round the edge, from the corner
    // the light comes from, with a soft glow inside it.
    final ring = frame.ring;
    if (ring != null && ring >= 0) {
      final strength =
          _clamp(ring / 0.12) * _clamp((1 - ring) / 0.35);
      final head = -0.75 * math.pi +
          Curves.easeInOutCubic.transform(ring) * 2 * math.pi;
      final light = SweepGradient(
        colors: [
          Colors.transparent,
          AppColors.gold.withValues(alpha: 0),
          AppColors.goldBright.withValues(alpha: 0.7 * strength),
          _white(0.95 * strength),
          Colors.transparent,
        ],
        stops: const [0, 0.62, 0.86, 0.95, 1],
        transform: GradientRotation(head - 0.95 * 2 * math.pi),
      ).createShader(rect);
      final edge = rrect.deflate(1);
      canvas.drawRRect(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..shader = light
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawRRect(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..shader = light,
      );
    }

    // The sparkles, catching at the corners.
    final sparkles = p.sparkles;
    if (sparkles != null) {
      final at = [
        const Offset(13, 13),
        Offset(w - 13, 15),
        Offset(15, h - 15),
        Offset(w - 11, h - 13),
      ];
      for (var i = 0; i < sparkles.length && i < at.length; i++) {
        final s = sparkles[i];
        paintSparkle(
          canvas,
          at[i],
          opacity: s.opacity,
          scale: s.scale * g.sparkle,
          rotation: s.rotation,
          color: g.sparkleColour,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassLightPainter old) =>
      !identical(old.frame, frame) ||
      old.radius != radius ||
      old.surface != surface;
}

// ---------------------------------------------------------------------
// The touch
// ---------------------------------------------------------------------

enum _Touch { idle, pending, armed, following }

/// The glass's touch on one tile — the concept's `down` / `move` / `up`
/// in the gesture arena, taking nothing away from what the tile does:
///
///   down      the pane leans toward the finger at once; the burst
///             follows a moment later unless the finger is already
///             moving off. The recognizer stays undecided, so the tap
///             under it still has the touch.
///   moves     past 8 points before the hold: a scroll. The glass
///             gives the touch up and eases home; the grid scrolls.
///   lifts     a tap, however slow: the glass gives up, the tap wins.
///   held      still for 0.12 s, within 10 points: armed.
///   slides    10 points after the hold: the glass takes the touch —
///             the tap and the scroll are told no — and every tile
///             the finger crosses leans after it, with a burst and a
///             tick of the selection haptic. Unless the slide is a
///             flick along the grid's scroll: a finger that rested a
///             moment and then threw the grid is scrolling it, so the
///             glass gives that touch up as well.
///
/// A touch that lands on a grid still coasting from a fling never gets
/// here: the scroll view keeps taps from its children while it moves,
/// and the touch only catches it.
class _GlassRecognizer extends OneSequenceGestureRecognizer {
  _GlassRecognizer({super.debugOwner});

  GlassTileState? tile;

  _Touch _phase = _Touch.idle;
  int? _pointer;
  Offset _start = Offset.zero;
  Offset _at = Offset.zero;
  Duration _when = Duration.zero;
  Timer? _hold;
  Timer? _flashWait;
  bool _flashed = false;

  /// The tile under the finger while following; null between tiles.
  GlassTileState? _held;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    final t = tile;
    // One finger at a time: a second one is left to whatever else
    // wants it.
    if (_pointer != null || t == null || !t._usable) return;
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _start = event.position;
    _at = event.position;
    _when = event.timeStamp;
    _phase = _Touch.pending;
    _flashed = false;
    _held = t;
    t._aim(event.position);
    _flashWait = Timer(GlassLook.burstDelay, _flashIfStill);
    _hold = Timer(GlassLook.hold, _arm);
  }

  void _flashIfStill() {
    _flashWait = null;
    if (_flashed || _phase == _Touch.idle) return;
    if ((_at - _start).distance > GlassLook.stillSlop) return;
    _flashed = true;
    _held?._flash();
  }

  void _arm() {
    _hold = null;
    if (_phase == _Touch.pending) _phase = _Touch.armed;
  }

  /// Whether the move that ends the hold is a flick along the grid's
  /// scroll: a finger rested on the grid and then thrown is scrolling
  /// it, whatever it did first. A slide that means to follow the tiles
  /// sets off slower than this.
  bool _flung(PointerMoveEvent e) {
    final axis = tile?._group?.axis;
    if (axis == null) return false;
    var ms = (e.timeStamp - _when).inMicroseconds / 1000;
    // No clock to go by: events made up rather than reported.
    if (ms <= 0) return false;
    // Nothing reported for a while and then this far at once: the
    // finger set off since the last report, within a frame or so.
    if (ms > 50) ms = 16;
    final d = e.position - _at;
    final along = axis == Axis.vertical ? d.dy.abs() : d.dx.abs();
    final across = axis == Axis.vertical ? d.dx.abs() : d.dy.abs();
    return along >= across && along / ms > GlassLook.flingSpeed;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      final travelled = (event.position - _start).distance;
      switch (_phase) {
        case _Touch.pending:
          if (travelled > GlassLook.scrollSlop) {
            _giveUp();
          } else {
            tile?._aim(event.position);
          }
        case _Touch.armed:
          if (travelled < GlassLook.holdSlop) {
            tile?._aim(event.position);
          } else if (_flung(event)) {
            _giveUp();
          } else {
            _begin(event.position);
          }
        case _Touch.following:
          _follow(event.position);
        case _Touch.idle:
          break;
      }
      _at = event.position;
      _when = event.timeStamp;
    } else if (event is PointerUpEvent) {
      if (_phase == _Touch.following) {
        _end();
      } else {
        // A tap: it still gets its light, however quick it was.
        if (!_flashed && _phase != _Touch.idle) {
          _flashed = true;
          _held?._flash();
        }
        _giveUp();
      }
    } else if (event is PointerCancelEvent) {
      if (_phase == _Touch.following) {
        _end();
      } else {
        _giveUp();
      }
    }
  }

  /// The slide after the hold: from here the touch is the glass's.
  void _begin(Offset at) {
    final p = _pointer;
    if (p == null) return;
    _phase = _Touch.following;
    resolvePointer(p, GestureDisposition.accepted);
    if (_phase != _Touch.following) return; // turned down after all
    HapticFeedback.selectionClick();
    // A finger that wavered at the start never set its first tile
    // alight; it does now.
    if (!_flashed) {
      _flashed = true;
      _held?._flash();
    }
    _follow(at, ticked: true);
  }

  /// The tile under the finger leans after it; crossing onto another
  /// one lets the last go and lights the new one.
  void _follow(Offset at, {bool ticked = false}) {
    final t = tile;
    final group = t?._group;
    final GlassTileState? under = group != null
        ? group.tileAt(at)
        : (t != null && t._contains(at) ? t : null);
    if (!identical(under, _held)) {
      _held?._release();
      _held = under;
      if (under != null) {
        under._flash();
        if (!ticked) HapticFeedback.selectionClick();
      }
    }
    _held?._aim(at);
  }

  void _giveUp() {
    final p = _pointer;
    _finish();
    if (p != null) {
      resolvePointer(p, GestureDisposition.rejected);
      stopTrackingPointer(p);
    }
  }

  void _end() {
    final p = _pointer;
    _finish();
    if (p != null) stopTrackingPointer(p);
  }

  void _finish() {
    _hold?.cancel();
    _hold = null;
    _flashWait?.cancel();
    _flashWait = null;
    if (_phase != _Touch.idle) _held?._release();
    _held = null;
    _phase = _Touch.idle;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    // The tap or the scroll has the touch: home.
    _finish();
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _finish();
    _pointer = null;
  }

  @override
  void dispose() {
    _finish();
    super.dispose();
  }

  @override
  String get debugDescription => 'glass';
}

// ---------------------------------------------------------------------
// The grid: one light, and the finger's way across
// ---------------------------------------------------------------------

/// The tiles of one [Scrollable] — or a tile on its own — sharing the
/// slow light and the hold-and-slide.
///
/// Made by the first tile that needs it and gone with the last, so
/// nothing has to be put around a grid for its tiles to find each
/// other.
class _GlassGroup {
  _GlassGroup._(this.scope);

  static final _groups = Expando<_GlassGroup>('glass');

  static _GlassGroup of(Object scope) =>
      _groups[scope] ??= _GlassGroup._(scope);

  final Object scope;
  final _tiles = <GlassTileState>{};
  Timer? _wait;
  int? _frameId;
  Duration? _stamp;
  double _time = 0;
  bool _gone = false;

  /// The way the grid scrolls; null for a tile on its own.
  Axis? get axis {
    final scope = this.scope;
    return scope is ScrollableState && scope.mounted
        ? axisDirectionToAxis(scope.axisDirection)
        : null;
  }

  void add(GlassTileState t) {
    _tiles.add(t);
    changed();
  }

  void remove(GlassTileState t) {
    _tiles.remove(t);
    if (_tiles.isNotEmpty) {
      changed();
      return;
    }
    _stop();
    _gone = true;
    if (identical(_groups[scope], this)) _groups[scope] = null;
  }

  /// A tile's ticker mode or motion setting changed.
  void changed() {
    if (_tiles.any((t) => t._lit)) {
      _arm();
    } else {
      _stop();
    }
  }

  void _arm() {
    if (_gone || _wait != null || _frameId != null) return;
    _wait = Timer(GlassLook.ambientStep, _request);
  }

  void _request() {
    _wait = null;
    if (_gone || !_tiles.any((t) => t._lit)) return;
    // On the frame, not on the timer: a step lands where a frame is
    // drawn, and a phone with its screen off draws none, so asks for
    // nothing.
    _frameId = SchedulerBinding.instance.scheduleFrameCallback(_step);
  }

  void _step(Duration stamp) {
    _frameId = null;
    if (_gone) return;
    final last = _stamp;
    _stamp = stamp;
    if (last != null) {
      _time += _clamp((stamp - last).inMicroseconds / 1e6, 0, 0.25);
    }
    // The light comes up over the first second rather than arriving
    // in one step with the grid.
    final strength = _clamp(_time / 1.2);
    for (final t in _tiles.toList()) {
      t._ambientTick(_time, strength);
    }
    _arm();
  }

  void _stop() {
    _wait?.cancel();
    _wait = null;
    final id = _frameId;
    if (id != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _frameId = null;
    }
    // A pause is not light time: the drift picks up where it stopped.
    _stamp = null;
  }

  /// The slow light at a point of the screen at [time], in degrees of
  /// tilt. Two slow swings that never line up, phased across the
  /// screen, so the light wanders rather than rocks, and a pane catches
  /// it a little later than the one above and to the left of it.
  static Offset lightAt(double time, Offset centre) {
    final phase = centre.dx * 0.0021 + centre.dy * 0.0014;
    const a = GlassLook.ambient;
    return Offset(
      a * math.sin(2 * math.pi * time / 13 + phase),
      a * 0.75 * math.sin(2 * math.pi * time / 19 + phase * 0.8 + 1.2),
    );
  }

  /// The tile under [global], as the screen stacks things: a tile
  /// scrolled under a pinned header is not under the finger.
  GlassTileState? tileAt(Offset global) {
    final scope = this.scope;
    if (scope is ScrollableState && scope.mounted) {
      final box = scope.context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final byBox = <RenderObject, GlassTileState>{
          for (final t in _tiles)
            if (t._box case final RenderBox b) b: t,
        };
        final result = BoxHitTestResult();
        box.hitTest(result, position: box.globalToLocal(global));
        for (final entry in result.path) {
          final target = entry.target;
          if (target is RenderObject) {
            final t = byBox[target];
            if (t != null) return t;
          }
        }
        return null;
      }
    }
    for (final t in _tiles) {
      if (t._contains(global)) return t;
    }
    return null;
  }
}
