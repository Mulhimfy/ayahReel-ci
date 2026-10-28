/// The arena's light.
///
/// Everything in Tanafus that moves on its own is here: the aurora
/// behind the screens, the glint that runs across a button when it is
/// pressed, the light that follows a finger over a card, the ring the
/// clock burns down, the burst of gold a right answer throws. It is
/// all paint and no assets, like the rest of the app's ornament, and
/// every one of them stops when the platform asks for reduced motion.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';
import 'illumination.dart';
import 'ambient_pace.dart';

/// The arena's colours: an aurora of deep hues that sits behind the
/// app's night without ever competing with its gold, which stays the
/// one colour a thing to tap is painted.
abstract final class ArenaPalette {
  static const indigo = Color(0xFF3A43C7);
  static const violet = Color(0xFF8A36D6);
  static const teal = Color(0xFF17A3A6);
  static const rose = Color(0xFFD23C7E);
  static const amber = Color(0xFFE8B34A);

  /// The aurora, in the order the blobs are laid.
  static const mesh = [indigo, violet, teal, rose, amber];

  /// A wrong answer. Rose rather than red: it is a miss, not an alarm.
  static const wrong = Color(0xFFD9506F);

  /// Instagram's sweep, the way its icon runs it, for the story door.
  static const instagram = [
    Color(0xFFF0943A),
    Color(0xFFDE2C5A),
    Color(0xFFB8218F),
    Color(0xFF6A3BB4),
  ];
}

/// Whether the platform has asked for less motion.
bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ---------------------------------------------------------------------
// The aurora
// ---------------------------------------------------------------------

/// Five soft blobs of colour drifting over each other, added to
/// whatever is behind them. The arena's sky.
///
/// One ticker, one painter, repainted through a listenable rather
/// than a rebuild, and parked by [TickerMode] whenever the screen it
/// is on is not the one showing.
class MeshBackdrop extends StatefulWidget {
  /// Overall strength, 0..1.
  final double alpha;
  final double speed;
  final int seed;
  final List<Color> colors;

  const MeshBackdrop({
    super.key,
    this.alpha = 0.55,
    this.speed = 1,
    this.seed = 1,
    this.colors = ArenaPalette.mesh,
  });

  @override
  State<MeshBackdrop> createState() => _MeshBackdropState();
}

