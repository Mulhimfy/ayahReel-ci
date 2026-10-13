import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'direct_share_button.dart' show instagramMesh;

/// Where in Instagram a finished reel goes.
enum InstagramTarget { story, reel }

/// "Story or reel?" — asked in a small panel that rises out of the
/// button that asked it, and answered with one tap. Null when the panel
/// is dismissed, which is a tap anywhere else.
///
/// [anchor] is the context of the button; the panel stands just above
/// it, its little caret pointing down at it, so the question visibly
/// belongs to the thing that was pressed.
Future<InstagramTarget?> showInstagramChoice(BuildContext anchor) {
  final navigator = Navigator.of(anchor);
  final overlay = navigator.overlay?.context.findRenderObject();
  final box = anchor.findRenderObject();
  Rect? at;
  if (overlay is RenderBox && box is RenderBox && box.hasSize) {
    at = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }
  HapticFeedback.selectionClick();
  return navigator.push(_ChoiceRoute(
    anchor: at,
    barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
  ));
}

class _ChoiceRoute extends PopupRoute<InstagramTarget> {
  _ChoiceRoute({required this.anchor, required this.barrierLabel});

  final Rect? anchor;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.32);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 360);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 170);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return _ChoicePanel(anchor: anchor, animation: animation);
  }
}

class _ChoicePanel extends StatelessWidget {
  final Rect? anchor;
  final Animation<double> animation;
  const _ChoicePanel({required this.anchor, required this.animation});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final pop = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    final panel = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l.sendToInstagram,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xF2161B22),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: instagramMesh[1].withValues(alpha: 0.18),
                  blurRadius: 28,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Option(
                    target: InstagramTarget.story,
                    label: l.igStory,
                    semantics: l.a11yIgStory,
                    animation: animation,
                    from: 0.0,
                  ),
                  const SizedBox(width: 7),
                  _Option(
                    target: InstagramTarget.reel,
                    label: l.igReel,
                    semantics: l.a11yIgReel,
                    animation: animation,
                    from: 0.12,
                  ),
                ],
              ),
            ),
          ),
          // The caret: the panel points at the button that asked.
          if (anchor != null)
            const CustomPaint(size: Size(18, 8), painter: _CaretPainter()),
        ],
      ),
    );

    return CustomSingleChildLayout(
      delegate: _Placement(anchor),
      child: AnimatedBuilder(
        animation: pop,
        builder: (context, child) {
          final t = reduce ? animation.value : pop.value;
          // Rises out of the button: grows from the caret, and tips up
          // from a slight lean back — paper lifting off the table.
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..rotateX(reduce ? 0 : (1 - t.clamp(0.0, 1.0)) * 0.55)
            ..scaleByDouble(
                0.86 + 0.14 * t, 0.86 + 0.14 * t, 1, 1);
          return Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: m,
              child: child,
            ),
          );
        },
        child: panel,
      ),
    );
  }
}

/// Places the panel above the button, centred on it and kept on screen;
/// below it when the button sits too near the top; at the bottom centre
/// when there is no button to point at.
class _Placement extends SingleChildLayoutDelegate {
  final Rect? anchor;
  const _Placement(this.anchor);

  static const _margin = 12.0;
  static const _gap = 6.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(
          const EdgeInsets.symmetric(horizontal: _margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = anchor;
    if (a == null) {
      return Offset((size.width - child.width) / 2,
          size.height - child.height - 48);
    }
    final double maxX = math.max(_margin, size.width - child.width - _margin);
    final double x =
        (a.center.dx - child.width / 2).clamp(_margin, maxX).toDouble();
    var y = a.top - child.height - _gap;
    if (y < _margin + 24) y = a.bottom + _gap;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_Placement old) => old.anchor != anchor;
}

class _Option extends StatefulWidget {
  final InstagramTarget target;
  final String label;
  final String semantics;
  final Animation<double> animation;

  /// Where in the entrance this option starts, so the two arrive one
  /// after the other rather than as a block.
  final double from;

