import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'a11y.dart';
import 'illumination.dart';
import 'mesh_glass.dart';

/// What Home's Create opens onto.
enum CreateKind { reel, quiz, card }

extension on CreateKind {
  MeshPalette get palette => switch (this) {
        CreateKind.reel => MeshPalette.reel,
        CreateKind.quiz => MeshPalette.quiz,
        CreateKind.card => MeshPalette.card,
      };

  String title(L10n l) => switch (this) {
        CreateKind.reel => l.chooseReel,
        CreateKind.quiz => l.chooseQuiz,
        CreateKind.card => l.chooseCard,
      };

  String line(L10n l) => switch (this) {
        CreateKind.reel => l.chooseReelLine,
        CreateKind.quiz => l.chooseQuizLine,
        CreateKind.card => l.chooseCardLine,
      };
}

// ---------------------------------------------------------------------
// The button
// ---------------------------------------------------------------------

/// Home's one door in: a pill of glass with lights drifting under it.
///
/// It used to be a gold bar breathing a gold glow over a photograph,
/// which read as yellow more than as light. This is the app's luminous
/// inks instead (aurora, iris, moonlight and a breath of gold) moving
/// slowly under frosted glass, the photograph showing through it, a
/// glint crossing it now and then. The glow under it takes its colours
/// from the same lights, so it stands off the picture without shouting.
///
/// [onPressed] is handed where the button is on screen: what it opens
/// grows out of it.
class CreateButton extends StatefulWidget {
  final String label;
  final String? hint;
  final ValueChanged<Rect> onPressed;
  final double height;

  const CreateButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.hint,
    this.height = 56,
  });

  @override
  State<CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<CreateButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 11),
  )..repeat();

  bool _still = false;

  /// Less motion asked for: the lights hold still where they are.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _clock.value = 0.3;
    } else {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _tap() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    HapticFeedback.mediumImpact();
    widget.onPressed(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final radius = BorderRadius.circular(h / 2);
    final t = Theme.of(context).textTheme;
    return A11yTap(
      label: widget.label,
      hint: widget.hint,
      onTap: _tap,
      child: Pressable(
        onTap: _tap,
        scale: 0.955,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x6E8F7BFF),
                blurRadius: 30,
                spreadRadius: -6,
                offset: Offset(0, 12),
              ),
              BoxShadow(
                color: Color(0x4D36D39A),
                blurRadius: 22,
                spreadRadius: -8,
                offset: Offset(-8, 4),
              ),
              BoxShadow(
                color: Color(0x404FB3FF),
                blurRadius: 22,
                spreadRadius: -8,
                offset: Offset(8, 4),
              ),
            ],
          ),
          child: SizedBox(
            height: h,
            child: MeshGlass(
              palette: MeshPalette.create,
              clock: _clock,
              radius: radius,
              opacity: 0.55,
              glow: 0.78,
              blur: 14,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PlusOrb(size: h * 0.48),
                    const SizedBox(width: 11),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(
                          fontSize: 17.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Color(0x73000000), blurRadius: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small orb of glass with a plus in it — or, [turn] of the way round,
/// a cross: the same mark opens the choice and closes it.
class _PlusOrb extends StatelessWidget {
  final double size;
  final double turn;

  const _PlusOrb({required this.size, this.turn = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
      ),
      child: CustomPaint(painter: _PlusPainter(turn: turn)),
    );
  }
}

class _PlusPainter extends CustomPainter {
  /// 0: a plus. 1: turned an eighth, a cross.
  final double turn;
  const _PlusPainter({required this.turn});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.24;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(turn * math.pi / 4);
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = math.max(1.6, size.shortestSide * 0.085)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), p);
    canvas.drawLine(Offset(0, -r), Offset(0, r), p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlusPainter old) => old.turn != turn;
}

// ---------------------------------------------------------------------
// The choice
// ---------------------------------------------------------------------

/// Opens the choice of what to make — a reel, a quiz, a card — growing
/// out of [from], the Create button's place on screen. Null when it was
/// closed without a choice.
///
/// Three panes of glass rise out of the button one after another and
/// swing up into place in depth, the reel first, then the quiz, then the
/// card; a ring of sparks goes out from where they came; the page behind
/// frosts over; and the button's plus turns into the cross that closes it.
/// Once in place they float, each on its own slow swell, and lean toward
/// a finger. Closing runs it all back into the button.
Future<CreateKind?> showCreateChooser(BuildContext context,
    {required Rect from}) {
  return Navigator.of(context).push<CreateKind>(
    PageRouteBuilder<CreateKind>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 780),
      reverseTransitionDuration: const Duration(milliseconds: 440),
      pageBuilder: (context, animation, _) =>
          _Chooser(animation: animation, from: from),
      transitionsBuilder: (context, animation, secondary, child) => child,
    ),
  );
}

