/// Tanafus — the arena. Every question it asks is made here.
///
/// The name is from 83:26, *so for this let the competitors compete*,
/// and the whole feature is built on one idea: a round is a pure
/// function of a seed. The same seed, scope and level produce the
/// same ten questions on any phone, which is what lets a score travel
/// as a twelve-letter code and be answered by somebody who was never
/// sent the questions — see `arena_challenge.dart`.
///
/// Nothing here is fetched. The Arabic is the bundled search index
/// (the whole Quran, as the reels render it), the surah facts are a
/// generated table, and the juz boundaries are thirty pairs of
/// numbers. A phone with no connection can play the whole thing.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'juz_index.dart';
import 'quran_search.dart';
import 'surah_facts.dart';
import 'surah_index.dart';

/// The six things a round can ask.
enum ArenaGame {
  /// The verse up to a pause; pick how it goes on.
  completeVerse,

  /// The verse with one word missing; pick the word.
  missingWord,

  /// A verse; name its surah.
  whichSurah,

  /// A verse; pick the verse that follows it.
  nextVerse,

  /// The words of a short verse, shuffled; put them back in order.
  orderWords,

  /// About the surah itself: its length, its place, its name.
  surahFacts,
}

/// What part of the Quran a round draws from.
enum ArenaScopeKind { quran, juz, surah }

/// The whole Quran, one juz, or one surah.
class ArenaScope {
  final ArenaScopeKind kind;

  /// The juz or surah number; 0 for the whole Quran.
  final int value;

  const ArenaScope._(this.kind, this.value);
  const ArenaScope.quran() : this._(ArenaScopeKind.quran, 0);
  const ArenaScope.juz(int juz) : this._(ArenaScopeKind.juz, juz);
  const ArenaScope.surah(int surah) : this._(ArenaScopeKind.surah, surah);

  bool get isQuran => kind == ArenaScopeKind.quran;
  bool get isJuz => kind == ArenaScopeKind.juz;
  bool get isSurah => kind == ArenaScopeKind.surah;

  /// A stable key, for best scores and the like: `q`, `j30`, `s18`.
  String get key => switch (kind) {
        ArenaScopeKind.quran => 'q',
        ArenaScopeKind.juz => 'j$value',
        ArenaScopeKind.surah => 's$value',
      };

  static ArenaScope? fromKey(String key) {
    if (key == 'q') return const ArenaScope.quran();
    if (key.length < 2) return null;
    final n = int.tryParse(key.substring(1));
    if (n == null) return null;
    if (key.startsWith('j') && n >= 1 && n <= 30) return ArenaScope.juz(n);
    if (key.startsWith('s') && n >= 1 && n <= 114) return ArenaScope.surah(n);
    return null;
  }

  /// The surahs the scope touches, in mushaf order.
  List<int> get surahs => switch (kind) {
        ArenaScopeKind.quran => [for (var s = 1; s <= 114; s++) s],
        ArenaScopeKind.surah => [value],
        ArenaScopeKind.juz => () {
            final (s0, _) = juzStart(value);
            final (s1, a1) = value < 30 ? juzStart(value + 1) : (114, 7);
            // The next juz opening on ayah 1 of a surah means that
            // surah is not in this one.
            final last = value < 30 && a1 == 1 ? s1 - 1 : s1;
            return [for (var s = s0; s <= last; s++) s];
          }(),
      };

  @override
  bool operator ==(Object other) =>
      other is ArenaScope && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'ArenaScope($key)';
}

/// Everything that decides which questions a round asks.
class ArenaSetup {
  final ArenaScope scope;
  final Set<ArenaGame> games;

  /// The clock on an ordinary question. Ordering words gets half as
  /// much again; a fact gets a little less.
  final int seconds;
  final int count;

  /// Whether a surah's name may be asked for by its meaning. Off for
  /// an Arabic reader, whose surah names are their meanings.
  final bool askMeanings;

  const ArenaSetup({
    required this.scope,
    required this.games,
    this.seconds = defaultSeconds,
    this.count = 10,
    this.askMeanings = true,
  });

  /// The clocks a round can be set to, and the one a round read back
  /// without one was played on.
  static const secondsOptions = [10, 15, 20, 30];
  static const defaultSeconds = 20;

  /// What the lobby opens on, every time: the longest clock, and the
  /// easiest question there is to answer. People found the arena hard
  /// on its old opening (every kind of question, twenty seconds each),
  /// so a first round is now the gentlest one, and anything harder is
  /// one tap away.
  static const longestSeconds = 30;
  static const easiestGame = ArenaGame.missingWord;

