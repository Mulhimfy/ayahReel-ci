import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Something on the reel that a finger moves and sizes: the surah's name,
/// the verse.
///
/// Pinching a line of type with two fingers that both have to land on it
/// is hard on a phone; this gives it handles. While it is touched — and
/// for a moment after — crop marks frame it, one at each corner, the way
/// a picture is framed for cutting. A finger on a corner sizes it on its
/// own: away from the middle grows it, towards the middle shrinks it.
/// Anywhere else one finger moves it and two pinch it, as before. A
/// double tap is [onDoubleTap].
///
/// [pad] is room around [child] for the fingers and the marks. It is
/// laid out as part of this box, so a caller that places the box by its
/// size (as the exporter places the verse card) passes none, and the
/// marks are then drawn on the child's own edge.
class ResizableBox extends StatefulWidget {
  final Widget child;

  /// The size it is at now, against its own: what a corner or a pinch
  /// is measured from.
  final double scale;

  /// A new size, asked for by a corner or a pinch. The caller clamps it.
  /// Null when it can be moved but not sized.
  final ValueChanged<double>? onResize;

  /// One finger moving it, or two, by this much.
  final ValueChanged<Offset>? onMove;

  /// The fingers lifted, after a move or a resize.
  final VoidCallback? onEnd;
  final VoidCallback? onDoubleTap;

  final double pad;

  /// How far in from the box's edge the marks are drawn.
  final double inset;

  /// Frames it when it first appears, for a moment, so the handles are
  /// found without being looked for.
  final bool hintOnAppear;

  const ResizableBox({
    super.key,
    required this.child,
    required this.scale,
    this.onResize,
    this.onMove,
    this.onEnd,
    this.onDoubleTap,
    this.pad = 0,
    this.inset = 0,
    this.hintOnAppear = false,
  });

  /// How far from a corner a finger still takes that corner.
  static const cornerReach = 34.0;

  /// How long the marks stay after the fingers lift.
  static const linger = Duration(milliseconds: 2400);

  @override
  State<ResizableBox> createState() => _ResizableBoxState();
}

class _ResizableBoxState extends State<ResizableBox> {
  bool _marks = false;
  Timer? _hide;

  /// The size when the fingers came down, which every step is measured
  /// from: the box is rebuilt at every step, so the size of the step
  /// before would compound.
  double _from = 1;

  /// Set while a corner is held: the box's middle, and how far from it
  /// the finger started.
  Offset? _centre;
  double _startReach = 1;
  int _lastStep = 0;

  @override
  void initState() {
    super.initState();
    if (widget.hintOnAppear) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _show();
        _hideLater();
      });
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _show() {
    _hide?.cancel();
    if (!_marks) setState(() => _marks = true);
  }

  void _hideLater() {
    _hide?.cancel();
    _hide = Timer(ResizableBox.linger, () {
      if (mounted) setState(() => _marks = false);
    });
  }

  bool _onCorner(Offset local, Size size) {
    const r = ResizableBox.cornerReach;
    final nearX = local.dx <= r || local.dx >= size.width - r;
    final nearY = local.dy <= r || local.dy >= size.height - r;
    return nearX && nearY;
  }

  void _start(ScaleStartDetails d) {
    _show();
    _from = widget.scale;
    _centre = null;
    final box = context.findRenderObject();
    if (widget.onResize != null &&
        d.pointerCount == 1 &&
        box is RenderBox &&
        box.hasSize &&
        _onCorner(d.localFocalPoint, box.size)) {
      final c = box.size.center(Offset.zero);
      _centre = c;
      _startReach = math.max(12, (d.localFocalPoint - c).distance);
      _lastStep = 0;
      HapticFeedback.selectionClick();
    }
  }

  void _update(ScaleUpdateDetails d) {
    final resize = widget.onResize;
    final c = _centre;
    if (c != null && resize != null) {
      final reach = (d.localFocalPoint - c).distance;
      final next = _from * reach / _startReach;
      // A light tick every tenth of the way, so the size is felt.
      final step = (next * 10).floor();
      if (step != _lastStep && _lastStep != 0) HapticFeedback.selectionClick();
      _lastStep = step;
      resize(next);
      return;
    }
    widget.onMove?.call(d.focalPointDelta);
    if (resize != null && d.pointerCount > 1) resize(_from * d.scale);
  }

  void _end(ScaleEndDetails _) {
    _centre = null;
    _hideLater();
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        // A scale recognizer is a pan recognizer too: one pointer is a
        // move, or a corner's resize; a second one makes it a pinch.
        ScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
          ScaleGestureRecognizer.new,
          (r) {
            r
              ..gestureSettings = const DeviceGestureSettings(touchSlop: 6)
              ..onStart = _start
              ..onUpdate = _update
              ..onEnd = _end;
          },
        ),
        if (widget.onDoubleTap != null)
          DoubleTapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
            DoubleTapGestureRecognizer.new,
            (r) => r.onDoubleTap = widget.onDoubleTap,
          ),
      },
      // The marks come with the first touch, before the finger has
      // moved far enough to be a drag: a finger that lands to resize
      // sees the handles at once.
      child: Listener(
        onPointerDown: (_) => _show(),
        onPointerUp: (_) => _hideLater(),
        onPointerCancel: (_) => _hideLater(),
        child: Stack(
          children: [
            Padding(padding: EdgeInsets.all(widget.pad), child: widget.child),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _marks ? 1 : 0,
                  duration: still
                      ? Duration.zero
                      : Duration(milliseconds: _marks ? 120 : 420),
                  child: CustomPaint(
                    painter: CropMarks(
                      inset: widget.inset,
                      resizable: widget.onResize != null,
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

/// The marks [ResizableBox] frames its child with: a hairline round it,
/// and at each corner a bracket and, where it can be sized, a handle.
/// Gold over a dark edge, so they read on a bright scenery and a dark
/// one alike.
class CropMarks extends CustomPainter {
  final double inset;
  final bool resizable;

  const CropMarks({this.inset = 0, this.resizable = true});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
        inset, inset, size.width - 2 * inset, size.height - 2 * inset);
    if (r.width <= 4 || r.height <= 4) return;
    final arm = math.min(14.0, math.min(r.width, r.height) * 0.3);

    final shade = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    final gold = Paint()
      ..color = AppColors.goldBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // The cut line: dashed, all the way round.
    _dashed(canvas, r, line);

    final corners = [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ];
    for (final (p, sx, sy) in corners) {
      final path = Path()
        ..moveTo(p.dx + sx * arm, p.dy)
        ..lineTo(p.dx, p.dy)
        ..lineTo(p.dx, p.dy + sy * arm);
      canvas
        ..drawPath(path, shade)
        ..drawPath(path, gold);
      if (resizable) {
        canvas
          ..drawCircle(
              p, 4.6, Paint()..color = Colors.black.withValues(alpha: 0.5))
          ..drawCircle(p, 3.4, Paint()..color = AppColors.goldBright);
      }
    }
  }

  static void _dashed(Canvas canvas, Rect r, Paint paint) {
    const dash = 5.0, gap = 4.0;
    void run(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      for (var t = 0.0; t < total; t += dash + gap) {
        canvas.drawLine(
            a + dir * t, a + dir * math.min(total, t + dash), paint);
      }
    }

    run(r.topLeft, r.topRight);
    run(r.topRight, r.bottomRight);
    run(r.bottomRight, r.bottomLeft);
    run(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant CropMarks old) =>
      old.inset != inset || old.resizable != resizable;
}
