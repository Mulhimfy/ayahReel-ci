import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'download.dart';
import 'models.dart';
import 'own_words.dart';
import 'recitation_service.dart';
import 'surah_index.dart';
import 'surah_slice.dart';
import 'trouble.dart';
import 'whole_file.dart';
import 'words_host.dart';

/// How a QUL recitation's times are brought onto the audio a voice plays.
enum QulFit {
  /// QUL aligned this voice's own per-ayah files: each verse's words are
  /// its file's, as they are.
  ayahFiles,

  /// QUL aligned this voice's own surah files, or the very same recording
  /// served one file per surah by another host: within a surah one shift
  /// brings every word over — the voice's offset to QUL's file
  /// ([QulSource.offsets]) and where the recording was cut from it
  /// ([Recitation.originMs]) — verse 1 and its basmala included.
  surahFile,

  /// The same recording, cut one file per ayah by its host: each verse's
  /// words are placed from where its own sound begins.
  perVerse,
}

/// How a verse 1 is placed, where QUL's first word of it may hold the
/// basmala — or, for a surah recorded with them, the isti'adha too —
/// that the voice's own file leaves out or keeps apart.
enum QulVerseOne {
  /// From its sound, as every other verse is, with its own bias.
  shift,

  /// From QUL's own verse start: the host cut its verse-1 file where
  /// QUL's verse starts.
  table,

  /// Not at all: neither finds its words.
  none,
}

/// Which QUL recitation times a voice, and how — as
/// tool/verify_word_timing.py measured it against the voice's own audio
/// (its `runtime` entry in tool/word_timing_verified.json).
@immutable
class QulSource {
  /// The id in QUL's surah recitations, or for [QulFit.ayahFiles] in its
  /// ayah recitations.
  final int recitation;
  final QulFit fit;

  /// Where QUL's first word starts against where this voice's sound
  /// rises through the threshold ([QulWords.soundIn]): added to every
  /// placing from an onset.
  final int biasMs;

  /// How a verse 1 is placed ([QulFit.perVerse]), with its own bias, and
  /// the surahs whose verse 1 no rule places.
  final QulVerseOne verseOne;
  final int verseOneBiasMs;
  final Set<int> verseOneOff;

  /// Surahs where QUL's recording is not this voice's — the host filled
  /// them from another take — and which therefore get no words.
  final Set<int> skip;

  /// For [QulFit.surahFile]: where a moment of QUL's file is in the
  /// voice's own, surah by surah — the voice's time is QUL's less this —
  /// and how far the two clocks part over a file, in parts per million.
  /// Empty for a voice whose files are QUL's own.
  final Map<int, int> offsets;
  final double driftPpm;

  /// For [QulFit.surahFile]: whether a recording cut before its place
  /// in the surah file was kept ([Recitation.originMs]) may still have
  /// its words placed from its verses' onsets. Only where the tool found
  /// that reliable: a host whose verse windows open in the middle of the
  /// sound would throw it out by a second and more.
  final bool onsetFallback;

  /// For a voice the app times itself (see [QulWords.owned]): its id on
  /// the app's own host, where its words are published already placed on
  /// the audio the app plays. Null for a recitation of QUL's.
  final String? own;

  const QulSource(
    this.recitation,
    this.fit, {
    this.own,
    this.biasMs = 0,
    this.verseOne = QulVerseOne.shift,
    this.verseOneBiasMs = 0,
    this.verseOneOff = const {},
    this.skip = const {},
    this.offsets = const {},
    this.driftPpm = 0,
    this.onsetFallback = false,
  });

  /// For [QulFit.surahFile]: the shift that puts [v] of [surah] on a
  /// recording whose first moment is [originMs] into the surah's file.
  int fileShift(QulVerse v, int surah, int originMs) =>
      -(offsets[surah] ?? 0) - originMs + (driftPpm * 1e-6 * v.firstMs).round();

