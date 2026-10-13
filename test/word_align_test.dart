import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/word_align_service.dart';

void main() {
  group('parseAlignJson', () {
    test('parses and sorts segments by start time', () {
      const json = '''
      [{"surah":112,"ayah":1,
        "segments":[[1,2,400,790],[0,1,30,390],[2,4,800,2300]],
        "stats":{"insertions":0,"deletions":0,"transpositions":0}}]
      ''';
      final m = WordAlignService.parseAlignJson(json);
      final spans = m[112]![1]!;
      expect(spans.length, 3);
      expect(spans.first.startMs, 30);
      expect(spans.first.startWord, 0);
      expect(spans.last.endWord, 4);
    });

    test('tolerates the align tool crash log before the JSON array '
        '(the canonical Sudais file ships that way)', () {
      const json = '''

Crashed Command '['./align', '../quran-uthmani.mod.txt']' blah
[{"surah":113,"ayah":5,"segments":[[0,1,30,1200]],
  "stats":{"insertions":0,"deletions":0,"transpositions":0}}]''';
      final m = WordAlignService.parseAlignJson(json);
      expect(m[113]![5]!.single.endMs, 1200);
    });

    test('tolerates entries with null segments '
        '(one each in the Shuraym and Minshawy Mujawwad files)', () {
      const json = '''
      [{"surah":2,"ayah":1,"segments":null,
        "stats":{"insertions":0,"deletions":0,"transpositions":0}},
       {"surah":2,"ayah":2,"segments":[[0,1,0,900]],
        "stats":{"insertions":0,"deletions":0,"transpositions":0}}]
      ''';
      final m = WordAlignService.parseAlignJson(json);
      expect(m[2]![1], isNull);
      expect(m[2]![2], isNotNull);
    });

    test('skips ayahs with no segments', () {
      const json = '''
      [{"surah":2,"ayah":1,"segments":[],
        "stats":{"insertions":0,"deletions":0,"transpositions":0}}]
      ''';
      expect(WordAlignService.parseAlignJson(json)[2], isNull);
    });
  });

  group('displayRange', () {
    // Four words as displayed for 112:1 (basmala already stripped).
    const clean112 = 'قُلْ هُوَ ٱللَّهُ أَحَدٌ';

    test('maps word indices 1:1 when there are no mark tokens', () {
      expect(WordAlignService.displayRange(clean112, 0, 1),
          (start: 0, end: 1));
      expect(WordAlignService.displayRange(clean112, 2, 4),
          (start: 2, end: 4));
    });

    test('skips standalone waqf-mark tokens and attaches them to the '
        'preceding word', () {
      // word ۘmark word word — as alquran.cloud serves pause marks.
      const text = 'ذَٰلِكَ ۖ ٱلْكِتَـٰبُ لَا';
      // Align word 0 = ذلك; its display range swallows the mark token.
      expect(
          WordAlignService.displayRange(text, 0, 1), (start: 0, end: 2));
      // Align word 1 = الكتاب (display token 2).
      expect(
          WordAlignService.displayRange(text, 1, 2), (start: 2, end: 3));
      // Range through the end covers the tail.
      expect(
          WordAlignService.displayRange(text, 1, 3), (start: 2, end: 4));
    });

    test('rejects indices that do not fit the text (fail-safe)', () {
      expect(WordAlignService.displayRange(clean112, 0, 5), isNull);
      expect(WordAlignService.displayRange(clean112, 4, 5), isNull);
      expect(WordAlignService.displayRange(clean112, 2, 2), isNull);
      expect(WordAlignService.displayRange(clean112, -1, 1), isNull);
    });

    test('handles the single-word muqataʾaʿat ayah', () {
      const alm = 'الٓمٓ';
      expect(WordAlignService.displayRange(alm, 0, 1), (start: 0, end: 1));
    });
  });

  group('highlightPlan', () {
    const clean112 = 'قُلْ هُوَ ٱللَّهُ أَحَدٌ';
    const ayahs = [
      Ayah(number: 1, arabic: clean112, translation: 't1'),
      Ayah(number: 2, arabic: 'ٱللَّهُ ٱلصَّمَدُ', translation: 't2'),
    ];
    const rec = Recitation(
      reciterId: 'r',
      surah: 112,
      audioPath: 'x',
      timings: [AyahTiming(1, 0, 2400), AyahTiming(2, 2400, 4400)],
    );

    test('gap-fills between spans and holds the last word to ayah end',
        () {
      final plan = WordAlignService.highlightPlan(
        recitation: rec,
        ayahs: ayahs,
        spansByAyah: {
          1: const [WordSpan(0, 1, 30, 390), WordSpan(1, 2, 600, 900)],
        },
        startAyah: 1,
        endAyah: 2,
      )!;
      final w = plan[1]!;
      expect(w.length, 2);
      // First window runs to the next span's start (pause included)...
      expect(w[0].startMs, 30);
      expect(w[0].endMs, 600);
      // ...and the last one holds until the ayah ends.
      expect(w[1].endMs, 2400);
      // Ayah 2 had no spans: no highlight windows, base card only.
      expect(plan[2], isNull);
    });

    test('clamps span times to the measured ayah duration', () {
      final plan = WordAlignService.highlightPlan(
        recitation: rec,
        ayahs: ayahs,
        spansByAyah: {
          1: const [WordSpan(0, 4, 100, 99999)],
        },
        startAyah: 1,
        endAyah: 1,
      )!;
      expect(plan[1]!.single.endMs, 2400);
    });

    test('drops spans whose word indices do not fit the text', () {
      final plan = WordAlignService.highlightPlan(
        recitation: rec,
        ayahs: ayahs,
        spansByAyah: {
          1: const [WordSpan(0, 9, 30, 390)],
        },
        startAyah: 1,
        endAyah: 1,
      );
      // The only span was invalid — no usable plan at all.
      expect(plan, isNull);
    });

    test('returns null when the selection would exceed the overlay cap',
        () {
      final plan = WordAlignService.highlightPlan(
        recitation: rec,
        ayahs: ayahs,
        spansByAyah: {
          1: const [WordSpan(0, 1, 0, 100), WordSpan(1, 2, 100, 200)],
        },
        startAyah: 1,
        endAyah: 1,
        maxOverlays: 2, // base + 2 windows = 3 > 2
      );
      expect(plan, isNull);
    });
  });

  group('which voices have word timings', () {
    Reciter byId(String id) => reciters.firstWhere((r) => r.id == id);

    test('eleven of the app\'s voices: nine exact folders and two same '
        'recordings at a lower bitrate', () {
      expect(WordAlignService.supportedCount(reciters), 11);
    });

    test('Husary and Abdul Basit murattal are covered by the 64kbps files',
        () {
      // Same recordings, verified pairwise with ffprobe — see the
      // service's class doc. Without the mapping these two, the app's
      // most-picked classical voices, had no highlight.
      expect(WordAlignService.supports(byId('husary')), isTrue);
      expect(WordAlignService.supports(byId('abdulbasit')), isTrue);
    });

    test('the teaching recitation is not mistaken for the murattal one',
        () {
      // Husary_Muallim_128kbps has a released file too, and it is a
      // different reading with different lengths. Nothing in the app
      // plays it, so nothing may be handed its timings.
      for (final r in reciters) {
        expect(r.everyAyahFolder, isNot('Husary_Muallim_128kbps'));
      }
      expect(WordAlignService.supports(byId('husary_mujawwad')), isFalse);
    });

    test('an upload never claims timings', () {
      const upload = Reciter(
        id: 'user_x',
        name: 'x',
        arabicName: 'x',
        style: '',
        source: OwnAudio(),
      );
      expect(WordAlignService.supports(upload), isFalse);
    });
  });
}
