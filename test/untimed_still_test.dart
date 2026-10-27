import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_ink.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/data/verse_numbering.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/data/word_align_service.dart';
import 'package:ayah_reels/state/creation_state.dart' show TextPreset;
import 'package:ayah_reels/widgets/verse_flourish.dart';
import 'package:ayah_reels/widgets/verse_stage.dart';

/// Nothing guessed where the timing isn't there or can't be believed
/// (the owner's reports of 2026-10-27): an app voice's verse its timing
/// doesn't reach stays still, and timing that has swallowed a pause is
/// dropped from the near tier and cut back in the vouched one.
void main() {
  const ayahs = [
    Ayah(
        number: 1,
        arabic: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
        translation: 'Say, He is God, One.'),
    Ayah(
        number: 2,
        arabic: 'ٱللَّهُ ٱلصَّمَدُ',
        translation: 'God, the Eternal Refuge.'),
  ];
  const rec = Recitation(
    reciterId: 'x',
    surah: 112,
    audioPath: '',
    timings: [AyahTiming(1, 0, 3000), AyahTiming(2, 3000, 6000)],
  );

  Widget stage(ValueNotifier<int> clock, {required bool even}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: VerseStage(
              clock: clock,
              units: VerseUnit.of(rec, 1, 2, null),
              ayahs: ayahs,
              recitation: rec,
              motion: const VerseMotion(thread: true, light: true),
              words: null,
              highlight: false,
              // Verse 1 is timed; verse 2 is not.
              wordTimes: const {
                1: [(0, 700), (700, 1400), (1400, 2100), (2100, 2800)],
              },
              evenWithoutTimes: even,
              width: 360,
              textColor: Colors.white,
              accent: const Color(0xFFEEC96B),
              ink: VerseInk.none,
              accentInk: VerseInk.none,
              textScale: 1,
              preset: TextPreset.classic,
              onLight: false,
              translation: VerseTranslation.english,
              numbering: VerseNumbering.off,
              showTranslation: true,
              surah: 112,
              verseFace: const ReelTypography().verse,
              translationFace: const ReelTypography().translation,
              onHeight: (_) {},
            ),
          ),
        ),
      );

  testWidgets('an app voice\'s untimed verse has no thread and no light',
      (t) async {
    final clock = ValueNotifier(500);
    await t.pumpWidget(stage(clock, even: false));
    expect(find.byType(VerseFlourish), findsOneWidget, reason: 'timed');
    clock.value = 4000;
    await t.pump();
    expect(find.byType(VerseFlourish), findsNothing, reason: 'untimed');
  });

  testWidgets('the user\'s own recording keeps the even pace', (t) async {
    final clock = ValueNotifier(4000);
    await t.pumpWidget(stage(clock, even: true));
    expect(find.byType(VerseFlourish), findsOneWidget);
  });

  group('timing as far as it can be believed', () {
    final murattal =
        reciters.firstWhere((r) => !r.style.startsWith('Mujawwad'));
    final mujawwad =
        reciters.firstWhere((r) => r.style.startsWith('Mujawwad'));
    const fine = [
      WordSpan(0, 1, 0, 900),
      WordSpan(1, 2, 900, 2000),
      WordSpan(2, 3, 2400, 3100),
    ];
    // A first word that swallowed a cry: 12 s.
    const swallowed = [
      WordSpan(0, 1, 0, 12000),
      WordSpan(1, 2, 12000, 13000),
    ];
    // A pause of 9 s between two words.
    const paused = [
      WordSpan(0, 1, 0, 900),
      WordSpan(1, 2, 9900, 10800),
    ];

    test('a near verse past the limits is dropped, the rest kept', () {
      final out = WordAlignService.believable(
          {1: fine, 2: swallowed, 3: paused},
          WordAlignService.limitsFor(murattal),
          near: true);
      expect(out.keys, [1]);
    });

    test('a vouched word past the limit is cut back, the verse kept', () {
      final out = WordAlignService.believable(
          {2: swallowed}, WordAlignService.limitsFor(murattal),
          near: false);
      expect(out[2]!.first.endMs, 10000);
      expect(out[2]![1].startMs, 12000);
    });

    test('mujawwad holds a word longer', () {
      final out = WordAlignService.believable(
          {2: swallowed}, WordAlignService.limitsFor(mujawwad),
          near: true);
      expect(out.keys, [2]);
    });
  });
}
