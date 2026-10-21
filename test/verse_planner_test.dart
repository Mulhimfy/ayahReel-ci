import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_ink.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/verse_numbering.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/render/verse_planner.dart';
import 'package:ayah_reels/state/creation_state.dart' show TextPreset;

/// The planner end to end, on the test's own font: a long verse is cut
/// into parts that each fit, timed by its words, its translation shared
/// out, every part held to one height; a short verse is left alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kursi = Ayah(
    number: 255,
    arabic: 'ٱللَّهُ لَآ إِلَـٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ ۚ لَا تَأْخُذُهُۥ '
        'سِنَةٌ وَلَا نَوْمٌ ۚ لَّهُۥ مَا فِى ٱلسَّمَـٰوَٰتِ وَمَا فِى ٱلْأَرْضِ ۗ '
        'مَن ذَا ٱلَّذِى يَشْفَعُ عِندَهُۥٓ إِلَّا بِإِذْنِهِۦ ۚ يَعْلَمُ مَا بَيْنَ '
        'أَيْدِيهِمْ وَمَا خَلْفَهُمْ',
    translation: 'Allāh - there is no deity except Him, the Ever-Living, the '
        'Self-Sustaining. Neither drowsiness overtakes Him nor sleep. To Him '
        'belongs whatever is in the heavens and whatever is on the earth. Who '
        'is it that can intercede with Him except by His permission? He '
        'knows what is [presently] before them and what will be after them.',
  );
  const short = Ayah(
    number: 256,
    arabic: 'قُلْ هُوَ',
    translation: 'Say, He is.',
  );
  const rec = Recitation(
    reciterId: 'r',
    surah: 2,
    audioPath: '',
    timings: [AyahTiming(255, 0, 24000), AyahTiming(256, 24000, 27000)],
  );
  final ayahs = List<Ayah>.filled(256, kursi)..[255] = short;
  const look = VerseLook(
    textScale: 1,
    preset: TextPreset.classic,
    typography: ReelTypography(),
    edition: VerseTranslation.english,
    numbering: VerseNumbering.mark,
    showTranslation: true,
    ink: VerseInk.none,
    surah: 2,
  );

  /// Each word its share of the verse by letters.
  Map<int, List<WordSpan>> alignment() {
    final out = <int, List<WordSpan>>{};
    for (final a in [kursi, short]) {
      final t = rec.timing(a.number);
      final tokens = VerseText.tokens(a.arabic);
      final letters = [
        for (final k in tokens)
          if (VerseText.isWord(k)) VerseText.letters(k),
      ];
      final total = letters.fold<int>(0, (n, x) => n + x);
      final spans = <WordSpan>[];
      var at = 300;
      final speech = t.durationMs - 600;
      for (var i = 0; i < letters.length; i++) {
        final len = speech * letters[i] ~/ total;
        spans.add(WordSpan(i, i + 1, at, at + len * 8 ~/ 10));
        at += len;
      }
      out[a.number] = spans;
    }
    return out;
  }

  test('the text alone says how many lines there are', () {
    final whole = VersePlanner.estimateLines(ayahs, 255, 256, 0, look);
    expect(whole, [kursi.arabic, short.arabic]);
    final lines = VersePlanner.estimateLines(ayahs, 255, 256, 2, look);
    expect(lines.length, greaterThan(2));
    // The short verse stays whole, and the cut one's lines are its words
    // in order.
    expect(lines.last, short.arabic);
    expect(lines.sublist(0, lines.length - 1).join(' '), kursi.arabic);
    expect(VersePlanner.estimateUnits(ayahs, 255, 256, 2, look), lines.length);
  });

  testWidgets('a long verse is cut, timed and shared out', (t) async {
    late VerseLinePlan plan;
    await t.runAsync(() async {
      plan = await VersePlanner.plan(
        lines: 2,
        ayahs: ayahs,
        recitation: rec,
        startAyah: 255,
        endAyah: 256,
        look: look,
        words: alignment(),
      );
    });
    expect(plan.partsOf(256), isNull, reason: 'the short verse is whole');
    final parts = plan.partsOf(255)!;
    expect(parts.length, greaterThan(1));
    // Gapless over the verse, in order, none too short to read.
    expect(parts.first.startMs, 0);
    expect(parts.last.endMs, 24000);
    for (var i = 0; i < parts.length; i++) {
      expect(parts[i].index, i);
      expect(parts[i].count, parts.length);
      expect(parts[i].durationMs,
          greaterThanOrEqualTo(PartTiming.minPartMs));
      if (i > 0) {
        expect(parts[i].startMs, parts[i - 1].endMs);
        expect(parts[i].tokenStart, parts[i - 1].tokenEnd);
      }
      // Each fits the lines it was cut for.
      final tokens = VerseText.tokens(kursi.arabic);
      expect(
          VersePlanner.linesOf(
              tokens, parts[i].tokenStart, parts[i].tokenEnd, look, 255),
          lessThanOrEqualTo(2));
    }
    // The words, and the translation, are all there, once.
    expect(parts.map((p) => p.arabic).join(' '), kursi.arabic);
    expect(parts.map((p) => p.translation).join(' '),
        kursi.translation);
    // One size and one height for every part of the verse.
    expect(parts.map((p) => p.fit).toSet(), hasLength(1));
    expect(parts.map((p) => p.height).toSet(), hasLength(1));
    expect(parts.first.height, greaterThan(0));
    // And the units the reel shows run through them.
    final units = VerseUnit.of(rec, 255, 256, plan);
    expect(units.length, parts.length + 1);
  });

  testWidgets('a verse with no timing it can be cut on stays whole',
      (t) async {
    late VerseLinePlan plan;
    await t.runAsync(() async {
      plan = await VersePlanner.plan(
        lines: 2,
        ayahs: ayahs,
        recitation: rec,
        startAyah: 255,
        endAyah: 256,
        look: look,
        // No word timing, and a recording with no pauses at all.
        loudness: () async =>
            List<double>.generate(2700, (i) => i.isEven ? 50 : 70),
      );
    });
    expect(plan.isEmpty, isTrue);
  });
}