  /// The shift that places verse [ayah] of [surah] whose window starts
  /// [windowMs] into the recording and whose sound begins at [onsetMs]
  /// (null when none was found), or null when it is not to be placed.
  int? shiftFor(QulVerse v, int surah, int ayah,
      {required int windowMs, required int? onsetMs}) {
    if (ayah == 1 && surah != 9) {
      if (verseOneOff.contains(surah)) return null;
      switch (verseOne) {
        case QulVerseOne.none:
          return null;
        case QulVerseOne.table:
          return windowMs - v.fromMs + verseOneBiasMs;
        case QulVerseOne.shift:
          return onsetMs == null
              ? null
              : onsetMs - v.firstMs + verseOneBiasMs;
      }
    }
    return onsetMs == null ? null : onsetMs - v.firstMs + biasMs;
  }
}

/// A verse's words placed on the app's recording: how many QUL counts in
/// it, and those inside the verse's window, as (position from 1, start,
/// end) in milliseconds from the window's start.
typedef Placed = ({int count, List<(int, int, int)> words});

/// One verse as QUL times it: where it starts and ends in QUL's file,
/// and each of its words, in the mushaf's own count.
@immutable
class QulVerse {
  final int fromMs;
  final int toMs;

  /// (position from 1, start, end) in QUL's file's milliseconds, in the
  /// order they are recited — which goes back over a few words where the
  /// reciter takes them again, as reciters do after a breath.
  final List<(int, int, int)> words;

  const QulVerse(this.fromMs, this.toMs, this.words);

  int get firstMs => words.first.$2;
  int get lastMs => words.last.$3;

  /// How many words the verse has: the furthest position recited.
  int get count {
    var n = 0;
    for (final (p, _, _) in words) {
      if (p > n) n = p;
    }
    return n;
  }
}

/// Word timing from the Quranic Universal Library (Tarteel) for the
/// voices whose recordings it has aligned word by word.
///
/// QUL times its own files: for most voices a gapless recording of each
/// surah, which is not the file this app plays — the app plays EveryAyah's
/// or KSU's per-ayah cut of it, or mp3quran's copy of it. So no voice is
/// in [sources] until `tool/verify_word_timing.py` has found the app's
/// audio inside QUL's, verse by verse, by cross-correlation, and measured
/// how close the placing below comes to where the words really are (see
/// `tool/word_timing_verified.json`, which test/word_timing_sources_test
/// holds this table to).
///
/// Placing is done on the phone. A recording cut out of a whole-surah
/// file knows where it was cut, so QUL's times move onto it exactly
/// ([QulFit.surahFile]). One assembled from another host's per-ayah
/// files knows only its own audio, and QUL's first word starts where a
/// verse's sound does, so each verse's words go where its sound begins
/// ([QulFit.perVerse]) — and a verse whose sound does not last about as
/// long as QUL's words is not the same take, and gets none: the
/// highlight falls back to the whole verse rather than light a word a
/// second late. What can't be checked on the phone — a surah its host
/// filled from another recording — the tool found, and [QulSource.skip]
/// leaves out.
abstract final class QulWords {
  static const _api = 'https://qul.tarteel.ai/api/v1/audio';

