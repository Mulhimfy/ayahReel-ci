import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/state/creation_state.dart';

/// What a reel is made with before anybody chooses: its long verses one
/// line at a time, the scenery changing with each line, the surah's
/// name at its head, and the light passing through the words.
void main() {
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  test('a new install makes reels line by line, titled, in the light', () {
    for (final s in [AppSettings.defaults, AppSettings.fromJson(const {})]) {
      expect(s.verseLines, 1);
      expect(s.scenesFollowLines, isTrue);
      expect(s.surahTitle, isTrue);
    }
    expect(VerseLines.preferred, 1);
    expect(CreationState().motion, VerseMotion.standard);
    expect(MotionPreset.of(VerseMotion.standard), MotionPreset.light);
    // The light needs no word timing: every voice has it.
    expect(VerseMotion.standard.followsWords, isFalse);
  });

  test('what the preview builds wrote under the old keys is not read', () {
    final s = AppSettings.fromJson(
        const {'verseLines': 0, 'surahTitle': false, 'surahName': false});
    expect(s.verseLines, 1);
    expect(s.surahTitle, isTrue);
  });

  test('a choice survives the round trip through the settings file', () {
    for (final n in [0, 1, 2, 3]) {
      final back = AppSettings.fromJson(AppSettings.defaults
          .copyWith(verseLines: n, surahTitle: n.isOdd)
          .toJson());
      expect(back.verseLines, n);
      expect(back.surahTitle, n.isOdd);
    }
  });

  test('a new reel starts from them', () {
    final s = CreationState()..startNewReel();
    expect(s.verseLines, 1);
    expect(s.surahTitle, isTrue);
    expect(s.pacing, ScenePacing.perLine);

    SettingsService.state.value = AppSettings.defaults
        .copyWith(verseLines: VerseLines.whole, surahTitle: false);
    s.startNewReel();
    expect(s.verseLines, VerseLines.whole);
    expect(s.surahTitle, isFalse);
    // Whole verses: the scenery changes with the verse, as it always did.
    expect(s.pacing, ScenePacing.perAyah);
  });
}