  /// The kinds of question from the easiest to answer to the hardest:
  /// a verse missing one word, its end to complete, its words to put in
  /// order, its surah to name, the verse that follows it, and facts about
  /// the surah itself.
  static const byEase = [
    ArenaGame.missingWord,
    ArenaGame.completeVerse,
    ArenaGame.orderWords,
    ArenaGame.whichSurah,
    ArenaGame.nextVerse,
    ArenaGame.surahFacts,
  ];

  /// [seconds] as the index a code carries, 0..3; anything the list
  /// does not hold rounds to the nearest it does.
  int get secondsIndex {
    var best = 0;
    for (var i = 1; i < secondsOptions.length; i++) {
      if ((secondsOptions[i] - seconds).abs() <
          (secondsOptions[best] - seconds).abs()) {
        best = i;
      }
    }
    return best;
  }

  ArenaSetup copyWith({
    ArenaScope? scope,
    Set<ArenaGame>? games,
    int? seconds,
    int? count,
    bool? askMeanings,
  }) =>
      ArenaSetup(
        scope: scope ?? this.scope,
        games: games ?? this.games,
        seconds: seconds ?? this.seconds,
        count: count ?? this.count,
        askMeanings: askMeanings ?? this.askMeanings,
      );

  /// The key a personal best is filed under.
  String get bestKey => scope.key;
}

/// A fact question's subject.
enum ArenaFactKind {
  verseCount,
  orderNumber,
  revelationPlace,
  comesAfter,
  nameMeaning,
  opensInJuz,
}

/// One thing that can be tapped as an answer. What it *is* decides
/// how the screen draws it and what a screen reader says.
sealed class ArenaOption {
  const ArenaOption();
}

/// A run of Quranic text — an ending, a word, a verse.
class VerseOption extends ArenaOption {
  final String text;
  const VerseOption(this.text);
}

/// A surah, by number; the screen names it in its own language.
class SurahOption extends ArenaOption {
  final int surah;
  const SurahOption(this.surah);
}

/// A plain number.
class NumberOption extends ArenaOption {
  final int number;
  const NumberOption(this.number);
}

/// Makkah or Madinah.
class PlaceOption extends ArenaOption {
  final bool makkah;
  const PlaceOption({required this.makkah});
}

/// A juz, by number.
class JuzOption extends ArenaOption {
  final int juz;
  const JuzOption(this.juz);
}

/// One question, ready to be asked.
class ArenaQuestion {
  final ArenaGame game;

  /// The verse the question is about; for a fact, the surah, with
  /// [ayah] 0.
  final int surah;
  final int ayah;

  /// Which fact, for [ArenaGame.surahFacts]; null otherwise.
  final ArenaFactKind? fact;

  /// The Arabic the question shows: the stem of a verse to complete,
  /// or the whole verse to name or follow. Empty for the word games
  /// (which show [tokens]) and for a fact.
  final String text;

  /// For a missing word: the verse's words in order, with the one at
  /// [blank] to be hidden. For ordering: the words, shuffled.
  final List<String> tokens;

  /// The index into [tokens] of the hidden word; -1 when none.
  final int blank;

  /// For ordering: `order[i]` is the index into [tokens] of the word
  /// that comes i-th in the verse.
  final List<int> order;

  final List<ArenaOption> options;

  /// The index of the right option; -1 for ordering, which has none.
  final int answer;

  /// How long the clock gives.
  final int seconds;

  const ArenaQuestion({
    required this.game,
    required this.surah,
    required this.ayah,
    this.fact,
    this.text = '',
    this.tokens = const [],
    this.blank = -1,
    this.order = const [],
    this.options = const [],
    this.answer = -1,
    required this.seconds,
  });

  /// The fact's meaning, in [lang]; only for a name question.
  String meaning(String lang) => surahFacts[surah - 1].meaning(lang);

  /// The answer as the option itself, for the reveal.
  ArenaOption? get correctOption => answer >= 0 ? options[answer] : null;

  /// For ordering: whether [sequence] — token indices, in the order
  /// they were placed — is the verse.
  bool ordered(List<int> sequence) {
    if (sequence.length != order.length) return false;
    for (var i = 0; i < order.length; i++) {
      if (sequence[i] != order[i]) return false;
    }
    return true;
  }
}

/// A verse as the arena reads it: its words, and the same words as
/// letters alone.
class ArenaVerse {
  final int surah;
  final int ayah;

  /// The words as the mushaf shows them, with no pause marks.
  final List<String> tokens;

  /// The same words normalized — see [QuranSearch.normalize].
  final List<String> keys;

  /// The whole verse normalized.
  final String key;

  /// Indices of the words a pause mark follows.
  final Set<int> pauseAfter;

  const ArenaVerse({
    required this.surah,
    required this.ayah,
    required this.tokens,
    required this.keys,
    required this.key,
    required this.pauseAfter,
  });

  int get words => tokens.length;

  String get text => tokens.join(' ');