  /// Voice id → the QUL recitation verified to be its recording, and the
  /// rules tool/verify_word_timing.py measured for placing its words —
  /// written from its `runtime` entries, which
  /// test/word_timing_sources_test.dart holds this table to. Measured
  /// word-start error once placed: 12-27 ms at the median, 36-111 ms at
  /// the 90th percentile.
  static const sources = <String, QulSource>{
    // Muhammad AbdulKareem: the same recording.
    'abdulkareem': QulSource(
      70,
      QulFit.perVerse,
      verseOne: QulVerseOne.table,
      verseOneBiasMs: 35,
      verseOneOff: {1, 3, 5, 6, 7, 11, 15, 19, 58, 78},
    ),
    // Ahmed Al-Ajmi: the same recording.
    'ajmi': QulSource(
      19,
      QulFit.perVerse,
      biasMs: 10,
      verseOne: QulVerseOne.none,
      skip: {
        27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54,
        55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68,
        69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82,
        83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96,
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110,
        111, 112, 113, 114,
      },
    ),
    // Mahmoud Ali Al-Banna: its files are QUL's own.
    'albanna': QulSource(
      129,
      QulFit.surahFile,
      biasMs: 20,
      onsetFallback: true,
    ),
    // Yasser Ad-Dussary: the same recording, but for the surahs it skips.
    'dussary': QulSource(
      174,
      QulFit.perVerse,
      biasMs: -5,
      verseOneBiasMs: -95,
      verseOneOff: {20, 21, 28, 59, 62, 67, 72, 77},
      skip: {9, 29},
    ),
    // Saad Al-Ghamdi: the same recording.
    'ghamdi': QulSource(
      13,
      QulFit.surahFile,
      biasMs: 15,
      driftPpm: -13.2,
      offsets: {
        1: -3831, 2: -5505, 3: -6896, 4: -9226, 5: -9254, 6: -9545,
        7: -9701, 8: -9562, 9: -3902, 10: -10314, 11: -5824, 12: -9694,
        13: -6322, 14: -5596, 15: -10131, 16: -6396, 17: -6148, 18: -9903,
        19: -5550, 20: -5445, 21: -9906, 22: -5370, 23: -5524, 24: -9142,
        25: -5277, 26: -5809, 27: -9250, 28: -4651, 29: -5758, 30: -9589,
        31: -5488, 32: -5332, 33: -6460, 34: -5570, 35: -9554, 36: -5446,
        37: -5683, 38: -5701, 39: -9502, 40: -5437, 41: -6193, 42: -4575,
        43: -8516, 44: -4838, 45: -4722, 46: -5460, 47: -5818, 48: -5342,
        49: -5946, 50: -9207, 51: -4153, 52: -4092, 53: -4338, 54: -4058,
        55: -4107, 56: -4031, 57: -4064, 58: -4045, 59: -7598, 60: -4159,
        61: -4074, 62: -4981, 63: -4212, 64: -4160, 65: -4117, 66: -4241,
        67: -6006, 68: -4900, 69: -4656, 70: -4812, 71: -4844, 72: -5460,
        73: -4636, 74: -8620, 75: -4830, 76: -4976, 77: -4832, 78: -5332,
        79: -5385, 80: -5563, 81: -5481, 82: -5645, 83: -5669, 84: -5433,
        85: -5313, 86: -5539, 87: -5529, 88: -5710, 89: -5501, 90: -6070,
        91: -5932, 92: -5447, 93: -5690, 94: -5591, 95: -5496, 96: -5575,
        97: -5748, 98: -5648, 99: -5731, 100: -5555, 101: -5498, 102: -5717,
        103: -5428, 104: -5670, 105: -6035, 106: -5431, 107: -5996, 108: -5636,
        109: -5396, 110: -5511, 111: -6134, 112: -5830, 113: -5546, 114: -5645,
      },
    ),
    // Al-Husary · Mujawwad: the same recording, but for the surahs it skips.
    'husary_mujawwad': QulSource(
      164,
      QulFit.perVerse,
      biasMs: 20,
      verseOneBiasMs: -5,
      verseOneOff: {1, 9, 16, 25, 37, 46, 72, 77, 89, 109, 111},
      skip: {17, 62},
    ),
    // Ahmad Al-Nufais: its files are QUL's own.
    'nufais': QulSource(42, QulFit.ayahFiles),
    // Mansour Al-Salimi: the same recording.
    'salimi': QulSource(
      179,
      QulFit.surahFile,
      biasMs: 90,
      offsets: {
        1: 8, 2: -4902, 3: -4870, 4: -4854, 5: -5373, 6: -4804,
        7: -4937, 8: -4989, 9: -6881, 10: -4774, 11: -4938, 12: -4925,
        13: -5032, 14: -4893, 15: -4755, 16: -5122, 17: -5022, 18: -4878,
        19: -5013, 20: -5058, 21: -5080, 22: -5230, 23: -5017, 24: -5020,
        25: -4905, 26: -4940, 27: -5038, 28: -4902, 29: -4828, 30: -4947,
        31: -4611, 32: -4915, 33: -4897, 34: -4853, 35: -4924, 36: -4980,
        37: -4928, 38: -5002, 39: -5011, 40: -4964, 41: -4917, 42: -4704,
        43: -4944, 44: -4956, 45: -5017, 46: -5029, 47: -5009, 48: -4901,
        49: -4952, 50: -4992, 51: -4965, 52: -4892, 53: -4761, 54: -4957,
        55: -4855, 56: -4854, 57: -4972, 58: -5010, 59: -4920, 60: -5035,
        61: -4994, 62: -4909, 63: -4910, 64: -4951, 65: -5036, 66: -4932,
        67: -4960, 68: -4636, 69: -4945, 70: -4932, 71: -4949, 72: -4916,
        73: -5089, 74: -4735, 75: -4956, 76: -4912, 77: -4994, 78: -5024,
        79: -4705, 80: -4838, 81: -5004, 82: -4887, 83: -4937, 84: -4986,
        85: -5090, 86: -4944, 87: -4838, 88: -4828, 89: -4958, 90: -4851,
        91: -4833, 92: -5110, 93: -4948, 94: -4730, 95: -4866, 96: -4865,
        97: -4912, 98: -4966, 99: -5007, 100: -4875, 101: -4923, 102: -4873,
        103: -4975, 104: -5170, 105: -4880, 106: -4937, 107: -4810, 108: -4908,
        109: -4942, 110: -4903, 111: -4942, 112: -5132, 113: -4922, 114: -12504,
      },
    ),
    // Hady Toure: its files are QUL's own.
    'toure': QulSource(
      172,
      QulFit.surahFile,
      biasMs: 10,
      onsetFallback: true,
    ),
    // Khalifa Al-Tunaiji: the same recording, but for the surahs it skips.
    'tunaiji': QulSource(
      161,
      QulFit.perVerse,
      verseOne: QulVerseOne.table,
      verseOneBiasMs: 25,
      skip: {1, 10, 13, 14, 72},
    ),
  };

