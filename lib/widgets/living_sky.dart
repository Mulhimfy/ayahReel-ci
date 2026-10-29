import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';
import 'ambient_motion.dart';
import 'ambient_pace.dart';

/// The sky the whole app sits inside.
///
/// Six layers, each reading the same scroll signal at its own rate,
/// which is the only reason it reads as depth rather than as a moving
/// picture:
///
///   1  the ground      a night gradient, warm at the foot
///   2  the veils       three slow washes of light, added not painted
///   3  the stars       three depths, each lagging the one in front
///   4  the motes       lamp dust, leaned over by the scroll
///   5  the finish      a dither that kills the banding, then a vignette
///
/// Light and dust and nothing else. There is no pattern behind the
/// tabs: a lattice at that scale stops being texture and starts being
/// a grid of shapes drawn on the wall behind the app.
///
/// Nothing here loops on a fixed beat the eye can catch: every drift
/// is phased against every other with an irrational-ish ratio, so the
/// sky never arrives back at a frame you have already seen.
///
/// It is all painted — no images, no shader assets — which keeps it
/// inside what a Shorebird patch is allowed to carry.
class LivingSky extends StatefulWidget {
  final AmbientMotion motion;

  /// Scales every layer at once, 0..1. Panels drawn *on* the sky run a
  /// smaller sky of their own at a higher value, so a card is denser
  /// than the page behind it.
  final double intensity;

  /// Warm light pooled along the bottom edge, under the rows.
  final bool horizon;

  /// The opaque night gradient at the bottom of the stack.
  ///
  /// Off for a sky drawn over frosted glass: the whole point of the
  /// glass is what shows through it, and a ground painted over that
  /// would put the hole straight back.
  final bool ground;

  /// Whether this sky is the one advancing [motion].
  ///
  /// Exactly one on screen may: the clock and the easing are stepped
  /// once per frame, and a second ticker calling into the same signal
  /// would run time at double speed and halve every follow constant.
  /// A panel drawing its own small sky over the page's sets this off
  /// and rides the page's clock.
  final bool drivesClock;

  const LivingSky({
    super.key,
    required this.motion,
    this.intensity = 1,
    this.horizon = true,
    this.ground = true,
    this.drivesClock = true,
  });

  @override
  State<LivingSky> createState() => _LivingSkyState();
}

