import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/verse_motion.dart';
import '../widgets/verse_flourish.dart' show LightLook, SparkLook, ThreadLook;

/// A verse card's overlay window, as the motion graph sees it.
@immutable
class MotionCard {
  /// The card's FFmpeg input.
  final int input;

  /// When it is drawn: absolute, already cut to the pass.
  final int startMs;
  final int endMs;

  /// The unit — whole verse or part of one — it belongs to: absolute,
  /// and *not* cut to the pass, so a unit that began in the pass before
  /// still fades out on its own clock.
  final int unitStartMs;
  final int unitEndMs;

  const MotionCard({
    required this.input,
    required this.startMs,
    required this.endMs,
    required this.unitStartMs,
    required this.unitEndMs,
  });
}

/// One line of a unit, for the thread and the light: where it is on its
/// card (export pixels), and how the recitation crosses it.
@immutable
class MotionRow {
  final double left;
  final double right;
  final double top;
  final double bottom;
  final double threadY;

  /// In ms into the unit.
  final RowProgress progress;

  const MotionRow({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.threadY,
    required this.progress,
  });

  int get width => (right - left).round();
}

/// A unit's flourishes: its rows, where its card sits in the frame, and
/// the glint card its light is cut from.
@immutable
class MotionUnit {
  final int startMs;
  final int endMs;

  /// The card's top in the frame (export pixels), with the card at rest,
  /// and its height — what a band cut from its glint card has to stay
  /// inside.
  final double cardTop;
  final double cardH;
  final List<MotionRow> rows;

  /// The FFmpeg input of this unit's glint card, when the light is on.
  final int? glintInput;

  const MotionUnit({
    required this.startMs,
    required this.endMs,
    required this.cardTop,
    required this.cardH,
    required this.rows,
    this.glintInput,
  });

  MotionUnit withGlint(int? input) => MotionUnit(
      startMs: startMs,
      endMs: endMs,
      cardTop: cardTop,
      cardH: cardH,
      rows: rows,
      glintInput: input);
}

/// Writes the verse cards' overlays with their motion into an FFmpeg
/// filter graph.
///
/// Every card is still one picture, decoded once. What moves is made
/// out of it without redrawing a letter:
///
///  * **arrival** — the stretch of a card's window inside its unit's
///    first or last few hundred milliseconds is drawn from a short
///    stream of copies of the card (`loop`), timed in the unit's own
///    clock so `fade` and the rise read unit time whatever pass this
///    is, then moved onto the pass's clock;
///  * **thread** — a strip half empty, half thread, of which a window as
///    wide as the line is cropped, sliding from the empty half into the
///    thread as the recitation crosses the line;
///  * **light** — a band cut from the unit's glint card at the place the
///    recitation has reached, laid back over the card at the same place;
///  * **spark** — a still, moved along the thread's growing end.
///
/// The preview draws the same from the same numbers; see
/// `VerseFlourish` and [VerseMotion].
abstract final class VerseMotionGraph {
  static const fps = 30;

  /// The card is 1080 wide and centred: its x in the frame is 0.
  static const cardW = 1080;

  static String _s(int ms) => (ms / 1000).toStringAsFixed(3);

  /// Unit time as an expression in the pass's clock `t`.
  static String _unitT(int unitStartMs, int passStartMs) {
    final shift = unitStartMs - passStartMs;
    return shift >= 0 ? '(t-${_s(shift)})' : '(t+${_s(-shift)})';
  }