  /// The last [n] words.
  String ending(int n) => tokens.sublist(tokens.length - n).join(' ');
  String endingKey(int n) => keys.sublist(keys.length - n).join(' ');
}

/// The Quran as the arena reads it, built once from the search index.
class ArenaCorpus {
  /// Surah by surah, index 0 being Al-Fatiha.
  final List<List<ArenaVerse>> bySurah;

  /// How many verses share a normalized text, across the Quran.
  final Map<String, int> keyCount;

  /// The same, within each surah.
  final List<Map<String, int>> surahKeyCount;

  /// Verses by their first two normalized words.
  final Map<String, List<ArenaVerse>> byOpening;

  ArenaCorpus._(this.bySurah, this.keyCount, this.surahKeyCount,
      this.byOpening);

  static Future<ArenaCorpus>? _loading;

  /// Reads the index once; the same corpus every call after that.
  /// Built off the UI isolate, for the reason [QuranSearch] parses
  /// there: every verse of the Quran tokenized and counted is a frozen
  /// lobby on a slow phone.
  /// A failed build (an isolate refused under memory pressure) isn't
  /// kept: the next call tries again instead of the lobby staying on
  /// "Opening…" until the app restarts.
  static Future<ArenaCorpus> load() => _loading ??= () async {
        try {
          final text = await QuranSearch.all();
          final keys = await QuranSearch.allKeys();
          return await compute(_buildFrom, (text, keys));
        } catch (_) {
          _loading = null;
          rethrow;
        }
      }();

  static ArenaCorpus _buildFrom(
          (List<List<String>>, List<List<String>>) index) =>
      build(index.$1, index.$2);

  /// Builds from the raw index — what [load] does, without the file.
  @visibleForTesting
  static ArenaCorpus build(List<List<String>> text, List<List<String>> keys) {
    final bySurah = <List<ArenaVerse>>[];
    final keyCount = <String, int>{};
    final surahKeyCount = <Map<String, int>>[];
    final byOpening = <String, List<ArenaVerse>>{};
    for (var s = 0; s < text.length; s++) {
      final verses = <ArenaVerse>[];
      final counts = <String, int>{};
      for (var a = 0; a < text[s].length; a++) {
        final raw = text[s][a].split(' ');
        final tokens = <String>[];
        final pauses = <int>{};
        for (final t in raw) {
          if (t.isEmpty) continue;
          if (_isMark(t)) {
            if (tokens.isNotEmpty) pauses.add(tokens.length - 1);
            continue;
          }
          tokens.add(t);
        }
        final key = keys[s][a];
        final normalized = key.isEmpty ? const <String>[] : key.split(' ');
        final v = ArenaVerse(
          surah: s + 1,
          ayah: a + 1,
          tokens: tokens,
          // A verse whose words and letters do not line up is kept
          // for the games that read it whole, and skipped by the
          // ones that read it word by word.
          keys: normalized.length == tokens.length ? normalized : const [],
          key: key,
          pauseAfter: pauses,
        );
        verses.add(v);
        keyCount[key] = (keyCount[key] ?? 0) + 1;
        counts[key] = (counts[key] ?? 0) + 1;
        if (normalized.length >= 2) {
          byOpening
              .putIfAbsent('${normalized[0]} ${normalized[1]}', () => [])
              .add(v);
        }
      }
      bySurah.add(verses);
      surahKeyCount.add(counts);
    }
    return ArenaCorpus._(bySurah, keyCount, surahKeyCount, byOpening);
  }

  /// A token that is a pause mark rather than a word: the small
  /// letters the mushaf sets between words, and the sajdah sign.
  static bool _isMark(String t) {
    for (final c in t.runes) {
      if (!((c >= 0x06D6 && c <= 0x06ED) || c == 0x0670 || c == 0x0640)) {
        return false;
      }
    }
    return true;
  }

  ArenaVerse verse(int surah, int ayah) => bySurah[surah - 1][ayah - 1];

  /// Every verse in [scope], in mushaf order.
  List<ArenaVerse> versesIn(ArenaScope scope) {
    switch (scope.kind) {
      case ArenaScopeKind.quran:
        return [for (final s in bySurah) ...s];
      case ArenaScopeKind.surah:
        return bySurah[scope.value - 1];
      case ArenaScopeKind.juz:
        final out = <ArenaVerse>[];
        for (final s in bySurah) {
          for (final v in s) {
            if (juzOf(v.surah, v.ayah) == scope.value) out.add(v);
          }
        }
        return out;
    }
  }

  /// Whether the verse's text appears nowhere else in the Quran.
  bool uniqueInQuran(ArenaVerse v) => keyCount[v.key] == 1;

  /// Whether the verse's text appears nowhere else in its surah.
  bool uniqueInSurah(ArenaVerse v) => surahKeyCount[v.surah - 1][v.key] == 1;

