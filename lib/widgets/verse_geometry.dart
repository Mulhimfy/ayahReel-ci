import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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
  /// timed).
  RowProgress progressFromWords(List<(int, int)?> times, int tokenOffset) {
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
