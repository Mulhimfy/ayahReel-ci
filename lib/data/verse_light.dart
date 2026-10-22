import 'package:flutter/foundation.dart';

import 'arena_service.dart';
import 'card_library.dart';
import 'reel_library.dart';
import 'surah_index.dart';

/// One time the user met a run of verses: a reel reciting them, a card
/// quoting them, a quiz question asked about one.
typedef VerseTouch = ({DateTime at, int surah, int from, int to});

/// The verses a user has lived with in the app, as places in the whole
/// Quran — what the "Your verses" card lights. Not only the reels: the
/// cards that quote a verse, and the verses the quiz asked about, too.
///
/// Read off what the app already keeps, so it is there in full for
/// somebody who has been making reels since long before the card
/// existed, not only for what they make from now on.
@immutable
class VerseLight {
  /// Per surah (1-based), the ayah runs lit, merged: in order, none
  /// overlapping or touching another.
  final Map<int, List<(int, int)>> ranges;

  /// The same runs as (surah, first ayah, last ayah), in the order they
  /// were first met: the order the card lights them in.
  final List<(int, int, int)> order;

  /// Distinct verses lit, and distinct surahs they are in.
  final int verses;
  final int surahs;

  const VerseLight._(this.ranges, this.order, this.verses, this.surahs);

  static const empty = VerseLight._({}, [], 0, 0);

  bool get isEmpty => order.isEmpty;

  /// From the reels alone. A reel whose surah cannot be named — an
  /// entry from some future build, say — is passed over rather than
  /// guessed.
  factory VerseLight.of(Iterable<SavedReel> reels) =>
      VerseLight.ofTouches(reelTouches(reels));

  /// From any mix of touches. A verse met twice is lit once; runs that
  /// overlap or meet become one, first met when the earliest of them
  /// was. A surah out of range is passed over, and ayahs past either
  /// end of their surah are held to it.
  factory VerseLight.ofTouches(Iterable<VerseTouch> touches) {
    final sorted = [...touches]..sort((a, b) => a.at.compareTo(b.at));
    // Per surah: each run, and when it was met, as its place in time.
    final runs = <int, List<(int, int, int)>>{};
    var met = 0;
    for (final t in sorted) {
      if (t.surah < 1 || t.surah > surahIndex.length) continue;
      final count = surahIndex[t.surah - 1].ayahCount;
      final from = t.from.clamp(1, count);
      final to = t.to.clamp(from, count);
      (runs[t.surah] ??= []).add((from, to, met++));
    }
    final ranges = <int, List<(int, int)>>{};
    // (first met, surah, from, to)
    final lit = <(int, int, int, int)>[];
    var verses = 0;
    for (final MapEntry(key: surah, value: list) in runs.entries) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
      final merged = <(int, int)>[];
      var (from, to, first) = list.first;
      for (final (f, t, m) in list.skip(1)) {
        if (f <= to + 1) {
          if (t > to) to = t;
          if (m < first) first = m;
          continue;
        }
        merged.add((from, to));
        lit.add((first, surah, from, to));
        (from, to, first) = (f, t, m);
      }
      merged.add((from, to));
      lit.add((first, surah, from, to));
      ranges[surah] = merged;
      for (final (a, b) in merged) {
        verses += b - a + 1;
      }
    }
    lit.sort((a, b) => a.$1.compareTo(b.$1));
    return VerseLight._(
      ranges,
      [for (final (_, s, f, t) in lit) (s, f, t)],
      verses,
      ranges.length,
    );
  }

  /// Every reel's verses, as touches.
  static List<VerseTouch> reelTouches(Iterable<SavedReel> reels) => [
        for (final r in reels)
          if (surahNumberOf(r) case final surah?)
            (at: r.createdAt, surah: surah, from: r.startAyah, to: r.endAyah),
      ];

  /// Everything the app keeps that names verses: the reels in the
  /// library ([reels] when the caller has them already), the cards
  /// that quote one, and the quiz's rounds. A source that can't be read
  /// costs only itself. Rounds filed before rounds kept their verses
  /// count once [ArenaService.fillVerses] has named them.
  static Future<VerseLight> gather({Iterable<SavedReel>? reels}) async {
    final touches = <VerseTouch>[];
    try {
      touches.addAll(reelTouches(reels ?? await ReelLibrary.load()));
    } catch (_) {}
    try {
      for (final deck in await CardLibrary.load()) {
        for (final slide in deck.slides) {
          final src = slide.source;
          if (!src.isVerse) continue;
          touches.add((
            at: deck.createdAt,
            surah: src.surah,
            from: src.startAyah,
            to: src.endAyah,
          ));
        }
      }
    } catch (_) {}
    try {
      await ArenaService.init();
      for (final round in ArenaService.state.value.history) {
        for (final (surah, ayah) in round.verses ?? const <(int, int)>[]) {
          touches.add((at: round.at, surah: surah, from: ayah, to: ayah));
        }
      }
    } catch (_) {}
    return VerseLight.ofTouches(touches);
  }

  /// The surah a saved reel recites: its recipe's, or — for a reel made
  /// before recipes were kept — the one its stored English name is.
  static int? surahNumberOf(SavedReel r) {
    final kept = r.recipe?.surah;
    if (kept != null && kept >= 1 && kept <= surahIndex.length) return kept;
    for (final s in surahIndex) {
      if (s.nameEnglish == r.surahName) return s.number;
    }
    return null;
  }
}
