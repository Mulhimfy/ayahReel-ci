import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/arena_engine.dart';
import 'package:ayah_reels/data/juz_index.dart';
import 'package:ayah_reels/data/quran_search.dart';
import 'package:ayah_reels/data/surah_facts.dart';
import 'package:ayah_reels/data/surah_index.dart';

/// The arena's questions, checked against the Quran they are made
/// from: every right answer really is the verse, every wrong one
/// really is not, and the same seed makes the same round twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ArenaCorpus corpus;

  setUpAll(() async {
    QuranSearch.loadFrom(await rootBundle.loadString(QuranSearch.asset));
    corpus = await ArenaCorpus.load();
  });

  const allGames = {
    ArenaGame.completeVerse,
    ArenaGame.missingWord,
    ArenaGame.whichSurah,
    ArenaGame.nextVerse,
    ArenaGame.orderWords,
    ArenaGame.surahFacts,
  };

  group('the corpus', () {
    test('is the whole Quran, word for word', () {
      expect(corpus.bySurah, hasLength(114));
      var verses = 0, irregular = 0;
      for (var s = 0; s < 114; s++) {
        expect(corpus.bySurah[s], hasLength(surahIndex[s].ayahCount),
            reason: 'surah ${s + 1}');
        for (final v in corpus.bySurah[s]) {
          verses++;
          expect(v.tokens, isNotEmpty);
          if (v.keys.isEmpty) irregular++;
          // No pause mark survives as a word.
          for (final t in v.tokens) {
            expect(t.runes.any((c) => c < 0x06D6 || c > 0x06ED), isTrue,
                reason: '${v.surah}:${v.ayah} keeps "$t" as a word');
          }
        }
      }
      expect(verses, 6236);
      // Every verse's words line up with its letters, so every verse
      // is open to the word games.
      expect(irregular, 0);
    });

    test('knows which verses repeat', () {
      // Ar-Rahman's refrain is not one verse and not unique to one
      // place in its surah.
      final refrain = corpus.verse(55, 13);
      expect(corpus.uniqueInQuran(refrain), isFalse);
      expect(corpus.uniqueInSurah(refrain), isFalse);
      // The opening letters open six surahs.
      expect(corpus.keyCount[corpus.verse(2, 1).key], 6);
      expect(corpus.uniqueInQuran(corpus.verse(2, 255)), isTrue);
    });

    test('sees a shared stem', () {
      // "يا أيها الذين آمنوا" opens dozens of verses; three words of
      // it name none of them.
      final v = corpus.verse(2, 153);
      expect(corpus.stemShared(v, 3), isTrue);
      // Ayat al-Kursi opens with the same seven words as 3:2 — so a
      // stem of seven words is two verses, and one of eight is one.
      expect(corpus.stemShared(corpus.verse(2, 255), 7), isTrue);
      expect(corpus.stemShared(corpus.verse(2, 255), 8), isFalse);
    });
  });

  group('the juz', () {
    test('thirty of them cover the Quran, in order, without a gap', () {
      var last = 1;
      var total = 0;
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= surahIndex[s - 1].ayahCount; a++) {
          final j = juzOf(s, a);
          expect(j, inInclusiveRange(last, last + 1), reason: '$s:$a');
          last = j;
          total++;
        }
      }
      expect(last, 30);
      expect(total, 6236);
      expect(juzOf(1, 1), 1);
      expect(juzOf(2, 141), 1);
      expect(juzOf(2, 142), 2);
      expect(juzOf(18, 74), 15);
      expect(juzOf(18, 75), 16);
      expect(juzOf(78, 1), 30);
      expect(juzOfSurah(67), 29);
    });

    test('a juz scope names the surahs it touches', () {
      expect(const ArenaScope.juz(1).surahs, [1, 2]);
      expect(const ArenaScope.juz(2).surahs, [2]);
      expect(const ArenaScope.juz(30).surahs,
          [for (var s = 78; s <= 114; s++) s]);
      expect(const ArenaScope.juz(29).surahs,
          [for (var s = 67; s <= 77; s++) s]);
      // Juz 16 opens mid-Kahf and ends at the end of Ta-Ha; juz 17
      // opens on Al-Anbiya 1.
      expect(const ArenaScope.juz(16).surahs, [18, 19, 20]);
      var total = 0;
      for (var j = 1; j <= 30; j++) {
        total += corpus.versesIn(ArenaScope.juz(j)).length;
      }
      expect(total, 6236);
      expect(corpus.versesIn(const ArenaScope.surah(112)), hasLength(4));
    });

    test('scope keys round-trip', () {
      for (final s in [
        const ArenaScope.quran(),
        const ArenaScope.juz(30),
        const ArenaScope.surah(18),
      ]) {
        expect(ArenaScope.fromKey(s.key), s);
      }
      expect(ArenaScope.fromKey(''), isNull);
      expect(ArenaScope.fromKey('j'), isNull);
      expect(ArenaScope.fromKey('j31'), isNull);
      expect(ArenaScope.fromKey('s0'), isNull);
      expect(ArenaScope.fromKey('x'), isNull);
    });
  });

  group('a round', () {
    /// Everything a question claims, checked against the corpus.
    void verify(ArenaQuestion q, ArenaSetup setup) {
      final where = '${q.game.name} ${q.surah}:${q.ayah}';
      if (q.game != ArenaGame.orderWords) {
        expect(q.answer, inInclusiveRange(0, q.options.length - 1),
            reason: where);
        expect(q.options.length,
            q.fact == ArenaFactKind.revelationPlace ? 2 : 4,
            reason: where);
        // No two options say the same thing.
        final seen = <String>{};
        for (final o in q.options) {
          final key = switch (o) {
            VerseOption(:final text) => 'v${QuranSearch.normalize(text)}',
            SurahOption(:final surah) => 's$surah',
            NumberOption(:final number) => 'n$number',
            PlaceOption(:final makkah) => 'p$makkah',
            JuzOption(:final juz) => 'j$juz',
          };
          expect(seen.add(key), isTrue, reason: '$where repeats $key');
        }
      }
      if (q.game != ArenaGame.surahFacts) {
        expect(q.surah, inInclusiveRange(1, 114));
        expect(q.ayah, inInclusiveRange(1, surahIndex[q.surah - 1].ayahCount));
        // The verse is in scope.
        switch (setup.scope.kind) {
          case ArenaScopeKind.quran:
            break;
          case ArenaScopeKind.juz:
            expect(juzOf(q.surah, q.ayah), setup.scope.value, reason: where);
          case ArenaScopeKind.surah:
            expect(q.surah, setup.scope.value, reason: where);
        }
      }
      final v = q.ayah > 0 ? corpus.verse(q.surah, q.ayah) : null;
      switch (q.game) {
        case ArenaGame.completeVerse:
          final answer = (q.options[q.answer] as VerseOption).text;
          expect('${q.text} $answer', v!.text, reason: where);
          // No wrong ending is the verse's ending.
          for (var i = 0; i < q.options.length; i++) {
            if (i == q.answer) continue;
            final t = (q.options[i] as VerseOption).text;
            expect(QuranSearch.normalize('${q.text} $t'),
                isNot(v.key), reason: where);
          }
          // The stem is not another verse's stem.
          expect(corpus.stemShared(v, q.text.split(' ').length), isFalse,
              reason: where);
        case ArenaGame.missingWord:
          expect(q.tokens, v!.tokens, reason: where);
          expect(q.blank, inInclusiveRange(0, q.tokens.length - 1));
          expect((q.options[q.answer] as VerseOption).text, q.tokens[q.blank],
              reason: where);
          for (var i = 0; i < q.options.length; i++) {
            if (i == q.answer) continue;
            final k = QuranSearch.normalize((q.options[i] as VerseOption).text);
            expect(v.keys, isNot(contains(k)), reason: where);
          }
        case ArenaGame.whichSurah:
          expect(q.text, v!.text, reason: where);
          expect((q.options[q.answer] as SurahOption).surah, q.surah);
          expect(corpus.uniqueInQuran(v), isTrue, reason: where);
          expect(setup.scope.isSurah, isFalse);
        case ArenaGame.nextVerse:
          expect(q.text, v!.text, reason: where);
          final next = corpus.verse(q.surah, q.ayah + 1);
          expect((q.options[q.answer] as VerseOption).text, next.text,
              reason: where);
          for (var i = 0; i < q.options.length; i++) {
            if (i == q.answer) continue;
            final t = (q.options[i] as VerseOption).text;
            expect(QuranSearch.normalize(t), isNot(next.key), reason: where);
          }
          expect(corpus.uniqueInSurah(v), isTrue, reason: where);
        case ArenaGame.orderWords:
          expect(q.tokens.length, v!.words, reason: where);
          expect(q.order.length, v.words);
          expect([for (final i in q.order) q.tokens[i]], v.tokens,
              reason: where);
          expect(q.ordered(q.order), isTrue);
          expect(q.ordered(q.order.reversed.toList()), isFalse);
          // Actually shuffled.
          expect(q.tokens, isNot(v.tokens), reason: where);
        case ArenaGame.surahFacts:
          expect(q.ayah, 0);
          final fact = surahFacts[q.surah - 1];
          switch (q.fact!) {
            case ArenaFactKind.verseCount:
              expect((q.options[q.answer] as NumberOption).number,
                  surahIndex[q.surah - 1].ayahCount);
            case ArenaFactKind.orderNumber:
            case ArenaFactKind.nameMeaning:
              expect((q.options[q.answer] as SurahOption).surah, q.surah);
            case ArenaFactKind.revelationPlace:
              expect(fact.disputed, isFalse, reason: where);
              expect((q.options[q.answer] as PlaceOption).makkah, fact.makki);
            case ArenaFactKind.comesAfter:
              expect((q.options[q.answer] as SurahOption).surah, q.surah + 1);
            case ArenaFactKind.opensInJuz:
              expect((q.options[q.answer] as JuzOption).juz,
                  juzOfSurah(q.surah));
          }
          if (!setup.askMeanings) {
            expect(q.fact, isNot(ArenaFactKind.nameMeaning));
          }
      }
    }

    test('is the same round for the same seed, and a different one for '
        'another', () {
      const setup = ArenaSetup(scope: ArenaScope.quran(), games: allGames);
      final a = ArenaRound.generate(corpus, setup, 4242);
      final b = ArenaRound.generate(corpus, setup, 4242);
      final c = ArenaRound.generate(corpus, setup, 4243);
      expect(a.questions, hasLength(10));
      for (var i = 0; i < 10; i++) {
        final x = a.questions[i], y = b.questions[i];
        expect(x.game, y.game);
        expect((x.surah, x.ayah), (y.surah, y.ayah));
        expect(x.text, y.text);
        expect(x.tokens, y.tokens);
        expect(x.order, y.order);
        expect(x.answer, y.answer);
        expect(x.options.length, y.options.length);
      }
      expect(
          [for (final q in a.questions) (q.game, q.surah, q.ayah)],
          isNot([for (final q in c.questions) (q.game, q.surah, q.ayah)]));
    });

    test('never asks about one verse twice', () {
      for (var seed = 0; seed < 30; seed++) {
        final round = ArenaRound.generate(corpus,
            const ArenaSetup(scope: ArenaScope.juz(30), games: allGames),
            seed);
        final seen = <(int, int)>{};
        for (final q in round.questions.where((q) => q.ayah > 0)) {
          expect(seen.add((q.surah, q.ayah)), isTrue,
              reason: 'seed $seed repeats ${q.surah}:${q.ayah}');
        }
      }
    });

    test('every question is true to the Quran, in every scope and game',
        () {
      final scopes = [
        const ArenaScope.quran(),
        const ArenaScope.juz(1),
        const ArenaScope.juz(16),
        const ArenaScope.juz(30),
        const ArenaScope.surah(2),
        const ArenaScope.surah(18),
        const ArenaScope.surah(55),
        const ArenaScope.surah(112),
        const ArenaScope.surah(108),
      ];
      var asked = 0;
      final byGame = <ArenaGame, int>{};
      for (final scope in scopes) {
        // The same six rounds a scope had when each was also played at
        // four clocks, which never changed a question.
        for (var seed = 0; seed < 6; seed++) {
          final setup = ArenaSetup(
              scope: scope, games: allGames, askMeanings: seed.isEven);
          final round = ArenaRound.generate(corpus, setup, seed * 7919);
          expect(round.questions, isNotEmpty, reason: '$scope $seed');
          for (final q in round.questions) {
            verify(q, setup);
            asked++;
            byGame[q.game] = (byGame[q.game] ?? 0) + 1;
          }
        }
      }
      expect(asked, greaterThan(300));
      for (final g in allGames) {
        expect(byGame[g], greaterThan(12), reason: '${g.name} rarely asked');
      }
    });

    test('a scope that cannot carry a game gets the others', () {
      // One surah: "which surah" would answer itself.
      expect(corpus.feasible(const ArenaScope.surah(18)),
          isNot(contains(ArenaGame.whichSurah)));
      expect(corpus.feasible(const ArenaScope.juz(30)), allGames);
      final round = ArenaRound.generate(
          corpus,
          const ArenaSetup(
              scope: ArenaScope.surah(18), games: {ArenaGame.whichSurah}),
          1);
      expect(round.questions, isNotEmpty);
      expect(round.questions.map((q) => q.game), isNot(contains(ArenaGame.whichSurah)));
      // Al-Kawthar has three verses; a round there is short, not empty.
      final tiny = ArenaRound.generate(corpus,
          const ArenaSetup(scope: ArenaScope.surah(108), games: allGames), 3);
      expect(tiny.questions, isNotEmpty);
      expect(tiny.questions.length, lessThanOrEqualTo(10));
    });

    test('a known seed makes a known round — the codes depend on it', () {
      // Pinned so a change to the generator that would break every
      // challenge code in the wild is a failing test, not a surprise.
      const setup = ArenaSetup(scope: ArenaScope.juz(30), games: allGames);
      final round = ArenaRound.generate(corpus, setup, 12345);
      final shape = [
        for (final q in round.questions) '${q.game.name}/${q.surah}:${q.ayah}'
      ];
      expect(shape, hasLength(10));
      expect(shape, kPinnedRound12345,
          reason: 'the generator changed; every challenge code in the '
              'wild now makes a different round');
    });
  });

  group('scoring', () {
    test('rewards a right answer and a run, with no clock to beat', () {
      expect(ArenaScoring.points(correct: false, combo: 9), 0);
      expect(ArenaScoring.points(correct: true, combo: 1), 150);
      expect(ArenaScoring.points(correct: true, combo: 2), 150);
      expect(ArenaScoring.points(correct: true, combo: 3), 188);
      expect(ArenaScoring.points(correct: true, combo: 5), 225);
      // What a perfect round was worth with a clock: bests still compare.
      expect(ArenaScoring.maxFor(10), 150 * 2 + 188 * 2 + 225 * 6);
    });

    test('a result adds itself up', () {
      const r = ArenaResult(
        setup: ArenaSetup(scope: ArenaScope.quran(), games: allGames),
        seed: 1,
        answers: [
          ArenaAnswer(chosen: 0, correct: true, points: 150),
          ArenaAnswer(chosen: 1, correct: true, points: 125),
          ArenaAnswer(chosen: -1, correct: false, points: 0),
          ArenaAnswer(chosen: 2, correct: true, points: 110),
        ],
      );
      expect(r.score, 385);
      expect(r.correct, 3);
      expect(r.asked, 4);
      expect(r.bestRun, 2);
      expect(r.tier, 2);
      final json = r.answers.map((a) => a.toJson()).toList();
      expect(ArenaAnswer.fromJson(json[2]).chosen, -1);
      expect(ArenaAnswer.fromJson(json[0]).points, 150);
      // An answer kept from when rounds had a clock still reads.
      final old = ArenaAnswer.fromJson(
          {'c': -1, 'ok': false, 't': 0.0, 'p': 0});
      expect(old.chosen, -1);
      expect(old.correct, isFalse);
    });

    test('tiers', () {
      ArenaResult of(int right, int asked) => ArenaResult(
            setup: const ArenaSetup(scope: ArenaScope.quran(), games: allGames),
            seed: 1,
            answers: [
              for (var i = 0; i < asked; i++)
                ArenaAnswer(chosen: 0, correct: i < right, points: 0),
            ],
          );
      expect(of(10, 10).tier, 4);
      expect(of(8, 10).tier, 3);
      expect(of(6, 10).tier, 2);
      expect(of(4, 10).tier, 1);
      expect(of(3, 10).tier, 0);
      expect(of(0, 0).tier, 0);
    });
  });
}

/// See the pinned-round test.
const kPinnedRound12345 = <String>[
  'missingWord/78:17',
  'nextVerse/88:24',
  'completeVerse/102:5',
  'orderWords/86:4',
  'surahFacts/112:0',
  'whichSurah/99:7',
  'missingWord/80:22',
  'nextVerse/89:11',
  'completeVerse/78:37',
  'orderWords/83:17',
];