  /// QUL's verified recitation for [r], or else the app's own timing of
  /// it (see [OwnWords]).
  static QulSource? sourceOf(Reciter r) =>
      sources[r.id] ?? OwnWords.sources[r.id];

  static bool supports(Reciter r) => sourceOf(r) != null;

  // ---- placing, shared by every voice it times -------------------------

  /// How long the loudness has to stay up for the verse's sound to have
  /// begun, rather than a click or a breath.
  static const holdMs = 50;

  /// For a whole-surah file: the most a verse's own onset may stray from
  /// the surah's one shift and still count as agreeing with it, and the
  /// share of verses that have to agree for the shift to be trusted.
  static const agreeMs = 140;
  static const agreeShare = 0.6;

  /// How far a verse's sound may run longer or shorter than QUL's words
  /// and still be the same take, placed from its onset: a second, or a
  /// twentieth of a long verse. Wide, because QUL's last word runs on a
  /// few hundred ms past the sound; what it catches is a file that opens
  /// on the verse before's tail, or a verse 1 whose first word holds a
  /// basmala the file leaves out, both off by seconds.
  static const checkMs = 1000;
  static const checkShare = 0.05;

  /// Whether a stretch of sound [sound] long is the same take as [v]'s
  /// words.
  static bool sameTake(QulVerse v, int sound) {
    final words = v.lastMs - v.firstMs;
    final share = (words * checkShare).round();
    return (sound - words).abs() <= (share > checkMs ? share : checkMs);
  }

  /// How far before its window a verse's first word may be placed and
  /// still be this verse: the breath the window was cut in.
  static const earlyMs = 400;

  /// The loudness above which [env] counts as sound: where its pauses
  /// end ([SurahSlice.quietBelow]).
  static double soundAbove(List<double> env) => SurahSlice.quietBelow(env);

  /// The first and last moment of sound in [env] (10 ms steps) between
  /// [fromMs] and [toMs]: where the loudness first rises above [above]
  /// and stays there for [holdMs], and where the last such stretch
  /// ends. Null when there is none.
  static (int, int)? soundIn(
      List<double> env, double above, int fromMs, int toMs) {
    final lo = (fromMs ~/ 10).clamp(0, env.length);
    final hi = ((toMs + 9) ~/ 10).clamp(lo, env.length);
    const need = (holdMs + 9) ~/ 10;
    int? first;
    int? last;
    var run = 0;
    for (var k = lo; k < hi; k++) {
      if (env[k] > above) {
        run++;
        if (run >= need) {
          first ??= k - need + 1;
          last = k + 1;
        }
      } else {
        run = 0;
      }
    }
    if (first == null || last == null) return null;
    return (first * 10, last * 10);
  }