  /// Whether another verse begins with the same [n] normalized words
  /// as [v] — which would make "how does it go on" a question with
  /// two right answers.
  bool stemShared(ArenaVerse v, int n) {
    if (v.keys.length < 2) return true;
    final others = byOpening['${v.keys[0]} ${v.keys[1]}'] ?? const [];
    for (final o in others) {
      if (identical(o, v)) continue;
      if (o.keys.length < n) continue;
      var same = true;
      for (var i = 0; i < n; i++) {
        if (o.keys[i] != v.keys[i]) {
          same = false;
          break;
        }
      }
      if (same) return true;
    }
    return false;
  }

  /// Which games can ask at least one question in [scope].
  Set<ArenaGame> feasible(ArenaScope scope, {bool askMeanings = true}) {
    final pool = versesIn(scope);
    final out = <ArenaGame>{};
    for (final v in pool) {
      if (v.keys.isEmpty) continue;
      if (!out.contains(ArenaGame.completeVerse) &&
          _Maker.completable(this, v)) {
        out.add(ArenaGame.completeVerse);
      }
      if (!out.contains(ArenaGame.missingWord) &&
          _Maker.blankable(v).isNotEmpty) {
        out.add(ArenaGame.missingWord);
      }
      if (!out.contains(ArenaGame.orderWords) && _Maker.orderable(v)) {
        out.add(ArenaGame.orderWords);
      }
      if (!out.contains(ArenaGame.nextVerse) && _Maker.followable(this, v)) {
        out.add(ArenaGame.nextVerse);
      }
      if (!out.contains(ArenaGame.whichSurah) &&
          !scope.isSurah &&
          _Maker.nameable(this, v)) {
        out.add(ArenaGame.whichSurah);
      }
    }
    out.add(ArenaGame.surahFacts);
    return out;
  }
}

/// A round: the questions a setup and a seed produce.
class ArenaRound {
  final ArenaSetup setup;
  final int seed;
  final List<ArenaQuestion> questions;

  const ArenaRound({
    required this.setup,
    required this.seed,
    required this.questions,
  });

  /// Seeds are twenty bits, so a round fits in a challenge code.
  static const seedBits = 20;
  static const seedLimit = 1 << seedBits;

  static int newSeed([math.Random? rnd]) =>
      (rnd ?? math.Random()).nextInt(seedLimit);

  /// The round [setup] and [seed] name. Deterministic: a second call
  /// with the same arguments builds the same questions, in the same
  /// order, with the options in the same order.
  static ArenaRound generate(ArenaCorpus corpus, ArenaSetup setup, int seed) {
    final rnd = math.Random(seed);
    final maker = _Maker(corpus, setup, rnd);
    final games = corpus
        .feasible(setup.scope, askMeanings: setup.askMeanings)
        .where(setup.games.contains)
        .toList();
    if (games.isEmpty) {
      // Nothing the user asked for can be asked here; fall back to
      // what can, so a round is never empty.
      games.addAll(corpus.feasible(setup.scope));
    }
    games.shuffle(rnd);
    final questions = <ArenaQuestion>[];
    final exhausted = <ArenaGame>{};
    var i = 0;
    while (questions.length < setup.count && exhausted.length < games.length) {
      final game = games[i % games.length];
      i++;
      if (exhausted.contains(game)) continue;
      final q = maker.make(game);
      if (q == null) {
        exhausted.add(game);
      } else {
        questions.add(q);
      }
    }
    return ArenaRound(setup: setup, seed: seed, questions: questions);
  }
}

/// Builds one question at a time, remembering what it has used.
class _Maker {
  final ArenaCorpus corpus;
  final ArenaSetup setup;
  final math.Random rnd;

  late final List<ArenaVerse> pool = corpus.versesIn(setup.scope);
  late final List<ArenaVerse> quran = corpus.versesIn(const ArenaScope.quran());
  late final List<int> surahs = setup.scope.surahs;

  /// Verses already asked about, in any game.
  final Set<({int surah, int ayah})> used = {};

  /// Facts already asked.
  final Set<(ArenaFactKind, int)> usedFacts = {};

  _Maker(this.corpus, this.setup, this.rnd);

  int seconds(ArenaGame game) {
    final base = setup.seconds;
    return switch (game) {
      ArenaGame.orderWords => base + base ~/ 2,
      ArenaGame.surahFacts => math.max(8, base - 5),
      _ => base,
    };
  }

  ArenaQuestion? make(ArenaGame game) {
    // A handful of random draws; a scope this small that none of them
    // lands is a scope this game has run dry in.
    for (var attempt = 0; attempt < 48; attempt++) {
      final q = switch (game) {
        ArenaGame.completeVerse => _complete(),
        ArenaGame.missingWord => _missing(),
        ArenaGame.whichSurah => _which(),
        ArenaGame.nextVerse => _next(),
        ArenaGame.orderWords => _order(),
        ArenaGame.surahFacts => _fact(),
      };
      if (q != null) return q;
    }
    return null;
  }