class _MeshBackdropState extends State<MeshBackdrop>
    with AmbientTickerProviderStateMixin {
  late final Ticker _ticker = ambient.createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  bool _still = false;

  void _tick(Duration elapsed) {
    _time.value = elapsed.inMicroseconds / 1e6 * widget.speed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reducedMotion(context);
    if (still == _still && (_ticker.isActive || still)) return;
    _still = still;
    if (still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MeshPainter(
          time: _time,
          alpha: widget.alpha,
          seed: widget.seed,
          colors: widget.colors,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// One frame of the aurora, painted once and never again: what the
/// story picture and any other still surface stand on.
class MeshStill extends StatelessWidget {
  final double time;
  final double alpha;
  final int seed;
  final List<Color> colors;

  const MeshStill({
    super.key,
    this.time = 3.7,
    this.alpha = 0.55,
    this.seed = 1,
    this.colors = ArenaPalette.mesh,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _MeshPainter(
          time: ValueNotifier(time),
          alpha: alpha,
          seed: seed,
          colors: colors,
        ),
        size: Size.infinite,
      );
}

class _MeshPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final double alpha;
  final int seed;
  final List<Color> colors;

  _MeshPainter({
    required this.time,
    required this.alpha,
    required this.seed,
    required this.colors,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final rnd = math.Random(seed);
    final n = colors.length;
    for (var i = 0; i < n; i++) {
      final bx = 0.15 + rnd.nextDouble() * 0.7;
      final by = 0.1 + rnd.nextDouble() * 0.8;
      final f1 = 0.08 + rnd.nextDouble() * 0.09;
      final f2 = 0.06 + rnd.nextDouble() * 0.08;
      final p1 = rnd.nextDouble() * math.pi * 2;
      final p2 = rnd.nextDouble() * math.pi * 2;
      final rr = 0.42 + rnd.nextDouble() * 0.3;
      final cx = size.width * (bx + 0.2 * math.sin(t * f1 * 2 * math.pi + p1));
      final cy =
          size.height * (by + 0.16 * math.cos(t * f2 * 2 * math.pi + p2));
      final r = size.shortestSide * rr;
      final c = colors[i];
      // Each blob breathes a little on its own clock, so the field
      // never settles into one shape.
      final breath = 0.85 + 0.15 * math.sin(t * 0.7 + i);
      canvas.drawCircle(
        Offset(cx, cy),
        r * breath,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              c.withValues(alpha: 0.38 * alpha),
              c.withValues(alpha: 0.12 * alpha),
              c.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: r * breath)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter old) =>
      old.alpha != alpha || old.seed != seed || old.colors != colors;
}

// ---------------------------------------------------------------------
// The glint
// ---------------------------------------------------------------------

/// Fires a [Glint].
class GlintController extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// A narrow band of light that runs across whatever it wraps in
/// about half a second — the flash a gilded button gives when it is
/// pressed. On its own, with [every], it runs now and then unasked,
/// the way a jewel catches the room.
///
/// Masks the child rather than painting over it, so it lights the
/// letters and the fill and leaves the gaps dark.
class Glint extends StatefulWidget {
  final Widget child;
  final GlintController? controller;

  /// How often it runs by itself; null for only when fired.
  final Duration? every;
  final double strength;

  const Glint({
    super.key,
    required this.child,
    this.controller,
    this.every,
    this.strength = 0.85,
  });

  @override
  State<Glint> createState() => _GlintState();
}

class _GlintState extends State<Glint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  Timer? _idle;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_fire);
    _armIdle();
  }

  void _armIdle() {
    final every = widget.every;
    if (every == null) return;
    // A random first wait, so two glints on one screen never run in
    // step.
    _idle = Timer(every * (0.4 + math.Random().nextDouble() * 0.8), () {
      _fire();
      _idle = Timer.periodic(every, (_) => _fire());
    });
  }

  void _fire() {
    if (!mounted || _still) return;
    _c.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = reducedMotion(context);
  }

  @override
  void didUpdateWidget(covariant Glint old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_fire);
      widget.controller?.addListener(_fire);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_fire);
    _idle?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        if (!_c.isAnimating) return child!;
        final v = Curves.easeInOutCubic.transform(_c.value);
        final head = -0.35 + v * 1.7;
        final s = widget.strength;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: const Alignment(-1, -0.7),
            end: const Alignment(1, 0.7),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.35 * s),
              Colors.white.withValues(alpha: s),
              Colors.white.withValues(alpha: 0.35 * s),
              Colors.transparent,
            ],
            stops: [
              (head - 0.22).clamp(0.0, 1.0),
              (head - 0.06).clamp(0.0, 1.0),
              head.clamp(0.0, 1.0),
              (head + 0.06).clamp(0.0, 1.0),
              (head + 0.22).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------
// Light that follows the finger
// ---------------------------------------------------------------------

/// Lights a card where it is touched: a soft pool of light under the
/// finger and the nearest stretch of the border brightening, both
/// fading when the finger lifts. The card reads as lit from where you
/// are, which is what makes it feel like a surface and not a picture
/// of one.
class TouchLight extends StatefulWidget {
  final Widget child;
  final BorderRadius radius;
  final Color color;
  final double strength;
  final bool enabled;

  const TouchLight({
    super.key,
    required this.child,
    required this.radius,
    this.color = AppColors.goldBright,
    this.strength = 1,
    this.enabled = true,
  });

  @override
  State<TouchLight> createState() => _TouchLightState();
}

class _TouchLightState extends State<TouchLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 520),
  );
  final _at = ValueNotifier<Offset?>(null);

  void _down(Offset p) {
    if (!widget.enabled) return;
    _at.value = p;
    _c.forward();
  }

  void _move(Offset p) {
    if (_c.value > 0) _at.value = p;
  }

  void _up() => _c.reverse();

  @override
  void dispose() {
    _c.dispose();
    _at.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _down(e.localPosition),
      onPointerMove: (e) => _move(e.localPosition),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: MouseRegion(
        onHover: (e) {
          if (!widget.enabled) return;
          _at.value = e.localPosition;
          if (_c.value == 0) _c.forward();
        },
        onExit: (_) => _up(),
        child: Stack(
          // The child fills whatever the card was given, so three of
          // these in a row of Expanded slots are three equal cards.
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _TouchLightPainter(
                      at: _at,
                      fade: _c,
                      radius: widget.radius,
                      color: widget.color,
                      strength: widget.strength,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TouchLightPainter extends CustomPainter {
  final ValueNotifier<Offset?> at;
  final Animation<double> fade;
  final BorderRadius radius;
  final Color color;
  final double strength;

  _TouchLightPainter({
    required this.at,
    required this.fade,
    required this.radius,
    required this.color,
    required this.strength,
  }) : super(repaint: Listenable.merge([at, fade]));

  @override
  void paint(Canvas canvas, Size size) {
    final p = at.value;
    final v = Curves.easeOut.transform(fade.value) * strength;
    if (p == null || v <= 0.01) return;
    final rect = Offset.zero & size;
    final rr = radius.toRRect(rect);
    canvas.save();
    canvas.clipRRect(rr);
    final r = size.longestSide * 0.6;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.16 * v),
            color.withValues(alpha: 0.05 * v),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.4, 1],
        ).createShader(Rect.fromCircle(center: p, radius: r)),
    );
    canvas.restore();
    // The border, lit near the finger and dark away from it.
    canvas.drawRRect(
      radius.toRRect(rect.deflate(0.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.95 * v),
            color.withValues(alpha: 0.35 * v),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.35, 1],
        ).createShader(
            Rect.fromCircle(center: p, radius: size.longestSide * 0.75)),
    );
  }

  @override
  bool shouldRepaint(covariant _TouchLightPainter old) =>
      old.radius != radius || old.color != color || old.strength != strength;
}

