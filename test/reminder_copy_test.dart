import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/reminder_copy.dart';
import 'package:ayah_reels/l10n/app_lang.dart';

/// One notification a day: three quizzes to two reels, never the same
/// line two days running, each one said for the hour it arrives at —
/// and not in the same words two days running — and the quiz never
/// named, only described.
void main() {
  group('the plan', () {
    test('three quizzes to two reels, in any fifty days', () {
      final start = DateTime(2026, 3, 1);
      final kinds = [
        for (var i = 0; i < 50; i++)
          ReminderCopy.kindOn(DateTime(start.year, start.month, start.day + i)),
      ];
      expect(kinds.where((k) => k == NudgeKind.quiz), hasLength(30));
      expect(kinds.where((k) => k == NudgeKind.reel), hasLength(20));
    });

    test('never three quizzes in a row, never two reels in a row', () {
      for (var i = 0; i < 60; i++) {
        final d = [
          for (var k = 0; k < 3; k++)
            ReminderCopy.kindOn(DateTime(2026, 1, 1 + i + k)),
        ];
        expect(d.every((k) => k == NudgeKind.quiz), isFalse);
        expect(d[0] == NudgeKind.reel && d[1] == NudgeKind.reel, isFalse);
      }
    });

    test('the same day is the same notification, whenever it is asked', () {
      expect(ReminderCopy.forDay(DateTime(2026, 7, 25, 21)),
          ReminderCopy.forDay(DateTime(2026, 7, 25, 21, 59)));
    });

    test('each kind walks its fifteen lines before one comes back', () {
      for (final kind in NudgeKind.values) {
        final seen = <int>[];
        for (var i = 0; seen.length < 15; i++) {
          final day = DateTime(2026, 2, 1 + i);
          if (ReminderCopy.kindOn(day) == kind) {
            seen.add(ReminderCopy.ordinalOn(day) % 15);
          }
        }
        expect(seen.toSet(), hasLength(15), reason: kind.name);
      }
    });

    test('no two days running share a title', () {
      for (var i = 0; i < 120; i++) {
        final a = ReminderCopy.forDay(DateTime(2026, 3, 1 + i, 21));
        final b = ReminderCopy.forDay(DateTime(2026, 3, 2 + i, 21));
        expect(a.title, isNot(b.title));
      }
    });
  });

  group('said for the hour it arrives', () {
    test('the parts of the day', () {
      expect(ReminderCopy.partOf(7), DayPart.morning);
      expect(ReminderCopy.partOf(13), DayPart.afternoon);
      expect(ReminderCopy.partOf(18), DayPart.evening);
      expect(ReminderCopy.partOf(20), DayPart.night);
      expect(ReminderCopy.partOf(21), DayPart.night);
      expect(ReminderCopy.partOf(2), DayPart.night);
    });

    test('at nine at night, said for the night; at seven, the morning', () {
      final nights = ReminderCopy.timePhrases[AppLang.en]![DayPart.night]!;
      final mornings =
          ReminderCopy.timePhrases[AppLang.en]![DayPart.morning]!;
      // Every day of a fortnight, both kinds among them.
      for (var i = 0; i < 14; i++) {
        final night = ReminderCopy.forDay(DateTime(2026, 4, 1 + i, 21));
        final morning = ReminderCopy.forDay(DateTime(2026, 4, 1 + i, 7));
        expect(nights.where('${night.title} ${night.body}'.contains),
            hasLength(1), reason: night.body);
        expect(mornings.where('${morning.title} ${morning.body}'.contains),
            hasLength(1), reason: morning.body);
      }
    });

    test('no two days running end alike, and a week hears every ending',
        () {
      for (final lang in AppLang.values) {
        for (final hour in [7, 13, 18, 21, 2]) {
          final phrases =
              ReminderCopy.timePhrases[lang]![ReminderCopy.partOf(hour)]!;
          final said = [
            for (var i = 0; i < 90; i++)
              ReminderCopy.phraseFor(DateTime(2026, 3, 1 + i, hour), lang),
          ];
          for (var i = 1; i < said.length; i++) {
            expect(said[i], isNot(said[i - 1]),
                reason: '${lang.code} at $hour:00, day $i');
          }
          expect(said.take(7).toSet(), phrases.toSet(),
              reason: '${lang.code} at $hour:00');
        }
      }
    });

    test('before you sleep and before bed are never neighbours', () {
      final nights = ReminderCopy.timePhrases[AppLang.en]![DayPart.night]!;
      for (var i = 0; i < 30; i++) {
        final pair = {
          ReminderCopy.phraseFor(DateTime(2026, 5, 1 + i, 21), AppLang.en),
          ReminderCopy.phraseFor(DateTime(2026, 5, 2 + i, 21), AppLang.en),
        };
        expect(pair.containsAll(['before you sleep', 'before bed']), isFalse);
        expect(nights, containsAll(pair));
      }
    });
  });

  group('every pool, every language', () {
    for (final lang in AppLang.values) {
      for (final (kind, pools) in [
        ('quiz', ReminderCopy.quizPools),
        ('reel', ReminderCopy.reelPools),
      ]) {
        test('${lang.code} $kind', () {
          final pool = pools[lang]!;
          expect(pool, hasLength(15));
          expect(pool.map((l) => l.title).toSet(), hasLength(15),
              reason: 'a repeated title reads as a bug');
          for (final l in pool) {
            // The part of the day goes in exactly once.
            expect('{t}'.allMatches('${l.title} ${l.body}'), hasLength(1),
                reason: '${l.title} / ${l.body}');
            // The quiz is described, never named.
            expect('${l.title} ${l.body}'.toLowerCase(),
                isNot(contains('tanafus')));
            expect('${l.title} ${l.body}', isNot(contains('تنافس')));
          }
          for (final part in DayPart.values) {
            final phrases = ReminderCopy.timePhrases[lang]![part]!;
            // Enough to take turns, and no two the same.
            expect(phrases.length, greaterThanOrEqualTo(3),
                reason: '${lang.code} ${part.name}');
            expect(phrases.toSet(), hasLength(phrases.length),
                reason: '${lang.code} ${part.name}');
            for (final phrase in phrases) {
              expect(phrase.trim(), phrase);
              expect(phrase, isNotEmpty);
            }
          }
        });
      }
    }
  });

  group("the share lines and Friday's second, every language", () {
    for (final lang in AppLang.values) {
      test(lang.code, () {
        for (final pool in [
          ReminderCopy.versesShare[lang]!,
          ReminderCopy.roundShare[lang]!,
          ReminderCopy.jumuahPools[lang]!,
        ]) {
          expect(pool, hasLength(3));
          for (final l in pool) {
            expect('{t}'.allMatches('${l.title} ${l.body}'), hasLength(1),
                reason: '${l.title} / ${l.body}');
            // Like the quiz lines: the quiz described, never named.
            expect('${l.title} ${l.body}'.toLowerCase(),
                isNot(contains('tanafus')));
            expect('${l.title} ${l.body}', isNot(contains('تنافس')));
          }
        }
        // The count is said, though not in every line: one of them lets
        // the picture speak.
        expect(
            ReminderCopy.versesShare[lang]!
                .where((l) => '${l.title} ${l.body}'.contains('{reels}')),
            hasLength(2));
        for (final l in ReminderCopy.roundShare[lang]!) {
          expect('${l.title} ${l.body}', contains('{score}'));
        }
      });
    }
  });

  test('a share line comes filled in: counts, score and the hour', () {
    final tuesday = DateTime(2026, 10, 13, 14);
    final v = ReminderCopy.shareLine(ShareKind.verses, tuesday,
        reels: '30 reels');
    expect('${v.title} ${v.body}', isNot(contains('{')));
    final r = ReminderCopy.shareLine(ShareKind.round, tuesday,
        rounds: '5 rounds', score: 960);
    expect('${r.title} ${r.body}', contains('960'));
    expect('${r.title} ${r.body}', isNot(contains('{')));
    final j = ReminderCopy.jumuahLine(DateTime(2026, 10, 16, 14));
    expect('${j.title} ${j.body}', isNot(contains('{')));
  });

  test('a count rounds down to its ten, so a line written ahead stays true',
      () {
    expect(ReminderCopy.roundDown(7), 7);
    expect(ReminderCopy.roundDown(34), 30);
    expect(ReminderCopy.roundDown(40), 40);
  });

  test("the week: five mornings, two afternoons, and Friday's second after "
      'the prayer', () {
    // Monday 12 October 2026 onwards.
    final week = [
      for (var d = 0; d < 7; d++) ReminderCopy.slotOn(DateTime(2026, 10, 12 + d))
    ];
    expect(week.where((s) => s == ReminderCopy.morning), hasLength(5));
    expect(week.where((s) => s == ReminderCopy.afternoon), hasLength(2));
    expect(ReminderCopy.slotOn(DateTime(2026, 10, 13)), ReminderCopy.afternoon,
        reason: "Tuesday's is the week's share");
    expect(ReminderCopy.fridaySecond(8), ReminderCopy.afternoon);
    expect(ReminderCopy.fridaySecond(13).hour, 9,
        reason: 'a reminder set around the prayer moves the second off it');
  });

  test('two things to share take turns, one takes both, none asks nothing',
      () {
    final tue = DateTime(2026, 10, 13);
    final fri = DateTime(2026, 10, 16);
    final a = ReminderCopy.shareFor(tue, verses: true, round: true, friday: false);
    final b = ReminderCopy.shareFor(fri, verses: true, round: true, friday: true);
    expect(a, isNot(b), reason: 'Tuesday and Friday hold opposite ones');
    final nextTue = DateTime(2026, 10, 20);
    expect(ReminderCopy.shareFor(nextTue, verses: true, round: true, friday: false),
        isNot(a), reason: 'and they swap with the week');
    expect(ReminderCopy.shareFor(tue, verses: true, round: false, friday: false),
        ShareKind.verses);
    expect(ReminderCopy.shareFor(fri, verses: false, round: true, friday: true),
        ShareKind.round);
    expect(ReminderCopy.shareFor(tue, verses: false, round: false, friday: false),
        isNull);
  });

  test('nothing is long enough to be cut off on a lock screen', () {
    for (final pool in [
      ReminderCopy.quizLines,
      ReminderCopy.reelLines,
      ReminderCopy.jumuahPools[AppLang.en]!,
      [
        for (final l in [
          ...ReminderCopy.versesShare[AppLang.en]!,
          ...ReminderCopy.roundShare[AppLang.en]!,
        ])
          (
            title: l.title
                .replaceAll('{reels}', '100 reels')
                .replaceAll('{rounds}', '100 rounds')
                .replaceAll('{score}', '1250'),
            body: l.body
                .replaceAll('{reels}', '100 reels')
                .replaceAll('{rounds}', '100 rounds')
                .replaceAll('{score}', '1250'),
          ),
      ],
    ]) {
      for (final l in pool) {
        for (final phrase in ReminderCopy.timePhrases[AppLang.en]!.values
            .expand((p) => p)) {
          expect(l.title.replaceAll('{t}', phrase).length,
              lessThanOrEqualTo(40), reason: l.title);
          expect(l.body.replaceAll('{t}', phrase).length,
              lessThanOrEqualTo(120), reason: l.body);
        }
      }
    }
  });
}
