import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/arena_engine.dart';
import '../data/surah_index.dart';
import '../theme/app_theme.dart';
import 'arena_fx.dart';

/// A round drawn as a constellation.
///
/// Every question the player met is a star: gold and lit when it was
/// answered, a hollow ring when it was not. The stars are scattered
/// over the whole disc the way stars are — each new one placed where
/// it has the most room — and the thread of play order walks from the
/// topmost star to its nearest neighbour and on, so the round reads as
/// a figure, the way a constellation does, and not as a tangle. A
/// fainter net joins every star to its two nearest. Beside each star,
/// the first words of its verse in the mushaf's own face, set on
/// whichever side of the star has room for them, so the picture is the
/// round itself and not a number with decoration.
///
/// One painter, three sizes: the story, the result page, and the
/// thumbnail a round keeps in the history. [progress] draws it in, star
/// by star, thread by thread.
class ConstellationNode {
  /// The first words of the verse, or the surah's name.
  final String label;
  final bool correct;
  const ConstellationNode(this.label, {required this.correct});

  /// The star a question makes: its verse's opening, or its surah.
  static ConstellationNode of(ArenaQuestion q, {required bool correct}) {
    List<String> words;
    switch (q.game) {
      case ArenaGame.missingWord:
        words = q.tokens;
      case ArenaGame.orderWords:
        words = [for (final i in q.order) q.tokens[i]];
      case ArenaGame.surahFacts:
        words = [surahIndex[q.surah - 1].nameArabic];
      case ArenaGame.completeVerse:
      case ArenaGame.whichSurah:
      case ArenaGame.nextVerse:
        words = q.text.split(' ');
    }
    return ConstellationNode(words.take(3).join(' '), correct: correct);
  }

  /// The stars of a whole round, in the order it was played.
  static List<ConstellationNode> ofRound(
          List<ArenaQuestion> questions, List<ArenaAnswer> answers) =>
      [
        for (var i = 0; i < answers.length && i < questions.length; i++)
          of(questions[i], correct: answers[i].correct),
      ];
}

class Constellation extends StatelessWidget {
  final List<ConstellationNode> nodes;

  /// Fixes where the stars stand, so a round's picture is the same
  /// every time it is drawn.
  final int seed;

  /// 0..1: how much of it has been drawn.
  final double progress;

  /// Whether the verses' words are set beside the stars. Off for a
  /// thumbnail.
  final bool labels;

  const Constellation({
    super.key,
    required this.nodes,
    required this.seed,
    this.progress = 1,
    this.labels = true,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: ConstellationPainter(
            nodes: nodes,
            seed: seed,
            progress: progress,
            labels: labels,
          ),
        ),
      ),
    );
  }
}

class ConstellationPainter extends CustomPainter {
  final List<ConstellationNode> nodes;
  final int seed;
  final double progress;
  final bool labels;

  ConstellationPainter({
    required this.nodes,
    required this.seed,
    this.progress = 1,
    this.labels = true,
  });

