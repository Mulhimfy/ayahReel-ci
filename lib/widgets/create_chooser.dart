import 'dart:math' as math;

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
/// It was a gold bar breathing a gold glow, which read as yellow more
/// than as light, then a pill of the app's blue-violet inks. It is gold
/// again, but as light: the house golds moving slowly under frosted
/// glass, the photograph showing through it, a glint crossing it now and
/// then, the glow under it warm and low (see [MeshPalette.create]).
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
            // A warm glow under it, in its own golds, low enough to lift
            // it off the photograph without a halo.
            boxShadow: const [
              BoxShadow(
                color: Color(0x5CD4A947),
                blurRadius: 28,
                spreadRadius: -6,
                offset: Offset(0, 12),
              ),
              BoxShadow(
                color: Color(0x33B07A2A),
                blurRadius: 20,
                spreadRadius: -8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SizedBox(
            height: h,
            child: MeshGlass(
              palette: MeshPalette.create,
              clock: _clock,
              radius: radius,
              opacity: 0.6,
              glow: 0.62,
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
/// Three small pills rise out of the button one after another and stand
/// over it, the reel nearest and largest, the quiz and the card a step
/// smaller above it, each as wide as its own name: a stack that tapers,
/// not three equal bars. The page stays where it is behind them, only a
/// shade dimmer — nothing frosts or fades away — and the button itself
/// turns into the cross that closes them. A tap anywhere else closes it
/// too.
///
/// Light on purpose: a third of a second in, no blur over the screen,
/// and nothing rebuilt while it stands — only the lights under the
/// glass move, and those are painted, not built.
Future<CreateKind?> showCreateChooser(BuildContext context,
    {required Rect from}) {
  return Navigator.of(context).push<CreateKind>(
    PageRouteBuilder<CreateKind>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (context, animation, _) =>
          _Chooser(animation: animation, from: from),
      transitionsBuilder: (context, animation, secondary, child) => child,
    ),
  );
}

/// How large each pill stands: the reel, the thing most people came
/// for, the largest and nearest the thumb.
extension _PillSize on CreateKind {
  double get pillHeight => switch (this) {
        CreateKind.reel => 54,
        CreateKind.quiz => 47,
        CreateKind.card => 43,
      };

  double get fontSize => switch (this) {
        CreateKind.reel => 16.5,
        CreateKind.quiz => 15,
        CreateKind.card => 14.5,
      };
}

class _Chooser extends StatefulWidget {
  final Animation<double> animation;
  final Rect from;

  const _Chooser({required this.animation, required this.from});

  @override
  State<_Chooser> createState() => _ChooserState();
}

class _ChooserState extends State<_Chooser>
    with SingleTickerProviderStateMixin {
  /// The lights under every pill, painted on their own clock.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 11),
  )..repeat();

  /// The pill chosen, which stays lit as the rest go back.
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

  static const _gap = 9.0;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final from = widget.from;
    var block = -_gap;
    for (final k in CreateKind.values) {
      block += k.pillHeight + _gap;
    }
    // Over the button when there is room, under it when there is not
    // (the page scrolled the button up under the status bar).
    final above = from.top - 12 - block >= pad.top + 8;
    // Nearest the button first: the reel, then the quiz, then the card.
    final order = above
        ? CreateKind.values.reversed.toList()
        : CreateKind.values.toList();
    // The stack stands on the button's middle, kept on the screen.
    final lim = math.max(0.0, size.width / 2 - 120);
    final dx = (from.center.dx - size.width / 2).clamp(-lim, lim).toDouble();
    // A route of its own has no Material over it, and text with none
    // falls back to the framework's warning style; a transparent one
    // hands it the theme's.
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: l.createChooserTitle,
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            final v = widget.animation.value.clamp(0.0, 1.0);
            return Stack(
              children: [
                // The page behind, a shade dimmer and still there; a tap
                // on it closes.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: ColoredBox(
                      color:
                          const Color(0xFF05070C).withValues(alpha: 0.26 * v),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: above ? null : from.bottom + 12,
                  bottom: above ? size.height - from.top + 12 : null,
                  child: Transform.translate(
                    offset: Offset(dx, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < order.length; i++) ...[
                          if (i > 0) const SizedBox(height: _gap),
                          _placed(
                            order[i],
                            v: v,
                            // How many pills stand between this one and
                            // the button.
                            reach: above ? order.length - 1 - i : i,
                            above: above,
                            l: l,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // The button, turned into the cross that closes.
                Positioned.fromRect(
                  rect: from,
                  child: Opacity(
                    opacity: v,
                    child: A11yTap(
                      label: MaterialLocalizations.of(context)
                          .closeButtonLabel,
                      onTap: _close,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                        child: _CloseFace(
                          clock: _clock,
                          height: from.height,
                          turn: Curves.easeOutCubic.transform(v),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One pill at [v] of the way in: rising out of the button toward its
  /// place and growing to size as it comes, a beat after the one nearer
  /// the button. [reach] counts the pills between it and the button.
  Widget _placed(CreateKind k,
      {required double v,
      required int reach,
      required bool above,
      required L10n l}) {
    final chosen = _chosen == k;
    final start = 0.09 * reach;
    final t = ((v - start) / (1 - 0.18)).clamp(0.0, 1.0);
    final rise = _still || chosen ? 1.0 : Curves.easeOutBack.transform(t);
    final fade = _still || chosen ? v : Curves.easeOut.transform(t);
    final travel = (reach + 1) * 46.0 * (1 - rise);
    final scale = chosen ? 1 + 0.06 * (1 - v) : 0.7 + 0.3 * rise;
    return Opacity(
      opacity: fade.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, above ? travel : -travel),
        child: Transform.scale(
          scale: scale,
          child: _Pill(
            kind: k,
            clock: _clock,
            title: k.title(l),
            line: k.line(l),
            onTap: () => _choose(k),
          ),
        ),
      ),
    );
  }
}

/// One choice: a pill of the kind's own lights, as wide as its name, its
/// mark in an orb of glass at its start.
class _Pill extends StatelessWidget {
  final CreateKind kind;
  final Animation<double> clock;
  final String title;
  final String line;
  final VoidCallback onTap;

  const _Pill({
    required this.kind,
    required this.clock,
    required this.title,
    required this.line,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final h = kind.pillHeight;
    final radius = BorderRadius.circular(h / 2);
    final palette = kind.palette;
    return A11yTap(
      label: '$title. $line',
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.95,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: palette.lights.first.withValues(alpha: 0.30),
                blurRadius: 18,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: h,
            child: MeshGlass(
              palette: palette,
              clock: clock,
              radius: radius,
              opacity: 0.88,
              glow: 0.62,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(5, 5, h * 0.42, 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GlyphOrb(kind: kind, size: h - 10),
                    SizedBox(width: h * 0.2),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: kind.fontSize,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Color(0x66000000), blurRadius: 8),
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

/// The Create button while the choice stands: the same pill of glass,
/// and in place of its plus and its word only the cross that closes,
/// turned from the plus as the pills rise.
class _CloseFace extends StatelessWidget {
  final Animation<double> clock;
  final double height;
  final double turn;

  const _CloseFace(
      {required this.clock, required this.height, required this.turn});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return MeshGlass(
      palette: MeshPalette.create,
      clock: clock,
      radius: radius,
      opacity: 0.92,
      glow: 0.7,
      child: Center(child: _PlusOrb(size: height * 0.52, turn: turn)),
    );
  }
}
