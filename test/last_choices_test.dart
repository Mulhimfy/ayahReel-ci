import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/dedication.dart';
import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/last_choices.dart';
import 'package:ayah_reels/data/reel_recipe.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/state/creation_state.dart';

/// The last reel's choices outlive the app: the voice, the surah and its
/// verses, and every choice of taste come back at the next launch; what
/// belongs to one reel alone does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('last_choices');
    LastChoices.debugReset();
    LastChoices.debugDir = dir;
  });
  tearDown(() {
    LastChoices.debugReset();
    LastChoices.debugDir = null;
    dir.deleteSync(recursive: true);
  });

  test('what lasts is kept, and what belongs to one reel is not', () {
    final s = CreationState()
      ..selectReciter(reciters[3])
      ..selectSurah(2)
      ..selectRange(255, 257)
      ..setVerseFace(VerseFace.values.last)
      ..setTextScale(1.3)
      ..setMotion(MotionPreset.rise.motion)
      ..setWordHighlight(false)
      ..setDedication(
          const Dedication(kind: DedicationKind.sadaqah, name: 'Fatima'))
      ..setPacing(ScenePacing.even);
    final j = LastChoices.snapshot(s);
    expect(j['reciterId'], reciters[3].id);
    expect((j['surah'], j['startAyah'], j['endAyah']), (2, 255, 257));
    for (final k in const [
      'dedication',
      'pacing',
      'transition',
      'trimMs',
      'verseLines',
      'surahTitle',
      'multiScene',
      'sceneWeights',
    ]) {
      expect(j.containsKey(k), isFalse, reason: k);
    }

    final back = CreationState();
    LastChoices.apply(ReelRecipe.fromJson(j), back);
    expect(back.reciter?.id, reciters[3].id);
    expect((back.surah, back.startAyah, back.endAyah), (2, 255, 257));
    expect(back.rangeChosen, isTrue);
    expect(back.verseFace, VerseFace.values.last);
    expect(back.textScale, 1.3);
    expect(back.motion, MotionPreset.rise.motion);
    expect(back.wordHighlight, isFalse);
    expect(back.dedication.isEmpty, isTrue);
  });

  test('a choice of no motion comes back as no motion', () {
    final s = CreationState()..setMotion(VerseMotion.none);
    final back = CreationState();
    expect(back.motion, VerseMotion.standard);
    LastChoices.apply(ReelRecipe.fromJson(LastChoices.snapshot(s)), back);
    expect(back.motion, VerseMotion.none);
  });

  test('verses past the end of the surah are held inside it', () {
    final back = CreationState();
    LastChoices.apply(
        ReelRecipe.fromJson(const {
          'reciterId': 'nobody',
          'surah': 1,
          'startAyah': 9,
          'endAyah': 12,
        }),
        back);
    expect((back.surah, back.startAyah, back.endAyah), (1, 7, 7));
    // A voice the app no longer has is left unchosen.
    expect(back.reciter, isNull);
  });

  test('written as they change, and read back at the next launch', () async {
    final s = CreationState();
    await LastChoices.init(s);
    // Nothing kept yet: the app's own defaults.
    expect(s.motion, VerseMotion.standard);
    expect(s.rangeChosen, isFalse);
    s
      ..selectReciter(reciters[1])
      ..selectSurah(18)
      ..selectRange(1, 10)
      ..setMotion(MotionPreset.thread.motion);
    await LastChoices.flush();
    expect(File('${dir.path}/last_choices.json').existsSync(), isTrue);

    // The next launch.
    LastChoices.debugReset();
    final next = CreationState();
    await LastChoices.init(next);
    expect(next.reciter?.id, reciters[1].id);
    expect((next.surah, next.startAyah, next.endAyah), (18, 1, 10));
    expect(next.motion, MotionPreset.thread.motion);
  });
}