  /// What a pass's graph needs besides the cards: which units' glint
  /// cards, and whether the thread strip and the spark are used.
  static ({Set<int> glintUnits, bool thread, bool spark}) uses({
    required List<MotionUnit> units,
    required VerseMotion motion,
    required int passStartMs,
    required int passEndMs,
  }) {
    final glint = <int>{};
    var thread = false;
    var spark = false;
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      if (u.endMs <= passStartMs || u.startMs >= passEndMs) continue;
      final w = motion.windowsFor(u.endMs - u.startMs);
      for (final r in u.rows) {
        if (r.progress.points.isEmpty) continue;
        if (motion.thread) {
          if (_threadSpan(u, r, passStartMs, passEndMs) != null) thread = true;
          if (_sparkSpan(u, r, w, passStartMs, passEndMs) != null) {
            spark = true;
          }
        }
        if (motion.light && _lightSpan(u, r, passStartMs, passEndMs) != null) {
          glint.add(i);
        }
      }
    }
    return (glintUnits: glint, thread: thread, spark: spark);
  }

  static (int, int)? _clip(int a, int b) => a < b ? (a, b) : null;

  static (int, int)? _threadSpan(MotionUnit u, MotionRow r, int p0, int p1) =>
      _clip(math.max(math.max(u.startMs + r.progress.startMs, u.startMs), p0),
          math.min(u.endMs, p1));

  static (int, int)? _sparkSpan(MotionUnit u, MotionRow r,
          ({int inMs, int outMs}) w, int p0, int p1) =>
      _clip(
          math.max(
              math.max(u.startMs + r.progress.startMs, u.startMs + w.inMs), p0),
          math.min(math.min(u.startMs + r.progress.endMs + 120, u.endMs - w.outMs),
              p1));

  static (int, int)? _lightSpan(MotionUnit u, MotionRow r, int p0, int p1) =>
      _clip(math.max(math.max(u.startMs + r.progress.startMs, u.startMs), p0),
          math.min(math.min(u.startMs + r.progress.endMs + LightLook.tailMs,
              u.endMs), p1));

  /// [fromMs]..[toMs] of a still made a stream, in unit time (so the
  /// filters in [filters] read unit time as `t`), then put on the pass's
  /// clock. One frame more than the stretch needs, so the last frame of
  /// the pass is never left without one.
  static String _stream(String src, String out,
      {required int fromMs,
      required int toMs,
      required int unitStartMs,
      required int passStartMs,
      required String filters}) {
    final frames = ((toMs - fromMs) * fps / 1000).ceil() + 1;
    final shift = unitStartMs - passStartMs;
    return '[$src]loop=loop=${frames - 1}:size=1:start=0,settb=1/1000,'
        'setpts=(N/$fps+${_s(fromMs - unitStartMs)})/TB,$filters'
        'setpts=PTS${shift >= 0 ? '+' : '-'}${_s(shift.abs())}/TB[$out];';
  }

  /// The card's own fades over [fromMs]..[toMs] of its unit, and the
  /// light's tail when [lightEndMs] is given.
  static String _fades(int fromMs, int toMs, int unitStartMs, int unitEndMs,
      ({int inMs, int outMs}) w,
      {int? lightEndMs}) {
    final b = StringBuffer();
    if (w.inMs > 0 && fromMs < unitStartMs + w.inMs) {
      b.write('fade=t=in:st=0:d=${_s(w.inMs)}:alpha=1,');
    }
    if (w.outMs > 0 && toMs > unitEndMs - w.outMs) {
      b.write('fade=t=out:st=${_s(unitEndMs - unitStartMs - w.outMs)}'
          ':d=${_s(w.outMs)}:alpha=1,');
    }
    if (lightEndMs != null && toMs > lightEndMs) {
      b.write('fade=t=out:st=${_s(lightEndMs - unitStartMs)}'
          ':d=${_s(LightLook.tailMs)}:alpha=1,');
    }
    return b.toString();
  }

  /// Writes the overlays of [cards], with [motion], chaining from
  /// [prev]; returns the label the chain ends on.
  ///
  /// [baseY] is the y the graph has always placed a verse card at, with
  /// `h` its height. Card pieces outside every fade are written exactly
  /// as they always were, so a reel whose motion is only a thread or a
  /// light keeps its cards' graph unchanged.
  static String write(
    StringBuffer f, {
    required String prev,
    required List<MotionCard> cards,
    required List<MotionUnit> units,
    required VerseMotion motion,
    required int passStartMs,
    required int passEndMs,
    required String baseY,
    int? threadInput,
    int? sparkInput,
  }) {
    var n = 0;
    String label() => 'q${n++}';
    String gate(int a, int b) =>
        "enable='gte(t,${_s(a - passStartMs)})*lt(t,${_s(b - passStartMs)})'";

    // ---- the cards ----
    for (final c in cards) {
      final u0 = c.unitStartMs, u1 = c.unitEndMs;
      final w = motion.windowsFor(u1 - u0);
      final pieces = <(int, int, bool)>[];
      var a = c.startMs;
      final b = c.endMs;
      if (w.inMs > 0 && a < u0 + w.inMs) {
        final e = math.min(b, u0 + w.inMs);
        if (a < e) pieces.add((a, e, true));
        a = e;
      }
      final mid = w.outMs > 0 ? math.min(b, u1 - w.outMs) : b;
      if (a < mid) {
        pieces.add((a, mid, false));
        a = mid;
      }
      if (a < b) pieces.add((a, b, true));
      if (pieces.isEmpty) continue;

      final srcs = <String>[];
      if (pieces.length == 1 && !pieces.first.$3) {
        srcs.add('${c.input}:v');
      } else {
        f.write('[${c.input}:v]format=rgba,split=${pieces.length}');
        for (var k = 0; k < pieces.length; k++) {
          final s = 'qc${c.input}_$k';
          srcs.add(s);
          f.write('[$s]');
        }
        f.write(';');
      }
      for (var k = 0; k < pieces.length; k++) {
        final (p0, p1, animated) = pieces[k];
        final out = label();
        if (!animated) {
          f.write("[$prev][${srcs[k]}]overlay=(W-w)/2:'$baseY':"
              '${gate(p0, p1)}[$out];');
        } else {
          final s = label();
          f.write(_stream(srcs[k], s,
              fromMs: p0,
              toMs: p1,
              unitStartMs: u0,
              passStartMs: passStartMs,
              filters: _fades(p0, p1, u0, u1, w)));
          final off = motion.offsetExpr(_unitT(u0, passStartMs), u1 - u0);
          final y = off == '0' ? baseY : '$baseY+($off)';
          f.write("[$prev][$s]overlay=(W-w)/2:'$y':eof_action=pass:"
              '${gate(p0, p1)}[$out];');
        }
        prev = out;
      }
    }

    // ---- what rides on them, unit by unit ----
    final use = uses(
        units: units,
        motion: motion,
        passStartMs: passStartMs,
        passEndMs: passEndMs);
    // Count each still's uses first: a filter input is read once, so
    // one used several times is split that many ways.
    final threadSpans = <(MotionUnit, MotionRow, (int, int))>[];
    final sparkSpans = <(MotionUnit, MotionRow, (int, int))>[];
    final lightSpans = <int, List<(MotionRow, (int, int))>>{};
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      if (u.endMs <= passStartMs || u.startMs >= passEndMs) continue;
      final w = motion.windowsFor(u.endMs - u.startMs);
      for (final r in u.rows) {
        if (r.progress.points.isEmpty || r.width <= 0) continue;
        if (motion.thread && threadInput != null) {
          final t = _threadSpan(u, r, passStartMs, passEndMs);
          if (t != null) threadSpans.add((u, r, t));
          final s = _sparkSpan(u, r, w, passStartMs, passEndMs);
          if (s != null && sparkInput != null) sparkSpans.add((u, r, s));
        }
        if (motion.light && u.glintInput != null && use.glintUnits.contains(i)) {
          final l = _lightSpan(u, r, passStartMs, passEndMs);
          if (l != null) (lightSpans[i] ??= []).add((r, l));
        }
      }
    }

    // The light, over the letters.
    for (final e in lightSpans.entries) {
      final u = units[e.key];
      final g = u.glintInput!;
      final rows = e.value;
      final w = motion.windowsFor(u.endMs - u.startMs);
      // One copy of the glint per layer, at the layer's strength — a
      // still, so this runs once and not every frame — and each split
      // between the unit's lines.
      const layers = LightLook.layers;
      f.write('[$g:v]format=rgba,split=${layers.length}');
      for (var j = 0; j < layers.length; j++) {
        f.write('[qg${g}_r$j]');
      }
      f.write(';');
      for (var j = 0; j < layers.length; j++) {
        final a = layers[j].$2;
        f.write('[qg${g}_r$j]'
            '${a >= 1 ? 'null' : 'colorchannelmixer=aa=${a.toStringAsFixed(2)}'}'
            ',split=${rows.length}');
        for (var k = 0; k < rows.length; k++) {
          f.write('[qg${g}_l${j}_$k]');
        }
        f.write(';');
      }
      final tu = _unitT(u.startMs, passStartMs);
      final off = motion.offsetExpr(tu, u.endMs - u.startMs);
      for (var k = 0; k < rows.length; k++) {
        final (r, (l0, l1)) = rows[k];
        final top = r.top.floor().clamp(0, math.max(0, u.cardH.floor() - 2));
        final h = math.max(2, math.min(r.bottom.ceil(), u.cardH.floor()) - top);
        final lightEnd = u.startMs + r.progress.endMs;
        for (var j = 0; j < layers.length; j++) {
          final src = 'qg${g}_l${j}_$k';
          final bw = layers[j].$1.round();
          String x(String t) =>
              'max(0,min(${cardW - bw},${r.right.toStringAsFixed(1)}'
              '-(${r.progress.expr(t)})-${(bw / 2).toStringAsFixed(1)}))';
          final s = label();
          f.write(_stream(src, s,
              fromMs: l0,
              toMs: l1,
              unitStartMs: u.startMs,
              passStartMs: passStartMs,
              filters: "crop=w=$bw:h=$h:x='${x('t')}':y=$top,"
                  '${_fades(l0, l1, u.startMs, u.endMs, w, lightEndMs: lightEnd)}'));
          final y = '${(u.cardTop + top).toStringAsFixed(0)}'
              '${off == '0' ? '' : '+($off)'}';
          final out = label();
          f.write("[$prev][$s]overlay=x='${x(tu)}':y='$y':eof_action=pass:"
              '${gate(l0, l1)}[$out];');
          prev = out;
        }
      }
    }

    // The thread, under them.
    if (threadSpans.isNotEmpty) {
      f.write('[$threadInput:v]format=rgba,split=${threadSpans.length}');
      for (var k = 0; k < threadSpans.length; k++) {
        f.write('[qt$k]');
      }
      f.write(';');
      for (var k = 0; k < threadSpans.length; k++) {
        final (u, r, (t0, t1)) = threadSpans[k];
        final w = motion.windowsFor(u.endMs - u.startMs);
        final rw = r.width;
        final s = label();
        f.write(_stream('qt$k', s,
            fromMs: t0,
            toMs: t1,
            unitStartMs: u.startMs,
            passStartMs: passStartMs,
            filters: 'crop=w=$rw:h=${ThreadLook.stripHeight.round()}'
                ":x='${(ThreadLook.half - rw).round()}+${r.progress.expr('t')}'"
                ':y=0,${_fades(t0, t1, u.startMs, u.endMs, w)}'));
        final tu = _unitT(u.startMs, passStartMs);
        final off = motion.offsetExpr(tu, u.endMs - u.startMs);
        final y = '${(u.cardTop + r.threadY - ThreadLook.stripHeight / 2).toStringAsFixed(0)}'
            '${off == '0' ? '' : '+($off)'}';
        final out = label();
        f.write("[$prev][$s]overlay=x=${r.left.round()}:y='$y':"
            'eof_action=pass:${gate(t0, t1)}[$out];');
        prev = out;
      }
    }

    // And the spark at its growing end, over everything.
    if (sparkSpans.isNotEmpty) {
      f.write('[$sparkInput:v]split=${sparkSpans.length}');
      for (var k = 0; k < sparkSpans.length; k++) {
        f.write('[qk$k]');
      }
      f.write(';');
      final half = (SparkLook.size / 2).toStringAsFixed(1);
      for (var k = 0; k < sparkSpans.length; k++) {
        final (u, r, (s0, s1)) = sparkSpans[k];
        final tu = _unitT(u.startMs, passStartMs);
        final off = motion.offsetExpr(tu, u.endMs - u.startMs);
        final x = '${r.right.toStringAsFixed(1)}-(${r.progress.expr(tu)})-$half';
        final y = '${(u.cardTop + r.threadY).toStringAsFixed(1)}-$half'
            '${off == '0' ? '' : '+($off)'}';
        final out = label();
        f.write("[$prev][qk$k]overlay=x='$x':y='$y':${gate(s0, s1)}[$out];");
        prev = out;
      }
    }
    return prev;
  }
}
