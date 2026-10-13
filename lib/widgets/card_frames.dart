import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/card_style.dart';
import 'illumination.dart';

/// The borders a card can wear, drawn rather than borrowed.
///
/// Every one of them is built from the shapes the rest of the app is
/// drawn with — the hairline, the seal, the arch — and every
/// measurement is a fraction of the card's width, so a frame is the
/// same frame in a 60px thumbnail and in a 1080px export. Nothing here
/// knows what size it is being drawn at.
class CardFramePainter extends CustomPainter {
  final CardFrame frame;
  final Color colour;

  const CardFramePainter({required this.frame, required this.colour});

  /// Stroke of the main rule, as a fraction of the card's width. A
  /// hair over a thousandth: at export it is a crisp two-pixel line,
  /// and in the composer it is still visibly a line rather than a
  /// smudge.
  static const _stroke = 0.0022;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame == CardFrame.none) return;
    final w = size.width;
    final inset = frame.inset * w;
    final rect = Rect.fromLTRB(
        inset, inset, size.width - inset, size.height - inset);
    final line = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke * w
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    switch (frame) {
      case CardFrame.none:
        return;

      case CardFrame.hairline:
        canvas.drawRect(rect, line);

      case CardFrame.double_:
        canvas.drawRect(rect, line..strokeWidth = _stroke * w * 1.6);
        canvas.drawRect(
          rect.deflate(0.018 * w),
          Paint()
            ..color = colour.withValues(alpha: colour.a * 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke * w * 0.7
            ..isAntiAlias = true,
        );

      case CardFrame.corners:
        final arm = 0.09 * w;
        final path = Path();
        for (final c in [
          (rect.topLeft, 1.0, 1.0),
          (rect.topRight, -1.0, 1.0),
          (rect.bottomRight, -1.0, -1.0),
          (rect.bottomLeft, 1.0, -1.0),
        ]) {
          final (p, sx, sy) = c;
          path
            ..moveTo(p.dx + sx * arm, p.dy)
            ..lineTo(p.dx, p.dy)
            ..lineTo(p.dx, p.dy + sy * arm);
        }
        canvas.drawPath(path, line..strokeCap = StrokeCap.square);

      case CardFrame.khatam:
        // Four rules that stop short of the corners, and a seal
        // standing in each gap — so the two read as one piece of
        // drawing rather than as a star dropped on a box. The gap is
        // cut by ending the lines, never by a blend mode: a `clear`
        // here would punch through the photograph as well.
        final r = 0.021 * w;
        final gap = r * 1.5;
        for (final seg in [
          (Offset(rect.left + gap, rect.top), Offset(rect.right - gap, rect.top)),
          (Offset(rect.left + gap, rect.bottom),
              Offset(rect.right - gap, rect.bottom)),
          (Offset(rect.left, rect.top + gap),
              Offset(rect.left, rect.bottom - gap)),
          (Offset(rect.right, rect.top + gap),
              Offset(rect.right, rect.bottom - gap)),
        ]) {
          canvas.drawLine(seg.$1, seg.$2, line);
        }
        final fill = Paint()
          ..color = colour
          ..isAntiAlias = true;
        for (final c in [
          rect.topLeft,
          rect.topRight,
          rect.bottomRight,
          rect.bottomLeft,
        ]) {
          canvas.drawPath(Khatam.star(c, r), fill);
        }

      case CardFrame.arch:
        // A mihrab: two piers, an arch across the top, a sill under
        // it. The spring line sits a little under half way, which is
        // where a pointed arch starts to read as one.
        final spring = rect.top + rect.height * 0.30;
        final apex = rect.top;
        final path = Path()
          ..moveTo(rect.left, rect.bottom)
          ..lineTo(rect.left, spring)
          ..quadraticBezierTo(
              rect.left, apex + rect.height * 0.02, rect.center.dx, apex)
          ..quadraticBezierTo(
              rect.right, apex + rect.height * 0.02, rect.right, spring)
          ..lineTo(rect.right, rect.bottom);
        canvas.drawPath(path, line);
        // The sill, drawn a shade wider than the piers, as a lintel
        // is laid under a doorway.
        canvas.drawLine(
          Offset(rect.left - 0.012 * w, rect.bottom),
          Offset(rect.right + 0.012 * w, rect.bottom),
          line..strokeWidth = _stroke * w * 1.7,
        );

      case CardFrame.panel:
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(0.035 * w));
        canvas.drawRRect(
          rrect,
          Paint()..color = const Color(0xFF000000).withValues(alpha: 0.26),
        );
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = colour.withValues(alpha: colour.a * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _stroke * w
            ..isAntiAlias = true,
        );
    }
  }

  @override
  bool shouldRepaint(covariant CardFramePainter old) =>
      old.frame != frame || old.colour != colour;
}

/// The gilded rule a block of text can stand on — the verse divider
/// the reels draw, at card scale.
class CardRule extends StatelessWidget {
  final double width;
  final Color colour;

  const CardRule({super.key, required this.width, required this.colour});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: math.max(1, width * 0.055),
      child: CustomPaint(painter: _RulePainter(colour)),
    );
  }
}

class _RulePainter extends CustomPainter {
  final Color colour;
  const _RulePainter(this.colour);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final r = size.height * 0.34;
    // A line that fades out at both ends with a seal in the middle:
    // the same figure the reels put under a verse.
    final line = Rect.fromLTRB(0, y - 0.6, size.width, y + 0.6);
    canvas.drawRect(
      line,
      Paint()
        ..shader = LinearGradient(
          colors: [
            colour.withValues(alpha: 0),
            colour.withValues(alpha: 0.75),
            colour.withValues(alpha: 0),
          ],
        ).createShader(line),
    );
    canvas.drawPath(
      Khatam.star(Offset(size.width / 2, y), r),
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(covariant _RulePainter old) => old.colour != colour;
}
