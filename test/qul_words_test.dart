import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/qul_words.dart';
import 'package:ayah_reels/data/word_align_service.dart';

/// QUL's word timing, from what it sends to the spans the highlight
/// reads: every verse checked as it is read, kept small on the phone,
/// and placed on the app's own recording from where each verse's sound
/// begins.
void main() {
  Map<String, dynamic> qul(Map<String, List<List<int>>> verses) => {
        'segments': {
          for (final e in verses.entries)
            e.key: {
              'time_from': e.value.first[1] - 100,
              'time_to': e.value.last[2],
              'segments': e.value,
            },
        },
      };

  group('reading QUL', () {
    test('every verse of the surah, words in order', () {
      final v = QulWords.parse(
          qul({
            '2:1': [
              [1, 1000, 1500],
              [2, 1500, 2400],
            ],
            '2:2': [
              [1, 3000, 3600],
            ],
          }),
          2);
      expect(v.keys, unorderedEquals([1, 2]));
      expect(v[1]!.words, [(1, 1000, 1500), (2, 1500, 2400)]);
      expect(v[1]!.fromMs, 900);
      expect(v[1]!.toMs, 2400);
    });

    test('a reciter taking words again is followed, word for word', () {
      final v = QulWords.parse(
          qul({
            '2:1': [
              [1, 1000, 1500],
              [2, 1500, 2000],
              [3, 2000, 2600],
              [2, 3100, 3500],
              [3, 3500, 4000],
              [4, 4000, 4800],
            ],
          }),
          2);
      expect(v[1]!.count, 4);
      expect(v[1]!.words, hasLength(6));
      final spans = WordAlignService.fromMushafWords(
          'قُلْ هُوَ ٱللَّهُ أَحَدٌ', (count: 4, words: v[1]!.words));
      expect([for (final s in spans!) s.startWord], [0, 1, 2, 1, 2, 3]);
      // Where each word was first reached is what the lines go by.
      final t = WordAlignService.tokenWindows('قُلْ هُوَ ٱللَّهُ أَحَدٌ', spans);
      expect(t.times[1], (1500, 2000));
    });

    test('a verse with a gap, a word out of order or no length is left out',
        () {
      final v = QulWords.parse(
          qul({
            '2:1': [
              [1, 1000, 1500],
              [3, 1500, 2400],
            ],
            '2:2': [
              [1, 3000, 3600],
              [2, 2900, 3700],
            ],
            '2:3': [
              [1, 4000, 4000],
            ],
            '2:4': [
              [1, 5000, 5400],
            ],
          }),
          2);
      expect(v.keys, [4]);
    });

    test('another surah, or nothing readable, is not taken', () {
      expect(
          () => QulWords.parse(
              qul({
                '3:1': [
                  [1, 0, 10],
                ],
              }),
              2),
          throwsFormatException);
      expect(() => QulWords.parse({'nothing': 1}, 2), throwsFormatException);
    });

    test("an ayah recitation's spans, each in its verse's own file", () {
      final v = QulWords.parseAyahSpans({
        'segments': {
          '112:1': {
            'segments': [
              [0, 1, 0, 3640],
              [1, 3, 3640, 4840],
              [3, 4, 4960, 5820],
            ],
          },
          // A word of no length: the verse is not taken.
          '112:2': {
            'segments': [
              [0, 1, 200, 200],
            ],
          },
        },
      }, 112);
      expect(v.keys, [1]);
      // The two-word span shared out between its words.
      expect(v[1]!.words,
          [(1, 0, 3640), (2, 3640, 4240), (3, 4240, 4840), (4, 4960, 5820)]);
      expect(v[1]!.count, 4);
    });

    test('kept on the phone in a small form that reads back the same', () {
      final v = QulWords.parse(
          qul({
            '67:1': [
              [1, 10, 400],
              [2, 400, 900],
              [3, 900, 2000],
            ],
          }),
          67);
      final back = QulWords.decodeCompact(QulWords.encodeCompact(v));
      expect(back[1]!.words, v[1]!.words);
      expect((back[1]!.fromMs, back[1]!.toMs), (v[1]!.fromMs, v[1]!.toMs));
      expect(() => QulWords.decodeCompact({'1': []}), throwsFormatException);
    });
  });

  group('where the sound is', () {
    /// Quiet at 20 dB, speech at 60, in 10 ms steps.
    List<double> env(int ms, List<(int, int)> loud) => [
          for (var k = 0; k < ms ~/ 10; k++)
            loud.any((r) => k * 10 >= r.$1 && k * 10 < r.$2) ? 60.0 : 20.0,
        ];

    test('from the first held rise to the end of the last', () {
      final e = env(3000, [(400, 1200), (1500, 2600)]);
      expect(QulWords.soundIn(e, 40, 0, 3000), (400, 2600));
      expect(QulWords.soundIn(e, 40, 1300, 3000), (1500, 2600));
    });

    test('a click shorter than the hold is not the verse beginning', () {
      final e = env(2000, [(100, 120), (500, 1500)]);
      expect(QulWords.soundIn(e, 40, 0, 2000), (500, 1500));
      expect(QulWords.soundIn(env(1000, const []), 40, 0, 1000), isNull);
    });

  });

  group('placing', () {
    const v = QulVerse(900, 5000, [(1, 1000, 2000), (2, 2000, 3500), (3, 3500, 5000)]);

    test('moved and counted from the window, cut at its edges', () {
      expect(QulWords.placed(v, 200, 1000, 10000),
          [(1, 200, 1200), (2, 1200, 2700), (3, 2700, 4200)]);
      // Past the window's end: the last word is cut there, and a word
      // wholly outside it is gone.
      expect(QulWords.placed(v, 200, 1000, 2000),
          [(1, 200, 1200), (2, 1200, 2000)]);
    });

    test('a verse lands in its window, or it is another take', () {
      expect(QulWords.lands(v, 0, 900, 5000), isTrue);
      // Its first word long before the window, or its last after it.
      expect(QulWords.lands(v, -1000, 900, 5000), isFalse);
      expect(QulWords.lands(v, 0, 900, 2000), isFalse);
      // A verse 1 whose first word holds the basmala the window was cut
      // after may start before it.
      expect(QulWords.lands(v, -1000, 900, 5000, opening: true), isTrue);
    });

    test('one shift for a surah, if most of its verses agree on it', () {
      const a = QulVerse(0, 0, [(1, 1000, 2000)]);
      const b = QulVerse(0, 0, [(1, 5000, 6000)]);
      const c = QulVerse(0, 0, [(1, 9000, 9500)]);
      expect(QulWords.surahShift([(a, 1300), (b, 5310), (c, 9290)]), 300);
      // Each verse a different distance off: not one take.
      expect(QulWords.surahShift([(a, 1300), (b, 6000), (c, 8000)]), isNull);
    });

    /// Quiet at 20 dB, speech at 60, in 10 ms steps.
    List<double> env(int ms, List<(int, int)> loud) => [
          for (var k = 0; k < ms ~/ 10; k++)
            loud.any((r) => k * 10 >= r.$1 && k * 10 < r.$2) ? 60.0 : 20.0,
        ];

    test('per verse: from where its sound begins, plus the voice\'s bias', () {
      const rec = Recitation(
        reciterId: 'r',
        surah: 2,
        audioPath: '',
        timings: [AyahTiming(2, 0, 5000)],
      );
      final out = QulWords.placeAll(
        src: const QulSource(1, QulFit.perVerse, biasMs: 20),
        verses: {2: v},
        rec: rec,
        env: env(5000, [(300, 4300)]),
      );
      expect(out[2]!.count, 3);
      expect(out[2]!.words.first, (1, 320, 1320));
      // A window too short for its words: another take, nothing placed.
      const short = Recitation(
        reciterId: 'r',
        surah: 2,
        audioPath: '',
        timings: [AyahTiming(2, 0, 2000)],
      );
      expect(
          QulWords.placeAll(
              src: const QulSource(1, QulFit.perVerse),
              verses: {2: v},
              rec: short,
              env: env(2000, [(300, 1900)])),
          isEmpty);
    });

    test('per verse, verse 1 from QUL\'s own verse start', () {
      // QUL's first word holds the basmala: from 900, where its verse
      // starts, and the window the host cut starts there too.
      const one = QulVerse(900, 9000, [(1, 900, 6000), (2, 6000, 9000)]);
      const rec = Recitation(
        reciterId: 'r',
        surah: 2,
        audioPath: '',
        timings: [AyahTiming(1, 0, 9000)],
      );
      final out = QulWords.placeAll(
        src: const QulSource(1, QulFit.perVerse,
            verseOne: QulVerseOne.table, verseOneBiasMs: 25),
        verses: {1: one},
        rec: rec,
        env: env(9000, [(100, 8900)]),
      );
      // Placed by the verse start, not by the sound, which begins with
      // the basmala QUL's first word holds.
      expect(out[1]!.words.first, (1, 25, 5125));
    });

    test('a surah file: one shift from the verses after the first', () {
      const v1 = QulVerse(0, 9000, [(1, 0, 6000), (2, 6000, 9000)]);
      const v2 = QulVerse(9200, 13000, [(1, 9300, 11000), (2, 11000, 13000)]);
      const v3 = QulVerse(13200, 17000, [(1, 13300, 15000), (2, 15000, 17000)]);
      // The app's slice starts 4000 ms into QUL's file, after the
      // basmala; each verse's sound begins where QUL's first word does.
      const rec = Recitation(
        reciterId: 'r',
        surah: 2,
        audioPath: '',
        timings: [
          AyahTiming(1, 0, 5100),
          AyahTiming(2, 5100, 9100),
          AyahTiming(3, 9100, 13100),
        ],
      );
      final e = env(13100, [(1500, 5000), (5300, 9000), (9300, 13000)]);
      final out = QulWords.placeAll(
        src: const QulSource(1, QulFit.surahFile, onsetFallback: true),
        verses: {1: v1, 2: v2, 3: v3},
        rec: rec,
        env: e,
      );
      expect(out.keys, unorderedEquals([1, 2, 3]));
      // Verse 2 by the shift of all: QUL 9300 is 5300 in the slice, 200
      // into its window.
      expect(out[2]!.words.first, (1, 200, 1900));
      // Verse 1's basmala word is cut at the window's start.
      expect(out[1]!.words.first, (1, 0, 2000));
    });

    test('a surah file cut from a known place: QUL\'s times, moved', () {
      const v2 = QulVerse(9200, 13000, [(1, 9300, 11000), (2, 11000, 13000)]);
      // The voice's file runs 500 ms behind QUL's, and the recording was
      // cut 4000 ms into it.
      const rec = Recitation(
        reciterId: 'r',
        surah: 2,
        audioPath: '',
        timings: [AyahTiming(2, 5000, 9000)],
        originMs: 4000,
      );
      final out = QulWords.placeAll(
        src: const QulSource(1, QulFit.surahFile, offsets: {2: -500}),
        verses: {2: v2},
        rec: rec,
      );
      // 9300 + 500 - 4000 = 5800 in the recording: 800 into the window.
      expect(out[2]!.words.first, (1, 800, 2500));
      // Without the place, and nothing to fall back on: no words.
      const old = Recitation(
        reciterId: 'r',
        surah: 2,
        audioPath: '',
        timings: [AyahTiming(2, 5000, 9000)],
      );
      expect(
          QulWords.placeAll(
              src: const QulSource(1, QulFit.surahFile, offsets: {2: -500}),
              verses: {2: v2},
              rec: old,
              env: const [60.0]),
          isEmpty);
    });

    test('a surah the voice was recorded again for gets no words', () {
      const rec = Recitation(
        reciterId: 'r',
        surah: 14,
        audioPath: '',
        timings: [AyahTiming(2, 0, 5000)],
      );
      expect(
          QulWords.placeAll(
            src: const QulSource(1, QulFit.perVerse, skip: {14}),
            verses: {2: v},
            rec: rec,
            env: env(5000, [(300, 4300)]),
          ),
          isEmpty);
    });
  });

  group('into the alignment\'s count', () {
    test('word for word where the two count alike', () {
      final spans = WordAlignService.fromMushafWords('قُلْ هُوَ ٱللَّهُ أَحَدٌ', (
        count: 4,
        words: [(1, 0, 300), (2, 300, 600), (3, 600, 1100), (4, 1100, 1800)],
      ));
      expect([for (final s in spans!) (s.startWord, s.endWord, s.startMs)],
          [(0, 1, 0), (1, 2, 300), (2, 3, 600), (3, 4, 1100)]);
    });

    test('بَعْدَ مَا, two words to QUL, is one to the alignment', () {
      const text = 'فَمَنۢ بَدَّلَهُۥ بَعْدَ مَا سَمِعَهُۥ';
      expect(WordAlignService.alignWords(text), [0, 1, 2, 2, 3]);
      final spans = WordAlignService.fromMushafWords(text, (
        count: 5,
        words: [
          (1, 0, 400),
          (2, 400, 900),
          (3, 900, 1200),
          (4, 1200, 1500),
          (5, 1500, 2100),
        ],
      ));
      expect([for (final s in spans!) (s.startWord, s.startMs, s.endMs)],
          [(0, 0, 400), (1, 400, 900), (2, 900, 1500), (3, 1500, 2100)]);
    });

    test('إِلْ يَاسِينَ, one word to QUL, is both of ours', () {
      const text = 'سَلَـٰمٌ عَلَىٰٓ إِلْ يَاسِينَ';
      final spans = WordAlignService.fromMushafWords(text, (
        count: 3,
        words: [(1, 0, 700), (2, 700, 1200), (3, 1200, 2400)],
      ));
      expect([for (final s in spans!) (s.startWord, s.endWord)],
          [(0, 1), (1, 2), (2, 4)]);
    });

    test('a pause sign is no word, and another count is no verse of ours',
        () {
      const text = 'ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ ۛ فِيهِ';
      expect(WordAlignService.alignWords(text), [0, 1, 2, 3, 4]);
      expect(
          WordAlignService.fromMushafWords(
              text, (count: 6, words: [(1, 0, 100)])),
          isNull);
    });
  });
}
