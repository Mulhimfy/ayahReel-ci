import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The colours of a [MeshGlass]: the glass's own tint, and the lights
/// that drift under it.
///
/// Every set is drawn from the luminous inks the verse can be written
/// in (see `VerseInk`): aurora, iris, nebula, ember, rose gold. The
/// surfaces that should feel alive glow in the same light as the words
/// they lead to, rather than in a palette of their own.
@immutable
class MeshPalette {
  /// The glass itself, laid over whatever is behind it.
  final Color tint;

  /// Three or four lights, each a soft disc that wanders the pane.
  final List<Color> lights;

  const MeshPalette({required this.tint, required this.lights});

  /// Home's Create: aurora green, iris violet and moonlit blue, with a
  /// breath of the house gold.
  static const create = MeshPalette(
    tint: Color(0xFF0E1424),
    lights: [
      Color(0xFF36D39A),
      Color(0xFF8F7BFF),
      Color(0xFF4FB3FF),
      Color(0xFFE0A93A),
    ],
  );

  /// A reel: the last of the day, coral into violet, amber at its edge.
  static const reel = MeshPalette(
    tint: Color(0xFF1B0F1E),
    lights: [Color(0xFFFF6F91), Color(0xFFB880FF), Color(0xFFFFB45A)],
  );

  /// The quiz: the northern lights.
  static const quiz = MeshPalette(
    tint: Color(0xFF0A1A1D),
    lights: [Color(0xFF36D39A), Color(0xFF5CE1E6), Color(0xFF7EA6FF)],
  );

  /// A card: gold leaf with rose and lavender in it.
  static const card = MeshPalette(
    tint: Color(0xFF1A1316),
    lights: [Color(0xFFE0A93A), Color(0xFFFF8FA3), Color(0xFF9D7BFF)],
  );

  /// The invitation to share the app: rose gold and dawn.
  static const invite = MeshPalette(
    tint: Color(0xFF17121A),
    lights: [Color(0xFFFFB08A), Color(0xFFE0A93A), Color(0xFFD65CFF)],
  );
}

/// Soft lights drifting on slow loops across a rounded pane, mixed the
/// way light mixes, over the pane's tint.
///
/// [clock] runs from 0 to 1 and repeats; each light goes once round its
/// own loop per turn, so nothing ever lines up the same way twice in a
/// short look. Three or four radial gradients a frame: cheap enough for
/// a button that never stops.
class MeshPainter extends CustomPainter {
  final MeshPalette palette;
  final Animation<double> clock;

  /// How much of the tint is laid down: lower lets what is behind the
  /// glass show through.
  final double opacity;

  /// The lights' strength, 0..1.
  final double glow;
  final BorderRadius radius;

  MeshPainter({
    required this.palette,
    required this.clock,
    required this.radius,
    this.opacity = 0.6,
    this.glow = 0.8,
  }) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    canvas.drawRect(
        rect, Paint()..color = palette.tint.withValues(alpha: opacity));
    final turn = clock.value * 2 * math.pi;
    final n = palette.lights.length;
    final reach = size.longestSide * 0.62;
    for (var i = 0; i < n; i++) {
      final phase = i * 2 * math.pi / n;
      final way = i.isEven ? 1.0 : -1.0;
      final c = Offset(
        size.width * (0.5 + 0.46 * math.sin(turn * way + phase)),
        size.height * (0.5 + 0.62 * math.cos(turn + phase * 1.7)),
      );
      final r = reach * (0.85 + 0.15 * math.sin(turn * 2 + phase));
      final colour = palette.lights[i];
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(
            c,
            r,
            [
              colour.withValues(alpha: 0.9 * glow),
              colour.withValues(alpha: 0.32 * glow),
              colour.withValues(alpha: 0),
            ],
            const [0, 0.45, 1],
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MeshPainter old) =>
      old.palette != palette ||
      old.clock != clock ||
      old.opacity != opacity ||
      old.glow != glow ||
      old.radius != radius;
}

/// What makes the pane read as glass: its top edge catching the light,
/// a glint that crosses it now and then, and a rim brighter where the
/// light falls than where it doesn't.
class GlassSheenPainter extends CustomPainter {
  /// The glint crosses while this is in the first [glintShare] of its
  /// turn. Null: no glint.
  final Animation<double>? clock;
  final BorderRadius radius;

  /// The colour the rim leans to at its foot.
  final Color edge;
  final double glintShare;

  /// The rim's width.
  final double rim;

  GlassSheenPainter({
    required this.radius,
    required this.edge,
    this.clock,
    this.glintShare = 0.16,
    this.rim = 1.1,
  }) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    canvas.save();
    canvas.clipRRect(rrect);
    final top = size.height * 0.55;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, top),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, top),
          [
            Colors.white.withValues(alpha: 0.19),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );
    final v = clock?.value ?? 1.0;
    if (v < glintShare) {
      final p = v / glintShare;
      final band = size.height * 1.4 + size.width * 0.18;
      final x = -band + p * (size.width + 2 * band);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, 0),
            Offset(x + band, size.height),
            [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.24),
              Colors.white.withValues(alpha: 0),
            ],
            const [0.3, 0.5, 0.7],
          ),
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rrect.deflate(rim / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.10),
            edge.withValues(alpha: 0.6),
          ],
          const [0, 0.5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant GlassSheenPainter old) =>
      old.clock != clock ||
      old.radius != radius ||
      old.edge != edge ||
      old.glintShare != glintShare ||
      old.rim != rim;
}

/// A pane of glass with a [MeshPalette]'s lights drifting under it: the
/// app's surface for the few things that should feel alive.
///
/// With [blur] it frosts what is behind it as well. A backdrop blur
/// re-reads everything under it every frame, so it is kept to small
/// panes — a button, a tile — and left off anything the size of the
/// screen.
class MeshGlass extends StatelessWidget {
  final MeshPalette palette;
  final Animation<double> clock;
  final BorderRadius radius;
  final double opacity;
  final double glow;
  final double blur;
  final Widget? child;

  const MeshGlass({
    super.key,
    required this.palette,
    required this.clock,
    required this.radius,
    this.opacity = 0.6,
    this.glow = 0.8,
    this.blur = 0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final pane = CustomPaint(
      painter: MeshPainter(
        palette: palette,
        clock: clock,
        radius: radius,
        opacity: opacity,
        glow: glow,
      ),
      foregroundPainter: GlassSheenPainter(
        clock: clock,
        radius: radius,
        edge: palette.lights.first,
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: radius,
      child: blur > 0
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: pane,
            )
          : pane,
    );
  }
}