// ---------------------------------------------------------------------
// Waiting
// ---------------------------------------------------------------------

/// A block standing in for something not drawn yet, with a glare
/// running over it so the wait reads as the page arriving rather than
/// the page being broken.
class GlareBlock extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius radius;

  const GlareBlock({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  State<GlareBlock> createState() => _GlareBlockState();
}

class _GlareBlockState extends State<GlareBlock>
    with AmbientTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: ambient,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: widget.radius,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final head = still ? 0.5 : -0.3 + _c.value * 1.6;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-1, -0.4),
                  end: const Alignment(1, 0.4),
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.05),
                    AppColors.goldBright.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.05),
                  ],
                  stops: [
                    0,
                    (head - 0.18).clamp(0.0, 1.0),
                    head.clamp(0.0, 1.0),
                    (head + 0.18).clamp(0.0, 1.0),
                    1,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The clock
// ---------------------------------------------------------------------

/// The ring the clock burns down: a full turn of the aurora's colours
/// that shortens as the seconds go, with a bright head, turning to
/// rose and beating in the last quarter.
class TimerRing extends StatelessWidget {
  /// 1 with the whole clock left, 0 with none.
  final Animation<double> remaining;
  final double size;
  final double stroke;
  final Widget? child;

  const TimerRing({
    super.key,
    required this.remaining,
    this.size = 64,
    this.stroke = 4,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _RingPainter(remaining, stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Animation<double> remaining;
  final double stroke;

  _RingPainter(this.remaining, this.stroke) : super(repaint: remaining);

  @override
  void paint(Canvas canvas, Size size) {
    final r = remaining.value.clamp(0.0, 1.0);
    final c = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke;
    final rect = Rect.fromCircle(center: c, radius: radius);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.7
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    if (r <= 0) return;
    final late = r < 0.25;
    // The last quarter beats: the stroke swells with the seconds.
    final beat = late ? 1 + 0.35 * (0.5 + 0.5 * math.sin(r * 60)) : 1.0;
    final sweep = 2 * math.pi * r;
    const start = -math.pi / 2;
    final colors = late
        ? [ArenaPalette.rose, ArenaPalette.wrong, ArenaPalette.amber]
        : [
            ArenaPalette.teal,
            ArenaPalette.indigo,
            ArenaPalette.violet,
            ArenaPalette.rose,
            ArenaPalette.amber,
            AppColors.goldBright,
          ];
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * beat
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          colors: colors,
          transform: const GradientRotation(start),
        ).createShader(rect),
    );
    // The head: where the light is right now.
    final a = start + sweep;
    final head = Offset(c.dx + radius * math.cos(a), c.dy + radius * math.sin(a));
    canvas.drawCircle(
      head,
      stroke * 1.1,
      Paint()
        ..color = (late ? ArenaPalette.wrong : AppColors.goldBright)
            .withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(head, stroke * 0.55, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.stroke != stroke;
}

// ---------------------------------------------------------------------
// The burst
// ---------------------------------------------------------------------

/// Fires a [GoldBurst] from a point.
class BurstController extends ChangeNotifier {
  Offset origin = Offset.zero;
  int generation = 0;
  double scale = 1;

  /// [at] in the coordinates of the [GoldBurst] that listens.
  void fire(Offset at, {double scale = 1}) {
    origin = at;
    this.scale = scale;
    generation++;
    notifyListeners();
  }
}

/// Gold thrown up from a point — seals and motes, rising, turning,
/// falling, gone in a second. A right answer, a new best, a win.
class GoldBurst extends StatefulWidget {
  final BurstController controller;
  final int count;

  const GoldBurst({super.key, required this.controller, this.count = 42});

  @override
  State<GoldBurst> createState() => _GoldBurstState();
}

class _Mote {
  final double angle, speed, size, spin, phase;
  final bool seal;
  final Color color;
  const _Mote(this.angle, this.speed, this.size, this.spin, this.phase,
      this.seal, this.color);
}

class _GoldBurstState extends State<GoldBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  List<_Mote> _motes = const [];
  Offset _origin = Offset.zero;
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_fire);
  }

  void _fire() {
    if (!mounted || reducedMotion(context)) return;
    final rnd = math.Random(widget.controller.generation);
    _origin = widget.controller.origin;
    _scale = widget.controller.scale;
    const colors = [
      AppColors.goldBright,
      AppColors.gold,
      Color(0xFFFFF2CE),
      ArenaPalette.amber,
      Colors.white,
    ];
    _motes = [
      for (var i = 0; i < widget.count; i++)
        _Mote(
          -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.6,
          (0.45 + rnd.nextDouble() * 0.9) * 260,
          (2 + rnd.nextDouble() * 4),
          (rnd.nextDouble() - 0.5) * 6,
          rnd.nextDouble(),
          rnd.nextDouble() < 0.35,
          colors[rnd.nextInt(colors.length)],
        ),
    ];
    _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant GoldBurst old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_fire);
      widget.controller.addListener(_fire);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_fire);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BurstPainter(_c, () => _motes, () => _origin, () => _scale),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final Animation<double> t;
  final List<_Mote> Function() motes;
  final Offset Function() origin;
  final double Function() scale;

  _BurstPainter(this.t, this.motes, this.origin, this.scale)
      : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v <= 0 || v >= 1 || !t.isAnimating) return;
    final o = origin();
    final s = scale();
    for (final m in motes()) {
      final life = (v - m.phase * 0.12).clamp(0.0, 1.0);
      if (life <= 0) continue;
      final d = m.speed * s * life * (1 - 0.4 * life);
      final x = o.dx + math.cos(m.angle) * d;
      final y = o.dy + math.sin(m.angle) * d + 320 * life * life;
      final alpha = (1 - life).clamp(0.0, 1.0);
      final r = m.size * s * (1 - 0.4 * life);
      final paint = Paint()..color = m.color.withValues(alpha: alpha);
      if (m.seal) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(m.spin * life);
        canvas.drawPath(Khatam.star(Offset.zero, r * 1.6), paint);
        canvas.restore();
      } else {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter old) => false;
}