  ArenaVerse _draw(List<ArenaVerse> from) => from[rnd.nextInt(from.length)];

  bool _fresh(ArenaVerse v) => !used.contains((surah: v.surah, ayah: v.ayah));

  void _use(ArenaVerse v) => used.add((surah: v.surah, ayah: v.ayah));

  /// [answer] and [wrong], shuffled; returns the options and where the
  /// answer landed.
  (List<ArenaOption>, int) _deal(ArenaOption answer, List<ArenaOption> wrong) {
    final all = [answer, ...wrong]..shuffle(rnd);
    return (all, all.indexOf(answer));
  }

  // ---- complete the verse -------------------------------------------

  static bool completable(ArenaCorpus c, ArenaVerse v) =>
      v.keys.isNotEmpty && v.words >= 5 && v.words <= 24;

  ArenaQuestion? _complete() {
    final v = _draw(pool);
    if (!completable(corpus, v) || !_fresh(v)) return null;
    final w = v.words;
    var cut = (w * 0.55).round().clamp(2, w - 2);
    // A cut on a pause, when there is one within reach: that is where
    // the verse itself breathes, and where a reciter would stop.
    for (var d = 0; d <= 2; d++) {
      if (v.pauseAfter.contains(cut - 1 + d) && cut + d <= w - 2) {
        cut += d;
        break;
      }
      if (v.pauseAfter.contains(cut - 1 - d) && cut - d >= 2) {
        cut -= d;
        break;
      }
    }
    // Lengthen the stem until no other verse shares it.
    while (cut <= w - 2 && corpus.stemShared(v, cut)) {
      cut++;
    }
    if (cut > w - 2) return null;
    final endLen = w - cut;
    if (endLen > 16) return null;
    final answer = v.ending(endLen);
    final answerKey = v.endingKey(endLen);
    final wrong = <VerseOption>[];
    final seen = <String>{answerKey};
    // Endings of other verses of the same length: the same surah's
    // first, then the scope's, then anyone's.
    for (final source in [
      corpus.bySurah[v.surah - 1],
      pool,
      quran,
    ]) {
      final candidates = source
          .where((o) =>
              o.keys.isNotEmpty &&
              o.words > endLen &&
              (o.surah != v.surah || o.ayah != v.ayah))
          .toList();
      for (var t = 0; t < 200 && wrong.length < 3 && candidates.isNotEmpty; t++) {
        final o = candidates[rnd.nextInt(candidates.length)];
        final k = o.endingKey(endLen);
        if (seen.contains(k)) continue;
        // Not an ending that starts the way the real one does: the
        // eye should have to read it.
        if (o.keys[o.words - endLen] == v.keys[cut] && t < 100) continue;
        seen.add(k);
        wrong.add(VerseOption(o.ending(endLen)));
      }
      if (wrong.length >= 3) break;
    }
    if (wrong.length < 3) return null;
    _use(v);
    final (options, index) = _deal(VerseOption(answer), wrong);
    return ArenaQuestion(
      game: ArenaGame.completeVerse,
      surah: v.surah,
      ayah: v.ayah,
      text: v.tokens.sublist(0, cut).join(' '),
      options: options,
      answer: index,
      seconds: seconds(ArenaGame.completeVerse),
    );
  }

  // ---- the missing word ---------------------------------------------

  /// Words that carry meaning on their own, and are worth asking for.
  static const _particles = <String>{
    'من', 'في', 'ما', 'لا', 'ان', 'الي', 'علي', 'عن', 'هو', 'هي', 'هم',
    'ثم', 'او', 'بل', 'قد', 'لم', 'لن', 'كل', 'بعد', 'قبل', 'اذ', 'اذا',
    'ذلك', 'الذي', 'الذين', 'التي', 'مع', 'ولا', 'وما', 'وان', 'فان',
    'فلا', 'ولم', 'يا', 'انا', 'نحن', 'انت', 'انتم', 'هذا', 'هذه', 'تلك',
    'عند', 'حتي', 'كان', 'كانوا', 'ليس', 'فيه', 'فيها', 'له', 'لها',
    'لهم', 'لكم', 'بها', 'بهم', 'منها', 'منهم', 'عليه', 'عليها', 'عليهم',
    'اليه', 'اليها', 'اليهم', 'به', 'بك', 'بي', 'لي', 'لك', 'اما', 'اي',
    'ايها', 'الا', 'فما', 'ومن', 'وهو', 'وهم', 'انه', 'انها',
    'انهم', 'لما', 'كما', 'فيما', 'مما', 'عما', 'ذا', 'كذلك', 'هنالك',
  };