class _LivingSkyState extends State<LivingSky>
    with AmbientTickerProviderStateMixin {
  /// Only the sky that drives the clock gets a ticker at all. The
  /// panels riding the page's clock never create one.
  Ticker? _ticker;
  Duration _last = Duration.zero;

  /// Rebuilt only when the size changes. The star field and the
  /// dither are both deterministic, so keeping them is what makes the
  /// sky the same sky every time the tab is opened.
  final _cache = _SkyCache();

  bool _still = false;

  @override
  void initState() {
    super.initState();
    // At the ambient beat when the page is still, and on every frame
    // while a scroll or anything else is drawing anyway: AmbientPace.
    if (widget.drivesClock) {
      _ticker = ambient.createTicker(_onFrame)..start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    // Reduced motion parks the sky at a composed frame rather than
    // blanking it: the picture was never the problem, the movement was.
    if (still) {
      _ticker?.stop();
      if (widget.drivesClock) widget.motion.settle(0);
    } else if (_ticker != null) {
      _last = Duration.zero;
      _ticker!.start();
    }
  }

  void _onFrame(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    widget.motion.settle(dt);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The sky repaints every frame and nothing above it does. Without
    // this boundary the whole page would be re-rastered with it.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SkyPainter(
          motion: widget.motion,
          cache: _cache,
          intensity: widget.intensity,
          horizon: widget.horizon,
          ground: widget.ground,
        ),
        size: Size.infinite,
        isComplex: true,
        willChange: !_still,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------

class _SkyCache {
  Size? size;
  ui.Picture? dither;
  List<_Star>? stars;
  List<_Mote>? motes;

  void invalidate(Size s) {
    if (size == s) return;
    size = s;
    dither?.dispose();
    dither = _buildDither(s);
    stars = _Star.field(s);
    motes = _Mote.field(s);
  }

  void dispose() {
    dither?.dispose();
    dither = null;
  }

  /// A fixed spray of near-invisible specks.
  ///
  /// Large dark gradients band on OLED phones — you get visible steps
  /// where two neighbouring 8-bit values meet. A little noise laid over
  /// the top breaks the step up and the banding stops being readable.
  /// It is the cheapest single thing on this screen that separates it
  /// from looking rendered.
  static ui.Picture _buildDither(Size s) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final rnd = math.Random(20240);
    final paint = Paint();
    final n = (s.width * s.height / 1100).clamp(260, 1400).toInt();
    for (var i = 0; i < n; i++) {
      paint.color = (rnd.nextBool() ? Colors.white : AppColors.gold)
          .withValues(alpha: 0.006 + rnd.nextDouble() * 0.014);
      canvas.drawRect(
        Rect.fromLTWH(
            rnd.nextDouble() * s.width, rnd.nextDouble() * s.height, 1.2, 1.2),
        paint,
      );
    }
    return rec.endRecording();
  }
}

// ---------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------

class _SkyPainter extends CustomPainter {
  final AmbientMotion motion;
  final _SkyCache cache;
  final double intensity;
  final bool horizon;
  final bool ground;

  _SkyPainter({
    required this.motion,
    required this.cache,
    required this.intensity,
    required this.horizon,
    required this.ground,
  }) : super(repaint: motion);

  /// The three washes. Each carries its own speed, its own phase and
  /// its own distance, and the speeds do not divide into each other.
  static const _veils = <_Veil>[
    _Veil(Color(0xFFD4A947), 0.150, 0.0000, 0.062, 0.185, 0.72),
    _Veil(Color(0xFF3E5C9E), 0.115, 2.1000, 0.041, 0.108, 0.95),
    _Veil(Color(0xFF2E7F79), 0.080, 4.3000, 0.089, 0.255, 0.58),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    cache.invalidate(size);

    final rect = Offset.zero & size;
    final t = motion.time;
    final depth = motion.depth;
    final drift = motion.drift;
    final energy = motion.energy;
    final k = intensity;

    canvas.clipRect(rect);

    if (ground) _ground(canvas, rect);
    _washes(canvas, rect, size, t, depth, drift, energy, k);
    _stars(canvas, size, t, depth, drift, energy, k);
    _motes(canvas, size, t, drift, energy, k);
    if (horizon) _horizon(canvas, rect, size, t, energy, k);
    if (cache.dither != null) canvas.drawPicture(cache.dither!);
    _vignette(canvas, rect);
  }

  /// Layer 1.
  ///
  /// Flat [AppColors.bg] for everything the hero photograph can reach,
  /// and only then a half-degree of warmth at the foot where the lamp
  /// is. The flat run is not laziness: the hero lands its scrim on
  /// exactly this value, and the two can only meet invisibly if the
  /// value is not still changing where they meet.
  void _ground(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D1117),
            Color(0xFF0D1117),
            Color(0xFF120F13),
          ],
          stops: [0.0, 0.80, 1.0],
        ).createShader(rect),
    );
  }

  /// Layer 2. Added rather than painted over: light on light gets
  /// brighter where two washes cross, which is what a real aurora
  /// does and what alpha compositing refuses to do.
  void _washes(Canvas canvas, Rect rect, Size size, double t, double depth,
      double drift, double energy, double k) {
    final span = size.shortestSide;
    for (final v in _veils) {
      final cx = size.width *
              (0.5 + 0.44 * math.sin(t * v.speed * 0.83 + v.phase)) -
          drift * v.lateral;
      final cy = size.height *
              (0.30 + 0.34 * math.cos(t * v.speed * 0.61 + v.phase * 1.7)) -
          depth * v.parallax;
      // A flick stretches the wash along the way the finger went and
      // brightens it — the sky leaning into the movement.
      final r = span * v.reach * (1 + 0.22 * energy);
      final bounds = Rect.fromCenter(
        center: Offset(cx, cy),
        width: r * 2 * (1 + 0.20 * energy),
        height: r * 2 * (1 - 0.10 * energy),
      );
      // Only the wash's own footprint. A radial gradient clamps to its
      // last stop past its edge, and that stop is fully transparent, so
      // every pixel of the frame outside [bounds] was being blended
      // with nothing — a full-screen fill per veil, three times a
      // frame, for no pixel anyone could see. Identical picture.
      canvas.drawRect(
        bounds.intersect(rect),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              v.color.withValues(alpha: v.alpha * k * (0.82 + 0.55 * energy)),
              v.color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(bounds),
      );
    }
  }

  /// Layer 3. Three depths. The near stars keep up with the page, the
  /// far ones barely move, and that gap is the parallax — the same one
  /// you get looking out of a train.
  void _stars(Canvas canvas, Size size, double t, double depth, double drift,
      double energy, double k) {
    final stars = cache.stars;
    if (stars == null) return;
    const bleed = _Star.bleed;
    final fw = size.width + bleed * 2;
    final fh = size.height + bleed * 2;
    final paint = Paint();
    for (final s in stars) {
      final x = (s.x - drift * s.lateral) % fw - bleed;
      final y = (s.y - depth * s.parallax) % fh - bleed;
      // Each one breathes on its own clock, so the field shimmers
      // instead of pulsing.
      final tw = 0.55 + 0.45 * math.sin(t * s.rate + s.phase);
      final a = s.alpha * tw * k * (1 + 0.35 * energy);
      paint.color = s.color.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), s.r, paint);
      // The nearest layer gets a halo, which is what sells it as being
      // in front of the others rather than merely larger.
      if (s.r > 1.25) {
        paint.color = s.color.withValues(alpha: (a * 0.20).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), s.r * 3.4, paint);
      }
    }
  }

  /// Layer 4. Dust rising through lamp light. It leans the way the
  /// page was flicked and speeds up while the flick is still in the
  /// air, then goes back to rising.
  void _motes(Canvas canvas, Size size, double t, double drift, double energy,
      double k) {
    final motes = cache.motes;
    if (motes == null) return;
    final paint = Paint()..blendMode = BlendMode.plus;
    for (final m in motes) {
      final rise = (m.y - t * m.speed * (1 + 1.6 * energy)) % (size.height + 80);
      final y = size.height + 40 - rise;
      final x = (m.x +
              math.sin(t * m.sway + m.phase) * m.swayBy -
              drift * 0.16) %
          (size.width + 60) -
          30;
      final a = m.alpha * k * (0.5 + 0.5 * math.sin(t * m.sway * 0.7 + m.phase));
      paint.color =
          AppColors.goldBright.withValues(alpha: a.clamp(0.0, 1.0) * 0.5);
      canvas.drawCircle(Offset(x, y), m.r * 2.6, paint);
      paint.color = AppColors.goldBright.withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), m.r, paint);
    }
  }

  /// A pool of warm light along the bottom edge, so the rows of reels
  /// are standing in something instead of floating on black.
  void _horizon(
      Canvas canvas, Rect rect, Size size, double t, double energy, double k) {
    final h = size.height * 0.34;
    final bounds = Rect.fromCenter(
      center: Offset(size.width * (0.5 + 0.06 * math.sin(t * 0.11)),
          size.height + h * 0.32),
      width: size.width * 1.9,
      height: h * 1.7,
    );
    canvas.drawRect(
      Rect.fromLTRB(rect.left, size.height - h, rect.right, rect.bottom),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            AppColors.gold
                .withValues(alpha: (0.085 + 0.055 * energy) * k),
            AppColors.gold.withValues(alpha: 0.0),
          ],
        ).createShader(bounds),
    );
  }

  /// Last. Pulls the corners down so the eye stays in the middle of
  /// the page where the words are.
  void _vignette(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.92,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.34),
          ],
          stops: const [0.52, 0.80, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SkyPainter old) =>
      old.intensity != intensity ||
      old.horizon != horizon ||
      old.ground != ground ||
      old.cache != cache;
}