  const _Option({
    required this.target,
    required this.label,
    required this.semantics,
    required this.animation,
    required this.from,
  });

  @override
  State<_Option> createState() => _OptionState();
}

class _OptionState extends State<_Option> {
  bool _down = false;

  void _pick() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(widget.target);
  }

  @override
  Widget build(BuildContext context) {
    final rise = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(widget.from, math.min(1.0, widget.from + 0.78),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: rise,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, 10 * (1 - rise.value)),
        child: Opacity(opacity: rise.value.clamp(0.0, 1.0), child: child),
      ),
      child: Semantics(
        button: true,
        label: widget.semantics,
        excludeSemantics: true,
        onTap: _pick,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: _pick,
          child: AnimatedScale(
            scale: _down ? 0.95 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: Container(
              height: 54,
              constraints: const BoxConstraints(minWidth: 124),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: _down ? 0.10 : 0.06),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 26,
                    child: CustomPaint(
                      painter: widget.target == InstagramTarget.story
                          ? const _StoryGlyph()
                          : const _ReelGlyph(),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Instagram's own sweep, run round a circle — the colours of its icon
/// in the order its icon runs them.
Shader _sweep(Rect r) => SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: 3 * math.pi / 2,
      colors: [...instagramMesh, instagramMesh.first],
      transform: const GradientRotation(math.pi / 4),
    ).createShader(r);

/// The story ring: the gradient circle Instagram draws round a story,
/// with the small "add" inside it.
class _StoryGlyph extends CustomPainter {
  const _StoryGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1.6;
    final ring = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..shader = _sweep(ring),
    );
    final plus = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final arm = r * 0.42;
    canvas.drawLine(c - Offset(arm, 0), c + Offset(arm, 0), plus);
    canvas.drawLine(c - Offset(0, arm), c + Offset(0, arm), plus);
  }

  @override
  bool shouldRepaint(_StoryGlyph old) => false;
}

/// The reel mark: a rounded frame with the clapper's band across its
/// top, and the play triangle under it.
class _ReelGlyph extends CustomPainter {
  const _ReelGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final box = Rect.fromCenter(
        center: size.center(Offset.zero), width: s - 3, height: s - 3);
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..shader = _sweep(box);
    canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(s * 0.26)), frame);
    final bandY = box.top + box.height * 0.3;
    canvas.drawLine(Offset(box.left, bandY), Offset(box.right, bandY), frame);
    final slash = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..shader = _sweep(box);
    for (final f in const [0.36, 0.66]) {
      final x = box.left + box.width * f;
      canvas.drawLine(Offset(x - box.width * 0.1, box.top + 1.4),
          Offset(x + box.width * 0.04, bandY), slash);
    }
    final mid = Offset(box.center.dx + s * 0.03, box.top + box.height * 0.64);
    final h = box.height * 0.2;
    final play = Path()
      ..moveTo(mid.dx - h * 0.75, mid.dy - h)
      ..lineTo(mid.dx + h, mid.dy)
      ..lineTo(mid.dx - h * 0.75, mid.dy + h)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ReelGlyph old) => false;
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xF2161B22));
  }

  @override
  bool shouldRepaint(_CaretPainter old) => false;
}

/// The camera outline Instagram's door is known by, drawn in white so
/// it sits on the button's own gradient. Painted rather than taken from
/// the icon font, which has no such glyph.
class InstagramGlyph extends StatelessWidget {
  final double size;
  const InstagramGlyph({super.key, this.size = 15});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _CameraPainter()),
      );
}

class _CameraPainter extends CustomPainter {
  const _CameraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..color = Colors.white;
    final box = Rect.fromCenter(
        center: size.center(Offset.zero), width: s * 0.86, height: s * 0.86);
    canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(s * 0.26)), line);
    canvas.drawCircle(box.center, s * 0.2, line);
    canvas.drawCircle(
      Offset(box.right - s * 0.2, box.top + s * 0.2),
      s * 0.055,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CameraPainter old) => false;
}