  static List<int> blankable(ArenaVerse v) {
    if (v.keys.isEmpty || v.words < 4 || v.words > 20) return const [];
    return [
      for (var i = 0; i < v.words; i++)
        if (v.keys[i].length >= 3 && !_particles.contains(v.keys[i])) i,
    ];
  }

  ArenaQuestion? _missing() {
    final v = _draw(pool);
    if (!_fresh(v)) return null;
    final blanks = blankable(v);
    if (blanks.isEmpty) return null;
    final blank = blanks[rnd.nextInt(blanks.length)];
    final answerKey = v.keys[blank];
    final inVerse = v.keys.toSet();
    final wrong = <VerseOption>[];
    final seen = <String>{answerKey};
    bool fits(String k, int slack) =>
        (k.length - answerKey.length).abs() <= slack &&
        !inVerse.contains(k) &&
        !_particles.contains(k) &&
        k.length >= 3;
    for (final (source, slack) in [
      (corpus.bySurah[v.surah - 1], 0),
      (pool, 0),
      (quran, 1),
      (quran, 3),
    ]) {
      for (var t = 0; t < 300 && wrong.length < 3; t++) {
        final o = source[rnd.nextInt(source.length)];
        if (o.keys.isEmpty) continue;
        final i = rnd.nextInt(o.words);
        final k = o.keys[i];
        if (seen.contains(k) || !fits(k, slack)) continue;
        // A wrong word rhymes with the right one for as long as one
        // can be found: the ear should not be able to answer alone.
        if (t < 150 && k[k.length - 1] != answerKey[answerKey.length - 1]) {
          continue;
        }
        seen.add(k);
        wrong.add(VerseOption(o.tokens[i]));
      }
      if (wrong.length >= 3) break;
    }
    if (wrong.length < 3) return null;
    _use(v);
    final (options, index) = _deal(VerseOption(v.tokens[blank]), wrong);
    return ArenaQuestion(
      game: ArenaGame.missingWord,
      surah: v.surah,
      ayah: v.ayah,
      tokens: v.tokens,
      blank: blank,
      options: options,
      answer: index,
      seconds: seconds(ArenaGame.missingWord),
    );
  }

  // ---- which surah ----------------------------------------------------

  static bool nameable(ArenaCorpus c, ArenaVerse v) =>
      v.words >= 4 && v.words <= 20 && c.uniqueInQuran(v);

  ArenaQuestion? _which() {
    if (setup.scope.isSurah) return null;
    final v = _draw(pool);
    if (!nameable(corpus, v) || !_fresh(v)) return null;
    final wrong = _otherSurahs(v.surah, 3, near: true);
    if (wrong.length < 3) return null;
    _use(v);
    final (options, index) =
        _deal(SurahOption(v.surah), [for (final s in wrong) SurahOption(s)]);
    return ArenaQuestion(
      game: ArenaGame.whichSurah,
      surah: v.surah,
      ayah: v.ayah,
      text: v.text,
      options: options,
      answer: index,
      seconds: seconds(ArenaGame.whichSurah),
    );
  }

  /// [n] surahs other than [surah] — its neighbours in the mushaf
  /// when [near], anyone otherwise. Never fewer than [n] as long as
  /// the Quran has that many surahs, which it does.
  List<int> _otherSurahs(int surah, int n, {required bool near}) {
    final out = <int>{};
    if (near) {
      // The same juz first, which is where a learner's confusion
      // actually lives, then the neighbours either side.
      final juz = juzOfSurah(surah);
      final sameJuz = [
        for (var s = 1; s <= 114; s++)
          if (s != surah && juzOfSurah(s) == juz) s
      ]..shuffle(rnd);
      out.addAll(sameJuz.take(n));
      for (var d = 1; out.length < n && d <= 114; d++) {
        for (final s in [surah - d, surah + d]) {
          if (s >= 1 && s <= 114 && s != surah) out.add(s);
          if (out.length >= n) break;
        }
      }
    }
    for (var t = 0; out.length < n && t < 400; t++) {
      final s = 1 + rnd.nextInt(114);
      if (s != surah) out.add(s);
    }
    return out.take(n).toList()..shuffle(rnd);
  }

  // ---- what comes next ------------------------------------------------

  static bool followable(ArenaCorpus c, ArenaVerse v) {
    final surah = c.bySurah[v.surah - 1];
    if (surah.length < 5 || v.ayah >= surah.length) return false;
    final next = surah[v.ayah];
    return v.words >= 3 &&
        v.words <= 24 &&
        next.words >= 2 &&
        next.words <= 24 &&
        c.uniqueInSurah(v) &&
        c.uniqueInSurah(next);
  }

