import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/word_align_service.dart';

/// Long verses cut into lines: where the cuts go, when each part comes
/// on, and what of the translation goes with it. All of it is pure, so
/// it is pinned here rather than trusted to look right on a phone.
void main() {
  // 2:255's opening, as the app's Uthmani text carries it: the pause
  // signs are tokens of their own.
  const kursi = 'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ '
      'لَا تَأْخُذُهُۥ سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُۥ مَا فِى ٱلسَّمَـٰوَٰتِ '
      'وَمَا فِى ٱلْأَرْضِ ۗ مَن ذَا ٱلَّذِى يَشْفَعُ عِندَهُۥٓ إِلَّا '
      'بِإِذْنِهِۦ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ';

  /// A stand-in for the card: a part fits while its letters do.
  bool Function(int, int) fitsLetters(List<String> tokens, int most) =>
      (s, e) {
        var n = 0;
        for (var k = s; k < e; k++) {
          n += VerseText.letters(tokens[k]) + 1;
        }
        return n <= most;
      };

  group('VerseText', () {
    test('tells words from pause signs and finds the sign after a word', () {
      expect(VerseText.isWord('ٱللَّهُ'), isTrue);
      expect(VerseText.isWord('ۚ'), isFalse);
      expect(VerseText.pauseAfter('ۚ'), PauseMark.allowed);
      expect(VerseText.pauseAfter('ۗ'), PauseMark.better);
      expect(VerseText.pauseAfter('ۙ'), PauseMark.never);
      expect(VerseText.pauseAfter('هُوَ'), isNull);
      expect(VerseText.opensNext('۞'), isTrue);
      expect(VerseText.letters('ۚ'), 0);
      expect(VerseText.letters('هُوَ'), 2);
    });
  });

  group('VerseSplitter', () {
    test('a verse that fits is not cut', () {
      final tokens = VerseText.tokens('بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ');
      expect(VerseSplitter.split(tokens, (s, e) => true), isNull);
    });

    test('cuts after the pause signs, never before them', () {
      final tokens = VerseText.tokens(kursi);
      final cuts = VerseSplitter.split(tokens, fitsLetters(tokens, 40))!;
      expect(cuts.first, 0);
      expect(cuts.last, tokens.length);
      for (var i = 1; i < cuts.length - 1; i++) {
        // A part never opens on a sign: it belongs to the word before.
        expect(VerseText.isWord(tokens[cuts[i]]), isTrue,
            reason: 'part $i opens on "${tokens[cuts[i]]}"');
      }
      // With room for a phrase a part, every cut lands on a sign.
      for (var i = 1; i < cuts.length - 1; i++) {
        expect(VerseText.pauseAfter(tokens[cuts[i] - 1]), isNotNull,
            reason: 'cut $i is not on a pause sign');
      }
      // And every part fits.
      final fits = fitsLetters(tokens, 40);
      for (var i = 0; i < cuts.length - 1; i++) {
        expect(fits(cuts[i], cuts[i + 1]), isTrue);
      }
    });

    test('no more parts than the pause signs need', () {
      final tokens = VerseText.tokens(kursi);
      final cuts = VerseSplitter.split(tokens, fitsLetters(tokens, 90))!;
      // 155 letters in all: two parts can hold them, and do.
      expect(cuts.length - 1, lessThanOrEqualTo(3));
    });

    test('one more line rather than a phrase cut in two', () {
      final tokens = VerseText.tokens(kursi);
      // Room for "لَّهُۥ مَا فِى ٱلسَّمَـٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ" and a
      // little more: a cut after its وَمَا would save a part, and must
      // not be taken.
      final cuts = VerseSplitter.split(tokens, fitsLetters(tokens, 50))!;
      final parts = [
        for (var i = 0; i < cuts.length - 1; i++)
          tokens.sublist(cuts[i], cuts[i + 1]).join(' '),
      ];
      for (var i = 1; i < cuts.length - 1; i++) {
        expect(VerseText.pauseAfter(tokens[cuts[i] - 1]), isNotNull,
            reason: 'cut $i is not on a pause sign: $parts');
      }
      expect(parts, contains('لَّهُۥ مَا فِى ٱلسَّمَـٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ'));
    });

    test('a cut with no sign falls before the فَ that opens a clause', () {
      // 2:256, too long a phrase to go whole between its signs.
      const verse = 'لَآ إِكْرَاهَ فِى ٱلدِّينِ ۖ قَد تَّبَيَّنَ ٱلرُّشْدُ مِنَ '
          'ٱلْغَىِّ ۚ فَمَن يَكْفُرْ بِٱلطَّـٰغُوتِ وَيُؤْمِنۢ بِٱللَّهِ فَقَدِ '
          'ٱسْتَمْسَكَ بِٱلْعُرْوَةِ ٱلْوُثْقَىٰ لَا ٱنفِصَامَ لَهَا ۗ '
          'وَٱللَّهُ سَمِيعٌ عَلِيمٌ';
      final tokens = VerseText.tokens(verse);
      final cuts = VerseSplitter.split(tokens, fitsLetters(tokens, 46))!;
      final plain = [
        for (final c in cuts.sublist(1, cuts.length - 1))
          if (VerseText.pauseAfter(tokens[c - 1]) == null) c,
      ];
      expect(plain, hasLength(1));
      expect(tokens[plain.single], 'فَقَدِ');
      // And no line ends on a particle waiting for its next word.
      for (final c in cuts.sublist(1, cuts.length - 1)) {
        expect(VerseText.bindsToNext(tokens[c - 1]), isFalse,
            reason: 'a line ends on ${tokens[c - 1]}');
      }
    });

    test('particles that wait for the next word, and what opens a clause',
        () {
      for (final w in ['فِى', 'وَمَا', 'مِنَ', 'عَلَىٰ', 'إِلَّا', 'وَلَا',
          'ٱلَّذِى', 'يَـٰٓأَيُّهَا', 'لَـٰكِنَّ']) {
        expect(VerseText.bindsToNext(w), isTrue, reason: w);
      }
      for (final w in ['ٱلْأَرْضِ', 'وَهُوَ', 'نَوْمٌ', 'فِيهِ', 'رَيْبَ']) {
        expect(VerseText.bindsToNext(w), isFalse, reason: w);
      }
      expect(VerseText.opensClause('فَمَن'), isTrue);
      expect(VerseText.opensClause('ثُمَّ'), isTrue);
      // وَ as often joins two things as it opens a clause; فِى is "in".
      expect(VerseText.opensClause('وَمَا'), isFalse);
      expect(VerseText.opensClause('فِى'), isFalse);
      expect(VerseText.bare('ٱلسَّمَـٰوَٰتِ'), 'السموت');
    });

    test('never cuts inside a group of words recited as one', () {
      final tokens = VerseText.tokens(kursi);
      final free = VerseSplitter.split(tokens, fitsLetters(tokens, 40))!;
      final held = {for (final c in free.sublist(1, free.length - 1)) c};
      final cuts = VerseSplitter.split(tokens, fitsLetters(tokens, 40),
          held: held);
      if (cuts != null) {
        for (final c in cuts.sublist(1, cuts.length - 1)) {
          expect(held.contains(c), isFalse);
        }
      }
    });

    test('a word too long for a part still makes a part of its own', () {
      final tokens = ['أ' * 30, 'ب' * 30, 'ج' * 30];
      final cuts = VerseSplitter.split(tokens, fitsLetters(tokens, 20))!;
      expect(cuts, [0, 1, 2, 3]);
    });
  });

  group('PartTiming.fromWords', () {
    test('a part ends just after the reciter finishes it', () {
      // Three words: 0-800, 1000-1800 (then a 600 ms breath), 2400-3000.
      final times = <(int, int)?>[(0, 800), (1000, 1800), (2400, 3000)];
      final b = PartTiming.fromWords(
          cuts: [0, 2, 3], times: times, verseStartMs: 5000, verseEndMs: 8200)!;
      expect(b.first, 5000);
      expect(b.last, 8200);
      // 40% of the 600 ms breath, which is under the 280 ms ceiling.
      expect(b[1], 5000 + 1800 + 240);
    });

    test('the linger never runs past its ceiling', () {
      final times = <(int, int)?>[(0, 900), (3000, 3900)];
      final b = PartTiming.fromWords(
          cuts: [0, 1, 2], times: times, verseStartMs: 0, verseEndMs: 4200)!;
      expect(b[1], 900 + PartTiming.lingerMs);
    });

    test('a pause sign takes no part in the timing', () {
      final times = <(int, int)?>[(0, 900), null, (1500, 2400)];
      final b = PartTiming.fromWords(
          cuts: [0, 2, 3], times: times, verseStartMs: 0, verseEndMs: 2600)!;
      expect(b[1], 900 + 240);
    });

    test('an untimed side of a cut leaves the verse whole', () {
      final times = <(int, int)?>[(0, 900), null];
      expect(
          PartTiming.fromWords(
              cuts: [0, 1, 2], times: times, verseStartMs: 0, verseEndMs: 2000),
          isNull);
    });

    test('a part too short to read leaves the verse whole', () {
      final times = <(int, int)?>[(0, 200), (250, 2400)];
      expect(
          PartTiming.fromWords(
              cuts: [0, 1, 2], times: times, verseStartMs: 0, verseEndMs: 2600),
          isNull);
    });
  });

  group('PartTiming.fromPauses', () {
    test('moves each cut to the nearest breath', () {
      // Letters 10 | 10: the estimate is the middle of the voiced span.
      final b = PartTiming.fromPauses(
        cuts: [0, 1, 2],
        letters: [10, 10],
        verseStartMs: 0,
        verseEndMs: 6000,
        voicedStartMs: 0,
        voicedEndMs: 6000,
        pauses: [(1000, 1300), (3200, 3700), (5900, 6000)],
      )!;
      // The breath at 3.2 s is the one near the 3 s estimate; the part
      // changes a little after the reciter stops.
      expect(b, [0, 3360, 6000]);
    });

    test('no breath near the estimate leaves the verse whole', () {
      expect(
        PartTiming.fromPauses(
          cuts: [0, 1, 2],
          letters: [10, 10],
          verseStartMs: 0,
          verseEndMs: 6000,
          pauses: [(200, 500)],
        ),
        isNull,
      );
    });

    test('pausesIn finds quiet runs and the voiced stretch', () {
      // 10 ms steps: 30 quiet, 50 loud, 25 quiet, 40 loud, 10 quiet.
      final env = [
        ...List.filled(30, 1.0),
        ...List.filled(50, 60.0),
        ...List.filled(25, 1.0),
        ...List.filled(40, 60.0),
        ...List.filled(10, 1.0),
      ];
      final p = PartTiming.pausesIn(env, 5, 0, env.length * 10);
      expect(p.pauses, [(0, 300), (800, 1050)]);
      expect(p.voicedStart, 300);
      expect(p.voicedEnd, 1450);
    });
  });

  group('TranslationSplit', () {
    // 2:256 as the app carries it, and Saheeh International's English.
    const v256 = 'لَآ إِكْرَاهَ فِى ٱلدِّينِ ۖ قَد تَّبَيَّنَ ٱلرُّشْدُ مِنَ '
        'ٱلْغَىِّ ۚ فَمَن يَكْفُرْ بِٱلطَّـٰغُوتِ وَيُؤْمِنۢ بِٱللَّهِ فَقَدِ '
        'ٱسْتَمْسَكَ بِٱلْعُرْوَةِ ٱلْوُثْقَىٰ لَا ٱنفِصَامَ لَهَا ۗ '
        'وَٱللَّهُ سَمِيعٌ عَلِيمٌ';
    const e256 = 'There shall be no compulsion in [acceptance of] the '
        'religion. The right course has become distinct from the wrong. So '
        'whoever disbelieves in ṭāghūt and believes in Allāh has grasped the '
        'most trustworthy handhold with no break in it. And Allāh is Hearing '
        'and Knowing.';

    test('a sentence for each stretch between the signs, when there is one',
        () {
      final tokens = VerseText.tokens(v256);
      final cuts = [
        0,
        tokens.indexOf('فَمَن'),
        tokens.indexOf('فَقَدِ'),
        tokens.indexOf('وَٱللَّهُ'),
        tokens.length,
      ];
      expect(TranslationSplit.forCuts(e256, tokens, cuts), [
        // The line that recites "the right course has become distinct"
        // carries it, not the line after.
        'There shall be no compulsion in [acceptance of] the religion. '
            'The right course has become distinct from the wrong.',
        // Inside a sentence: by the share of its own stretch, and not on
        // the "in" that waits for its word.
        'So whoever disbelieves in ṭāghūt and believes in Allāh',
        'has grasped the most trustworthy handhold with no break in it.',
        'And Allāh is Hearing and Knowing.',
      ]);
    });

    test('by shares of the verse when the sentences are not one a stretch',
        () {
      final tokens = VerseText.tokens(v256);
      final cuts = [0, tokens.indexOf('فَمَن'), tokens.length];
      // One sentence fewer than the verse has stretches.
      const merged = 'There shall be no compulsion in [acceptance of] the '
          'religion; the right course has become distinct from the wrong, so '
          'whoever disbelieves in ṭāghūt and believes in Allāh has grasped '
          'the most trustworthy handhold with no break in it. And Allāh is '
          'Hearing and Knowing.';
      final pieces = TranslationSplit.forCuts(merged, tokens, cuts);
      expect(pieces, hasLength(2));
      expect(pieces.join(' '), merged);
    });

    test('cuts at punctuation near each share', () {
      const t = 'Allah - there is no deity except Him, the Ever-Living, the '
          'Sustainer of existence. Neither drowsiness overtakes Him nor sleep.';
      final pieces = TranslationSplit.split(t, [0.5]);
      expect(pieces, hasLength(2));
      expect(pieces.first, matches(RegExp(r'[,.]$')), reason: pieces.first);
      expect('${pieces[0]} ${pieces[1]}', t);
    });

    test('never cuts inside brackets', () {
      const t = 'Who is it that can intercede with Him except by His permission '
          '[to do so]? He knows what is [presently] before them and what will '
          'be after them.';
      for (final f in [0.3, 0.5, 0.7]) {
        for (final p in TranslationSplit.split(t, [f])) {
          expect('['.allMatches(p).length, ']'.allMatches(p).length,
              reason: p);
        }
      }
    });

    test('always as many pieces as parts', () {
      expect(TranslationSplit.split('', [0.5, 0.7]), ['', '', '']);
      expect(TranslationSplit.split('one', [0.5]), ['one', '']);
      final p = TranslationSplit.split('a b c d e f g h', [0.25, 0.5, 0.75]);
      expect(p, hasLength(4));
      expect(p.join(' '), 'a b c d e f g h');
    });
  });

  group('the plan', () {
    const rec = Recitation(
      reciterId: 'r',
      surah: 2,
      audioPath: 'x',
      timings: [
        AyahTiming(1, 0, 4000),
        AyahTiming(2, 4000, 10000),
        AyahTiming(3, 10000, 13000),
      ],
    );
    VersePart part(int i, int n, int from, int to, int t0, int t1) => VersePart(
          ayah: 2,
          index: i,
          count: n,
          tokenStart: from,
          tokenEnd: to,
          startMs: t0,
          endMs: t1,
          arabic: 'x',
          translation: 'y',
          fit: 1,
        );
    final plan = VerseLinePlan(2, {
      2: [part(0, 2, 0, 3, 4000, 7000), part(1, 2, 3, 6, 7000, 10000)],
    });

    test('units are the verses, with a cut verse standing as its parts', () {
      final units = VerseUnit.of(rec, 1, 3, plan);
      expect(units.map((u) => (u.ayah, u.startMs, u.endMs)).toList(), [
        (1, 0, 4000),
        (2, 4000, 7000),
        (2, 7000, 10000),
        (3, 10000, 13000),
      ]);
      expect(VerseUnit.indexAt(units, 7000), 2);
      expect(VerseUnit.indexAt(units, 99999), 3);
    });

    test("a unit's word times are its own tokens, from its own start", () {
      final units = VerseUnit.of(rec, 1, 3, plan);
      final verse = <(int, int)?>[
        (0, 500), (600, 1000), null, (3100, 3500), (3600, 4000), (4100, 5000)
      ];
      expect(units[2].timesIn(verse, 4000),
          [(100, 500), (600, 1000), (1100, 2000)]);
      expect(units[1].timesIn(verse, 4000),
          [(0, 500), (600, 1000), null]);
      expect(units[0].timesIn(null, 0), isNull);
    });

    test('the fingerprint is stable and moves with the cuts', () {
      final again = VerseLinePlan(2, {
        2: [part(0, 2, 0, 3, 4000, 7000), part(1, 2, 3, 6, 7000, 10000)],
      });
      final moved = VerseLinePlan(2, {
        2: [part(0, 2, 0, 3, 4000, 7100), part(1, 2, 3, 6, 7100, 10000)],
      });
      expect(again.fingerprint, plan.fingerprint);
      expect(again, plan);
      expect(moved.fingerprint, isNot(plan.fingerprint));
      expect(VerseLinePlan.empty.fingerprint, '');
    });
  });

  group('WordAlignService.tokenWindows', () {
    test('marks take their word, groups hold their inside', () {
      const text = 'قُلْ هُوَ ۚ ٱللَّهُ أَحَدٌ';
      final w = WordAlignService.tokenWindows(text, const [
        WordSpan(0, 1, 0, 400),
        WordSpan(1, 2, 500, 900),
        WordSpan(2, 4, 1000, 2000),
      ]);
      expect(w.times, [(0, 400), (500, 900), (500, 900), (1000, 2000),
          (1000, 2000)]);
      // Inside the two-word group, and between هُوَ and its sign.
      expect(w.held, containsAll([2, 4]));
      expect(w.held.contains(3), isFalse);
    });
  });
}
