import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../data/verse_motion.dart';
import 'ayah_overlay.dart' show AyahOverlay;
import 'verse_geometry.dart';

/// The gold thread, drawn the one way twice: live under the preview's
/// verse, and into the strip the exporter crops it from.
abstract final class ThreadLook {
  /// Height of the strip the thread is drawn in, at 1080 wide: the line
  /// and the glow around it.
  static const stripHeight = 40.0;

  /// The strip is two of these side by side: empty, then the thread.
  /// Cropping a line-wide window that slides from one half into the
  /// other is what draws the thread out word by word without FFmpeg
  /// redrawing anything. Wider than any line a card can hold (936).
  static const half = 960.0;

  static const _core = 3.4;
  static const _glow = 6.0;

  /// The thread from [from] to [to] at height [y], at scale [s].
  static void paint(
      Canvas canvas, double from, double to, double y, double s, Color colour) {
    if (to <= from) return;
    canvas.drawRect(
      Rect.fromLTRB(from, y - _core * s, to, y + _core * s),
      Paint()
        ..color = colour.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _glow * s),
    );
    final core = Rect.fromLTRB(from, y - _core * s / 2, to, y + _core * s / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(core, Radius.circular(_core * s / 2)),
      Paint()
        ..shader = ui.Gradient.linear(
          core.topCenter,
          core.bottomCenter,
          [
            Color.lerp(colour, const Color(0xFFFFFFFF), 0.55)!,
            colour,
            Color.lerp(colour, const Color(0xFF000000), 0.25)!,
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  /// The whole strip, as the exporter rasterizes it.
  static void paintStrip(Canvas canvas, Color colour) {
    paint(canvas, half, 2 * half + 60, stripHeight / 2, 1, colour);
  }
}

/// The spark that rides the thread's growing end.
abstract final class SparkLook {
  /// Its square's side at 1080 wide.
  static const size = 56.0;

  static void paint(Canvas canvas, Offset centre, double s, Color colour) {
    final r = size / 2 * s;
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          r,
          [
            const Color(0xFFFFFFFF),
            Color.lerp(colour, const Color(0xFFFFFFFF), 0.4)!
                .withValues(alpha: 0.95),
            colour.withValues(alpha: 0.35),
            colour.withValues(alpha: 0),
          ],
          const [0.0, 0.14, 0.42, 1.0],
        ),
    );
  }
}

/// The band of light that passes through the letters.
abstract final class LightLook {
  /// The band's layers at 1080 wide, widest and faintest first, as
  /// (width, alpha): each a crop of the glint card laid over the ones
  /// before it, which is as close to a light with soft edges as crops of
  /// one picture get. Four steps, so no edge of the band reads as a box
  /// around the word; the core is the glint at full strength.
  static const layers = <(double, double)>[
    (216, 0.14),
    (140, 0.26),
    (88, 0.45),
    (48, 1.0),
  ];

  /// After a line is crossed, the light fades out over this long.
  static const tailMs = 220;

  /// Where a band [width] wide centred on [centre] is cut from a card
  /// [cardW] wide: kept inside the card, as FFmpeg's crop keeps it.
  static double leftOf(double centre, double width, double cardW) =>
      (centre - width / 2).clamp(0.0, cardW - width);

  /// The light's own fade at [ms] into the unit, for a line crossed by
  /// [endMs]: whole until then, gone [tailMs] later.
  static double tailAt(int ms, int endMs) =>
      ms <= endMs ? 1 : (1 - (ms - endMs) / tailMs).clamp(0.0, 1.0);
}

/// Paints the thread, the spark and the light over a verse card, from
/// the card's own laid-out paragraph — see [VerseTextAnchor].
///
/// The preview's half of the motion. The exporter's half lays small
/// pictures over the card at the same places and times, worked out
/// from the same rows and the same [RowProgress]; see
/// `VerseMotionGraph`.
class VerseFlourish extends SingleChildRenderObjectWidget {
  /// The card's Arabic: the verse, or the part of it on screen.
  final String arabic;

  /// Card width over 1080.
  final double scale;

  /// The card's own type scale — what the glint's glow is sized by.
  final double ts;

  /// Where the unit is, and how long it is.
  final int ms;
  final int unitMs;
  final VerseMotion motion;

  /// Each token's recited window, in ms into the unit; null to cross
  /// each line at an even pace.
  final List<(int, int)?>? times;

  /// The thread's and the spark's colour: the reel's accent.
  final Color accent;

  /// The light's colour (see [AyahOverlay.lightTintOf]); the accent
  /// when not given.
  final Color? lightTint;

  const VerseFlourish({
    super.key,
    required this.arabic,
    required this.scale,
    required this.ts,
    required this.ms,
    required this.unitMs,
    required this.motion,
    required this.times,
    required this.accent,
    this.lightTint,
    required Widget super.child,
  });

  @override
  RenderVerseFlourish createRenderObject(BuildContext context) =>
      RenderVerseFlourish(this);

  @override
  void updateRenderObject(
          BuildContext context, RenderVerseFlourish renderObject) =>
      renderObject.update(this);
}

class RenderVerseFlourish extends RenderProxyBox {
  RenderVerseFlourish(VerseFlourish w) : _w = w;