// ---------------------------------------------------------------------
// Small movements
// ---------------------------------------------------------------------

/// A number that counts up to its value.
class CountUp extends StatelessWidget {
  final int value;
  final TextStyle style;
  final Duration duration;
  final String Function(int)? format;

  const CountUp({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: still ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final n = v.round();
        return Text(format?.call(n) ?? '$n', style: style);
      },
    );
  }
}

/// Shakes a [Shaker].
class ShakeController extends ChangeNotifier {
  void shake() => notifyListeners();
}

/// A sideways shake — the small "no" a wrong answer gets.
class Shaker extends StatefulWidget {
  final ShakeController controller;
  final Widget child;
  const Shaker({super.key, required this.controller, required this.child});

  @override
  State<Shaker> createState() => _ShakerState();
}

class _ShakerState extends State<Shaker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_go);
  }

  void _go() {
    if (mounted && !reducedMotion(context)) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant Shaker old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_go);
      widget.controller.addListener(_go);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_go);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value;
        final dx = math.sin(v * math.pi * 4) * 9 * (1 - v);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// A row of small seals, one per question: filled gold once answered,
/// the current one lit, the rest waiting as outlines.
class SealProgress extends StatelessWidget {
  final int count;
  final int done;
  final int current;
  final double size;

  const SealProgress({
    super.key,
    required this.count,
    required this.done,
    required this.current,
    this.size = 9,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.22),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: i < done ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, v, _) {
                final lit = i == current && i >= done;
                return Transform.scale(
                  scale: 1 + 0.35 * v * (1 - v) * 4,
                  child: SealGlyph(
                    size: size,
                    filled: v > 0.5,
                    color: v > 0.5
                        ? Color.lerp(AppColors.gold, AppColors.goldBright, v)!
                        : lit
                            ? AppColors.goldBright
                            : AppColors.textSecondary.withValues(alpha: 0.55),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// A child that rises into place: a short lift, a fade and a hair of
/// scale, after [delay]. The staggered entrance every list in the
/// arena makes.
class Rise extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double from;

  const Rise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.from = 18,
  });

  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _wait = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, widget.from * (1 - v)),
            child: Transform.scale(scale: 0.97 + 0.03 * v, child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------
// The cartouche as glass
// ---------------------------------------------------------------------

/// Clips to the manuscript cartouche.
class CartoucheClipper extends CustomClipper<Path> {
  const CartoucheClipper();

  @override
  Path getClip(Size size) => Khatam.cartouche(Offset.zero & size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}

/// A pane of dark glass cut as a cartouche, with a ring of the
/// aurora's light running round its edge.
///
/// [turn] is where the ring's light is, 0..1 of a full turn; drive it
/// from a controller and the light circles the pane.
class CartouchePane extends StatelessWidget {
  final Widget child;
  final Animation<double> turn;
  final double blur;
  final double ringStrength;

  const CartouchePane({
    super.key,
    required this.child,
    required this.turn,
    this.blur = 12,
    this.ringStrength = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipPath(
          clipper: const CartoucheClipper(),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF1A2130).withValues(alpha: 0.62),
                    AppColors.bg.withValues(alpha: 0.86),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CartoucheRingPainter(turn, ringStrength),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartoucheRingPainter extends CustomPainter {
  final Animation<double> turn;
  final double strength;
  _CartoucheRingPainter(this.turn, this.strength) : super(repaint: turn);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Khatam.cartouche(rect.deflate(0.7));
    // The quiet ring, always there.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.gold.withValues(alpha: 0.32 * strength),
    );
    // The light going round.
    final a = turn.value * 2 * math.pi;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = SweepGradient(
          colors: [
            Colors.transparent,
            ArenaPalette.teal.withValues(alpha: 0.5 * strength),
            AppColors.goldBright.withValues(alpha: 0.95 * strength),
            ArenaPalette.rose.withValues(alpha: 0.5 * strength),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0, 0.08, 0.16, 0.24, 0.34, 1],
          transform: GradientRotation(a),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _CartoucheRingPainter old) =>
      old.strength != strength;
}

// ---------------------------------------------------------------------
// The way in
// ---------------------------------------------------------------------

/// The route the arena opens on: the page rises out of a bloom of
/// gold at the top of the screen, where the button that opened it is.
class BloomRoute<T> extends PageRouteBuilder<T> {
  BloomRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: const Duration(milliseconds: 480),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, a, b) => builder(context),
          transitionsBuilder: (context, a, b, child) {
            final v = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
            return Stack(
              fit: StackFit.expand,
              children: [
                FadeTransition(
                  opacity: v,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, -0.035),
                      end: Offset.zero,
                    ).animate(v),
                    child: ScaleTransition(
                      scale: Tween(begin: 0.96, end: 1.0).animate(v),
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: a,
                    builder: (context, _) {
                      final s = math.sin(a.value * math.pi);
                      if (s <= 0.01) return const SizedBox.shrink();
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -1.1),
                            radius: 1.1,
                            colors: [
                              AppColors.goldBright.withValues(alpha: 0.32 * s),
                              ArenaPalette.violet.withValues(alpha: 0.12 * s),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.35, 1],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
}

// ---------------------------------------------------------------------
// The mark
// ---------------------------------------------------------------------

/// Tanafus's own mark: a crown of light.
///
/// The crown is the oldest outline there is for having won, and the
/// one the Prophet ﷺ promised the one who carries the Quran — a crown
/// of light on the Day of Judgement. This is that crown drawn the way
/// the arena draws a round: as a constellation. Seven stars stand at
/// its points, its valleys and the ends of its band, the three at the
/// points the brightest, joined by a thread of light into the crown's
/// outline. So the mark is the card, and the card is the mark.
///
/// Geometry rather than an asset, like the rest of the app's marks, so
/// it is crisp at every size from a roundel to a story and it ships in
/// a patch. [phase] runs the light along the thread and twinkles the
/// stars; at 0 the crown stands still.
class TanafusMark extends StatelessWidget {
  final double size;
  final double phase;
  final Color color;
  final Color? shade;
  final bool glow;

  const TanafusMark({
    super.key,
    required this.size,
    this.phase = 0,
    this.color = AppColors.goldBright,
    this.shade,
    this.glow = true,
  });

  /// The crown's outline, in a square of [side]: the band's two ends,
  /// the three points with a valley between each pair, and the band
  /// closing it. Unit coordinates, y down.
  static const _outline = [
    Offset(0.10, 0.80), // band, left
    Offset(0.13, 0.30), // point, left
    Offset(0.33, 0.56), // valley
    Offset(0.50, 0.13), // point, centre
    Offset(0.67, 0.56), // valley
    Offset(0.87, 0.30), // point, right
    Offset(0.90, 0.80), // band, right
  ];

  /// Which of the outline's corners is a point (the bright stars), a
  /// valley (the faint ones), or the band's end.
  static const _weight = [0.62, 0.86, 0.42, 1.0, 0.42, 0.86, 0.62];

  /// The seven stars, in a square of [side].
  static List<Offset> stars(double side) =>
      [for (final p in _outline) Offset(p.dx * side, p.dy * side)];

  /// The thread: the outline as a closed path.
  static Path path(double side) {
    final s = stars(side);
    final p = Path()..moveTo(s.first.dx, s.first.dy);
    for (final o in s.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    p.close();
    return p;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _MarkPainter(phase, color, shade, glow),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  final double phase;
  final Color color;
  final Color? shade;
  final bool glow;
  const _MarkPainter(this.phase, this.color, this.shade, this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final dx = (size.width - side) / 2, dy = (size.height - side) / 2;
    canvas.translate(dx, dy);
    final stars = TanafusMark.stars(side);
    final thread = TanafusMark.path(side);
    final dark = shade ?? const Color(0xFFC9973B);
    final rect = Offset.zero & Size(side, side);
    final t = phase % 1;
    // Small marks are drawn a little heavier, so a roundel still reads
    // as a crown and not as a scribble.
    final small = side < 40;
    final line = (small ? 0.062 : side < 150 ? 0.048 : 0.040) * side;

    // The band: a fainter second line inside the base, which is what
    // makes a crown a crown and not a zigzag.
    final band = Path()
      ..moveTo(0.16 * side, 0.70 * side)
      ..lineTo(0.84 * side, 0.70 * side);

    final threadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = line
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFFFF2CE), color, dark],
      ).createShader(rect);

    if (glow) {
      canvas.drawPath(
        thread,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = line * 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withValues(alpha: 0.32)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.05),
      );
    }
    canvas.drawPath(thread, threadPaint);
    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line * 0.7
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: small ? 0.55 : 0.45),
    );

    // The light going round the thread.
    if (phase != 0) {
      for (final metric in thread.computeMetrics()) {
        final len = metric.length;
        final span = len * 0.16;
        final start = t * len;
        final pieces = start + span <= len
            ? [(start, start + span)]
            : [(start, len), (0.0, start + span - len)];
        for (final (a, b) in pieces) {
          final piece = metric.extractPath(a, b);
          canvas.drawPath(
            piece,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = line * 1.9
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFFFFF6DC).withValues(alpha: 0.55)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, line),
          );
          canvas.drawPath(
            piece,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = line * 1.1
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFFFFF6DC),
          );
        }
      }
    }

    // The stars, brightest at the points; each twinkling on its own
    // beat when the mark is alive.
    for (var i = 0; i < stars.length; i++) {
      final w = TanafusMark._weight[i];
      final tw = phase == 0
          ? 1.0
          : 0.86 + 0.14 * math.sin(2 * math.pi * (t * 2 + i * 0.29));
      final r = side * (small ? 0.10 : 0.085) * w * tw;
      final c = stars[i];
      if (glow) {
        canvas.drawCircle(
          c,
          r * 2.4,
          Paint()
            ..color = color.withValues(alpha: 0.42 * w * tw)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.1),
        );
      }
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            const Color(0xFFFFFBEE),
            const Color(0xFFFFF2CE),
            color,
          ], stops: const [0, 0.45, 1])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // The centre point wears a flare: four fine rays, the light of it.
    final top = stars[3];
    final flare = side * (small ? 0.16 : 0.19) *
        (phase == 0 ? 1 : 0.9 + 0.1 * math.sin(2 * math.pi * t * 2));
    final ray = Paint()
      ..strokeWidth = line * 0.45
      ..strokeCap = StrokeCap.round
      ..shader = RadialGradient(colors: [
        const Color(0xFFFFF6DC),
        color.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: top, radius: flare));
    canvas.drawLine(top - Offset(0, flare), top + Offset(0, flare), ray);
    canvas.drawLine(top - Offset(flare, 0), top + Offset(flare, 0), ray);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.phase != phase || old.color != color || old.glow != glow;
}
