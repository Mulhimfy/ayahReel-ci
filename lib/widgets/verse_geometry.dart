import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../data/verse_lines.dart' show TokenTimes;
import '../data/verse_motion.dart';

/// Marks the verse's Arabic paragraph inside a card, so the card's
/// geometry can be read off the real layout rather than re-derived.
///
/// The thread and the light have to land on the letters the card drew.
/// Working out where those are from a copy of the card's style would be
/// a second layout that could drift from the first; reading the
/// laid-out paragraph cannot. The preview reads it live, and the
/// exporter reads it off the card it rasterizes — the same widget.
class VerseTextAnchor extends SingleChildRenderObjectWidget {
  const VerseTextAnchor({super.key, required Widget super.child});

  @override
  RenderVerseAnchor createRenderObject(BuildContext context) =>
      RenderVerseAnchor();
}

class RenderVerseAnchor extends RenderProxyBox {
  /// The first paragraph under the anchor: the verse itself. A card in
  /// a luminous ink draws two copies of it, one over the other, laid
  /// out alike; either is the verse.
  RenderParagraph? get paragraph {
    RenderParagraph? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderParagraph) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final c = child;
    if (c != null) visit(c);
    return found;
  }

  /// The anchor under [root], if any.
  static RenderVerseAnchor? find(RenderObject root) {
    RenderVerseAnchor? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderVerseAnchor) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    visit(root);
    return found;
  }
}

/// One line of a verse as the card laid it out.
@immutable
class VerseRow {
  /// The display tokens on this line, in reading order.
  final List<int> tokens;

  /// Each token's box, in the coordinates of whatever the geometry was
  /// measured against (the card, for the exporter).
  final Map<int, Rect> boxes;

  /// The line's extent: right to left, as the text runs.
  final double left;
  final double right;
  final double top;
  final double bottom;