  ArenaQuestion? _next() {
    final v = _draw(pool);
    if (!followable(corpus, v) || !_fresh(v)) return null;
    final surah = corpus.bySurah[v.surah - 1];
    final next = surah[v.ayah];
    final wrong = <VerseOption>[];
    final seen = <String>{next.key, v.key};
    final candidates = surah
        .where((o) =>
            o.ayah != v.ayah &&
            o.ayah != next.ayah &&
            o.words >= 2 &&
            o.words <= 24)
        .toList();
    if (candidates.length < 3) return null;
    for (var t = 0; t < 200 && wrong.length < 3; t++) {
      final o = candidates[rnd.nextInt(candidates.length)];
      if (seen.contains(o.key)) continue;
      // Close in length, so length gives nothing away; a verse three
      // times the size of the others is a verse nobody has to read.
      if (t < 100 && (o.words - next.words).abs() > 3) continue;
      seen.add(o.key);
      wrong.add(VerseOption(o.text));
    }
    if (wrong.length < 3) return null;
    _use(v);
    _use(next);
    final (options, index) = _deal(VerseOption(next.text), wrong);
    return ArenaQuestion(
      game: ArenaGame.nextVerse,
      surah: v.surah,
      ayah: v.ayah,
      text: v.text,
      options: options,
      answer: index,
      seconds: seconds(ArenaGame.nextVerse),
    );
  }

  // ---- order the words ------------------------------------------------

  static bool orderable(ArenaVerse v) =>
      v.keys.isNotEmpty &&
      v.words >= 4 &&
      v.words <= 8 &&
      v.keys.toSet().length == v.words;

  ArenaQuestion? _order() {
    final v = _draw(pool);
    if (!orderable(v) || !_fresh(v)) return null;
    final n = v.words;
    final indices = [for (var i = 0; i < n; i++) i];
    // Shuffled until it is actually out of order.
    for (var t = 0; t < 20; t++) {
      indices.shuffle(rnd);
      var moved = false;
      for (var i = 0; i < n; i++) {
        if (indices[i] != i) {
          moved = true;
          break;
        }
      }
      if (moved) break;
    }
    // tokens[j] is the verse's word indices[j]; order[i] is where
    // word i went.
    final tokens = [for (final i in indices) v.tokens[i]];
    final order = List<int>.filled(n, 0);
    for (var j = 0; j < n; j++) {
      order[indices[j]] = j;
    }
    _use(v);
    return ArenaQuestion(
      game: ArenaGame.orderWords,
      surah: v.surah,
      ayah: v.ayah,
      tokens: tokens,
      order: order,
      seconds: seconds(ArenaGame.orderWords),
    );
  }

  // ---- surah facts ----------------------------------------------------

  ArenaQuestion? _fact() {
    final surah = surahs[rnd.nextInt(surahs.length)];
    final fact = surahFacts[surah - 1];
    final kinds = [
      ArenaFactKind.verseCount,
      ArenaFactKind.orderNumber,
      if (!fact.disputed) ArenaFactKind.revelationPlace,
      if (surah < 114) ArenaFactKind.comesAfter,
      if (setup.askMeanings) ArenaFactKind.nameMeaning,
      ArenaFactKind.opensInJuz,
    ]..shuffle(rnd);
    for (final kind in kinds) {
      if (usedFacts.contains((kind, surah))) continue;
      final q = _factOf(kind, surah);
      if (q == null) continue;
      usedFacts.add((kind, surah));
      return q;
    }
    return null;
  }