  /// [v]'s words moved by [shiftMs] (QUL's time + shift = the
  /// recording's), as (start, end) from the start of a window
  /// [windowMs] into the recording and [lengthMs] long. Words that fall
  /// wholly outside it are left out; one that runs over an edge is cut
  /// at it.
  static List<(int, int, int)> placed(
      QulVerse v, int shiftMs, int windowMs, int lengthMs) {
    final out = <(int, int, int)>[];
    for (final (p, s, e) in v.words) {
      final a = (s + shiftMs - windowMs).clamp(0, lengthMs);
      final b = (e + shiftMs - windowMs).clamp(0, lengthMs);
      if (b > a) out.add((p, a, b));
    }
    return out;
  }

  /// Whether [v], moved by [shiftMs], lands in a window [windowMs] into
  /// the recording and [lengthMs] long: its first word not well before
  /// the window — unless [opening], a verse 1 whose first word holds the
  /// basmala the window was cut after — and its last word starting
  /// inside it. A verse that doesn't is another take, or not found.
  static bool lands(QulVerse v, int shiftMs, int windowMs, int lengthMs,
      {bool opening = false}) {
    final first = v.firstMs + shiftMs - windowMs;
    final last = v.words.last.$2 + shiftMs - windowMs;
    return (opening || first >= -earlyMs) && last < lengthMs && last >= 0;
  }

  /// The surah's one shift, from each verse's onset in the recording
  /// against its first word in QUL's: the middle of them, if enough of
  /// the verses agree with it to say the two are one take. Null when
  /// they don't.
  static int? surahShift(List<(QulVerse, int)> onsets) {
    if (onsets.isEmpty) return null;
    final d = [for (final (v, at) in onsets) at - v.firstMs]..sort();
    final mid = d[d.length ~/ 2];
    final agree = d.where((x) => (x - mid).abs() <= agreeMs).length;
    if (agree < onsets.length * agreeShare) return null;
    return mid;
  }

  /// Whether ayah [a] of [surah] opens with words its own recording
  /// gives to the basmala: every verse 1 but At-Tawbah's.
  static bool _opens(int surah, int a) => a == 1 && surah != 9;

  /// Every verse of [rec] that can be placed: how many words QUL counts
  /// in it, and those that fall inside its window, as (position, start,
  /// end) from the window's start.
  static Map<int, Placed> placeAll({
    required QulSource src,
    required Map<int, QulVerse> verses,
    required Recitation rec,
    List<double>? env,
  }) {
    final out = <int, Placed>{};
    if (src.skip.contains(rec.surah)) return out;
    void put(AyahTiming t, QulVerse v, int shift) {
      final opening = _opens(rec.surah, t.ayah);
      if (!lands(v, shift, t.startMs, t.durationMs, opening: opening)) return;
      out[t.ayah] =
          (count: v.count, words: placed(v, shift, t.startMs, t.durationMs));
    }

    if (src.fit == QulFit.ayahFiles) {
      for (final t in rec.timings) {
        final v = verses[t.ayah];
        if (v == null) continue;
        out[t.ayah] = (count: v.count, words: placed(v, 0, 0, t.durationMs));
      }
      return out;
    }
    final origin = rec.originMs;
    if (src.fit == QulFit.surahFile && origin != null) {
      // Cut from a known place in the surah's file: QUL's times, moved.
      for (final t in rec.timings) {
        final v = verses[t.ayah];
        if (v != null) put(t, v, src.fileShift(v, rec.surah, origin));
      }
      return out;
    }
    if (src.fit == QulFit.surahFile && !src.onsetFallback) return out;
    final e = env;
    if (e == null || e.isEmpty) return out;
    // Each verse's sound, by its own window's loudness.
    final sounds = <int, (int, int)>{};
    for (final t in rec.timings) {
      final lo = (t.startMs ~/ 10).clamp(0, e.length);
      final hi = ((t.endMs + 9) ~/ 10).clamp(lo, e.length);
      if (hi <= lo) continue;
      final s = soundIn(e, soundAbove(e.sublist(lo, hi)), t.startMs, t.endMs);
      if (s != null) sounds[t.ayah] = s;
    }
    if (src.fit == QulFit.surahFile) {
      // One shift for the surah, from its onsets: a verse 1 opens on the
      // basmala QUL's first word holds, which is no onset of that word,
      // so the shift is the other verses' when there are any.
      final pairs = [
        for (final t in rec.timings)
          if (verses[t.ayah] != null && sounds[t.ayah] != null)
            (t.ayah, verses[t.ayah]!, sounds[t.ayah]!.$1),
      ];
      final rest = [
        for (final (a, v, o) in pairs)
          if (!_opens(rec.surah, a)) (v, o),
      ];
      final shift = surahShift(
          rest.isNotEmpty ? rest : [for (final (_, v, o) in pairs) (v, o)]);
      if (shift == null) return out;
      for (final t in rec.timings) {
        final v = verses[t.ayah];
        if (v != null) put(t, v, shift + src.biasMs);
      }
      return out;
    }
    for (final t in rec.timings) {
      final v = verses[t.ayah];
      if (v == null) continue;
      final sound = sounds[t.ayah];
      final shift = src.shiftFor(v, rec.surah, t.ayah,
          windowMs: t.startMs, onsetMs: sound?.$1);
      if (shift == null) continue;
      // Placed from its onset: the sound must last as long as the words.
      final fromOnset = !(_opens(rec.surah, t.ayah) &&
          src.verseOne == QulVerseOne.table);
      if (fromOnset && (sound == null || !sameTake(v, sound.$2 - sound.$1))) {
        continue;
      }
      put(t, v, shift);
    }
    return out;
  }

