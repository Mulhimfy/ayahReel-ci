import 'package:flutter/foundation.dart';

import 'models.dart';

/// How a reel shows a verse too long to sit in the frame at full size.
///
/// [whole] is the original behaviour: the verse is shown at once and
/// shrinks to fit. Any other value is the most lines of it on screen at
/// a time: the verse is cut into parts that each fit that many lines,
/// and each part shows while the reciter reads it.
///
/// Only verses that need it are cut. A verse that fits in that many
/// lines is shown whole either way, and so is a verse whose cuts could
/// not be timed to the recitation (see [PartTiming]): a part that
/// changed in the middle of a word would be worse than a small verse.
abstract final class VerseLines {
  static const whole = 0;

  /// The choices offered, after [whole].
  static const choices = [1, 2, 3];

  /// What "line by line" starts on.
  static const preferred = 2;

  static int clamp(int v) => v < 0 ? 0 : (v > 3 ? 3 : v);
}

/// The pause signs a mushaf prints over the text, as the Uthmani text
/// this app shows carries them: each its own space-separated token,
/// after the word it belongs to.
///
/// [cutCost] is how much a part ending there costs the splitter: the
/// signs that ask for a stop are where a verse reads best cut, and the
/// reciter almost always breathes at them, which is what lets a cut be
/// timed to the recitation. "Do not stop here" is the worst place short
/// of the middle of a phrase.
enum PauseMark {
  /// م — a stop is required.
  mustStop(0x06D8, 0),

  /// قلى — stopping is better.
  better(0x06D7, 0),

  /// ج — a stop is allowed.
  allowed(0x06DA, 2),

  /// صلى — carrying on is better, a stop is allowed.
  carryOn(0x06D6, 6),

  /// ∴ — stop at one of the pair, not both.
  paired(0x06DB, 10),

  /// س — a brief pause without a breath.
  saktah(0x06DC, 30),

  /// لا — do not stop here.
  never(0x06D9, 90);

  const PauseMark(this.codePoint, this.cutCost);

  final int codePoint;
  final double cutCost;

  static PauseMark? of(int rune) {
    for (final m in values) {
      if (m.codePoint == rune) return m;
    }
    return null;
  }
}

/// What the splitter needs to know about the verse's space-split tokens.
abstract final class VerseText {
  /// ۞ — the hizb sign opens the word after it.
  static const _hizb = 0x06DE;

  static List<String> tokens(String arabic) => arabic.split(' ');

  static bool _isLetter(int r) =>
      (r >= 0x0621 && r <= 0x064A) ||
      (r >= 0x066E && r <= 0x06D3) ||
      r == 0x06D5;

  /// Whether [token] carries at least one Arabic letter — a word, as
  /// opposed to a pause sign or an ornament.
  static bool isWord(String token) => token.runes.any(_isLetter);

  /// The pause sign at the end of [token], if it has one: a bare sign,
  /// or a word the sign was written onto.
  static PauseMark? pauseAfter(String token) {
    final runes = token.runes.toList();
    for (var i = runes.length - 1; i >= 0; i--) {
      final m = PauseMark.of(runes[i]);
      if (m != null) return m;
      // Only marks and joiners may sit after the sign.
      if (_isLetter(runes[i])) return null;
    }
    return null;
  }

  /// Whether [token] belongs to the word after it rather than before.
  static bool opensNext(String token) =>
      !isWord(token) && token.runes.contains(_hizb);

  /// Arabic letters in [token]: what a part's share of the recitation is
  /// estimated from when no word timing says otherwise.
  static int letters(String token) => token.runes.where(_isLetter).length;
}

/// Where a long verse is cut.
///
/// Pure: what fits is asked of a callback, so this knows nothing about
/// fonts and can be tested with a fake one. The real one lays the part
/// out exactly as the verse card will (see `VerseGeometry`).
abstract final class VerseSplitter {
  /// Every part costs this much, so fewer parts always win unless the
  /// cuts they force are bad ones.
  static const partCost = 100.0;

  /// A cut between two words with no pause sign over them: half a part.
  /// A phrase cut in two reads worse than one more part does, and where
  /// a voice has no word timing such a cut has no breath to be timed to.
  static const plainCutCost = 50.0;

  /// A part of a single word, in a verse of more than two.
  static const orphanCost = 60.0;

  /// How much an uneven part costs, per its distance from an even share.
  static const balanceWeight = 25.0;