  const VerseRow({
    required this.tokens,
    required this.boxes,
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;

  /// This line as JSON, exactly: what a card kept on disk keeps of its
  /// layout, so a card reused is placed as the one drawn (see
  /// `AyahRasterizer`).
  Map<String, Object> toJson() => {
        't': tokens,
        'b': [
          for (final k in tokens)
            if (boxes[k] case final r?) [k, r.left, r.top, r.right, r.bottom],
        ],
        'e': [left, right, top, bottom],
      };

  /// [toJson] read back; throws on anything else.
  static VerseRow fromJson(Object? j) {
    final m = j as Map;
    double d(Object? x) => (x as num).toDouble();
    final e = m['e'] as List;
    return VerseRow(
      tokens: [for (final t in m['t'] as List) t as int],
      boxes: {
        for (final b in m['b'] as List)
          (b as List)[0] as int: Rect.fromLTRB(d(b[1]), d(b[2]), d(b[3]), d(b[4])),
      },
      left: d(e[0]),
      right: d(e[1]),
      top: d(e[2]),
      bottom: d(e[3]),
    );
  }

  /// Where the thread runs: just under the letters. A share of the way
  /// down the line's tight box rather than its baseline, because the
  /// box is what every face reports alike.
  double get threadY => top + height * VerseRows.threadShare;

  VerseRow scaled(double s, Offset by) => VerseRow(
        tokens: tokens,
        boxes: {
          for (final e in boxes.entries)
            e.key: Rect.fromLTRB(e.value.left * s + by.dx,
                e.value.top * s + by.dy, e.value.right * s + by.dx,
                e.value.bottom * s + by.dy),
        },
        left: left * s + by.dx,
        right: right * s + by.dx,
        top: top * s + by.dy,
        bottom: bottom * s + by.dy,
      );

  /// This line's progress from word timing: [times] are each token's
  /// window relative to the unit's start (null for a token nothing
  /// timed). Where they carry the recitation's own order (a
  /// [TokenTimes] whose reciter went back over words), it follows that.
  RowProgress progressFromWords(List<(int, int)?> times, int tokenOffset) {
    final recited = times is TokenTimes ? times.recited : null;
    if (recited != null) return _progressRecited(recited, tokenOffset);
    final words = <({int startMs, int endMs, double from, double to})>[];
    for (final k in tokens) {
      final i = k + tokenOffset;
      if (i < 0 || i >= times.length) continue;
      final t = times[i];
      final b = boxes[k];
      if (t == null || b == null) continue;
      words.add((
        startMs: t.$1,
        endMs: t.$2,
        from: (right - b.right).clamp(0.0, width),
        to: (right - b.left).clamp(0.0, width),
      ));
    }
    return RowProgress.words(words, width);
  }

  /// [progressFromWords] where the reciter went back over words, from
  /// the recitation in its order ([TokenTimes.recited], in the unit's
  /// tokens). A stretch on this line's words moves it along them, back
  /// as well as on. While the voice is on words before the line, once it
  /// was reached, the line is back at its start; on words after it, it
  /// is done. Its light shows each time the voice is on it
  /// (RowProgress.visits): a line the voice comes back to lights again.
  RowProgress _progressRecited(
      List<(int, int, int, int)> recited, int tokenOffset) {
    final mine = [for (final k in tokens) k + tokenOffset];
    if (mine.isEmpty) return RowProgress(const [], width);
    final first = mine.first;
    final last = mine.last;
    final pts = <(int, double)>[];
    void add(int t, double v, {bool jump = false}) {
      // Never back in time; a jump back in place is a millisecond's.
      if (pts.isNotEmpty && t <= pts.last.$1) t = pts.last.$1 + 1;
      // A jump (back, or onto the line from elsewhere): it waits where it
      // was, then moves when the voice does, rather than drifting there
      // through the breath before.
      if (jump && pts.isNotEmpty && v != pts.last.$2 && t - pts.last.$1 > 1) {
        pts.add((t - 1, pts.last.$2));
      }
      pts.add((t, v.clamp(0.0, width)));
    }

    final visits = <(int, int)>[];
    int? since; // when the voice came onto the line, while it is on it
    var until = 0; // the end of its last stretch on the line
    var reached = false;
    for (final (a, b, s, e) in recited) {
      final end = e > s ? e : s + 1;
      if (b > first && a <= last) {
        final on = [
          for (final i in mine)
            if (i >= a && i < b) i,
        ];
        final b0 = on.isEmpty ? null : boxes[on.first - tokenOffset];
        final b1 = on.isEmpty ? null : boxes[on.last - tokenOffset];
        if (b0 == null || b1 == null) continue;
        final x = right - b0.right;
        add(s, x,
            jump: since == null || (pts.isNotEmpty && x < pts.last.$2));
        since ??= pts.last.$1;
        add(end, right - b1.left);
        until = pts.last.$1;
        reached = true;
      } else if (reached) {
        if (since != null) {
          visits.add((since, until));
          since = null;
          // On to the next line: this one's last word reaches its far
          // end, as RowProgress.words has it.
          if (a > last && pts.last.$2 < width) {
            pts[pts.length - 1] = (pts.last.$1, width);
          }
        }
        // Back before the line: it is at its start until the voice is
        // on it again.
        if (b <= first && pts.last.$2 > 0) add(s, 0, jump: true);
      }
    }
    if (pts.isEmpty) return RowProgress(const [], width);
    if (since != null) {
      visits.add((since, until));
      if (pts.last.$2 < width) pts[pts.length - 1] = (pts.last.$1, width);
    }
    return RowProgress(pts, width, visits);
  }
}

/// The lines of a verse card, read off its laid-out paragraph.
abstract final class VerseRows {
  /// How far down a line's box the thread sits.
  static const threadShare = 0.80;

  /// The rows of the card under [root], in [root]'s coordinates; empty
  /// when there is no verse in it. [arabic] is the text the card was
  /// given (the verse, or the part of it), whose space-split tokens the
  /// rows are counted in.
  static List<VerseRow> measure(RenderBox root, String arabic) {
    final anchor = RenderVerseAnchor.find(root);
    final p = anchor?.paragraph;
    if (p == null || !p.hasSize) return const [];
    final at = p.localToGlobal(Offset.zero, ancestor: root);
    return of(p, arabic, at);
  }

  /// The rows of [p], offset by [at].
  static List<VerseRow> of(RenderParagraph p, String arabic, Offset at) {
    final tokens = arabic.split(' ');
    final boxes = <int, Rect>{};
    var offset = 0;
    for (var i = 0; i < tokens.length; i++) {
      final len = tokens[i].length;
      if (len > 0) {
        final b = p.getBoxesForSelection(
          TextSelection(baseOffset: offset, extentOffset: offset + len),
          boxHeightStyle: ui.BoxHeightStyle.tight,
        );
        Rect? r;
        for (final x in b) {
          final rect = x.toRect().shift(at);
          r = r == null ? rect : r.expandToInclude(rect);
        }
        if (r != null && r.width > 0) boxes[i] = r;
      }
      offset += len + 1; // the space after it
    }
    return group(boxes);
  }

  /// Tokens grouped into lines by where their boxes sit, each line in
  /// reading order (right to left).
  static List<VerseRow> group(Map<int, Rect> boxes) {
    final keys = boxes.keys.toList()..sort();
    final rows = <List<int>>[];
    for (final k in keys) {
      final c = boxes[k]!.center.dy;
      List<int>? into;
      for (final r in rows) {
        final b = boxes[r.first]!;
        if (c >= b.top && c <= b.bottom) {
          into = r;
          break;
        }
      }
      if (into == null) {
        rows.add([k]);
      } else {
        into.add(k);
      }
    }
    rows.sort((a, b) => boxes[a.first]!.top.compareTo(boxes[b.first]!.top));
    return [
      for (final r in rows)
        VerseRow(
          tokens: r,
          boxes: {for (final k in r) k: boxes[k]!},
          left: r.map((k) => boxes[k]!.left).reduce((a, b) => a < b ? a : b),
          right:
              r.map((k) => boxes[k]!.right).reduce((a, b) => a > b ? a : b),
          top: r.map((k) => boxes[k]!.top).reduce((a, b) => a < b ? a : b),
          bottom:
              r.map((k) => boxes[k]!.bottom).reduce((a, b) => a > b ? a : b),
        ),
    ];
  }

  /// Progress for every row of a unit with no word timing: each line
  /// crossed at an even pace over its share of the letters, inside the
  /// stretch of the unit the voice takes ([fromMs]..[toMs], unit time).
  static List<RowProgress> even(
      List<VerseRow> rows, List<String> tokens, int fromMs, int toMs) {
    int lettersOf(VerseRow r) {
      var n = 0;
      for (final k in r.tokens) {
        if (k < tokens.length) n += _letters(tokens[k]);
      }
      return n < 1 ? 1 : n;
    }

    final counts = [for (final r in rows) lettersOf(r)];
    final total = counts.fold<int>(0, (a, b) => a + b);
    final span = toMs - fromMs;
    final out = <RowProgress>[];
    var done = 0;
    for (var i = 0; i < rows.length; i++) {
      final a = fromMs + span * done ~/ total;
      done += counts[i];
      final b = fromMs + span * done ~/ total;
      out.add(RowProgress.even(a, b, rows[i].width));
    }
    return out;
  }

  static int _letters(String t) => t.runes
      .where((r) =>
          (r >= 0x0621 && r <= 0x064A) ||
          (r >= 0x066E && r <= 0x06D3) ||
          r == 0x06D5)
      .length;

  /// Where the voice runs inside a unit with no word timing, as unit
  /// time: a little in from either end, where the breath around the
  /// recitation usually is.
  static ({int fromMs, int toMs}) voicedIn(int unitMs) {
    final lead = (unitMs * 0.08).round().clamp(0, 250);
    final tail = (unitMs * 0.12).round().clamp(0, 400);
    final to = unitMs - tail;
    return (fromMs: lead, toMs: to > lead ? to : lead + 1);
  }
}
