import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/surah_index.dart';
import '../data/verse_light.dart';
import '../theme/app_theme.dart';
import 'illumination.dart' show Khatam;

/// The whole Quran as a sun: one ray for each of the 114 surahs,
/// clockwise from the top in the order of the mushaf, each as long as
/// its surah — square-rooted, so the shortest are still there — and
/// every verse a bead along its ray. The outline is the real shape of
/// the book: the long Medinan surahs flare at the top right, the short
/// Meccan ones close the circle as a fringe.
///
/// The verses somebody has met in the app — in their reels, their
/// cards, the quiz — burn on it as segments of their rays. Everyone's
/// sun has the same shape; nobody's lights the same way.
abstract final class QuranSun {
  /// The sun with [light] on it, still, painted straight onto [canvas]
  /// in a square of [size]: for a picture drawn outside any widget —
  /// the notification that offers the card to be shared.
  static void paintStill(Canvas canvas, Size size, VerseLight light) {
    const _SunBase().paint(canvas, size);
    _SunLight(light: light).paint(canvas, size);
  }

  /// Where the beads start: the hub, as a share of the sun's radius.
  static const hub = 0.17;

  static double angleOf(int surah) =>
      -math.pi / 2 + (surah - 0.5) / surahIndex.length * math.pi * 2;

  /// The ray's length past the hub, as a share of the span from the hub
  /// to the rim.
  static double lengthOf(int surah) =>
      0.1 + 0.9 * math.sqrt(surahIndex[surah - 1].ayahCount) / math.sqrt(286);
}

/// The sun, live: it turns up out of the dark, the lit verses burning
/// in one run at a time in the order they were first met, and then
/// breathes.
/// [animate] off draws the settled sun at once — what goes into the
/// shared picture.
class QuranSunView extends StatefulWidget {
  final VerseLight light;
  final bool animate;

  const QuranSunView({super.key, required this.light, this.animate = true});

  @override
  State<QuranSunView> createState() => _QuranSunViewState();
}

class _QuranSunViewState extends State<QuranSunView>
    with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
    value: widget.animate ? 0 : 1,
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3800),
  );

  /// The glow's opacity as the sun breathes.
  late final Animation<double> _glow =
      Tween(begin: 0.82, end: 1.0).animate(_breath);

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _in.forward().whenComplete(() {
        if (mounted) _breath.repeat(reverse: true);
      });
    }
  }

  @override
  void didUpdateWidget(QuranSunView old) {
    super.didUpdateWidget(old);
    // New verses light where they belong without the whole entrance
    // again: only the burning-in runs once more. Not while the entrance
    // is still running — the light read a moment after it began (the
    // cards', the quiz's) just burns in with it.
    if (widget.animate &&
        !_in.isAnimating &&
        !identical(old.light, widget.light) &&
        old.light.order.length != widget.light.order.length) {
      _breath.stop();
      _in
        ..value = 0.45
        ..forward().whenComplete(() {
          if (mounted) _breath.repeat(reverse: true);
        });
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.animate ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final rise = CurvedAnimation(
        parent: _in, curve: const Interval(0, 0.45, curve: Curves.easeOutCubic));
    const base = RepaintBoundary(
      child: CustomPaint(
        painter: _SunBase(),
        size: Size.infinite,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (still)
          base
        else
          AnimatedBuilder(
            animation: rise,
            builder: (context, child) {
              final t = rise.value;
              // Turned a few degrees and a shade small as it surfaces,
              // the way a light comes up rather than switches on.
              return Opacity(
                opacity: t,
                child: Transform.rotate(
                  angle: (1 - t) * -0.14,
                  child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
                ),
              );
            },
            child: base,
          ),
        if (still)
          CustomPaint(
            painter: _SunLight(light: widget.light),
            size: Size.infinite,
          )
        else ...[
          // The lit verses in two layers, each painted only while they
          // burn in: the glow, which then breathes by its layer's
          // opacity alone, and the cores over it. A long history is
          // hundreds of blurred strokes, and a breath is every frame.
          FadeTransition(
            opacity: _glow,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _SunLight(
                    light: widget.light, ignite: _in, part: _SunPart.glow),
                size: Size.infinite,
              ),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: _SunLight(
                  light: widget.light, ignite: _in, part: _SunPart.core),
              size: Size.infinite,
            ),
          ),
        ],
      ],
    );
  }
}

/// Everything that is the same on every sun: the beads, the ray tips,
/// two faint rings, and the hub with its seal.
class _SunBase extends CustomPainter {
  const _SunBase();

  /// Six weights of bead, from the hub out: each drawn in one call.
  static const _bands = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * 0.95;
    final r0 = radius * QuranSun.hub;
    final span = radius - r0;
    final unit = size.shortestSide / 1080;

    for (final (k, alpha) in [(1.0, 0.10), (0.62, 0.06)]) {
      canvas.drawCircle(
        c,
        radius * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3 * unit
          ..color = AppColors.goldBright.withValues(alpha: alpha),
      );
    }