  /// Whether the verse may be cut before token [at]. Never inside an
  /// aligned group of words ([held]), never so that a part opens on a
  /// pause sign (it belongs to the word before it), and never between
  /// ۞ and its word.
  static bool canCutAt(List<String> tokens, int at, Set<int> held) {
    if (at <= 0 || at >= tokens.length) return false;
    if (held.contains(at)) return false;
    final next = tokens[at];
    if (!VerseText.isWord(next) && !VerseText.opensNext(next)) return false;
    if (VerseText.opensNext(tokens[at - 1])) return false;
    return true;
  }

  static double cutCost(List<String> tokens, int at,
          {double plain = plainCutCost}) =>
      VerseText.pauseAfter(tokens[at - 1])?.cutCost ?? plain;

  /// The cut positions — 0, then each token a new part opens on, then
  /// [tokens].length — or null when the verse fits whole.
  ///
  /// [fits] answers whether tokens `[start, end)` fit as one part; an
  /// `end` of [tokens].length is the verse's last part, which carries
  /// the verse-end sign when there is one. It must not get *more*
  /// likely to fit as `end` grows, apart from that last step.
  ///
  /// [plainCost] is what a cut with no pause sign costs; a caller that
  /// can only time cuts by the reciter's breaths makes it dearer.
  static List<int>? split(
    List<String> tokens,
    bool Function(int start, int end) fits, {
    Set<int> held = const {},
    double plainCost = plainCutCost,
  }) {
    final n = tokens.length;
    if (n < 2) return null;
    final memo = <int, bool>{};
    bool ok(int s, int e) => memo.putIfAbsent(s * 4096 + e, () => fits(s, e));
    if (ok(0, n)) return null;

    final cuts = [
      for (var k = 1; k < n; k++)
        if (canCutAt(tokens, k, held)) k,
    ];
    if (cuts.isEmpty) return null;
    final ends = [...cuts, n];

    // The furthest end a part opening at [s] can run to.
    int reach(int s) {
      if (ok(s, n)) return n;
      final first = ends.indexWhere((e) => e > s);
      // Binary search over the cut positions before the verse's end.
      var lo = first, hi = ends.length - 2, best = -1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (ok(s, ends[mid])) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      // Not even one word fits: take it anyway, a part has to hold
      // something.
      return best >= 0 ? ends[best] : ends[first];
    }

    final letters = [for (final t in tokens) VerseText.letters(t)];
    final words = [for (final t in tokens) VerseText.isWord(t) ? 1 : 0];
    final sumLetters = List<int>.filled(n + 1, 0);
    final sumWords = List<int>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      sumLetters[i + 1] = sumLetters[i] + letters[i];
      sumWords[i + 1] = sumWords[i] + words[i];
    }
    final totalWords = sumWords[n];

    // The fewest parts there can be, which is what an even share is a
    // share of.
    var fewest = 0;
    for (var s = 0; s < n;) {
      s = reach(s);
      fewest++;
    }
    final ideal = sumLetters[n] / (fewest < 1 ? 1 : fewest);

    double partCostOf(int s, int e) {
      final l = sumLetters[e] - sumLetters[s];
      var c = partCost +
          (ideal <= 0 ? 0 : balanceWeight * (l - ideal).abs() / ideal);
      if (sumWords[e] - sumWords[s] <= 1 && totalWords > 2) c += orphanCost;
      return c;
    }

    final starts = [0, ...cuts];
    final best = <int, double>{n: 0};
    final next = <int, int>{};
    for (var i = starts.length - 1; i >= 0; i--) {
      final s = starts[i];
      final far = reach(s);
      var bestCost = double.infinity;
      var bestEnd = -1;
      for (final e in ends) {
        if (e <= s) continue;
        if (e > far) break;
        final rest = best[e];
        if (rest == null) continue;
        final c = partCostOf(s, e) +
            (e < n ? cutCost(tokens, e, plain: plainCost) : 0) +
            rest;
        if (c < bestCost) {
          bestCost = c;
          bestEnd = e;
        }
      }
      if (bestEnd >= 0) {
        best[s] = bestCost;
        next[s] = bestEnd;
      }
    }
    if (!next.containsKey(0)) return null;
    final out = [0];
    var at = 0;
    while (at < n) {
      at = next[at]!;
      out.add(at);
    }
    return out.length > 2 ? out : null;
  }
}

/// When each part of a cut verse comes on screen.
///
/// Two ways in, both ending on the moment the reciter finishes a part's
/// last word: word timing where the voice has it, and the recitation's
/// own pauses where it does not. A cut neither can place is no cut at
/// all, and the verse is shown whole.
abstract final class PartTiming {
  /// No part shorter than this on screen.
  static const minPartMs = 700;

