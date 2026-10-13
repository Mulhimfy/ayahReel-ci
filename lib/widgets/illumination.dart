import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';

/// The app's ornamental vocabulary, drawn rather than assembled.
///
/// Every shape here comes out of the same tradition the app is about:
/// the khatam — the eight-pointed seal built from two squares laid
/// across each other — the hairline rule that fades into the margin,
/// and the cartouche that carries a name on a manuscript page. None of
/// it is a rounded rectangle with a border, because a rounded
/// rectangle with a border says nothing.
///
/// It is all path geometry and no assets, which also keeps every one
/// of these shapes shippable in a Shorebird patch.
abstract final class Khatam {
  /// The seal itself: two squares of circumradius [r], one square to
  /// the frame and one turned through 45°, centred on [c].
  ///
  /// This is the construction, not an approximation of it — which is
  /// why the octagon falls out of the middle on its own and the eight
  /// points come out at the right width without a magic ratio.
  static Path seal(Offset c, double r, {double rotation = 0}) {
    final path = Path();
    for (final turn in const [0.0, math.pi / 4]) {
      for (var i = 0; i < 4; i++) {
        final a = rotation + turn + i * math.pi / 2 + math.pi / 4;
        final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
    }
    return path;
  }

  /// The seal as one filled outline — an eight-pointed star polygon,
  /// for the places that want a solid glyph rather than an interlace.
  /// The waist ratio is the true one: where the two squares cross.
  static Path star(Offset c, double r, {double rotation = 0}) {
    const waist = 0.7654; // cos(45°) / cos(22.5°)
    final path = Path();
    for (var i = 0; i < 16; i++) {
      final a = rotation + i * math.pi / 8 - math.pi / 2;
      final rr = i.isEven ? r : r * waist;
      final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  /// A field of seals on a square grid, with a small turned square in
  /// each gap — the tiling as it is cut into a screen, running past
  /// every edge so it never reads as a motif that has been placed.
  ///
  /// [bleed] extends the field beyond [size] on every side, so the
  /// pattern can be scrolled under the screen without its edge
  /// arriving.
  static Path lattice(Size size, double cell, {double bleed = 0}) {
    final path = Path();
    final r = cell * 0.5;
    final cols = ((size.width + bleed * 2) / cell).ceil() + 1;
    final rows = ((size.height + bleed * 2) / cell).ceil() + 1;
    for (var j = 0; j <= rows; j++) {
      for (var i = 0; i <= cols; i++) {
        final c = Offset(-bleed + i * cell, -bleed + j * cell);
        path.addPath(seal(c, r), Offset.zero);
        // The interstice: a small turned square sitting where four
        // seals meet, which is what stops the gaps reading as holes.
        path.addPath(
          seal(c + Offset(cell / 2, cell / 2), cell * 0.17),
          Offset.zero,
        );
      }
    }
    return path;
  }

  /// The manuscript cartouche: a long panel that comes to a soft point
  /// at both ends. Used wherever a small piece of text wants to look
  /// awarded rather than boxed.
  static Path cartouche(Rect r) {
    final nose = math.min(r.height * 0.62, r.width * 0.28);
    final my = r.center.dy;
    return Path()
      ..moveTo(r.left, my)
      ..quadraticBezierTo(r.left + nose * 0.30, r.top + r.height * 0.10,
          r.left + nose, r.top)
      ..lineTo(r.right - nose, r.top)
      ..quadraticBezierTo(r.right - nose * 0.30, r.top + r.height * 0.10,
          r.right, my)
      ..quadraticBezierTo(r.right - nose * 0.30, r.bottom - r.height * 0.10,
          r.right - nose, r.bottom)
      ..lineTo(r.left + nose, r.bottom)
      ..quadraticBezierTo(r.left + nose * 0.30, r.bottom - r.height * 0.10,
          r.left, my)
      ..close();
  }
}

/// A small drawn seal, for the places a bullet or an icon would
/// otherwise go.
class SealGlyph extends StatelessWidget {
  final double size;
  final Color color;
  final bool filled;
  const SealGlyph({
    super.key,
    this.size = 12,
    this.color = AppColors.gold,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SealPainter(color, filled)),
      );
}

class _SealPainter extends CustomPainter {
  final Color color;
  final bool filled;
  const _SealPainter(this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Khatam.star(size.center(Offset.zero), size.shortestSide / 2);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _SealPainter old) =>
      old.color != color || old.filled != filled;
}

/// Title, then a hairline that runs to the margin and dies there under
/// a single seal. The section headings of the app, and the reason the
/// page reads as a page instead of a stack of cards.
class SectionRule extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// In place of the title's text: a heading that is also a switch,
  /// say. [title] is still what the heading is called.
  final Widget? titleWidget;

  const SectionRule({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.titleWidget,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // A heading to a screen reader as well as to the eye, so the
    // sections of a page can be jumped between: the title and its
    // line under it as one heading, in its place on the page, with
    // the action on the rule as a button of its own after it.
    return Semantics(
      container: true,
      header: true,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // A switch for a title has two names to fit: it gets the
            // larger share of the room, the rule the rest.
            Flexible(
              flex: titleWidget == null ? 1 : 3,
              child: titleWidget ??
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(letterSpacing: 0.1),
                  ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 0.9,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [
                      AppColors.gold.withValues(alpha: 0.42),
                      AppColors.gold.withValues(alpha: 0.03),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const SealGlyph(size: 7, color: Color(0x99D4A947)),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(fontSize: 12.5),
          ),
        ],
      ],
      ),
    );
  }
}

/// A hairline that fades out towards one end. The rule that flanks an
/// ornament, on its own, for the places that supply their own centre
/// piece.
///
/// [towardsEnd] is in reading order, not screen order, so a divider
/// built from a pair of these stays symmetrical when the app flips to
/// Arabic.
class OrnamentHairline extends StatelessWidget {
  final bool towardsEnd;
  final Color color;
  const OrnamentHairline({
    super.key,
    required this.towardsEnd,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: 0.8,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: towardsEnd
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            end: towardsEnd
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            colors: [
              color.withValues(alpha: 0.55),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      );
}

/// Text filled with beaten gold rather than painted one flat colour.
///
/// The gradient is angled across the line, so the top of a letter is
/// nearer the light than its foot — the same trick a gilder uses, and
/// the reason gold leaf reads as metal and a gold hex value does not.
class GildedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  const GildedText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFF2CE),
          Color(0xFFEEC96B),
          Color(0xFFC9973B),
          Color(0xFFF0D492),
        ],
      ).createShader(rect),
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}