    final bands = List.generate(_bands, (_) => <double>[]);
    final tips = <double>[];
    for (var s = 1; s <= surahIndex.length; s++) {
      final a = QuranSun.angleOf(s);
      final len = span * QuranSun.lengthOf(s);
      final n = surahIndex[s - 1].ayahCount;
      final dx = math.cos(a), dy = math.sin(a);
      for (var v = 1; v <= n; v++) {
        final t = (v - 0.5) / n;
        final r = r0 + len * t;
        final band = math.min(_bands - 1, (t * _bands).floor());
        bands[band]
          ..add(c.dx + dx * r)
          ..add(c.dy + dy * r);
      }
      final tip = r0 + len + 6.5 * unit;
      tips
        ..add(c.dx + dx * tip)
        ..add(c.dy + dy * tip);
    }
    for (var b = 0; b < _bands; b++) {
      final t = (b + 0.5) / _bands;
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(bands[b]),
        Paint()
          ..color = const Color(0xFFF0D696).withValues(alpha: 0.10 + 0.32 * t)
          ..strokeWidth = 3.7 * unit * (0.8 + 0.5 * t)
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList(tips),
      Paint()
        ..color = const Color(0x8CFAECC8)
        ..strokeWidth = 5.6 * unit
        ..strokeCap = StrokeCap.round,
    );

    // The hub: a pool of light, a ring, and the seal.
    canvas.drawCircle(
      c,
      r0,
      Paint()
        ..shader = ui.Gradient.radial(c, r0, [
          AppColors.goldBright.withValues(alpha: 0.35),
          AppColors.goldBright.withValues(alpha: 0),
        ]),
    );
    canvas.drawCircle(
      c,
      r0 * 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7 * unit
        ..color = AppColors.goldBright.withValues(alpha: 0.45),
    );
    canvas.drawPath(
        Khatam.star(c, r0 * 0.42), Paint()..color = const Color(0xF2F4D682));
    canvas.drawPath(Khatam.star(c, r0 * 0.2, rotation: math.pi / 8),
        Paint()..color = const Color(0xFF0B1020));
  }

  @override
  bool shouldRepaint(_SunBase old) => false;
}

/// Which of the lit verses' two layers a [_SunLight] paints.
enum _SunPart { all, glow, core }

/// The lit verses: a burning segment of each run's ray, a spark at its
/// outer end. With [ignite], the runs burn in one after another in the
/// order they were first met. [part] paints the soft glow or the bright
/// cores alone, so the glow can breathe as a layer; [_SunPart.all] is
/// both, for a still picture.
class _SunLight extends CustomPainter {
  final VerseLight light;
  final Animation<double>? ignite;
  final _SunPart part;

  _SunLight({required this.light, this.ignite, this.part = _SunPart.all})
      : super(repaint: ignite);

  @override
  void paint(Canvas canvas, Size size) {
    if (light.isEmpty) return;
    final c = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * 0.95;
    final r0 = radius * QuranSun.hub;
    final span = radius - r0;
    final unit = size.shortestSide / 1080;
    final p = ignite?.value ?? 1;
    final count = light.order.length;

    // Each run as far as it has burned in: its two ends, and how lit.
    final runs = <(Offset, Offset, double)>[];
    for (var i = 0; i < count; i++) {
      // Each run's turn to burn in, through the last three fifths of
      // the entrance; the sun itself surfaces in the first two.
      final start = 0.38 + 0.5 * (count == 1 ? 0 : i / (count - 1));
      final k = ((p - start) / 0.14).clamp(0.0, 1.0);
      if (k <= 0) continue;
      final (s, from, to) = light.order[i];
      final n = surahIndex[s - 1].ayahCount;
      final a = QuranSun.angleOf(s);
      final len = span * QuranSun.lengthOf(s);
      final dir = Offset(math.cos(a), math.sin(a));
      final r1 = r0 + len * (from - 1) / n;
      final r2 = r1 + (r0 + len * to / n - r1) * Curves.easeOutCubic.transform(k);
      runs.add((c + dir * r1, c + dir * r2, k));
    }

    if (part != _SunPart.core) {
      final halo = Paint()
        ..strokeWidth = 17 * unit
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8.5 * unit);
      final sparkGlow = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * unit);
      for (final (p1, p2, k) in runs) {
        halo.color = AppColors.goldBright.withValues(alpha: 0.95 * k);
        canvas.drawLine(p1, p2, halo);
        sparkGlow.color = AppColors.goldBright.withValues(alpha: 0.9 * k);
        canvas.drawCircle(p2, 9 * unit, sparkGlow);
      }
    }
    if (part != _SunPart.glow) {
      final core = Paint()
        ..strokeWidth = 6.6 * unit
        ..strokeCap = StrokeCap.round;
      final spark = Paint();
      for (final (p1, p2, k) in runs) {
        core.color = const Color(0xFFFFF0C2).withValues(alpha: k);
        canvas.drawLine(p1, p2, core);
        spark.color = const Color(0xFFFFFAEB).withValues(alpha: k);
        canvas.drawCircle(p2, 3.6 * unit, spark);
      }
    }
  }

  @override
  bool shouldRepaint(_SunLight old) =>
      !identical(old.light, light) ||
      old.ignite != ignite ||
      old.part != part;
}