class _Chooser extends StatefulWidget {
  final Animation<double> animation;
  final Rect from;

  const _Chooser({required this.animation, required this.from});

  @override
  State<_Chooser> createState() => _ChooserState();
}

class _ChooserState extends State<_Chooser> with TickerProviderStateMixin {
  /// The lights under every pane, and the panes' slow swell once they
  /// are in place.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 11),
  )..repeat();

  /// The pane chosen, which brightens and swells as the rest fall back.
  CreateKind? _chosen;

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _clock.value = 0.3;
    } else {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _close() {
    if (_chosen != null) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  void _choose(CreateKind k) {
    if (_chosen != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _chosen = k);
    Navigator.of(context).pop(k);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final w = math.min(size.width - 40, 380.0);
    const tileH = 92.0, gap = 14.0, orb = 54.0;
    const block = 3 * tileH + 2 * gap;
    // The panes stand in the middle of the screen, the cross under them;
    // the title line over them.
    final top = math.max(
        pad.top + 70, (size.height - block - orb - 30) / 2 - 10);
    final left = (size.width - w) / 2;
    final orbAt = Offset(size.width / 2, top + block + 30 + orb / 2);
    // A route of its own has no Material over it, and text with none
    // falls back to the framework's warning style; a transparent one
    // hands it the theme's.
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
      animation: Listenable.merge([widget.animation, _clock]),
      builder: (context, _) {
        final v = widget.animation.value;
        final reversing = widget.animation.status == AnimationStatus.reverse;
        final ground = Curves.easeOut.transform(v.clamp(0.0, 1.0));
        final orbIn = Curves.easeOutCubic
            .transform(const Interval(0, 0.5).transform(v.clamp(0.0, 1.0)));
        return Stack(
          children: [
            // The page behind, frosted and dimmed; a tap on it closes.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                      sigmaX: 16 * ground, sigmaY: 16 * ground),
                  child: ColoredBox(
                    color: const Color(0xFF05070C)
                        .withValues(alpha: 0.58 * ground),
                  ),
                ),
              ),
            ),
            // Sparks from the button, on the way in.
            if (!_still && !reversing && v < 0.8)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SparksPainter(
                      centre: widget.from.center,
                      progress: v / 0.8,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: left,
              width: w,
              top: top - 44,
              child: IgnorePointer(
                child: Opacity(
                  opacity: Curves.easeOut.transform(
                      const Interval(0.3, 0.8).transform(v.clamp(0.0, 1.0))),
                  child: Text(
                    l.createChooserTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1,
                      color: Color(0xD9FFFFFF),
                    ),
                  ),
                ),
              ),
            ),
            for (final k in CreateKind.values)
              _placed(
                k,
                v: v,
                rect: Rect.fromLTWH(
                    left, top + k.index * (tileH + gap), w, tileH),
                l: l,
              ),
            // The cross, where the button's plus was, settling under the
            // panes.
            Positioned(
              left: ui.lerpDouble(widget.from.center.dx, orbAt.dx, orbIn)! -
                  orb / 2,
              top: ui.lerpDouble(widget.from.center.dy, orbAt.dy, orbIn)! -
                  orb / 2,
              width: orb,
              height: orb,
              child: Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: A11yTap(
                  label: MaterialLocalizations.of(context).closeButtonLabel,
                  onTap: _close,
                  child: GestureDetector(
                    onTap: _close,
                    child: _CloseOrb(clock: _clock, turn: orbIn),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      ),
    );
  }

  /// One pane at [v] of the way in: flying up out of the button, swung
  /// back in depth and turned toward the middle, and arriving with a
  /// little overshoot. Each starts a beat after the one above it.
  Widget _placed(CreateKind k,
      {required double v, required Rect rect, required L10n l}) {
    final i = k.index;
    final start = 0.06 + 0.11 * i;
    final local = ((v - start) / 0.6).clamp(0.0, 1.0);
    final chosen = _chosen == k;
    double fly, swing, fade;
    if (_still) {
      fly = 1;
      swing = 1;
      fade = v.clamp(0.0, 1.0);
    } else if (chosen) {
      // The chosen one doesn't go back into the button: it stays,
      // swelling and brightening as it fades.
      fly = 1;
      swing = 1;
      fade = v.clamp(0.0, 1.0);
    } else {
      fly = Curves.easeOutBack.transform(local);
      swing = Curves.easeOutCubic.transform(local);
      fade = Curves.easeOut.transform((local / 0.35).clamp(0.0, 1.0));
    }
    final delta = widget.from.center - rect.center;
    final settled = !_still && v >= 1 && _chosen == null;
    final turn = _clock.value * 2 * math.pi;
    final swell = settled ? math.sin(turn * 2 + i * 1.3) : 0.0;
    final sway = settled ? math.cos(turn * 2 + i * 0.9) : 0.0;
    final scale = chosen
        ? 1 + (1 - v.clamp(0.0, 1.0)) * 0.10
        : ui.lerpDouble(0.28, 1.0, fly)!;
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0011)
      ..rotateX((1 - swing) * 1.15 + swell * 0.022)
      ..rotateY((1 - swing) * (1 - i) * 0.6 + sway * 0.03);
    return Positioned.fromRect(
      rect: rect,
      child: Opacity(
        opacity: fade,
        child: Transform.translate(
          offset: delta * (1 - fly) + Offset(0, swell * 2.4),
          child: Transform(
            alignment: Alignment.center,
            transform: m,
            child: Transform.scale(
              scale: scale,
              child: _Tile(
                kind: k,
                clock: _clock,
                title: k.title(l),
                line: k.line(l),
                flash: chosen ? 1 - v.clamp(0.0, 1.0) : 0,
                onTap: () => _choose(k),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One choice: a pane of the kind's own lights, its mark in an orb of
/// glass, its name and one line on what it makes.
///
/// It leans toward the finger while pressed, as the scenery tiles do.
class _Tile extends StatefulWidget {
  final CreateKind kind;
  final Animation<double> clock;
  final String title;
  final String line;

  /// 0..1: the light that floods the pane when it is chosen.
  final double flash;
  final VoidCallback onTap;

  const _Tile({
    required this.kind,
    required this.clock,
    required this.title,
    required this.line,
    required this.flash,
    required this.onTap,
  });

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  /// Where the finger is on the pane, -1..1 each way; null when nothing
  /// is touching it.
  Offset? _lean;

  void _touch(Offset local, Size size) {
    if (size.isEmpty) return;
    setState(() => _lean = Offset(
          (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
          (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
        ));
  }

  void _release() {
    if (_lean != null) setState(() => _lean = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.kind.palette;
    const radius = BorderRadius.all(Radius.circular(26));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final lean = _lean ?? Offset.zero;
    return A11yTap(
      label: '${widget.title}. ${widget.line}',
      onTap: widget.onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          return Listener(
            onPointerDown: (e) => _touch(e.localPosition, size),
            onPointerMove: (e) => _touch(e.localPosition, size),
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: TweenAnimationBuilder<Offset>(
                tween: Tween(end: lean),
                duration: Duration(milliseconds: _lean == null ? 420 : 120),
                curve: _lean == null ? Curves.easeOutBack : Curves.easeOut,
                builder: (context, o, child) => Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateX(-o.dy * 0.12)
                    ..rotateY(o.dx * 0.16),
                  child: child,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color: palette.lights.first.withValues(alpha: 0.34),
                        blurRadius: 30,
                        spreadRadius: -8,
                        offset: const Offset(0, 14),
                      ),
                      BoxShadow(
                        color: palette.lights[1].withValues(alpha: 0.22),
                        blurRadius: 24,
                        spreadRadius: -10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: MeshGlass(
                    palette: palette,
                    clock: widget.clock,
                    radius: radius,
                    opacity: 0.86,
                    glow: 0.7,
                    child: Stack(
                      // The pane is the tile's full height; what is on it
                      // stands in the middle of it, not at its top.
                      alignment: AlignmentDirectional.centerStart,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              _GlyphOrb(kind: widget.kind, size: 54),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        height: 1.15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                        color: Colors.white,
                                        shadows: [
                                          Shadow(
                                              color: Color(0x66000000),
                                              blurRadius: 10),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.line,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.3,
                                        color: Colors.white
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CustomPaint(
                                  painter: _ChevronPainter(rtl: rtl),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.flash > 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: Colors.white
                                    .withValues(alpha: 0.28 * widget.flash),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The kind's mark, drawn rather than borrowed from an icon set, in an
/// orb of glass lit by the kind's first light.
class _GlyphOrb extends StatelessWidget {
  final CreateKind kind;
  final double size;

  const _GlyphOrb({required this.kind, required this.size});

  @override
  Widget build(BuildContext context) {
    final glow = kind.palette.lights.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.45),
          radius: 0.95,
          colors: [
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.07),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(color: glow.withValues(alpha: 0.45), blurRadius: 18),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.24),
        child: CustomPaint(painter: _GlyphPainter(kind)),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final CreateKind kind;
  const _GlyphPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, s * 0.075)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = Colors.white;
    switch (kind) {
      case CreateKind.reel:
        // An upright frame with a play mark in it, and the edge of
        // another standing behind.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.22, s * 0.06, s * 0.84, s * 0.94),
            Radius.circular(s * 0.14),
          ),
          line,
        );
        canvas.drawLine(Offset(s * 0.10, s * 0.20), Offset(s * 0.10, s * 0.80),
            line);
        canvas.drawPath(
          Path()
            ..moveTo(s * 0.44, s * 0.34)
            ..lineTo(s * 0.68, s * 0.50)
            ..lineTo(s * 0.44, s * 0.66)
            ..close(),
          fill,
        );
      case CreateKind.quiz:
        // The eight-pointed star, and a question in it.
        canvas.drawPath(
            Khatam.star(Offset(s / 2, s / 2), s * 0.50), line);
        final q = TextPainter(
          text: TextSpan(
            text: '?',
            style: TextStyle(
              color: Colors.white,
              fontSize: s * 0.46,
              height: 1.0,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        q.paint(canvas,
            Offset((s - q.width) / 2, (s - q.height) / 2 + s * 0.01));
        q.dispose();
      case CreateKind.card:
        // A card with two lines of writing, and a crescent over them.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.12, s * 0.04, s * 0.88, s * 0.96),
            Radius.circular(s * 0.12),
          ),
          line,
        );
        final moon = Path.combine(
          PathOperation.difference,
          Path()
            ..addOval(Rect.fromCircle(
                center: Offset(s * 0.50, s * 0.34), radius: s * 0.15)),
          Path()
            ..addOval(Rect.fromCircle(
                center: Offset(s * 0.57, s * 0.29), radius: s * 0.13)),
        );
        canvas.drawPath(moon, fill);
        canvas.drawLine(
            Offset(s * 0.30, s * 0.63), Offset(s * 0.70, s * 0.63), line);
        canvas.drawLine(
            Offset(s * 0.36, s * 0.78), Offset(s * 0.64, s * 0.78), line);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.kind != kind;
}

class _ChevronPainter extends CustomPainter {
  final bool rtl;
  const _ChevronPainter({required this.rtl});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final x0 = rtl ? s * 0.64 : s * 0.36;
    final x1 = rtl ? s * 0.34 : s * 0.66;
    canvas.drawPath(
      Path()
        ..moveTo(x0, s * 0.18)
        ..lineTo(x1, s * 0.50)
        ..lineTo(x0, s * 0.82),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.rtl != rtl;
}

/// The button's plus, turned into the cross that closes the choice.
class _CloseOrb extends StatelessWidget {
  final Animation<double> clock;
  final double turn;

  const _CloseOrb({required this.clock, required this.turn});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x668F7BFF),
            blurRadius: 24,
            spreadRadius: -4,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: MeshGlass(
        palette: MeshPalette.create,
        clock: clock,
        radius: const BorderRadius.all(Radius.circular(27)),
        opacity: 0.8,
        glow: 0.7,
        child: Center(child: _PlusOrb(size: 30, turn: turn)),
      ),
    );
  }
}

/// A ring of sparks going out from the button as the panes leave it,
/// in the panes' own colours, fading as they go.
class _SparksPainter extends CustomPainter {
  final Offset centre;

  /// 0..1 of the way out.
  final double progress;

  const _SparksPainter({required this.centre, required this.progress});

  static final _colours = [
    ...MeshPalette.reel.lights,
    ...MeshPalette.quiz.lights,
    ...MeshPalette.card.lights,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0 || p >= 1) return;
    final out = Curves.easeOutCubic.transform(p);
    final alpha = (1 - p) * (p < 0.12 ? p / 0.12 : 1);
    const n = 26;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n + (i.isEven ? 0.08 : -0.05);
      final reach = 34 + (150 + (i % 5) * 18) * out;
      final at = centre + Offset(math.cos(a), math.sin(a)) * reach;
      final r = 0.7 + 2.4 * (1 - p) * (i % 3 == 0 ? 1.3 : 1);
      final c = _colours[i % _colours.length];
      canvas.drawCircle(
        at,
        r * 2.6,
        Paint()..color = c.withValues(alpha: 0.18 * alpha),
      );
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = Color.lerp(c, Colors.white, 0.45)!
              .withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparksPainter old) =>
      old.progress != progress || old.centre != centre;
}