  /// After the reciter finishes a part, it stays this share of the
  /// breath that follows, so the eye sees it complete — and never longer
  /// than [lingerMs].
  static const lingerShare = 0.4;
  static const lingerMs = 280;

  /// The boundaries of each part, absolute — the verse's own start, each
  /// cut, the verse's own end — from word timing.
  ///
  /// [times] holds each token's recited window, relative to the verse's
  /// start; null for a token nothing timed (a pause sign, or a word the
  /// alignment dropped).
  static List<int>? fromWords({
    required List<int> cuts,
    required List<(int, int)?> times,
    required int verseStartMs,
    required int verseEndMs,
  }) {
    final out = [verseStartMs];
    for (var c = 1; c < cuts.length - 1; c++) {
      final at = cuts[c];
      int? lastEnd;
      for (var k = at - 1; k >= cuts[c - 1]; k--) {
        final t = times[k];
        if (t != null) {
          lastEnd = t.$2;
          break;
        }
      }
      int? nextStart;
      for (var k = at; k < cuts[c + 1]; k++) {
        final t = times[k];
        if (t != null) {
          nextStart = t.$1;
          break;
        }
      }
      if (lastEnd == null || nextStart == null) return null;
      final gap = nextStart - lastEnd;
      final linger = gap <= 0
          ? 0
          : (gap * lingerShare).round().clamp(0, lingerMs);
      final t = verseStartMs + (gap < 0 ? nextStart : lastEnd + linger);
      out.add(t);
    }
    out.add(verseEndMs);
    return _checked(out);
  }

  /// The same from the recitation's pauses, for a voice with no word
  /// timing: each cut is placed where the letters before it put it
  /// within the verse's voiced stretch, then moved to the reciter's
  /// nearest real pause. Null when any cut has no pause near enough.
  ///
  /// [pauses] are absolute (from, to) windows of quiet, at least a
  /// breath long. [voicedStartMs]..[voicedEndMs] is where the verse is
  /// actually recited inside its window, when that is known.
  static List<int>? fromPauses({
    required List<int> cuts,
    required List<int> letters,
    required int verseStartMs,
    required int verseEndMs,
    required List<(int, int)> pauses,
    int? voicedStartMs,
    int? voicedEndMs,
  }) {
    final v0 = voicedStartMs ?? verseStartMs;
    final v1 = voicedEndMs ?? verseEndMs;
    if (v1 <= v0) return null;
    final total = letters.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return null;
    int lettersBefore(int at) {
      var n = 0;
      for (var k = 0; k < at && k < letters.length; k++) {
        n += letters[k];
      }
      return n;
    }

    final estimate = [
      for (final c in cuts) v0 + (v1 - v0) * lettersBefore(c) / total,
    ];
    final out = [verseStartMs];
    for (var c = 1; c < cuts.length - 1; c++) {
      final e = estimate[c];
      final shortest = [
        estimate[c] - estimate[c - 1],
        estimate[c + 1] - estimate[c],
      ].reduce((a, b) => a < b ? a : b);
      final reachMs = (shortest * 0.35).clamp(500.0, 2200.0);
      final floor = out.last + minPartMs;
      final ceiling = verseEndMs - minPartMs;
      (int, int)? pick;
      var pickScore = double.infinity;
      for (final p in pauses) {
        final mid = (p.$1 + p.$2) / 2;
        if ((mid - e).abs() > reachMs) continue;
        final at = _cutIn(p);
        if (at < floor || at > ceiling) continue;
        final len = (p.$2 - p.$1).toDouble();
        final score =
            (mid - e).abs() / reachMs - 0.25 * (len / 700).clamp(0.0, 1.0);
        if (score < pickScore) {
          pickScore = score;
          pick = p;
        }
      }
      if (pick == null) return null;
      out.add(_cutIn(pick));
    }
    out.add(verseEndMs);
    return _checked(out);
  }

  /// Where in a pause the part changes: just after the reciter stops.
  static int _cutIn((int, int) p) {
    final len = p.$2 - p.$1;
    return p.$1 + (len ~/ 2 < 160 ? len ~/ 2 : 160);
  }

  static List<int>? _checked(List<int> b) {
    for (var i = 1; i < b.length; i++) {
      if (b[i] - b[i - 1] < minPartMs) return null;
    }
    return b;
  }