  // ---- QUL's data --------------------------------------------------------

  /// One surah's verses, as QUL publishes them for [src]: from memory,
  /// then from disk, then from QUL. Null when it can't be had or can't
  /// be read; callers then have no words for the surah.
  static Future<Map<int, QulVerse>?> versesOf(QulSource src, int surah) async {
    final key = src.own != null
        ? 'o${src.own}_$surah'
        : '${src.fit == QulFit.ayahFiles ? 'a' : 's'}${src.recitation}_$surah';
    final hit = _memory.remove(key);
    if (hit != null) return _memory[key] = hit;
    Map<int, QulVerse>? verses;
    try {
      final f = await _file(key);
      if (f.existsSync()) {
        try {
          verses = decodeCompact(jsonDecode(await f.readAsString()));
        } catch (_) {
          // Written by an older build, or cut short: fetched again.
        }
      }
      if (verses == null) {
        final count = surahIndex[surah - 1].ayahCount;
        final json = await _fetch(src, surah, count);
        verses = src.own != null
            ? decodeCompact(json)
            : src.fit == QulFit.ayahFiles
                ? parseAyahSpans(json, surah)
                : parse(json, surah);
        await writeWhole(f, jsonEncode(encodeCompact(verses)));
      }
    } catch (e) {
      rlog('qul: no words for ${src.recitation} surah $surah ($e)');
      return null;
    }
    _memory[key] = verses;
    while (_memory.length > 3) {
      _memory.remove(_memory.keys.first);
    }
    return verses;
  }

  static final _memory = <String, Map<int, QulVerse>>{};

  static Future<Object?> _fetch(QulSource src, int surah, int count) async {
    // A page holds ten verses unless asked for the whole surah.
    final own = src.own;
    // The app's own timing: one file per voice and surah, in the shape
    // [encodeCompact] writes, served only with the app's key.
    final url = own != null
        ? Uri.parse('${WordsHost.base}/$own/$surah.json')
        : src.fit == QulFit.ayahFiles
        ? Uri.parse('$_api/ayah_segments/${src.recitation}'
            '?surah=$surah&per_page=$count')
        : Uri.parse('$_api/surah_segments/${src.recitation}'
            '?surah=$surah&from=1&to=$count&per_page=$count');
    Object? last;
    final client = http.Client();
    try {
      for (var attempt = 1; attempt <= Download.attempts; attempt++) {
        try {
          final res = await Download.get(client, url,
              headers: own != null ? WordsHost.headers : const {});
          if (res.statusCode != 200) throw BadStatus(res.statusCode);
          return jsonDecode(res.body);
        } catch (e) {
          last = e;
          if (Download.isFinal(e) || e is FormatException) break;
          if (attempt < Download.attempts) {
            await Future<void>.delayed(Download.backoff(attempt));
          }
        }
      }
    } finally {
      client.close();
    }
    throw last ?? const FormatException('no answer');
  }