/// Draws the illuminated border of a panel: a double rule, hairline
/// outside and heavier inside, with a seal set into each corner when
/// [sealSize] is more than nothing.
///
/// [progress] 0..1 fades the whole ornament in — the panels use it to
/// let the gold arrive a beat after the panel itself.
class IlluminatedBorder extends StatelessWidget {
  final BorderRadius radius;
  final double progress;
  final double sealSize;
  final Color color;

  const IlluminatedBorder({
    super.key,
    required this.radius,
    this.progress = 1,
    this.sealSize = 9,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _BorderPainter(radius, progress, sealSize, color),
          size: Size.infinite,
        ),
      );
}

class _BorderPainter extends CustomPainter {
  final BorderRadius radius;
  final double progress;
  final double sealSize;
  final Color color;
  const _BorderPainter(this.radius, this.progress, this.sealSize, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01) return;
    final rect = Offset.zero & size;

    // Outer hairline, right on the edge.
    canvas.drawRRect(
      radius.toRRect(rect.deflate(0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = color.withValues(alpha: 0.34 * progress),
    );
    // Inner rule, set in by a hair — the doubling is the whole effect.
    final innerR = BorderRadius.all(
      Radius.circular(math.max(0, radius.topLeft.x - 5)),
    );
    canvas.drawRRect(
      innerR.toRRect(rect.deflate(5.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = color.withValues(alpha: 0.15 * progress),
    );

    if (sealSize <= 0) return;
    // A seal in each corner, sitting on the inner rule.
    final inset = radius.topLeft.x * 0.62 + 3;
    for (final c in [
      Offset(inset, inset),
      Offset(size.width - inset, inset),
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
    ]) {
      canvas.drawPath(
        Khatam.star(c, sealSize / 2),
        Paint()..color = color.withValues(alpha: 0.5 * progress),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BorderPainter old) =>
      old.progress != progress ||
      old.radius != radius ||
      old.sealSize != sealSize ||
      old.color != color;
}

/// Walks a soft band of light across whatever it wraps, on a long
/// loop with a long pause — the highlight travelling over gilding as
/// the page is tilted.
///
/// It masks its child rather than painting over it, so it lights the
/// letterforms and leaves the space between them dark.
class Sheen extends StatefulWidget {
  final Widget child;
  final Duration period;
  final double strength;

  /// Where in the loop this instance starts, 0..1 — so two sheens on
  /// one screen do not sweep in lockstep.
  final double phase;

  const Sheen({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 5200),
    this.strength = 0.5,
    this.phase = 0,
  });

  @override
  State<Sheen> createState() => _SheenState();
}

class _SheenState extends State<Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)
        ..value = widget.phase
        ..repeat();

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    still ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return widget.child;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Most of the loop is the rest between passes: the band
          // crosses in the first third and the rest is quiet.
          final t = _c.value;
          if (t > 0.42) return child!;
          final travel = Curves.easeInOutSine.transform(t / 0.42);
          final head = -0.45 + travel * 1.9;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: widget.strength),
                Colors.transparent,
              ],
              stops: [
                (head - 0.16).clamp(0.0, 1.0),
                head.clamp(0.0, 1.0),
                (head + 0.16).clamp(0.0, 1.0),
              ],
            ).createShader(rect),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// A pane of dark glass: the panel body every card on Home is built
