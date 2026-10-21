import 'package:flutter/foundation.dart';

import 'models.dart';
import 'verse_lines.dart';

/// What a unit's card shows of the recitation over one stretch of time:
/// which of its words are lit, and from which on they wait faint.
///
/// The word highlight lights the word being recited; the trail keeps
/// every recited word lit; the unveil leaves the words not yet reached
/// faint. All three are the same card in a different colour per word,
/// so a unit's whole run is a handful of cards, one per word — exactly
/// what the word highlight has always cost the export.
@immutable
class FollowWindow {
  /// Absolute, in the recording's clock.
  final int startMs;
  final int endMs;

  /// Tokens of the unit's own text (the part's, for a part).
  final ({int start, int end})? lit;
  final int? dimFrom;

  const FollowWindow(this.startMs, this.endMs, this.lit, this.dimFrom);

  /// The plain card: nothing lit, nothing faint.
  bool get isBase => lit == null && dimFrom == null;

  /// Names the card this window draws, for its file.
  String get key => isBase
      ? 'base'
      : 'w${lit == null ? 'x' : '${lit!.start}_${lit!.end}'}'
          '_d${dimFrom ?? 'x'}';

  @override
  bool operator ==(Object other) =>
      other is FollowWindow &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.lit == lit &&
      other.dimFrom == dimFrom;

  @override
  int get hashCode => Object.hash(startMs, endMs, lit, dimFrom);

  @override
  String toString() => 'FollowWindow($startMs-$endMs $key)';
}

abstract final class VerseFollow {
  /// The windows covering [unit], gapless and in order.
  ///
  /// [spans] are the verse's word windows as the highlight plan holds
  /// them: relative to the verse's start, gap-filled, in the verse's own
  /// display tokens. Null, or nothing asked of them, is the one plain
  /// card for the whole unit.
  static List<FollowWindow> of({
    required VerseUnit unit,
    required int verseStartMs,
    required List<HighlightSpan>? spans,
    required bool highlight,
    required bool trail,
    required bool unveil,
  }) {
    final whole = [FollowWindow(unit.startMs, unit.endMs, null, null)];
    if (spans == null || spans.isEmpty || !(highlight || trail || unveil)) {
      return whole;
    }
    final part = unit.part;
    final from = part?.tokenStart ?? 0;
    final to = part?.tokenEnd ?? 1 << 30;
    final inUnit = <(int, int, int, int)>[];
    for (final s in spans) {
      if (s.tokenStart < from || s.tokenEnd > to) continue;
      final a = (verseStartMs + s.startMs).clamp(unit.startMs, unit.endMs);
      final b = (verseStartMs + s.endMs).clamp(unit.startMs, unit.endMs);
      if (b <= a) continue;
      inUnit.add((a, b, s.tokenStart - from, s.tokenEnd - from));
    }
    if (inUnit.isEmpty) return whole;

    ({int start, int end})? litFor(int s, int e) {
      if (trail) return (start: 0, end: e);
      if (highlight) return (start: s, end: e);
      return null;
    }

    final out = <FollowWindow>[];
    void add(int a, int b, ({int start, int end})? lit, int? dim) {
      if (out.isNotEmpty && a < out.last.endMs) a = out.last.endMs;
      if (b <= a) return;
      if (out.isNotEmpty) {
        final last = out.last;
        // Touching windows that draw the same card are one window.
        if (last.endMs == a && last.lit == lit && last.dimFrom == dim) {
          out[out.length - 1] = FollowWindow(last.startMs, b, lit, dim);
          return;
        }
      }
      out.add(FollowWindow(a, b, lit, dim));
    }

    // Before the first word: nothing lit yet, and everything still
    // waiting for the unveil.
    add(unit.startMs, inUnit.first.$1, null, unveil ? 0 : null);
    for (var i = 0; i < inUnit.length; i++) {
      final (a, b, s, e) = inUnit[i];
      // A gap between two windows (a word the alignment dropped) holds
      // what the window before it showed rather than flashing the plain
      // card.
      final end = i + 1 < inUnit.length ? inUnit[i + 1].$1 : unit.endMs;
      add(a, end > b ? end : b, litFor(s, e), unveil ? e : null);
    }
    return out;
  }

  /// The window at [ms], or the last when [ms] has run past.
  static FollowWindow at(List<FollowWindow> windows, int ms) {
    for (final w in windows) {
      if (ms < w.endMs) return w;
    }
    return windows.last;
  }
}
