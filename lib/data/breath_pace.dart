import 'dart:math' as math;

import 'models.dart';
import 'surah_slice.dart';
import 'verse_lines.dart';

/// Where the words of a verse with no word timing fall, going by its
/// recording's loudness: what the thread and the light follow on an
/// upload, and on the few verses of an app voice that nothing times.
///
/// The even pace crosses a verse at one speed over a guess at where its
/// voice is, so where the reciter stops for breath the light runs on
/// through the silence and ends up ahead of the voice. Here the voice's
/// own edges are measured, and the light waits through every pause of
/// [minPauseMs] or more: the words are spread, by their letters, over
/// the time the reciter is actually heard. A madd is voice, not
/// silence, so the loudness can't see one; a madd sign only weighs its
/// word a little more ([maddWeight]). Only word timing knows a madd.
///
/// Measured against quran-align's word timing on eight EveryAyah voices
/// (2026-10-25, 60 verses each, half of them long): the median word
/// start error falls from 1.2 s to 0.92 s on the four voices this was
/// tuned on and from 0.80 s to 0.69 s on four it was not, the 90th
/// percentile by 13% on both, and the median on every voice. Holding
/// each breath to a word boundary measured worse, and was left out.
abstract final class BreathPace {
  /// The shortest pause the light waits through. Shorter ones are mostly
  /// the gap inside a word, which the even pace already rides over.
  static const minPauseMs = 350;

  /// How many letters a madd sign adds to its word.
  static const maddWeight = 2;

  /// A stretch whose voice fills less of it than this is too quiet, or
  /// too noisy, to read, and keeps the even pace.
  static const minVoicedShare = 0.3;
  static const minVoicedMs = 300;

  static const _madd = 0x0653;

  /// Each verse's tokens' windows, in ms from the verse's start, for the
  /// verses of `[startAyah, endAyah]` that [wants] (every one when
  /// null) and the loudness can read; the rest are left out, and keep
  /// the even pace. [env] is the whole recording's loudness, in 10 ms
  /// steps ([SurahSlice.envelopeOf]); a cut verse is read part by part,
  /// each inside its own window ([plan]), so its words never leave the
  /// line they are shown on.
  static Map<int, List<(int, int)?>> reelTimes({
    required List<double> env,
    required Recitation recitation,
    required List<Ayah> ayahs,
    required int startAyah,
    required int endAyah,
    VerseLinePlan? plan,
    bool Function(int ayah)? wants,
  }) {
    final out = <int, List<(int, int)?>>{};
    if (env.isEmpty || !recitation.covers(startAyah, endAyah)) return out;
    // The same quiet the line cuts are found by.
    final lo =
        (recitation.timing(startAyah).startMs ~/ 10).clamp(0, env.length);
    final hi = (recitation.timing(endAyah).endMs ~/ 10).clamp(lo, env.length);
    final quiet = SurahSlice.quietBelow(hi > lo ? env.sublist(lo, hi) : env);
    for (var a = startAyah; a <= endAyah; a++) {
      if (a - 1 >= ayahs.length) break;
      if (wants != null && !wants(a)) continue;
      final t = recitation.timing(a);
      final times = verseTimes(
        tokens: VerseText.tokens(ayahs[a - 1].arabic),
        env: env,
        quiet: quiet,
        verseStartMs: t.startMs,
        verseEndMs: t.endMs,
        parts: plan?.partsOf(a),
      );
      if (times != null) out[a] = times;
    }
    return out;
  }

  /// One verse's tokens' windows, in ms from [verseStartMs]; null when
  /// any of its stretches — the verse, or each of its [parts] — can't be
  /// read, so the verse keeps the even pace whole rather than in part.
  static List<(int, int)?>? verseTimes({
    required List<String> tokens,
    required List<double> env,
    required double quiet,
    required int verseStartMs,
    required int verseEndMs,
    List<VersePart>? parts,
  }) {
    final out = List<(int, int)?>.filled(tokens.length, null);
    final stretches = parts == null || parts.isEmpty
        ? [(0, tokens.length, verseStartMs, verseEndMs)]
        : [
            for (final p in parts)
              (p.tokenStart, p.tokenEnd, p.startMs, p.endMs),
          ];
    for (final (k0, k1, from, to) in stretches) {
      final end = math.min(k1, tokens.length);
      if (k0 >= end) return null;
      final w = stretch(tokens.sublist(k0, end), env, quiet, from, to);
      if (w == null) return null;
      for (var k = k0; k < end; k++) {
        final x = w[k - k0];
        out[k] = (x.$1 - verseStartMs, x.$2 - verseStartMs);
      }
    }
    return out;
  }

  /// How much of a stretch's time [token] takes: its letters, a little
  /// more for a madd; nothing for a pause sign.
  static int weightOf(String token) {
    if (!VerseText.isWord(token)) return 0;
    var madds = 0;
    for (final r in token.runes) {
      if (r == _madd) madds++;
    }
    return VerseText.letters(token) + maddWeight * madds;
  }

  /// Each of [tokens]' (start, end), absolute, inside the stretch
  /// `[fromMs, toMs)` of the recording that holds them; null when the
  /// loudness can't say where the voice is in it.
  static List<(int, int)>? stretch(List<String> tokens, List<double> env,
      double quiet, int fromMs, int toMs) {
    final n = tokens.length;
    final weights = [for (final k in tokens) weightOf(k)];
    final total = weights.fold<int>(0, (a, b) => a + b);
    if (n == 0 || total <= 0) return null;
    final p = PartTiming.pausesIn(env, quiet, fromMs, toMs);
    final v0 = p.voicedStart, v1 = p.voicedEnd;
    if (v0 == null || v1 == null) return null;
    if (v1 - v0 < math.max(minVoicedMs, minVoicedShare * (toMs - fromMs))) {
      return null;
    }
    final silent = [
      for (final q in PartTiming.pausesIn(env, quiet, v0, v1).pauses)
        if (q.$1 > v0 && q.$2 < v1 && q.$2 - q.$1 >= minPauseMs) q,
    ];
    var voice = (v1 - v0).toDouble();
    for (final (a, b) in silent) {
      voice -= b - a;
    }
    if (voice <= 0) return null;

    // [x] ms of voice after the stretch's start, stepping over the
    // silences: a word that would open on one opens after it.
    double walk(double x, {required bool opening}) {
      var t = v0.toDouble();
      var left = x;
      for (final (a, b) in silent) {
        final room = a - t;
        if (left < room || (left == room && !opening)) return t + left;
        left -= room;
        t = b.toDouble();
      }
      return t + left;
    }

    final out = List<(int, int)>.filled(n, (0, 0));
    var done = 0;
    for (var k = 0; k < n; k++) {
      final from = walk(voice * done / total, opening: true);
      done += weights[k];
      final to = walk(voice * done / total, opening: false);
      out[k] = (from.round(), to.round());
    }
    return out;
  }
}