  /// Where the stars stand, in a square of [side], indexed by the order
  /// the questions were asked in.
  ///
  /// Scattered first: every star after the first is placed at the best
  /// of two dozen seeded tries, the one farthest from every star already
  /// standing, which spreads them over the disc the way a night sky is
  /// spread — evenly, and nowhere in a row. Then threaded: a walk from
  /// the topmost star to its nearest unvisited neighbour and on, so the
  /// line of play order is the figure the eye follows.
  static List<Offset> positions(int n, int seed, double side) {
    if (n == 0) return const [];
    final c = Offset(side / 2, side / 2);
    final rnd = math.Random(seed);
    final reach = side * 0.37;
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      Offset? best;
      var bestD = -1.0;
      final tries = i == 0 ? 1 : 24;
      for (var k = 0; k < tries; k++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final r = reach * math.sqrt(rnd.nextDouble());
        final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        var d = double.infinity;
        for (final q in pts) {
          d = math.min(d, (p - q).distance);
        }
        if (d > bestD) {
          bestD = d;
          best = p;
        }
      }
      pts.add(best!);
    }
    final left = List<bool>.filled(n, true);
    var cur = 0;
    for (var i = 1; i < n; i++) {
      if (pts[i].dy < pts[cur].dy) cur = i;
    }
    final out = <Offset>[];
    while (out.length < n) {
      out.add(pts[cur]);
      left[cur] = false;
      var next = -1;
      var nd = double.infinity;
      for (var j = 0; j < n; j++) {
        if (!left[j]) continue;
        final d = (pts[j] - pts[cur]).distance;
        if (d < nd) {
          nd = d;
          next = j;
        }
      }
      if (next < 0) break;
      cur = next;
    }
    return out;
  }

  /// The net: each star to its two nearest, without doubles.
  static List<(int, int)> web(List<Offset> p) {
    final out = <(int, int)>{};
    for (var i = 0; i < p.length; i++) {
      final others = [
        for (var j = 0; j < p.length; j++)
          if (j != i) j
      ]..sort((a, b) => (p[a] - p[i]).distance.compareTo((p[b] - p[i]).distance));
      for (final j in others.take(2)) {
        out.add(i < j ? (i, j) : (j, i));
      }
    }
    return out.toList();
  }

  /// The far, faint stars behind the round — depth, not information.
  static List<Offset> specks(int seed, double side, {int count = 34}) {
    final rnd = math.Random(seed ^ 0x5eed);
    return [
      for (var i = 0; i < count; i++)
        Offset(rnd.nextDouble() * side, rnd.nextDouble() * side),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final n = nodes.length;
    if (n == 0) return;
    final p = positions(n, seed, side);
    final k = side / 1080; // everything below is drawn in story pixels
    final t = progress.clamp(0.0, 1.0);
    final big = labels && side >= 300;
    // Nothing thinner than a hair, however small the picture: the
    // thumbnail on the shelf has to show its net too.
    double px(double v, double floor) => math.max(v, floor);

    // The far stars.
    if (big) {
      final rnd = math.Random(seed);
      for (final s in specks(seed, side)) {
        final a = 0.12 + rnd.nextDouble() * 0.22;
        canvas.drawCircle(
          s,
          px(1.4 * k, 0.8) * (0.6 + rnd.nextDouble() * 0.8),
          Paint()..color = const Color(0xFFFFF6DC).withValues(alpha: a * t),
        );
      }
    }

    // The net, faint, whole stars only.
    final lit = (t * n).floor();
    for (final (a, b) in web(p)) {
      if (a >= lit || b >= lit) continue;
      canvas.drawLine(
        p[a],
        p[b],
        Paint()
          ..strokeWidth = px(1.1 * k, 0.6)
          ..color = AppColors.gold.withValues(alpha: 0.24),
      );
    }

    // The thread: the round in the order it was played, drawn out to
    // where the progress has reached.
    final reach = t * (n - 1);
    for (var i = 0; i < n - 1; i++) {
      if (i > reach) break;
      final f = (reach - i).clamp(0.0, 1.0);
      final to = Offset.lerp(p[i], p[i + 1], f)!;
      canvas.drawLine(
        p[i],
        to,
        Paint()
          ..strokeWidth = px(2.2 * k, 0.9)
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [
            AppColors.goldBright.withValues(alpha: 0.7),
            AppColors.gold.withValues(alpha: 0.42),
          ]).createShader(Rect.fromPoints(p[i], p[i + 1])),
      );
    }

    // The stars, each a little its own size.
    final sizes = math.Random(seed ^ 0x57a5);
    final scale = [for (var i = 0; i < n; i++) 0.88 + sizes.nextDouble() * 0.24];
    final pops = <double>[];
    for (var i = 0; i < n; i++) {
      final pop = ((t * n) - i).clamp(0.0, 1.0);
      pops.add(pop);
      if (pop <= 0) continue;
      final s = Curves.easeOutBack.transform(pop);
      final node = nodes[i];
      final r = px(9.0 * k, 2.4) * scale[i] * s;
      if (node.correct) {
        canvas.drawCircle(
          p[i],
          r * 2.8,
          Paint()
            ..color = AppColors.gold.withValues(alpha: 0.38 * s)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, px(11 * k, 2.5)),
        );
        canvas.drawCircle(
          p[i],
          r,
          Paint()
            ..shader = const RadialGradient(colors: [
              Color(0xFFFFFBEE),
              Color(0xFFFFF0C8),
              AppColors.goldBright,
              AppColors.gold,
            ], stops: [0, 0.35, 0.7, 1])
                .createShader(Rect.fromCircle(center: p[i], radius: r)),
        );
        canvas.drawCircle(
          p[i],
          r * 2.0,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(1.0 * k, 0.5)
            ..color = AppColors.goldBright.withValues(alpha: 0.32 * s),
        );
        // Four fine rays on the bright ones, so they twinkle in a still.
        if (big) {
          final f = r * 3.2;
          final ray = Paint()
            ..strokeWidth = px(1.2 * k, 0.6)
            ..strokeCap = StrokeCap.round
            ..shader = RadialGradient(colors: [
              const Color(0xFFFFF6DC).withValues(alpha: 0.9 * s),
              AppColors.goldBright.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: p[i], radius: f));
          canvas.drawLine(p[i] - Offset(0, f), p[i] + Offset(0, f), ray);
          canvas.drawLine(p[i] - Offset(f, 0), p[i] + Offset(f, 0), ray);
        }
      } else {
        canvas.drawCircle(
          p[i],
          r * 0.95,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = px(2.0 * k, 1.0)
            ..color = ArenaPalette.wrong.withValues(alpha: 0.85 * s),
        );
        canvas.drawCircle(
          p[i],
          r * 0.32,
          Paint()..color = ArenaPalette.wrong.withValues(alpha: 0.55 * s),
        );
      }
    }

    if (big) _labels(canvas, size, p, pops, k);
  }

  /// The verses' first words beside their stars, each on the side of
  /// its star with the most room: away from the other stars, away from
  /// the labels already set, and inside the frame.
  void _labels(
      Canvas canvas, Size size, List<Offset> p, List<double> pops, double k) {
    final gap = 20 * k;
    final margin = 26 * k;
    final frame = Offset.zero & size;
    final c = size.center(Offset.zero);
    final placed = <Rect>[];
    for (var i = 0; i < p.length; i++) {
      final pop = pops[i];
      final node = nodes[i];
      final painter = TextPainter(
        text: TextSpan(
          text: node.label,
          style: AppTheme.quran(
            size: 27 * k,
            color: node.correct
                ? AppColors.goldBright.withValues(alpha: 0.92 * pop)
                : AppColors.textSecondary.withValues(alpha: 0.72 * pop),
          ).copyWith(height: 1.2),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 200 * k);
      final w = painter.width, h = painter.height;
      final at = p[i];
      // Eight ways to hang it: the four sides, then the corners.
      final ways = <(Offset, double)>[
        (Offset(at.dx + gap, at.dy - h / 2), 0),
        (Offset(at.dx - gap - w, at.dy - h / 2), 0),
        (Offset(at.dx - w / 2, at.dy - gap - h), 0.4),
        (Offset(at.dx - w / 2, at.dy + gap), 0.4),
        (Offset(at.dx + gap * 0.7, at.dy - gap * 0.7 - h), 1.0),
        (Offset(at.dx - gap * 0.7 - w, at.dy - gap * 0.7 - h), 1.0),
        (Offset(at.dx + gap * 0.7, at.dy + gap * 0.7), 1.0),
        (Offset(at.dx - gap * 0.7 - w, at.dy + gap * 0.7), 1.0),
      ];
      Rect? best;
      var bestCost = double.infinity;
      for (final (o, bias) in ways) {
        final r = Rect.fromLTWH(o.dx, o.dy, w, h);
        var cost = bias;
        if (!frame.contains(r.topLeft) || !frame.contains(r.bottomRight)) {
          cost += 100;
        }
        final wide = r.inflate(margin);
        for (var j = 0; j < p.length; j++) {
          if (j == i) continue;
          if (wide.contains(p[j])) cost += 40;
        }
        for (final q in placed) {
          if (q.overlaps(r.inflate(margin * 0.4))) cost += 60;
        }
        // Everything else equal, hang it away from the middle, where
        // the figure is densest.
        final outward = (r.center - c).distance - (at - c).distance;
        cost -= outward / size.width * 3;
        if (cost < bestCost) {
          bestCost = cost;
          best = r;
        }
      }
      placed.add(best!);
      if (pop > 0) painter.paint(canvas, best.topLeft);
    }
  }

  @override
  bool shouldRepaint(covariant ConstellationPainter old) =>
      old.progress != progress ||
      old.seed != seed ||
      old.labels != labels ||
      old.nodes != nodes;
}

/// A round's constellation drawing itself in, the way the result page
/// shows it: threads first, stars one by one.
class ConstellationReveal extends StatefulWidget {
  final List<ConstellationNode> nodes;
  final int seed;
  final Duration duration;
  final Duration delay;

  const ConstellationReveal({
    super.key,
    required this.nodes,
    required this.seed,
    this.duration = const Duration(milliseconds: 2200),
    this.delay = const Duration(milliseconds: 300),
  });

  @override
  State<ConstellationReveal> createState() => _ConstellationRevealState();
}

class _ConstellationRevealState extends State<ConstellationReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
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
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Constellation(
        nodes: widget.nodes,
        seed: widget.seed,
        progress: Curves.easeOutCubic.transform(_c.value),
      ),
    );
  }
}
