import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/card_style.dart';
import 'illumination.dart';

/// The borders a card can wear, drawn rather than borrowed.
///
/// Every one of them is built from the shapes the rest of the app is
/// drawn with — the hairline, the seal, the arch, the lattice — and every
/// measurement is a fraction of the card's width, so a frame is the
/// same frame in a 60px thumbnail and in a 1080px export. Nothing here
/// knows what size it is being drawn at.
///
/// Some are flat ink; some stand off the card — a gilded moulding lit
/// from the top left, a slab of frosted glass on its own shadow, a
/// loose pile of sheets. The light always comes from the top left, so
/// two of them on one deck agree about where the sun is.
class CardFramePainter extends CustomPainter {
  final CardFrame frame;
  final Color colour;

  const CardFramePainter({required this.frame, required this.colour});

  /// Stroke of the main rule, as a fraction of the card's width. A
  /// hair over a thousandth: at export it is a crisp two-pixel line,
  /// and in the composer it is still visibly a line rather than a
  /// smudge.
  static const _stroke = 0.0022;

  Color _a(double k) => colour.withValues(alpha: colour.a * k);
  Color get _deep => Color.lerp(colour, Colors.black, 0.55)!;

  Paint _line(double w, {double k = 1, double alpha = 1}) => Paint()
    ..color = _a(alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = _stroke * w * k
    ..strokeJoin = StrokeJoin.miter
    ..isAntiAlias = true;

  static Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  static Paint _blurred(Color c, double sigma) => Paint()
    ..color = c
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);

  static Path _diamond(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy - r)
    ..lineTo(c.dx + r, c.dy)
    ..lineTo(c.dx, c.dy + r)
    ..lineTo(c.dx - r, c.dy)
    ..close();

  /// The four corners of [r], clockwise from the top left, each with
  /// the signs that point from it into the card.
  static List<(Offset, double, double)> _corners(Rect r) => [
        (r.topLeft, 1, 1),
        (r.topRight, -1, 1),
        (r.bottomRight, -1, -1),
        (r.bottomLeft, 1, -1),
      ];

  /// A band between [outer] and [inner], for the frames that are one.
  static Path _band(Rect outer, Rect inner) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(outer)
    ..addRect(inner);

