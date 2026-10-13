import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/reel_duration.dart';
import 'package:ayah_reels/data/ruku_index.dart';
import 'package:ayah_reels/data/series_library.dart';
import 'package:ayah_reels/data/series_planner.dart';
import 'package:ayah_reels/data/surah_index.dart';

/// A series is the whole surah, in order, cut where the passages end.
/// What is pinned here: the cuts cover everything and skip nothing,
/// they fall on the mushaf's own passage boundaries whenever the
/// arithmetic allows, and the day-by-day bookkeeping around them.
void main() {
  /// A stand-in surah of [n] verses, each [letters] letters long
  /// (Arabic letters only, so the estimator counts them). Three is a
  /// very short verse — under two seconds read — so a stand-in of a
  /// hundred verses still fits under the minute in a handful of
  /// reels, and the tests about *where* the cuts fall are not
  /// overruled by the cap on how long a reel may run.
  List<Ayah> fake(int n, {int letters = 3}) => [
        for (var i = 1; i <= n; i++)
          Ayah(
            number: i,
            arabic: List.filled(letters, 'ب').join(),
            translation: '',
          ),
      ];

  group('covering the surah', () {
    test('starts at ayah 1, ends at the last, and skips nothing', () {
      for (final n in [1, 2, 7, 30, 110, 286]) {
        for (final k in [1, 3, 7, 30]) {
          final cuts =
              SeriesPlanner.split(surah: 2, ayahs: fake(n), reels: k);
          expect(cuts.first.startAyah, 1, reason: 'n=$n k=$k');
          expect(cuts.last.endAyah, n, reason: 'n=$n k=$k');
          for (var i = 1; i < cuts.length; i++) {
            expect(cuts[i].startAyah, cuts[i - 1].endAyah + 1,
                reason: 'gap at reel $i for n=$n k=$k');
          }
          // As many as asked, unless the surah has fewer verses — or
          // the minute needed more.
          expect(cuts.length, greaterThanOrEqualTo(k > n ? n : k));
          expect(cuts.length, lessThanOrEqualTo(n));
        }
      }
    });

    test('never more reels than verses', () {
      expect(SeriesPlanner.split(surah: 112, ayahs: fake(4), reels: 21),
          hasLength(4));
    });

    test('one reel is the whole surah', () {
      final cuts = SeriesPlanner.split(surah: 1, ayahs: fatiha, reels: 1);
      expect(cuts, hasLength(1));
      expect(cuts.single.startAyah, 1);
      expect(cuts.single.endAyah, 7);
      expect(
          cuts.single.estimateMs,
          ReelDuration.estimateMs(fatiha, startAyah: 1, endAyah: 7));
    });
  });

  group('where the cuts fall', () {
    test('lands on ruku boundaries when the arithmetic allows', () {
      // Ya-Sin: 83 verses in five passages, at 1, 13, 33, 51 and 68.
      // Five reels of a surah with five passages should be the five
      // passages.
      final starts = rukuStarts[36]!;
      expect(starts, [1, 13, 33, 51, 68]);
      final cuts = SeriesPlanner.split(surah: 36, ayahs: fake(83), reels: 5);
      expect(cuts.map((c) => c.startAyah).toList(), starts);
    });

    test('prefers a passage boundary over a perfectly even deal', () {
      // Al-Kahf: 110 verses, passages at 1, 13, 18, 23, 32, 45, 50, 54,
      // 60, 71, 83, 102. Asked for four reels of equal verses the deal
      // would be 28/28/27/27 — none of which is a boundary. The planner
      // gives up some evenness to cut where the story breaks.
      final cuts = SeriesPlanner.split(surah: 18, ayahs: fake(110), reels: 4);
      final starts = rukuStarts[18]!.toSet();
      for (final c in cuts.skip(1)) {
        expect(starts, contains(c.startAyah),
            reason: 'reel starting at ${c.startAyah} cuts mid-passage');
      }
    });

    test('but not at any price: reels stay within sight of each other',
        () {
      final cuts = SeriesPlanner.split(surah: 18, ayahs: fake(110), reels: 4);
      final longest = cuts.map((c) => c.estimateMs).reduce((a, b) => a > b ? a : b);
      final shortest = cuts.map((c) => c.estimateMs).reduce((a, b) => a < b ? a : b);
      expect(longest, lessThan(shortest * 3));
    });

    test('with as many reels as passages, the cuts are mostly passages',
        () {
      // Al-Baqarah over forty reels: forty passages. Not every passage
      // is a reel — one runs fourteen verses and one runs two, and the
      // planner will split the long one and join the short one rather
      // than post a fortnight's worth on one day and a breath on the
      // next — but the great majority of the cuts are the mushaf's own.
      final cuts = SeriesPlanner.split(surah: 2, ayahs: fake(286), reels: 40);
      final starts = rukuStarts[2]!.toSet();
      final onBoundary =
          cuts.where((c) => starts.contains(c.startAyah)).length;
      expect(onBoundary, greaterThanOrEqualTo(30),
          reason: '${cuts.map((c) => c.startAyah)}');
      // And a cut that is not a boundary is only ever made inside a
      // passage longer than the average reel — never one verse short
      // of a boundary for no reason.
      const avg = 286 / 40;
      for (final c in cuts) {
        if (starts.contains(c.startAyah)) continue;
        final passage = rukuStarts[2]!.lastWhere((a) => a <= c.startAyah);
        final next = rukuStarts[2]!.firstWhere((a) => a > c.startAyah,
            orElse: () => 287);
        expect(next - passage, greaterThan(avg),
            reason: 'cut at ${c.startAyah} inside a short passage');
      }
    });

    test('a slower voice makes the same cuts, just longer estimates', () {
      // A pace that keeps every reel between the floor and the cap at
      // both speeds — past either the slower voice rightly gets
      // different cuts.
      final a = SeriesPlanner.split(surah: 36, ayahs: fake(83), reels: 5);
      final b = SeriesPlanner.split(
          surah: 36, ayahs: fake(83), reels: 5, pace: 1.2);
      expect(b.map((c) => c.startAyah), a.map((c) => c.startAyah));
      expect(b.first.estimateMs, (a.first.estimateMs * 1.2).round());
    });

    test('long verses are spread, not piled onto one reel', () {
      // 83 verses of fifteen seconds over five reels: five is not
      // possible under the minute, so the count gives — twenty-one
      // reels of four verses or so — and the deal stays even, not one
      // reel of thirty-five verses and the rest of twelve.
      final cuts = SeriesPlanner.split(
          surah: 36, ayahs: fake(83, letters: 60), reels: 5);
      expect(cuts.length, greaterThanOrEqualTo(21));
      final longest = cuts.map((c) => c.ayahCount).reduce((a, b) => a > b ? a : b);
      final shortest = cuts.map((c) => c.ayahCount).reduce((a, b) => a < b ? a : b);
      expect(longest - shortest, lessThanOrEqualTo(1),
          reason: '${cuts.map((c) => c.ayahCount)}');
    });

    test('no reel of more than one verse runs past the minute', () {
      for (final letters in [12, 40, 60, 120]) {
        final ayahs = fake(83, letters: letters);
        for (final reels in [1, 3, 7, 30]) {
          final cuts = SeriesPlanner.split(surah: 36, ayahs: ayahs, reels: reels);
          for (final c in cuts) {
            if (c.ayahCount > 1) {
              expect(c.estimateMs, lessThanOrEqualTo(SeriesPlanner.maxCutMs),
                  reason: '$letters letters, $reels reels: $c');
            }
          }
          expect(cuts.first.startAyah, 1);
          expect(cuts.last.endAyah, 83);
        }
      }
    });

    test('a verse longer than the minute on its own stands alone', () {
      // 300 letters is over a minute read; it cannot be cut, so it is
      // dealt as a reel of one and its neighbours stay under the cap.
      final ayahs = [
        ...fake(4),
        Ayah(number: 5, arabic: List.filled(300, 'ب').join(), translation: ''),
        ...fake(4).map((a) => Ayah(
            number: a.number + 5, arabic: a.arabic, translation: '')),
      ];
      final cuts = SeriesPlanner.split(surah: 36, ayahs: ayahs, reels: 1);
      final long = cuts.singleWhere((c) => c.startAyah <= 5 && c.endAyah >= 5);
      expect(long.ayahCount, 1);
      for (final c in cuts) {
        if (c.ayahCount > 1) {
          expect(c.estimateMs, lessThanOrEqualTo(SeriesPlanner.maxCutMs));
        }
      }
    });

    test('the ruku table covers every surah and starts each at ayah 1',
        () {
      expect(rukuStarts, hasLength(114));
      var total = 0;
      for (final s in surahIndex) {
        final starts = rukuStarts[s.number]!;
        expect(starts.first, 1, reason: 'surah ${s.number}');
        expect(starts.last, lessThanOrEqualTo(s.ayahCount),
            reason: 'surah ${s.number}');
        for (var i = 1; i < starts.length; i++) {
          expect(starts[i], greaterThan(starts[i - 1]));
        }
        total += starts.length;
      }
      expect(total, 558);
    });
  });

  group('suggesting a length', () {
    test('about a minute a reel, and never more reels than verses', () {
      final long = fake(100, letters: 100); // ~24 s a verse
      final n = SeriesPlanner.suggestedReels(long);
      final total = ReelDuration.estimateMs(long, startAyah: 1, endAyah: 100);
      expect(n, (total / SeriesPlanner.idealReelMs).ceil());
      expect(SeriesPlanner.suggestedReels(fatiha), lessThanOrEqualTo(7));
      expect(SeriesPlanner.suggestedReels(fake(2, letters: 5)), 1);
    });
  });

  group('days', () {
    test('deals reels out in order, the last day short if need be', () {
      final cuts = SeriesPlanner.split(surah: 2, ayahs: fake(20), reels: 7);
      final days = SeriesPlanner.byDay(cuts, 3);
      expect(days.map((d) => d.length), [3, 3, 1]);
      expect(days[1].first.startAyah, cuts[3].startAyah);
    });

    test('over a chosen number of days, that many days, evenly', () {
      final cuts = SeriesPlanner.split(surah: 2, ayahs: fake(20), reels: 7);
      final days = SeriesPlanner.overDays(cuts, 3);
      expect(days.map((d) => d.length), [3, 2, 2]);
      expect(days[2].last.endAyah, 20);
      // Fewer reels than days: the days shrink to the reels.
      expect(SeriesPlanner.overDays(cuts, 30).length, 7);
      // Seven days is seven days, whatever the minute made of it.
      final many = SeriesPlanner.split(
          surah: 2, ayahs: fake(100, letters: 60), reels: 7);
      expect(many.length, greaterThan(7));
      final week = SeriesPlanner.overDays(many, 7);
      expect(week.length, 7);
      expect(week.expand((d) => d).toList(), many);
    });
  });

  group('the series itself', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('series');
      SeriesLibrary.fileOverride = File('${tmp.path}/series.json');
      SeriesLibrary.resetForTest();
    });
    tearDown(() {
      SeriesLibrary.fileOverride = null;
      SeriesLibrary.resetForTest();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {/* Windows holds the handle; the runner cleans up */}
    });

    ReelSeries plan({int reels = 6, int perDay = 2}) => ReelSeries.plan(
          surah: 36,
          reciterId: 'alafasy',
          perDay: perDay,
          cuts: SeriesPlanner.split(surah: 36, ayahs: fake(83), reels: reels),
          now: DateTime(2026, 9, 1, 10),
        );

    test('a plan spans its days and numbers its reels in order', () {
      final s = plan();
      expect(s.days, 3);
      expect(s.reels.map((r) => r.index), [0, 1, 2, 3, 4, 5]);
      expect(s.reelsOn(2).map((r) => r.index), [2, 3]);
      expect(s.finished, isFalse);
      expect(s.nextDay, 1);
    });

    test('a day is done when its reels are, or when the user says so',
        () async {
      await SeriesLibrary.add(plan());
      var s = (await SeriesLibrary.active())!;
      expect(s.isDayDone(1), isFalse);
      s = (await SeriesLibrary.markReelDone(s.id, 0, savedReelId: 'r0'))!;
      expect(s.isDayDone(1), isFalse, reason: 'one of two reels');
      s = (await SeriesLibrary.markReelDone(s.id, 1, savedReelId: 'r1'))!;
      expect(s.isDayDone(1), isTrue);
      expect(s.reels[1].savedReelId, 'r1');
      expect(s.nextDay, 2);
      // A long press finishes day 3 without a single reel made.
      s = (await SeriesLibrary.toggleDay(s.id, 3))!;
      expect(s.isDayDone(3), isTrue);
      expect(s.daysDone, 2);
      // And takes it back.
      s = (await SeriesLibrary.toggleDay(s.id, 3))!;
      expect(s.isDayDone(3), isFalse);
      // But cannot take back a day whose reels are really done.
      s = (await SeriesLibrary.toggleDay(s.id, 1))!;
      expect(s.isDayDone(1), isTrue);
    });

    test('a day with more reels than asked for is done with the ones asked',
        () async {
      // Six reels over two days, one a day asked: three to choose from
      // each day, and one of them finishes it.
      final s0 = ReelSeries.plan(
        surah: 36,
        reciterId: 'alafasy',
        perDay: 1,
        days: 2,
        cuts: SeriesPlanner.split(surah: 36, ayahs: fake(83), reels: 6),
        now: DateTime(2026, 9, 1, 10),
      );
      expect(s0.reelsOn(1), hasLength(3));
      await SeriesLibrary.add(s0);
      var s = (await SeriesLibrary.active())!;
      s = (await SeriesLibrary.markReelDone(s.id, 2, savedReelId: 'r2'))!;
      expect(s.isDayDone(1), isTrue, reason: 'any one of the three');
      expect(s.nextDay, 2);
    });

    test('today counts from the day the series was made', () {
      final s = plan();
      expect(s.todayIndex(DateTime(2026, 9, 1, 23)), 1);
      expect(s.todayIndex(DateTime(2026, 9, 2, 0, 5)), 2);
      expect(s.todayIndex(DateTime(2026, 10, 1)), 3, reason: 'clamped');
      expect(s.todayIndex(DateTime(2026, 8, 1)), 1, reason: 'clamped');
    });

    test('survives a round trip through the file', () async {
      await SeriesLibrary.add(plan());
      await SeriesLibrary.markReelDone((await SeriesLibrary.active())!.id, 0);
      SeriesLibrary.resetForTest();
      final s = (await SeriesLibrary.load()).single;
      expect(s.surah, 36);
      expect(s.reels[0].done, isTrue);
      expect(s.reels[1].done, isFalse);
      expect(s.startedAt, DateTime(2026, 9, 1, 10));
    });

    test('a new series replaces the old one, deleted or not', () async {
      final old = plan(reels: 3, perDay: 1);
      await SeriesLibrary.add(old);
      final fresh = ReelSeries.plan(
        surah: 1,
        reciterId: 'husary',
        perDay: 1,
        cuts: SeriesPlanner.split(surah: 1, ayahs: fatiha, reels: 2),
        now: DateTime(2026, 9, 3),
      );
      await SeriesLibrary.add(fresh);
      expect((await SeriesLibrary.active())!.id, fresh.id);
      expect(await SeriesLibrary.byId(old.id), isNull);
      await SeriesLibrary.remove(fresh.id);
      expect(await SeriesLibrary.active(), isNull);
    });

    test('a plan over chosen days lands on exactly those days', () {
      final s = ReelSeries.plan(
        surah: 36,
        reciterId: 'alafasy',
        perDay: 1,
        days: 3,
        cuts: SeriesPlanner.split(surah: 36, ayahs: fake(83), reels: 8),
        now: DateTime(2026, 9, 1, 10),
      );
      expect(s.days, 3);
      expect([1, 2, 3].map((d) => s.reelsOn(d).length), [3, 3, 2]);
    });

    test('the active series is the newest unfinished one', () async {
      final old = plan(reels: 1, perDay: 1);
      await SeriesLibrary.add(old);
      for (final r in old.reels) {
        await SeriesLibrary.markReelDone(old.id, r.index);
      }
      expect(await SeriesLibrary.active(), isNull);
      final fresh = ReelSeries.plan(
        surah: 1,
        reciterId: 'husary',
        perDay: 1,
        cuts: SeriesPlanner.split(surah: 1, ayahs: fatiha, reels: 2),
        now: DateTime(2026, 9, 3),
      );
      await SeriesLibrary.add(fresh);
      expect((await SeriesLibrary.active())!.id, fresh.id);
    });
  });
}