/// on. Blurs what is behind it, so the sky shows through as colour
/// without ever showing through as detail.
class GlassPane extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final double blur;
  final Color tint;

  const GlassPane({
    super.key,
    required this.child,
    required this.radius,
    this.blur = 14,
    this.tint = const Color(0x991A2130),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(color: tint, borderRadius: radius),
          child: child,
        ),
      ),
    );
  }
}

/// Gives a card the weight of a thing you can push.
///
/// A tap presses it a percent or two into the page and lets it come
/// back on a curve that overshoots very slightly, so the surface reads
/// as having some give. Ink ripples are deliberately not used on these
/// panels: a rectangle of grey spreading across gilding looks like
/// exactly what it is.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// How far in the press goes. Big panels want less than small ones —
  /// the same percentage across a wide card reads as a lurch.
  final double scale;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.982,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v || !mounted) return;
    // A press is cancelled mid-build when the tap is taken away under
    // a finger (onTap turning null as the parent rebuilds): the
    // recognizer is disposed inside that build, and a setState there
    // throws. The release waits for the frame to finish.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _set(v));
      return;
    }
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        // Down fast, back slow: a press should feel answered
        // immediately and released unhurriedly.
        duration: Duration(milliseconds: _down ? 90 : 320),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// A regular octagon — the shape that falls out of the middle of the
/// khatam when its two squares cross.
///
/// It is a real [OutlinedBorder], so Material clips its ink to it and
/// casts its shadow from it, and a button cut this way behaves like
/// any other button while looking like nothing else in the app.
class OctagonBorder extends OutlinedBorder {
  const OctagonBorder({super.side = BorderSide.none});

  /// The corner cut of a regular octagon inscribed in a square:
  /// (s − s/(1+√2)) / 2.
  static const _cut = 0.29289321881;

  Path _path(Rect rect) {
    final c = rect.shortestSide * _cut;
    return Path()
      ..moveTo(rect.left + c, rect.top)
      ..lineTo(rect.right - c, rect.top)
      ..lineTo(rect.right, rect.top + c)
      ..lineTo(rect.right, rect.bottom - c)
      ..lineTo(rect.right - c, rect.bottom)
      ..lineTo(rect.left + c, rect.bottom)
      ..lineTo(rect.left, rect.bottom - c)
      ..lineTo(rect.left, rect.top + c)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      _path(rect.deflate(side.strokeOffset / 2)),
      side.toPaint(),
    );
  }

  @override
  OctagonBorder copyWith({BorderSide? side}) =>
      OctagonBorder(side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => OctagonBorder(side: side.scale(t));

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  bool operator ==(Object other) =>
      other is OctagonBorder && other.side == side;

  @override
  int get hashCode => side.hashCode;
}