  /// The quiet stretches inside `[fromMs, toMs)` of a loudness envelope
  /// in 10 ms steps, as absolute windows; and where the voice starts and
  /// stops inside it. [quiet] is the level at or below which it counts
  /// as silent, [minMs] the shortest pause that counts as a breath.
  static ({List<(int, int)> pauses, int? voicedStart, int? voicedEnd})
      pausesIn(List<double> env, double quiet, int fromMs, int toMs,
          {int minMs = 200}) {
    final lo = (fromMs / 10).floor().clamp(0, env.length);
    final hi = (toMs / 10).ceil().clamp(0, env.length);
    final pauses = <(int, int)>[];
    int? runFrom;
    int? first;
    int? last;
    for (var k = lo; k <= hi; k++) {
      final silent = k >= hi || env[k] <= quiet;
      if (k < hi && !silent) {
        first ??= k;
        last = k;
      }
      if (silent && k < hi) {
        runFrom ??= k;
      } else if (runFrom != null) {
        if ((k - runFrom) * 10 >= minMs) pauses.add((runFrom * 10, k * 10));
        runFrom = null;
      }
    }
    return (
      pauses: pauses,
      voicedStart: first == null ? null : first * 10,
      voicedEnd: last == null ? null : (last + 1) * 10,
    );
  }
}

/// Cuts a translation to go with the parts of its verse.
///
/// A translation's words don't line up with the Arabic's, so each piece
/// takes the share of the text its part takes of the verse, moved to
/// the nearest punctuation when there is some close by, and to the
/// nearest space when there is not — never inside brackets, where the
/// translators put their glosses.
abstract final class TranslationSplit {
  static const _stops = {
    ',', ';', ':', '.', '!', '?', '—', '–', '،', '؛', '۔', '؟', ')', ']', '"',
    '”', '’', '»',
  };

  /// [text] in `at.length + 1` pieces; [at] are the cumulative shares
  /// of the verse where each new part begins, ascending in (0, 1).
  static List<String> split(String text, List<double> at) {
    final t = text.trim();
    if (at.isEmpty) return [t];
    if (t.isEmpty) return List.filled(at.length + 1, '');
    // Every space outside brackets is somewhere a piece may end.
    final spaces = <int>[];
    final strong = <int>{};
    var depth = 0;
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (ch == '(' || ch == '[') depth++;
      if ((ch == ')' || ch == ']') && depth > 0) depth--;
      if (ch == ' ' && depth == 0 && i > 0) {
        spaces.add(i);
        if (_stops.contains(t[i - 1])) strong.add(i);
      }
    }
    if (spaces.isEmpty) {
      return [t, for (var i = 0; i < at.length; i++) ''];
    }
    final reach = (t.length / (at.length + 1) * 0.3).clamp(12.0, 80.0);
    final picks = <int>[];
    var floor = 0;
    for (final f in at) {
      final target = f * t.length;
      int? best;
      var bestD = double.infinity;
      // Punctuation within reach first.
      for (final s in strong) {
        if (s <= floor) continue;
        final d = (s - target).abs();
        if (d <= reach && d < bestD) {
          best = s;
          bestD = d;
        }
      }
      if (best == null) {
        for (final s in spaces) {
          if (s <= floor) continue;
          final d = (s - target).abs();
          if (d < bestD) {
            best = s;
            bestD = d;
          }
        }
      }
      if (best == null) break;
      picks.add(best);
      floor = best;
    }
    final out = <String>[];
    var from = 0;
    for (final p in picks) {
      out.add(t.substring(from, p).trim());
      from = p;
    }
    out.add(t.substring(from).trim());
    while (out.length < at.length + 1) {
      out.add('');
    }
    return out;
  }
}

/// One part of a verse cut by [VerseSplitter], timed by [PartTiming].
@immutable
class VersePart {
  final int ayah;

  /// Which part, from 0, of [count].
  final int index;
  final int count;

  /// The display tokens of the verse's Arabic this part holds.
  final int tokenStart;
  final int tokenEnd;

  /// On screen from..to, absolute in the recording's clock.
  final int startMs;
  final int endMs;

  /// The part's own Arabic and its share of the translation.
  final String arabic;
  final String translation;

  /// The size factor every part of this verse is set at, so the type
  /// does not change size from one part to the next.
  final double fit;

  /// The height of the tallest part of this verse's card at 1080 wide,
  /// which every part is held to; 0 before it has been measured.
  final double height;

  const VersePart({
    required this.ayah,
    required this.index,
    required this.count,
    required this.tokenStart,
    required this.tokenEnd,
    required this.startMs,
    required this.endMs,
    required this.arabic,
    required this.translation,
    required this.fit,
    this.height = 0,
  });

  VersePart withHeight(double h) => VersePart(
        ayah: ayah,
        index: index,
        count: count,
        tokenStart: tokenStart,
        tokenEnd: tokenEnd,
        startMs: startMs,
        endMs: endMs,
        arabic: arabic,
        translation: translation,
        fit: fit,
        height: h,
      );