  @override
  void paint(Canvas canvas, Size size) {
    if (frame == CardFrame.none) return;
    final w = size.width;
    final inset = frame.inset * w;
    final rect = Rect.fromLTRB(
        inset, inset, size.width - inset, size.height - inset);

    switch (frame) {
      case CardFrame.none:
        return;

      case CardFrame.hairline:
        canvas.drawRect(rect, _line(w));

      case CardFrame.double_:
        canvas.drawRect(rect, _line(w, k: 1.6));
        canvas.drawRect(rect.deflate(0.018 * w), _line(w, k: 0.7, alpha: 0.75));

      case CardFrame.corners:
        // A bracket at each corner, a shorter one tucked inside it, and
        // a small diamond on the corner point itself.
        final arm = 0.1 * w, arm2 = 0.05 * w, gap = 0.016 * w;
        final outer = _line(w, k: 1.3)..strokeCap = StrokeCap.square;
        final inner = _line(w, k: 0.7, alpha: 0.6)..strokeCap = StrokeCap.square;
        for (final (p, sx, sy) in _corners(rect)) {
          canvas.drawPath(
              Path()
                ..moveTo(p.dx + sx * arm, p.dy)
                ..lineTo(p.dx, p.dy)
                ..lineTo(p.dx, p.dy + sy * arm),
              outer);
          final q = p + Offset(sx * gap, sy * gap);
          canvas.drawPath(
              Path()
                ..moveTo(q.dx + sx * arm2, q.dy)
                ..lineTo(q.dx, q.dy)
                ..lineTo(q.dx, q.dy + sy * arm2),
              inner);
          canvas.drawPath(_diamond(p, 0.009 * w), _fill(colour));
        }

      case CardFrame.khatam:
        // Four rules that stop short of the corners, and a seal
        // standing in each gap — so the two read as one piece of
        // drawing rather than as a star dropped on a box. The gap is
        // cut by ending the lines, never by a blend mode: a `clear`
        // here would punch through the photograph as well.
        final r = 0.021 * w;
        final gap = r * 1.5;
        final line = _line(w);
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
        for (final (c, _, _) in _corners(rect)) {
          canvas.drawPath(Khatam.star(c, r), _fill(colour));
        }

      case CardFrame.arch:
        _arch(canvas, rect, w);

      case CardFrame.panel:
        // A darkened slab lifted on a soft shadow, its edge catching the
        // light along the top.
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(0.035 * w));
        canvas.drawRRect(rrect.shift(Offset(0, 0.012 * w)),
            _blurred(Colors.black.withValues(alpha: 0.3), 0.012 * w));
        canvas.drawRRect(
            rrect, _fill(Colors.black.withValues(alpha: 0.26)));
        canvas.drawRRect(
          rrect,
          _line(w)
            ..shader = ui.Gradient.linear(
              rect.topCenter,
              rect.bottomCenter,
              [_a(0.75), _a(0.45), _a(0.3)],
              const [0, 0.5, 1],
            ),
        );

      case CardFrame.gilt:
        _gilt(canvas, size, w);

      case CardFrame.glass:
        _glass(canvas, rect, w);

      case CardFrame.layers:
        _layers(canvas, size, rect, w);

      case CardFrame.glow:
        _glow(canvas, rect, w);

      case CardFrame.girih:
        _girih(canvas, rect, w);

      case CardFrame.zellige:
        _zellige(canvas, rect, w);

      case CardFrame.lattice:
        _lattice(canvas, rect, w);

      case CardFrame.arabesque:
        _arabesque(canvas, rect, w);

      case CardFrame.cartouche:
        _cartouche(canvas, rect, w);

      case CardFrame.stars:
        _stars(canvas, rect, w);
    }
  }

  /// A mihrab: two piers, an arch across the top with a second, finer
  /// one inside it, capitals where they spring, a seal for a keystone,
  /// and a sill laid a shade wider than the piers.
  void _arch(Canvas canvas, Rect rect, double w) {
    (Path, double) arch(Rect r, double bottom, double springAt) {
      final spring = r.top + (bottom - r.top) * springAt;
      final h = bottom - r.top;
      final path = Path()
        ..moveTo(r.left, bottom)
        ..lineTo(r.left, spring)
        ..quadraticBezierTo(r.left, r.top + h * 0.02, r.center.dx, r.top)
        ..quadraticBezierTo(r.right, r.top + h * 0.02, r.right, spring)
        ..lineTo(r.right, bottom);
      return (path, spring);
    }

    final (outer, spring) = arch(rect, rect.bottom, 0.30);
    canvas.drawPath(outer, _line(w, k: 1.2));
    final (inner, _) = arch(rect.deflate(0.02 * w), rect.bottom, 0.31);
    canvas.drawPath(inner, _line(w, k: 0.7, alpha: 0.6));
    final capital = _line(w, k: 1.4);
    for (final x in [rect.left, rect.right]) {
      canvas.drawLine(Offset(x - 0.014 * w, spring),
          Offset(x + 0.014 * w, spring), capital);
    }
    canvas.drawPath(
        Khatam.star(rect.topCenter, 0.017 * w), _fill(colour));
    canvas.drawLine(
      Offset(rect.left - 0.012 * w, rect.bottom),
      Offset(rect.right + 0.012 * w, rect.bottom),
      _line(w, k: 1.7),
    );
  }

  /// A gilded moulding, lit from the top left: four mitred sides, each
  /// shaded across its width like a rounded bead with a lip inside, the
  /// lit two bright and the far two in shadow, and the moulding's own
  /// shadow falling on the picture under its lit sides.
  void _gilt(Canvas canvas, Size size, double w) {
    final o = Rect.fromLTRB(
        0.03 * w, 0.03 * w, size.width - 0.03 * w, size.height - 0.03 * w);
    final b = 0.03 * w;
    final i = o.deflate(b);
    final light = Color.lerp(colour, Colors.white, 0.62)!;
    final deep = Color.lerp(colour, Colors.black, 0.5)!;
    final deeper = Color.lerp(colour, Colors.black, 0.72)!;
    const stops = [0.0, 0.12, 0.38, 0.66, 0.84, 0.9, 1.0];
    final lit = [deep, colour, light, colour, deep, light, deep];
    final dark = [deeper, deep, colour, deep, deeper, colour, deeper];
    for (final (pts, from, to, isLit) in [
      ([o.topLeft, o.topRight, i.topRight, i.topLeft], Offset(0, o.top),
          Offset(0, i.top), true),
      ([o.topLeft, i.topLeft, i.bottomLeft, o.bottomLeft], Offset(o.left, 0),
          Offset(i.left, 0), true),
      ([o.topRight, o.bottomRight, i.bottomRight, i.topRight],
          Offset(o.right, 0), Offset(i.right, 0), false),
      ([o.bottomLeft, i.bottomLeft, i.bottomRight, o.bottomRight],
          Offset(0, o.bottom), Offset(0, i.bottom), false),
    ]) {
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()
          ..isAntiAlias = true
          ..shader =
              ui.Gradient.linear(from, to, isLit ? lit : dark, stops),
      );
    }
    final mitre = Paint()
      ..color = deeper.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.0012 * w;
    for (final (a, z) in [
      (o.topLeft, i.topLeft),
      (o.topRight, i.topRight),
      (o.bottomRight, i.bottomRight),
      (o.bottomLeft, i.bottomLeft),
    ]) {
      canvas.drawLine(a, z, mitre);
    }
    final edge = Paint()
      ..color = deeper.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.0016 * w;
    canvas.drawRect(o, edge);
    canvas.drawRect(i, edge);
    final shade = 0.02 * w;
    canvas.drawRect(
      Rect.fromLTWH(i.left, i.top, i.width, shade),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, i.top), Offset(0, i.top + shade),
            [Colors.black.withValues(alpha: 0.45), Colors.transparent]),
    );
    canvas.drawRect(
      Rect.fromLTWH(i.left, i.top, shade, i.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset(i.left, 0), Offset(i.left + shade, 0),
            [Colors.black.withValues(alpha: 0.4), Colors.transparent]),
    );
    for (final (c, sx, sy) in _corners(o)) {
      final m = c + Offset(sx * b / 2, sy * b / 2);
      canvas.drawPath(Khatam.star(m, b * 0.36), _fill(light));
      canvas.drawPath(Khatam.star(m, b * 0.14), _fill(deep));
    }
  }

  /// Frosted glass lifted off the picture on its own shadow: darkened a
  /// little for the words, frosted brighter toward the light, a curve of
  /// sheen across its top, and a rim that is white where the light
  /// catches it and the frame's colour round the rest.
  void _glass(Canvas canvas, Rect r, double w) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(0.045 * w));
    canvas.drawRRect(rr.shift(Offset(0, 0.022 * w)),
        _blurred(Colors.black.withValues(alpha: 0.42), 0.028 * w));
    canvas.drawRRect(rr, _fill(Colors.black.withValues(alpha: 0.22)));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.08),
        ], const [0, 0.5, 1]),
    );
    canvas.save();
    canvas.clipRRect(rr);
    final h = r.height;
    final sheen = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + h * 0.16)
      ..quadraticBezierTo(r.center.dx, r.top + h * 0.30, r.left, r.top + h * 0.22)
      ..close();
    canvas.drawPath(
      sheen,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, r.top), Offset(0, r.top + h * 0.3), [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.003 * w
        ..isAntiAlias = true
        ..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, [
          Colors.white.withValues(alpha: 0.75),
          _a(0.6),
          _a(0.25),
        ], const [0, 0.45, 1]),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(0.007 * w), Radius.circular(0.038 * w)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.0012 * w
        ..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  /// Three sheets in a loose pile: the two behind turned a little each
  /// way, only their edges showing round the one carrying the words.
  void _layers(Canvas canvas, Size size, Rect f, double w) {
    final rad = Radius.circular(0.026 * w);
    final front = RRect.fromRectAndRadius(f, rad);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(front);
    final mid = size.center(Offset.zero);
    for (final (deg, alpha) in [(-3.2, 0.35), (2.4, 0.55)]) {
      canvas.save();
      canvas.clipPath(outside);
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(deg * math.pi / 180);
      canvas.translate(-mid.dx, -mid.dy);
      canvas.drawRRect(front.shift(Offset(0, 0.006 * w)),
          _blurred(Colors.black.withValues(alpha: 0.35), 0.01 * w));
      canvas.drawRRect(front, _fill(const Color(0x8C0A0C12)));
      canvas.drawRRect(front, _line(w, k: 0.9, alpha: alpha));
      canvas.restore();
    }
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(front.shift(Offset(0, 0.01 * w)),
        _blurred(Colors.black.withValues(alpha: 0.45), 0.014 * w));
    canvas.restore();
    canvas.drawRRect(front, _fill(Colors.black.withValues(alpha: 0.16)));
    canvas.drawRRect(
      front,
      _line(w, k: 1.1)
        ..shader = ui.Gradient.linear(
            f.topLeft, f.bottomRight, [Color.lerp(colour, Colors.white, 0.4)!, _a(0.7)]),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(f.deflate(0.014 * w), Radius.circular(0.016 * w)),
      _line(w, k: 0.6, alpha: 0.4),
    );
  }

  /// A line of light: one rule glowing, with a seal burning at each
  /// corner — the frame for a night photograph.
  void _glow(Canvas canvas, Rect r, double w) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(0.02 * w));
    final hot = Color.lerp(colour, Colors.white, 0.55)!;
    for (final (sigma, alpha, width) in [(0.03, 0.55, 0.008), (0.012, 0.8, 0.005)]) {
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * w
          ..color = _a(alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * w),
      );
    }
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.0026 * w
        ..color = hot
        ..isAntiAlias = true,
    );
    for (final (c, _, _) in _corners(r)) {
      canvas.drawCircle(c, 0.03 * w, _blurred(_a(0.9), 0.014 * w));
      canvas.drawPath(Khatam.star(c, 0.022 * w), _fill(hot));
    }
  }

  /// A band of eight-pointed stars, each pair joined by a turned square,
  /// threaded on one fine line between two rules; a larger star, with a
  /// star inside it, at every corner.
  void _girih(Canvas canvas, Rect frameRect, double w) {
    final o = frameRect;
    final b = 0.044 * w;
    final i = o.deflate(b);
    final m = o.deflate(b / 2);
    canvas.drawPath(_band(o, i), _fill(_a(0.10)));
    final rule = _line(w, k: 0.9);
    canvas.drawRect(o, rule);
    canvas.drawRect(i, rule);
    canvas.drawRect(m, _line(w, k: 0.5, alpha: 0.45));
    final r = b * 0.32;
    final star = _fill(colour);
    final heart = _fill(_deep);
    final link = _fill(_a(0.6));
    void side(Offset a, Offset z) {
      final n = math.max(1, ((z - a).distance / (b * 1.6)).round());
      for (var k = 1; k < n; k++) {
        final p = Offset.lerp(a, z, k / n)!;
        canvas.drawPath(Khatam.star(p, r), star);
        canvas.drawPath(Khatam.star(p, r * 0.42, rotation: math.pi / 8), heart);
      }
      for (var k = 0; k < n; k++) {
        canvas.drawPath(_diamond(Offset.lerp(a, z, (k + 0.5) / n)!, r * 0.42), link);
      }
    }

    side(m.topLeft, m.topRight);
    side(m.bottomLeft, m.bottomRight);
    side(m.topLeft, m.bottomLeft);
    side(m.topRight, m.bottomRight);
    for (final (c, _, _) in _corners(m)) {
      canvas.drawPath(Khatam.star(c, r * 1.5), star);
      canvas.drawPath(Khatam.star(c, r * 0.7, rotation: math.pi / 8), heart);
      canvas.drawPath(Khatam.star(c, r * 0.3), star);
    }
  }

  /// Tiles: a band of diamonds set point to point, each lit across its
  /// face with a dark one set in it, a seal on a dark square at every
  /// corner, and a rule each side.
  void _zellige(Canvas canvas, Rect frameRect, double w) {
    final o = frameRect;
    final b = 0.04 * w;
    final i = o.deflate(b);
    final m = o.deflate(b / 2);
    final light = Color.lerp(colour, Colors.white, 0.4)!;
    final deep = Color.lerp(colour, Colors.black, 0.6)!;
    canvas.drawPath(_band(o, i), _fill(_a(0.16)));
    void side(Offset a, Offset z) {
      final n = math.max(1, ((z - a).distance / b).round());
      for (var k = 0; k < n; k++) {
        final p = Offset.lerp(a, z, (k + 0.5) / n)!;
        canvas.drawPath(
          _diamond(p, b * 0.46),
          Paint()
            ..isAntiAlias = true
            ..shader = ui.Gradient.linear(p - Offset(b / 2, b / 2),
                p + Offset(b / 2, b / 2), [light, colour]),
        );
        canvas.drawPath(_diamond(p, b * 0.2), _fill(deep));
      }
    }

    side(m.topLeft + Offset(b / 2, 0), m.topRight - Offset(b / 2, 0));
    side(m.bottomLeft + Offset(b / 2, 0), m.bottomRight - Offset(b / 2, 0));
    side(m.topLeft + Offset(0, b / 2), m.bottomLeft - Offset(0, b / 2));
    side(m.topRight + Offset(0, b / 2), m.bottomRight - Offset(0, b / 2));
    for (final (c, _, _) in _corners(m)) {
      canvas.drawRect(Rect.fromCenter(center: c, width: b, height: b), _fill(deep));
      canvas.drawPath(Khatam.star(c, b * 0.42), _fill(colour));
    }
    final rule = _line(w, k: 0.9);
    canvas.drawRect(o, rule);
    canvas.drawRect(i, rule);
  }

  /// A carved screen: the app's own lattice of seals, cut into a band
  /// between two rules, the way a mashrabiya frames a window.
  void _lattice(Canvas canvas, Rect frameRect, double w) {
    final o = frameRect;
    final i = o.deflate(0.06 * w);
    canvas.save();
    canvas.clipPath(_band(o, i));
    canvas.drawRect(o, _fill(_a(0.11)));
    canvas.translate(o.left, o.top);
    canvas.drawPath(
      Khatam.lattice(o.size, 0.05 * w),
      _line(w, k: 0.8, alpha: 0.85),
    );
    canvas.restore();
    canvas.drawRect(o, _line(w));
    canvas.drawRect(i, _line(w, k: 0.8, alpha: 0.8));
  }

  /// A flourish in each corner: the outer rule runs square; the inner
  /// one sweeps in to the corner, where a leaf points in along the
  /// diagonal between two buds, a seal at its point; a diamond at the
  /// middle of every side.
  void _arabesque(Canvas canvas, Rect r, double w) {
    final s = 0.16 * w, d = 0.016 * w;
    canvas.drawRect(r, _line(w));
    for (final c in [r.topCenter, r.bottomCenter, r.centerLeft, r.centerRight]) {
      canvas.drawPath(_diamond(c, 0.012 * w), _fill(colour));
    }
    final inner = _line(w, k: 0.7, alpha: 0.7);
    canvas.drawLine(Offset(r.left + s, r.top + d), Offset(r.right - s, r.top + d), inner);
    canvas.drawLine(
        Offset(r.left + s, r.bottom - d), Offset(r.right - s, r.bottom - d), inner);
    canvas.drawLine(Offset(r.left + d, r.top + s), Offset(r.left + d, r.bottom - s), inner);
    canvas.drawLine(
        Offset(r.right - d, r.top + s), Offset(r.right - d, r.bottom - s), inner);

    final sweep = Path()
      ..moveTo(s, d)
      ..cubicTo(s * 0.62, d, s * 0.34, s * 0.1, s * 0.22, s * 0.22);
    final bud = Path()
      ..moveTo(s * 0.5, d * 1.15)
      ..cubicTo(s * 0.38, d * 1.2, s * 0.26, d * 0.55, s * 0.3, d * 0.2)
      ..cubicTo(s * 0.33, d * 0.35, s * 0.4, d * 0.5, s * 0.38, d * 0.95);
    final leaf = Path()
      ..moveTo(s * 0.16, s * 0.16)
      ..quadraticBezierTo(s * 0.42, s * 0.2, s * 0.44, s * 0.44)
      ..quadraticBezierTo(s * 0.2, s * 0.42, s * 0.16, s * 0.16)
      ..close();
    final sweepPaint = _line(w, k: 0.9, alpha: 0.85)..strokeCap = StrokeCap.round;
    final budPaint = _line(w, k: 0.7, alpha: 0.75)..strokeCap = StrokeCap.round;
    final leafPaint = Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(Offset(s * 0.16, s * 0.16),
          Offset(s * 0.44, s * 0.44), [_a(0.95), Color.lerp(colour, Colors.white, 0.35)!]);
    final vein = Paint()
      ..color = _deep.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke * w * 0.5;
    // The diagonal mirror, for the second arm of each corner.
    final swap = Float64List.fromList(
        [0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    for (final (c, sx, sy) in _corners(r)) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(sx, sy);
      for (final flip in [false, true]) {
        if (flip) {
          canvas.save();
          canvas.transform(swap);
        }
        canvas.drawPath(sweep, sweepPaint);
        canvas.drawPath(bud, budPaint);
        if (flip) canvas.restore();
      }
      canvas.drawPath(leaf, leafPaint);
      canvas.drawLine(Offset(s * 0.19, s * 0.19), Offset(s * 0.38, s * 0.38), vein);
      canvas.drawPath(Khatam.star(Offset(s * 0.52, s * 0.52), s * 0.055), _fill(colour));
      canvas.drawPath(_diamond(Offset(s * 0.075, s * 0.075), s * 0.04), _fill(colour));
      canvas.restore();
    }
  }

  /// An Ottoman cartouche: a double line whose corners are cut inward
  /// in quarter circles, a dot in each cut, a seal top and bottom.
  void _cartouche(Canvas canvas, Rect r, double w) {
    Path shape(Rect x, double q) => Path()
      ..moveTo(x.left + q, x.top)
      ..lineTo(x.right - q, x.top)
      ..arcTo(Rect.fromCircle(center: x.topRight, radius: q), math.pi,
          -math.pi / 2, false)
      ..lineTo(x.right, x.bottom - q)
      ..arcTo(Rect.fromCircle(center: x.bottomRight, radius: q),
          3 * math.pi / 2, -math.pi / 2, false)
      ..lineTo(x.left + q, x.bottom)
      ..arcTo(Rect.fromCircle(center: x.bottomLeft, radius: q), 0,
          -math.pi / 2, false)
      ..lineTo(x.left, x.top + q)
      ..arcTo(Rect.fromCircle(center: x.topLeft, radius: q), math.pi / 2,
          -math.pi / 2, false)
      ..close();
    final q = 0.07 * w, d = 0.014 * w;
    canvas.drawPath(shape(r, q), _line(w, k: 1.2));
    canvas.drawPath(shape(r.deflate(d), q + d), _line(w, k: 0.7, alpha: 0.6));
    for (final (c, sx, sy) in _corners(r)) {
      canvas.drawCircle(
          c + Offset(sx * q * 0.42, sy * q * 0.42), 0.007 * w, _fill(colour));
    }
    for (final c in [r.topCenter, r.bottomCenter]) {
      canvas.drawPath(Khatam.star(c, 0.018 * w), _fill(colour));
    }
  }

  /// A night's border: small stars round the card, a few brighter and
  /// haloed, a four-pointed sparkle at every corner. The same stars on
  /// every card — the scatter is seeded, not random.
  void _stars(Canvas canvas, Rect r, double w) {
    var seed = 7;
    double rnd() => (seed = (seed * 16807) % 2147483647) / 2147483647;
    final step = 0.026 * w;
    final points = <Offset>[];
    void side(Offset a, Offset z) {
      final n = ((z - a).distance / step).round();
      for (var k = 0; k < n; k++) {
        points.add(Offset.lerp(a, z, k / n)!);
      }
    }

    side(r.topLeft, r.topRight);
    side(r.topRight, r.bottomRight);
    side(r.bottomRight, r.bottomLeft);
    side(r.bottomLeft, r.topLeft);
    final bright = Color.lerp(colour, Colors.white, 0.5)!;
    for (final p in points) {
      final big = rnd() > 0.82;
      final radius = (big ? 0.0045 : 0.002 + rnd() * 0.0016) * w;
      if (big) {
        canvas.drawCircle(p, radius * 2.2, _blurred(_a(0.8), 0.004 * w));
      }
      canvas.drawCircle(
          p, radius, _fill(big ? bright : _a(0.55 + rnd() * 0.4)));
    }
    final sparkle = Color.lerp(colour, Colors.white, 0.6)!;
    for (final (c, _, _) in _corners(r)) {
      final s = 0.03 * w, k = 0.004 * w;
      final p = Path()
        ..moveTo(c.dx, c.dy - s)
        ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + s, c.dy)
        ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + s)
        ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - s, c.dy)
        ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - s)
        ..close();
      canvas.drawPath(p, _blurred(_a(0.7), 0.006 * w));
      canvas.drawPath(p, _fill(sparkle));
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