  VerseFlourish _w;
  List<VerseRow>? _rows;
  List<RowProgress>? _progress;
  TextPainter? _glint;

  void update(VerseFlourish w) {
    final relaid = w.arabic != _w.arabic ||
        w.scale != _w.scale ||
        w.ts != _w.ts ||
        !identical(w.times, _w.times) ||
        w.unitMs != _w.unitMs;
    final retinted = (w.lightTint ?? w.accent) != (_w.lightTint ?? _w.accent);
    _w = w;
    if (relaid) {
      _forget();
    } else if (retinted) {
      _glint?.dispose();
      _glint = null;
    }
    markNeedsPaint();
  }

  void _forget() {
    _rows = null;
    _progress = null;
    _glint?.dispose();
    _glint = null;
  }

  @override
  void performLayout() {
    super.performLayout();
    _forget();
  }

  @override
  void dispose() {
    _glint?.dispose();
    super.dispose();
  }

  List<RowProgress> _progressFor(List<VerseRow> rows) {
    final times = _w.times;
    if (times != null) {
      return [for (final r in rows) r.progressFromWords(times, 0)];
    }
    final v = VerseRows.voicedIn(_w.unitMs);
    return VerseRows.even(rows, _w.arabic.split(' '), v.fromMs, v.toMs);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final m = _w.motion;
    if (!m.thread && !m.light) return;
    final rows = _rows ??= VerseRows.measure(this, _w.arabic);
    if (rows.isEmpty) return;
    final progress = _progress ??= _progressFor(rows);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final ms = _w.ms;
    final s = _w.scale;
    if (m.light) _paintLight(canvas, rows, progress, ms, s);
    if (m.thread) {
      final w = m.windowsFor(_w.unitMs);
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final p = progress[i];
        if (p.points.isEmpty || ms < p.startMs) continue;
        final g = p.at(ms);
        final y = r.threadY;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(
            r.left, y - ThreadLook.stripHeight / 2 * s, r.right,
            y + ThreadLook.stripHeight / 2 * s));
        ThreadLook.paint(
            canvas, r.right - g, r.right + 60 * s, y, s, _w.accent);
        canvas.restore();
        // The spark rides the growing end, and is not there while the
        // card itself is still arriving or already leaving: it is a
        // still picture in the export, which cannot fade with it.
        final sparkOn = p.visitAt(ms, 120) != null &&
            ms >= w.inMs &&
            ms <= _w.unitMs - w.outMs;
        if (sparkOn) SparkLook.paint(canvas, Offset(r.right - g, y), s, _w.accent);
      }
    }
    canvas.restore();
  }

  void _paintLight(Canvas canvas, List<VerseRow> rows,
      List<RowProgress> progress, int ms, double s) {
    final glint = _glint ??= _glintPainter();
    if (glint == null) return;
    final anchor = RenderVerseAnchor.find(this);
    final p = anchor?.paragraph;
    if (p == null) return;
    final at = p.localToGlobal(Offset.zero, ancestor: this);
    final cardW = size.width;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final pr = progress[i];
      if (pr.points.isEmpty) continue;
      final visit = pr.visitAt(ms, LightLook.tailMs);
      if (visit == null) continue;
      final tail = LightLook.tailAt(ms, visit.$2);
      final cx = r.right - pr.at(ms);
      for (final (width, a) in LightLook.layers) {
        final w = width * s;
        final left = LightLook.leftOf(cx, w, cardW);
        final band = Rect.fromLTRB(left, r.top, left + w, r.bottom);
        canvas.save();
        canvas.clipRect(band);
        canvas.saveLayer(
            band,
            Paint()
              ..color = const Color(0xFF000000).withValues(alpha: a * tail));
        glint.paint(canvas, at);
        canvas.restore();
        canvas.restore();
      }
    }
  }

  /// The verse's own paragraph again, in light: laid out exactly as the
  /// card's, since only colour and glow differ.
  TextPainter? _glintPainter() {
    final p = RenderVerseAnchor.find(this)?.paragraph;
    if (p == null) return null;
    final tint = _w.lightTint ?? _w.accent;
    final glow = AyahOverlay.glintGlowFor(_w.ts, tint);
    final colour = AyahOverlay.glintColourFor(tint);
    InlineSpan lit(InlineSpan span) {
      if (span is! TextSpan) return span;
      final mark = (span.text ?? '').startsWith(' ');
      return TextSpan(
        text: span.text,
        style: (span.style ?? const TextStyle()).copyWith(
          color: mark ? const Color(0x00000000) : colour,
          shadows: mark ? const [] : glow,
        ),
        children: span.children?.map(lit).toList(),
      );
    }

    return TextPainter(
      text: lit(p.text),
      textAlign: p.textAlign,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      maxLines: p.maxLines,
      locale: p.locale,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
      textHeightBehavior: p.textHeightBehavior,
    )..layout(
        minWidth: p.constraints.minWidth, maxWidth: p.constraints.maxWidth);
  }
}
