import 'dart:math' as math;

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

  /// What "line by line" starts on, and what a new install has: one
  /// line at a time, the largest the verse is ever set.
  static const preferred = 1;

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

  /// لا — do not stop here. Dearer than a phrase cut in two: the
  /// reciter carries straight on, and the meaning with them.
  never(0x06D9, 300);

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

  /// [token]'s letters alone, spelled plainly: the hamza seats and the
  /// wasla as alif, the alif maqsura as ya, every mark and tatweel gone.
  static String bare(String token) {
    final out = StringBuffer();
    for (final r in token.runes) {
      // Tatweel and the dagger alif sit inside the letter ranges.
      if (!_isLetter(r) || r == 0x0640 || r == 0x0670) continue;
      out.writeCharCode(switch (r) {
        0x0622 || 0x0623 || 0x0625 || 0x0671 => 0x0627,
        0x0649 => 0x064A,
        _ => r,
      });
    }
    return out.toString();
  }

  /// The particles that belong to the word after them, spelled [bare].
  static const _binding = {
    'لا', 'ما', 'من', 'في', 'علي', 'الي', 'الا', 'ان', 'قد', 'لم', 'لن', //
    'يا', 'عن', 'او', 'ثم', 'بل', 'كي', 'لكن', 'اذا', 'اذ', 'حتي', 'يايها',
    'لما', 'كما', 'مما', 'ممن', 'عما', 'بما', 'لمن', 'فيما', 'الذي',
    'الذين', 'التي', 'لو', 'ليس', 'كل', 'هل',
  };

  /// Whether [token] is a particle — with or without the و or ف before
  /// it — that a line should not end on.
  static bool bindsToNext(String token) {
    final b = bare(token);
    if (_binding.contains(b)) return true;
    return b.length > 2 &&
        (b.startsWith('و') || b.startsWith('ف')) &&
        _binding.contains(b.substring(1));
  }

  /// Whether [token] opens a clause: فَ before its word — "then", "so",
  /// the answer to a condition — or ثُمَّ. Not وَ, which as often joins
  /// "the heavens and the earth" as it opens anything.
  static bool opensClause(String token) {
    final r = token.runes.toList();
    if (r.length >= 2 && r[0] == 0x0641 && r[1] == 0x064E) return true;
    return bare(token) == 'ثم';
  }
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

  /// A cut between two words with no pause sign over them: more than a
  /// part. A line that holds half a phrase says half a thing — with one
  /// line at a time it is alone on the screen — and a verse reads better
  /// in one more line cut at its pause signs. Where a voice has no word
  /// timing such a cut has no breath to be timed to, either. When there
  /// is no avoiding one, [cutCost] picks where it hurts least.
  static const plainCutCost = 180.0;

  /// What a cut with no sign costs, as a share of [plainCutCost], before
  /// the فَ or ثُمَّ that opens a clause — a phrase boundary the mushaf
  /// does not mark, cheaper than one more part — and after a particle
  /// that belongs to the word after it, which leaves a line waiting
  /// for its next word.
  static const clauseShare = 0.3;
  static const particleShare = 2.5;

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
      {double plain = plainCutCost}) {
    final mark = VerseText.pauseAfter(tokens[at - 1]);
    if (mark != null) return mark.cutCost;
    // No sign: least bad before the فَ or ثُمَّ that opens a clause, worst
    // after a particle that belongs to the word after it — a line that
    // ends on "and what" or "in" is waiting for its next word.
    if (VerseText.bindsToNext(tokens[at - 1])) return plain * particleShare;
    if (VerseText.opensClause(tokens[at])) return plain * clauseShare;
    return plain;
  }

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
  /// What a cut costs, as a share of what it would, where the reciter
  /// was heard to breathe ([split]'s `breaths`): a cut a voice with no
  /// word timing can actually be timed to.
  static const breathShare = 0.4;

  static List<int>? split(
    List<String> tokens,
    bool Function(int start, int end) fits, {
    Set<int> held = const {},
    double plainCost = plainCutCost,
    Set<int> breaths = const {},
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
            (e < n
                ? cutCost(tokens, e, plain: plainCost) *
                    (breaths.contains(e) ? breathShare : 1)
                : 0) +
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

  /// The same for a voice with no word timing, taking every breath the
  /// recording shows ([breathsIn]) and, where a cut has none near it,
  /// placing it all the same: at the quietest moment around where its
  /// letters put it, which is the gap between two words far more often
  /// than the middle of one. So a verse that needs cutting is cut, rather
  /// than shown whole for want of a breath — the reciter's breath where
  /// there is one, the best guess where there is not. [guessed] is how
  /// many cuts had to be guessed.
  ///
  /// Null only when the verse can't be cut at all: no voice in it, or a
  /// part that would be on screen for less than [minPartMs].
  static ({List<int> bounds, int guessed})? fromBreaths({
    required List<int> cuts,
    required List<int> letters,
    required int verseStartMs,
    required int verseEndMs,
    required List<(int, int)> breaths,
    required List<double> env,
    int? voicedStartMs,
    int? voicedEndMs,
  }) {
    final v0 = voicedStartMs ?? verseStartMs;
    final v1 = voicedEndMs ?? verseEndMs;
    if (v1 <= v0) return null;
    final total = letters.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return null;
    final before = List<int>.filled(letters.length + 1, 0);
    for (var k = 0; k < letters.length; k++) {
      before[k + 1] = before[k] + letters[k];
    }
    double estimateAt(int cut) =>
        v0 + (v1 - v0) * before[cut.clamp(0, letters.length)] / total;
    final estimate = [for (final c in cuts) estimateAt(c)];
    final out = [verseStartMs];
    var guessed = 0;
    for (var c = 1; c < cuts.length - 1; c++) {
      final e = estimate[c];
      final shortest = math.min(
          estimate[c] - estimate[c - 1], estimate[c + 1] - estimate[c]);
      final reachMs = (shortest * 0.35).clamp(500.0, 2200.0);
      final floor = out.last + minPartMs;
      final ceiling = verseEndMs - minPartMs;
      (int, int)? pick;
      var pickScore = double.infinity;
      for (final p in breaths) {
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
      if (pick != null) {
        out.add(_cutIn(pick));
        continue;
      }
      // No breath near it: the quietest moment within a few hundred
      // milliseconds of the estimate, inside what the parts allow.
      final lo = math.max(floor, (e - quietReachMs).round());
      final hi = math.min(ceiling, (e + quietReachMs).round());
      if (hi < lo) return null;
      var at = e.round().clamp(lo, hi);
      var level = double.infinity;
      for (var k = lo ~/ 10; k * 10 <= hi && k < env.length; k++) {
        if (k * 10 < lo || k < 0) continue;
        if (env[k] < level) {
          level = env[k];
          at = k * 10;
        }
      }
      out.add(at);
      guessed++;
    }
    out.add(verseEndMs);
    final checked = _checked(out);
    return checked == null ? null : (bounds: checked, guessed: guessed);
  }

  /// How far either side of a cut's estimate [fromBreaths] looks for the
  /// quietest moment, when no breath is near enough to take.
  static const quietReachMs = 420;

  /// Every breath a reciter takes inside `[fromMs, toMs)`: the pauses,
  /// where the recording goes quiet ([pausesIn]), and the dips, where in a
  /// recording too reverberant to go quiet the level still falls well
  /// under the stretch around it ([dipsIn]). Absolute windows, in order,
  /// none overlapping a pause.
  static List<(int, int)> breathsIn(
      List<double> env, double quiet, int fromMs, int toMs) {
    final pauses = pausesIn(env, quiet, fromMs, toMs).pauses;
    final out = [...pauses];
    for (final d in dipsIn(env, fromMs, toMs)) {
      if (pauses.any((p) => d.$1 < p.$2 && p.$1 < d.$2)) continue;
      out.add(d);
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  /// How far under the level around it a dip has to fall, in dB, and for
  /// how long: a breath in an echoing hall, not the space between two
  /// syllables. The level around it is the mean over [dipAroundMs] either
  /// side.
  static const dipDb = 9.0;
  static const dipMs = 90;
  static const dipAroundMs = 350;

  /// The dips of [env] inside `[fromMs, toMs)`: see [breathsIn].
  static List<(int, int)> dipsIn(List<double> env, int fromMs, int toMs) {
    final lo = (fromMs / 10).floor().clamp(0, env.length);
    final hi = (toMs / 10).ceil().clamp(lo, env.length);
    const around = dipAroundMs ~/ 10;
    if (hi - lo < 2 * around) return const [];
    final sums = List<double>.filled(hi - lo + 1, 0);
    for (var k = lo; k < hi; k++) {
      sums[k - lo + 1] = sums[k - lo] + env[k];
    }
    final out = <(int, int)>[];
    int? from;
    for (var k = lo; k <= hi; k++) {
      var low = false;
      if (k < hi) {
        final a = math.max(lo, k - around), b = math.min(hi, k + around + 1);
        final mean = (sums[b - lo] - sums[a - lo]) / (b - a);
        low = env[k] <= mean - dipDb;
      }
      if (low) {
        from ??= k;
      } else if (from != null) {
        if ((k - from) * 10 >= dipMs) out.add((from * 10, k * 10));
        from = null;
      }
    }
    return out;
  }

  /// The token positions a cut could open on that fall at one of
  /// [breaths], by where the letters before them put them inside the
  /// voiced stretch `[voicedStartMs, voicedEndMs)`: what [VerseSplitter]
  /// is told to prefer for a voice with no word timing, so its cuts land
  /// where the reciter can be heard to breathe.
  static Set<int> cutsAtBreaths({
    required List<int> letters,
    required List<(int, int)> breaths,
    required int voicedStartMs,
    required int voicedEndMs,
  }) {
    final total = letters.fold<int>(0, (a, b) => a + b);
    final span = voicedEndMs - voicedStartMs;
    if (total <= 0 || span <= 0) return const {};
    final out = <int>{};
    for (final p in breaths) {
      final mid = (p.$1 + p.$2) / 2;
      if (mid <= voicedStartMs || mid >= voicedEndMs) continue;
      final want = (mid - voicedStartMs) / span * total;
      var best = -1;
      var bestGap = double.infinity;
      var n = 0;
      for (var k = 1; k < letters.length; k++) {
        n += letters[k - 1];
        final gap = (n - want).abs();
        if (gap < bestGap) {
          bestGap = gap;
          best = k;
        }
      }
      // Within an eighth of the verse's letters of where it was heard.
      if (best > 0 && bestGap <= total / 8) out.add(best);
    }
    return out;
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

  /// What ends a sentence, in every edition's script.
  static const _sentenceEnders = {'.', '!', '?', ';', '؛', '۔', '؟'};

  /// Words a piece should not end on, in the editions' languages: the
  /// articles, prepositions, conjunctions and auxiliaries that belong to
  /// the word after them.
  static const _dangling = {
    // English
    'a', 'an', 'the', 'of', 'in', 'on', 'at', 'to', 'by', 'for', 'from',
    'with', 'and', 'or', 'but', 'as', 'that', 'than', 'into', 'upon',
    'over', 'his', 'her', 'their', 'its', 'our', 'your', 'my', 'is', 'are',
    'was', 'were', 'be', 'has', 'have', 'had', 'who', 'which', 'whom',
    'whose', 'not', 'no', 'will', 'shall',
    // German
    'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen',
    'einem', 'einer', 'und', 'oder', 'zu', 'im', 'mit', 'von', 'vom',
    'auf', 'am', 'für', 'aus', 'bei', 'nach', 'über', 'unter', 'ist',
    'sind', 'hat', 'haben', 'wer', 'nicht', 'kein', 'keine',
    // Indonesian
    'di', 'ke', 'dari', 'yang', 'dan', 'atau', 'dengan', 'untuk', 'pada',
    'kepada', 'dalam', 'tidak', 'adalah',
    // Urdu
    'کے', 'کی', 'کا', 'میں', 'سے', 'اور', 'کو', 'پر', 'نے', 'جو', 'یا',
  };

  /// Whether the word before the space at [i] in [t] is [_dangling].
  static bool _dangles(String t, int i) {
    final start = t.lastIndexOf(' ', i - 1) + 1;
    final w = t.substring(start, i).toLowerCase();
    return _dangling.contains(w);
  }

  /// [text] in pieces for a verse cut at [cuts] — token positions of
  /// [tokens], 0 and the end included.
  ///
  /// An edition usually renders the verse clause by clause, a sentence
  /// for each stretch between the pause signs. When it has exactly as
  /// many sentences as the verse has such stretches, each is the other's:
  /// a cut at a sign is a cut at the end of its sentence, and a cut
  /// inside a stretch goes where its share of that stretch's letters
  /// falls in that sentence. Shares of the whole verse alone ([split])
  /// put 2:256's "The right course has become distinct from the wrong"
  /// under the line after the one that recites it, English sentences
  /// being of other lengths than the Arabic phrases. Otherwise, shares.
  static List<String> forCuts(
      String text, List<String> tokens, List<int> cuts) {
    final t = text.trim();
    final n = tokens.length;
    final inner = cuts.length > 2 ? cuts.sublist(1, cuts.length - 1) : <int>[];
    if (inner.isEmpty) return [t];
    final letters = [for (final k in tokens) VerseText.letters(k)];
    double shareOf(int from, int to, int at) {
      var a = 0, all = 0;
      for (var k = from; k < to; k++) {
        all += letters[k];
        if (k < at) a += letters[k];
      }
      return all == 0 ? 0.5 : a / all;
    }

    final whole = [for (final c in inner) shareOf(0, n, c)];
    final phrases = [
      for (var p = 1; p < n; p++)
        if (_endsPhrase(tokens[p - 1])) p,
    ];
    final sentences = _sentenceEnds(t);
    if (phrases.isEmpty || phrases.length != sentences.length) {
      return split(t, whole);
    }
    final pa = [0, ...phrases, n];
    final se = [0, ...sentences, t.length];
    final picks = <int>[];
    for (var k = 0; k < pa.length - 1; k++) {
      final inside = [
        for (final c in inner)
          if (c > pa[k] && c < pa[k + 1]) c,
      ];
      if (inside.isNotEmpty) {
        final piece = t.substring(se[k], se[k + 1]);
        final at = _cutPositions(piece,
            [for (final c in inside) shareOf(pa[k], pa[k + 1], c)]);
        if (at.length != inside.length) return split(t, whole);
        picks.addAll([for (final a in at) se[k] + a]);
      }
      if (k < pa.length - 2 && inner.contains(pa[k + 1])) picks.add(se[k + 1]);
    }
    if (picks.length != inner.length) return split(t, whole);
    final out = <String>[];
    var from = 0;
    for (final p in picks) {
      out.add(t.substring(from, p).trim());
      from = p;
    }
    out.add(t.substring(from).trim());
    if (out.any((p) => p.isEmpty)) return split(t, whole);
    return out;
  }

  /// Whether a stretch of the verse ends at [token]: a sign that stops
  /// or allows a stop — not ∴, whose pair is one pause between them, nor
  /// the brief breathless one, nor "do not stop".
  static bool _endsPhrase(String token) => switch (VerseText.pauseAfter(token)) {
        PauseMark.mustStop ||
        PauseMark.better ||
        PauseMark.allowed ||
        PauseMark.carryOn =>
          true,
        _ => false,
      };

  /// Where each sentence of [t] but the last ends: the space after its
  /// full stop (or after the quote or bracket that closes on one),
  /// outside brackets.
  static List<int> _sentenceEnds(String t) {
    final out = <int>[];
    var depth = 0;
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (ch == '(' || ch == '[') depth++;
      if ((ch == ')' || ch == ']') && depth > 0) depth--;
      if (ch != ' ' || depth > 0 || i < 1) continue;
      final before = t[i - 1];
      final ends = _sentenceEnders.contains(before) ||
          (i > 1 &&
              '"”’»)]'.contains(before) &&
              _sentenceEnders.contains(t[i - 2]));
      if (ends) out.add(i);
    }
    return out;
  }

  /// [text] in `at.length + 1` pieces; [at] are the cumulative shares
  /// of the verse where each new part begins, ascending in (0, 1).
  static List<String> split(String text, List<double> at) {
    final t = text.trim();
    if (at.isEmpty) return [t];
    if (t.isEmpty) return List.filled(at.length + 1, '');
    final picks = _cutPositions(t, at);
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

  /// Where in [t] each piece after the first begins, for the shares [at]:
  /// at punctuation within reach of each share, else the nearest space;
  /// never inside brackets. Fewer than [at] when [t] runs out of spaces.
  static List<int> _cutPositions(String t, List<double> at) {
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
    if (spaces.isEmpty) return const [];
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
          // A piece that ends on "in" or "the" is waiting for the word
          // it belongs to: another space is taken unless much further.
          final d = (s - target).abs() + (_dangles(t, s) ? 30 : 0);
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
    return picks;
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

  /// Verses that were too long for [lines] and still shown whole: no
  /// cut in them could be timed. What the lines control says something
  /// about, since a choice of one line that leaves some verses whole is
  /// otherwise a choice that seems not to have worked.
  final int whole;

  const VerseLinePlan(this.lines, this.byAyah, {this.whole = 0});

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

  /// The verse's units over `[startAyah, endAyah]`, in order and gapless
  /// — led, for a reel that opens a surah on verse 1 with a recording
  /// that carries the basmala, by the basmala's own unit, numbered 0
  /// (see [Recitation.opensWithBasmala]).
  static List<VerseUnit> of(
    Recitation rec,
    int startAyah,
    int endAyah,
    VerseLinePlan? plan,
  ) {
    final out = <VerseUnit>[];
    if (startAyah == 1 && rec.opensWithBasmala) {
      final b = rec.timings.first;
      out.add(VerseUnit(0, null, b.startMs, b.endMs));
    }
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