  /// QUL's `segments` for one surah, every verse checked: every word
  /// starting no earlier than the one before it and ending after it
  /// starts, and every position from 1 to the furthest recited at least
  /// once — a reciter may take words again, but none may be missing. A
  /// verse that fails is left out; the rest stand.
  @visibleForTesting
  static Map<int, QulVerse> parse(Object? json, int surah) {
    final segments = json is Map ? json['segments'] : null;
    if (segments is! Map) throw const FormatException('no segments');
    final out = <int, QulVerse>{};
    for (final e in segments.entries) {
      final key = '${e.key}';
      final colon = key.indexOf(':');
      if (colon < 0 || key.substring(0, colon) != '$surah') continue;
      final ayah = int.tryParse(key.substring(colon + 1));
      final v = e.value;
      if (ayah == null || v is! Map) continue;
      final words = <(int, int, int)>[];
      var ok = true;
      final raw = v['segments'];
      if (raw is! List || raw.isEmpty) continue;
      for (final w in raw) {
        if (w is! List || w.length < 3 ||
            w[0] is! num || w[1] is! num || w[2] is! num) {
          ok = false;
          break;
        }
        final p = (w[0] as num).toInt();
        final s = (w[1] as num).toInt();
        final t = (w[2] as num).toInt();
        if (p < 1 || t <= s || (words.isNotEmpty && s < words.last.$2)) {
          ok = false;
          break;
        }
        words.add((p, s, t));
      }
      final from = v['time_from'];
      final to = v['time_to'];
      if (!ok || from is! num || to is! num) continue;
      final verse = QulVerse(from.toInt(), to.toInt(), words);
      final seen = {for (final (p, _, _) in words) p};
      if (seen.length != verse.count) continue;
      out[ayah] = verse;
    }
    if (out.isEmpty) throw const FormatException('no verse could be read');
    return out;
  }

  /// QUL's ayah recitation for one surah: per verse, spans of `[first
  /// word from 0, past its last word, start, end]` in the verse's own
  /// file — quran-align's layout — as single words, a span of several
  /// shared out evenly between them. Checked as [parse] checks.
  @visibleForTesting
  static Map<int, QulVerse> parseAyahSpans(Object? json, int surah) {
    final segments = json is Map ? json['segments'] : null;
    if (segments is! Map) throw const FormatException('no segments');
    final out = <int, QulVerse>{};
    for (final e in segments.entries) {
      final key = '${e.key}';
      final colon = key.indexOf(':');
      if (colon < 0 || key.substring(0, colon) != '$surah') continue;
      final ayah = int.tryParse(key.substring(colon + 1));
      final v = e.value;
      final raw = v is Map ? v['segments'] : null;
      if (ayah == null || raw is! List || raw.isEmpty) continue;
      final words = <(int, int, int)>[];
      var ok = true;
      for (final w in raw) {
        if (w is! List || w.length < 4 || w.take(4).any((x) => x is! num)) {
          ok = false;
          break;
        }
        final a = (w[0] as num).toInt();
        final b = (w[1] as num).toInt();
        final st = (w[2] as num).toInt();
        final en = (w[3] as num).toInt();
        if (a < 0 || b <= a || en <= st ||
            (words.isNotEmpty && st < words.last.$2)) {
          ok = false;
          break;
        }
        final n = b - a;
        for (var k = 0; k < n; k++) {
          final s0 = st + ((en - st) * k / n).round();
          final s1 = st + ((en - st) * (k + 1) / n).round();
          words.add((a + k + 1, s0, s1 > s0 ? s1 : s0 + 1));
        }
      }
      if (!ok) continue;
      final verse = QulVerse(words.first.$2, words.last.$3, words);
      final seen = {for (final (p, _, _) in words) p};
      if (seen.length != verse.count) continue;
      out[ayah] = verse;
    }
    if (out.isEmpty) throw const FormatException('no verse could be read');
    return out;
  }

  /// A surah's verses as kept on the phone: `{"ayah": [from, to, p, s, e,
  /// p, s, e, …]}` — a fifth of what QUL sends.
  @visibleForTesting
  static Map<String, dynamic> encodeCompact(Map<int, QulVerse> verses) => {
        'v': 1,
        for (final e in verses.entries)
          '${e.key}': [
            e.value.fromMs,
            e.value.toMs,
            for (final (p, s, t) in e.value.words) ...[p, s, t],
          ],
      };