  ArenaQuestion? _factOf(ArenaFactKind kind, int surah) {
    final secs = seconds(ArenaGame.surahFacts);
    ArenaQuestion q(List<ArenaOption> options, int answer) => ArenaQuestion(
          game: ArenaGame.surahFacts,
          surah: surah,
          ayah: 0,
          fact: kind,
          options: options,
          answer: answer,
          seconds: secs,
        );
    switch (kind) {
      case ArenaFactKind.verseCount:
        final count = surahIndex[surah - 1].ayahCount;
        final wrong = <int>{};
        // Other surahs' lengths near this one, so every number on the
        // screen is a length some surah really has.
        final near = [
          for (final s in surahIndex)
            if (s.number != surah &&
                s.ayahCount != count &&
                (s.ayahCount - count).abs() <= math.max(3, count ~/ 2))
              s.ayahCount
        ]..shuffle(rnd);
        wrong.addAll(near.take(3));
        for (var d = 1; wrong.length < 3; d++) {
          for (final c in [count + d, count - d]) {
            if (c > 0 && c != count) wrong.add(c);
            if (wrong.length >= 3) break;
          }
        }
        final (options, answer) = _deal(NumberOption(count),
            [for (final c in wrong.take(3)) NumberOption(c)]);
        return q(options, answer);
      case ArenaFactKind.orderNumber:
        final others = _otherSurahs(surah, 3, near: true);
        final (options, answer) = _deal(
            SurahOption(surah), [for (final s in others) SurahOption(s)]);
        return q(options, answer);
      case ArenaFactKind.revelationPlace:
        final fact = surahFacts[surah - 1];
        if (fact.disputed) return null;
        return q(const [PlaceOption(makkah: true), PlaceOption(makkah: false)],
            fact.makki ? 0 : 1);
      case ArenaFactKind.comesAfter:
        if (surah >= 114) return null;
        final others = <int>{};
        // The neighbours, which is the whole difficulty of the
        // question, then anyone.
        for (final s in [surah - 1, surah + 2, surah + 3, surah - 2]) {
          if (s >= 1 && s <= 114 && s != surah && s != surah + 1) {
            others.add(s);
          }
        }
        for (final s in _otherSurahs(surah, 6, near: false)) {
          if (others.length >= 3) break;
          if (s != surah + 1) others.add(s);
        }
        final wrong = others.toList()..shuffle(rnd);
        final (options, answer) = _deal(SurahOption(surah + 1),
            [for (final s in wrong.take(3)) SurahOption(s)]);
        return q(options, answer);
      case ArenaFactKind.nameMeaning:
        if (!setup.askMeanings) return null;
        final others = _otherSurahs(surah, 3, near: true);
        final (options, answer) = _deal(
            SurahOption(surah), [for (final s in others) SurahOption(s)]);
        return q(options, answer);
      case ArenaFactKind.opensInJuz:
        final juz = juzOfSurah(surah);
        final wrong = <int>{};
        for (var d = 1; wrong.length < 3 && d <= 30; d++) {
          for (final j in [juz + d, juz - d]) {
            if (j >= 1 && j <= 30 && j != juz) wrong.add(j);
            if (wrong.length >= 3) break;
          }
        }
        final list = wrong.toList()..shuffle(rnd);
        final (options, answer) =
            _deal(JuzOption(juz), [for (final j in list) JuzOption(j)]);
        return q(options, answer);
    }
  }
}

/// What a question is worth.
///
/// A right answer is a hundred, up to fifty more for the time left on
/// the clock, and a run of right answers multiplies it: three in a row
/// is a quarter more, five in a row half again. A wrong answer, or the
/// clock running out, is nothing — and ends the run.
abstract final class ArenaScoring {
  static const base = 100;
  static const speedBonus = 50;

  static int points({
    required bool correct,
    required double timeLeft,
    required int combo,
  }) {
    if (!correct) return 0;
    final raw = base + (speedBonus * timeLeft.clamp(0.0, 1.0)).round();
    return (raw * multiplier(combo)).round();
  }

  /// [combo] counts this answer: the third right in a row is 3.
  static double multiplier(int combo) => combo >= 5
      ? 1.5
      : combo >= 3
          ? 1.25
          : 1.0;

  /// The most [questions] can be worth.
  static int maxFor(int questions) {
    var total = 0;
    for (var i = 1; i <= questions; i++) {
      total += points(correct: true, timeLeft: 1, combo: i);
    }
    return total;
  }
}

/// How one question went.
class ArenaAnswer {
  /// The option tapped; -1 for the clock running out, or an ordering.
  final int chosen;
  final bool correct;

  /// Fraction of the clock left when it was answered, 0..1.
  final double timeLeft;
  final int points;

  const ArenaAnswer({
    required this.chosen,
    required this.correct,
    required this.timeLeft,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'c': chosen,
        'ok': correct,
        't': timeLeft,
        'p': points,
      };

  static ArenaAnswer fromJson(Map<String, dynamic> j) => ArenaAnswer(
        chosen: j['c'] as int? ?? -1,
        correct: j['ok'] as bool? ?? false,
        timeLeft: (j['t'] as num?)?.toDouble() ?? 0,
        points: j['p'] as int? ?? 0,
      );
}

/// How a round went, for one player.
class ArenaResult {
  final ArenaSetup setup;
  final int seed;
  final List<ArenaAnswer> answers;

  const ArenaResult({
    required this.setup,
    required this.seed,
    required this.answers,
  });

  int get score => answers.fold(0, (s, a) => s + a.points);
  int get correct => answers.where((a) => a.correct).length;
  int get asked => answers.length;
  double get fraction => asked == 0 ? 0 : correct / asked;

  /// The longest run of right answers.
  int get bestRun {
    var best = 0, run = 0;
    for (final a in answers) {
      run = a.correct ? run + 1 : 0;
      if (run > best) best = run;
    }
    return best;
  }

  /// The standing the round earns, 0..4: the name is the screen's.
  int get tier => asked > 0 && correct == asked
      ? 4
      : fraction >= 0.8
          ? 3
          : fraction >= 0.6
              ? 2
              : fraction >= 0.4
                  ? 1
                  : 0;
}