  bool get isFirst => index == 0;
  bool get isLast => index == count - 1;
  int get durationMs => endMs - startMs;

  @override
  bool operator ==(Object other) =>
      other is VersePart &&
      other.ayah == ayah &&
      other.index == index &&
      other.count == count &&
      other.tokenStart == tokenStart &&
      other.tokenEnd == tokenEnd &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.arabic == arabic &&
      other.translation == translation &&
      other.fit == fit &&
      other.height == height;

  @override
  int get hashCode => Object.hash(ayah, index, count, tokenStart, tokenEnd,
      startMs, endMs, arabic, translation, fit, height);

  @override
  String toString() => 'VersePart($ayah.$index/$count tokens '
      '$tokenStart-$tokenEnd, $startMs-$endMs)';
}

/// Which verses of a reel are cut, and how. Verses absent from it are
/// shown whole.
@immutable
class VerseLinePlan {
  /// The most lines on screen at a time this was planned for.
  final int lines;
  final Map<int, List<VersePart>> byAyah;

  const VerseLinePlan(this.lines, this.byAyah);

  static const empty = VerseLinePlan(VerseLines.whole, {});

  bool get isEmpty => byAyah.isEmpty;

  List<VersePart>? partsOf(int ayah) => byAyah[ayah];

  int get partCount =>
      byAyah.values.fold<int>(0, (n, parts) => n + parts.length);

  /// Stable across runs (unlike [Object.hash]), for the render's cache
  /// key: the same cuts at the same times are the same reel.
  String get fingerprint {
    if (byAyah.isEmpty) return '';
    var h = 0x811c9dc5;
    void mix(int v) {
      h = ((h ^ (v & 0xFFFFFFFF)) * 0x01000193) & 0xFFFFFFFF;
    }

    final ayahs = byAyah.keys.toList()..sort();
    mix(lines);
    for (final a in ayahs) {
      for (final p in byAyah[a]!) {
        mix(a);
        mix(p.tokenStart);
        mix(p.tokenEnd);
        mix(p.startMs);
        mix(p.endMs);
        mix((p.fit * 1000).round());
        mix(p.height.round());
        for (final c in p.translation.codeUnits) {
          mix(c);
        }
      }
    }
    return h.toRadixString(36);
  }

  @override
  bool operator ==(Object other) =>
      other is VerseLinePlan &&
      other.lines == lines &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(lines, fingerprint);
}

/// One thing on screen in turn: a whole verse, or one part of a cut one.
/// Scenes can change on these (see `ScenePlan`), and the motion runs on
/// them (see `VerseMotion`).
@immutable
class VerseUnit {
  final int ayah;

  /// Null for a verse shown whole.
  final VersePart? part;
  final int startMs;
  final int endMs;

  const VerseUnit(this.ayah, this.part, this.startMs, this.endMs);

  int get durationMs => endMs - startMs;

  /// [verseTimes] — each of the verse's tokens' recited windows, in ms
  /// from the verse's start — as this unit's own: its tokens only, in
  /// ms from the unit's start. Null without word timing.
  List<(int, int)?>? timesIn(List<(int, int)?>? verseTimes, int verseStartMs) {
    if (verseTimes == null) return null;
    final from = part?.tokenStart ?? 0;
    final to = part?.tokenEnd ?? verseTimes.length;
    final shift = verseStartMs - startMs;
    return [
      for (var k = from; k < to && k < verseTimes.length; k++)
        verseTimes[k] == null
            ? null
            : (verseTimes[k]!.$1 + shift, verseTimes[k]!.$2 + shift),
    ];
  }

  /// The verse's units over `[startAyah, endAyah]`, in order and gapless.
  static List<VerseUnit> of(
    Recitation rec,
    int startAyah,
    int endAyah,
    VerseLinePlan? plan,
  ) {
    final out = <VerseUnit>[];
    for (var a = startAyah; a <= endAyah; a++) {
      final parts = plan?.partsOf(a);
      if (parts == null || parts.isEmpty) {
        final t = rec.timing(a);
        out.add(VerseUnit(a, null, t.startMs, t.endMs));
      } else {
        for (final p in parts) {
          out.add(VerseUnit(a, p, p.startMs, p.endMs));
        }
      }
    }
    return out;
  }

  /// The unit on screen at [ms], or the last when it has run past.
  static int indexAt(List<VerseUnit> units, int ms) {
    for (var i = 0; i < units.length; i++) {
      if (ms < units[i].endMs) return i;
    }
    return units.length - 1;
  }
}