  @visibleForTesting
  static Map<int, QulVerse> decodeCompact(Object? json) {
    if (json is! Map || json['v'] != 1) throw const FormatException('old');
    final out = <int, QulVerse>{};
    for (final e in json.entries) {
      if (e.key == 'v') continue;
      final ayah = int.parse('${e.key}');
      final n = (e.value as List).cast<num>();
      if (n.length < 5 || (n.length - 2) % 3 != 0) {
        throw const FormatException('bad verse');
      }
      out[ayah] = QulVerse(n[0].toInt(), n[1].toInt(), [
        for (var i = 2; i < n.length; i += 3)
          (n[i].toInt(), n[i + 1].toInt(), n[i + 2].toInt()),
      ]);
    }
    return out;
  }

  static Future<File> _file(String key) async {
    final dir = debugDir ??
        Directory('${(await getApplicationSupportDirectory()).path}/qul_words');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$key.json');
  }

  @visibleForTesting
  static Directory? debugDir;

  @visibleForTesting
  static void debugReset() => _memory.clear();

  // ---- what the app asks for -------------------------------------------

  /// One verse's words in a clip the verse picker's listen plays: placed
  /// on the clip's own audio, and counted from the verse's window in the
  /// file ([LiveClip.windowMs]). Null when there are none to be had.
  static Future<Placed?> forClip(
      Reciter reciter, int surah, LiveClip clip) async {
    final src = sourceOf(reciter);
    if (src == null || src.skip.contains(surah)) return null;
    final v = (await versesOf(src, surah))?[clip.ayah];
    if (v == null) return null;
    if (src.fit == QulFit.ayahFiles) {
      // The ayah's own file, as QUL timed it.
      return (count: v.count, words: placed(v, 0, 0, 1 << 30));
    }
    final from = clip.windowMs;
    final opening = _opens(surah, clip.ayah);
    if (src.fit == QulFit.surahFile) {
      final origin = clip.originMs;
      final source = reciter.source;
      final ownTable = source is SurahFiles &&
          source.timing is QulTiming &&
          (source.timing as QulTiming).recitation == src.recitation;
      final int shift;
      if (origin != null) {
        shift = src.fileShift(v, surah, origin);
      } else if (ownTable) {
        // QUL's own file, cut where QUL's own table puts the verse.
        shift = from - v.fromMs;
      } else {
        return null;
      }
      final length = clip.toMs - from;
      if (!lands(v, shift, from, length, opening: opening)) return null;
      return (count: v.count, words: placed(v, shift, from, length));
    }
    final env = await RecitationService.loudness(clip.path);
    if (env == null || env.isEmpty) return null;
    // A per-ayah file's window is the whole file; a verse cut out of a
    // longer one is the clip.
    final to = clip.windowMs == clip.fromMs ? clip.toMs : env.length * 10;
    final lo = (from ~/ 10).clamp(0, env.length);
    final hi = ((to + 9) ~/ 10).clamp(lo, env.length);
    if (hi <= lo) return null;
    final sound = soundIn(env, soundAbove(env.sublist(lo, hi)), from, to);
    final shift =
        src.shiftFor(v, surah, clip.ayah, windowMs: from, onsetMs: sound?.$1);
    if (shift == null) return null;
    final fromOnset = !(opening && src.verseOne == QulVerseOne.table);
    if (fromOnset && (sound == null || !sameTake(v, sound.$2 - sound.$1))) {
      return null;
    }
    if (!lands(v, shift, from, to - from, opening: opening)) return null;
    return (count: v.count, words: placed(v, shift, from, to - from));
  }

  /// Each verse of [rec]'s words, as (position, start, end) from the
  /// verse's window in [rec]: QUL's, placed on this recording. Null when
  /// [reciter] has no QUL timing or none could be had.
  static Future<Map<int, Placed>?> forRecitation(
      Reciter reciter, Recitation rec) async {
    final src = sourceOf(reciter);
    if (src == null) return null;
    final verses = await versesOf(src, rec.surah);
    if (verses == null) return null;
    final env = src.fit == QulFit.ayahFiles
        ? null
        : await RecitationService.loudness(rec.audioPath);
    if (src.fit != QulFit.ayahFiles && env == null) return null;
    final placedWords =
        placeAll(src: src, verses: verses, rec: rec, env: env);
    return placedWords.isEmpty ? null : placedWords;
  }
}