// ---------------------------------------------------------------------
// The furniture
// ---------------------------------------------------------------------

class _Veil {
  final Color color;
  final double alpha;

  /// Radians per second of the drift. None of these divides into
  /// another, so the three never come back into phase.
  final double phase;
  final double speed;

  /// How much of the page's own travel this wash takes on. Small is
  /// far away.
  final double parallax;
  final double lateral;
  final double reach;

  const _Veil(this.color, this.alpha, this.phase, this.speed, this.parallax,
      this.reach)
      : lateral = parallax * 0.55;
}

class _Star {
  static const bleed = 140.0;

  final double x, y, r, alpha, rate, phase, parallax, lateral;
  final Color color;

  const _Star(this.x, this.y, this.r, this.alpha, this.rate, this.phase,
      this.parallax, this.lateral, this.color);

  /// Three depths, deterministic, so the sky is the same sky every
  /// time the tab is opened.
  static List<_Star> field(Size s) {
    final rnd = math.Random(9137);
    final w = s.width + bleed * 2;
    final h = s.height + bleed * 2;
    final area = (w * h) / (400 * 900); // counts tuned on a stock phone
    final out = <_Star>[];
    // Trimmed from 92 to 58. Past about here another star is another
    // draw call a frame and nothing anybody can see.
    const layers = [
      (count: 28, rMin: 0.5, rMax: 0.9, a: 0.32, par: 0.14),
      (count: 20, rMin: 0.8, rMax: 1.3, a: 0.44, par: 0.30),
      (count: 10, rMin: 1.3, rMax: 1.9, a: 0.58, par: 0.52),
    ];
    for (final l in layers) {
      final n = (l.count * area).clamp(6, 140).toInt();
      for (var i = 0; i < n; i++) {
        out.add(_Star(
          rnd.nextDouble() * w,
          rnd.nextDouble() * h,
          l.rMin + rnd.nextDouble() * (l.rMax - l.rMin),
          l.a * (0.6 + rnd.nextDouble() * 0.4),
          0.5 + rnd.nextDouble() * 1.6,
          rnd.nextDouble() * math.pi * 2,
          l.par,
          l.par * 0.55,
          rnd.nextDouble() < 0.32 ? AppColors.gold : Colors.white,
        ));
      }
    }
    return out;
  }
}

class _Mote {
  final double x, y, r, alpha, speed, sway, swayBy, phase;
  const _Mote(this.x, this.y, this.r, this.alpha, this.speed, this.sway,
      this.swayBy, this.phase);

  static List<_Mote> field(Size s) {
    final rnd = math.Random(4421);
    final n = ((s.width * s.height) / 42000).clamp(4, 12).toInt();
    return [
      for (var i = 0; i < n; i++)
        _Mote(
          rnd.nextDouble() * (s.width + 60),
          rnd.nextDouble() * (s.height + 80),
          0.7 + rnd.nextDouble() * 1.0,
          0.18 + rnd.nextDouble() * 0.26,
          5 + rnd.nextDouble() * 11,
          0.25 + rnd.nextDouble() * 0.5,
          8 + rnd.nextDouble() * 20,
          rnd.nextDouble() * math.pi * 2,
        ),
    ];
  }
}
