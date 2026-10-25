import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/reel_effects.dart';
import 'package:ayah_reels/data/reel_recipe.dart';
import 'package:ayah_reels/data/dedication.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_ink.dart';
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/state/creation_state.dart';

/// A recipe is what lets a finished reel be opened again. What is
/// pinned here: everything the preview can change survives the round
/// trip through JSON, and applying it back puts the creation state
/// where the user left it — including the two things that are easy to
/// get wrong, the ink colour after the backdrop has had its say and a
/// run of several sceneries in their original order.
void main() {
  const still = ReelBackground.still(
    id: 'sky_pexels_01',
    name: 'Sky 1',
    imageAsset: 'assets/backgrounds/sky_pexels_01.jpg',
    gradientArgb: [0xFF000000, 0xFF111111],
  );
  const still2 = ReelBackground.still(
    id: 'desert_pexels_01',
    name: 'Desert 1',
    imageAsset: 'assets/backgrounds/desert_pexels_01.jpg',
    gradientArgb: [0xFF000000, 0xFF111111],
  );
  const own = ReelBackground.deviceFile(
    id: 'custom_abc',
    name: 'Your photo',
    filePath: '/tmp/own.jpg',
    fileIsImage: true,
  );

  test('captures what the state holds and comes back the same', () {
    final s = CreationState()
      ..startNewReel()
      ..selectReciter(reciters[1])
      ..selectSurah(36)
      ..selectRange(1, 3)
      ..setLayout(ReelLayout.letterbox)
      ..setRoundedCorners(false)
      ..setBackdropColor(0xFFF3EADA)
      ..setTextColor(0xFFEEC96B)
      ..setAccentColor(0xFF9CC7F5)
      ..setVerseFace(VerseFace.scheherazade)
      ..setTranslationFace(TranslationFace.cormorant)
      ..setTranslationFace(TranslationFace.nastaliq)
      ..setEffects(const ReelEffects(
        look: ReelLook.golden,
        warmth: 0.4,
        vignette: 0.6,
        fade: true,
      ))
      ..setTextScale(1.2)
      ..setTextPreset(TextPreset.glow)
      ..setOverlayAlign(0.8)
      ..setWordHighlight(false)
      ..selectBackground(still)
      ..setMultiScene(true)
      ..toggleScene(own, limit: 3)
      ..toggleScene(still2, limit: 3)
      ..setSceneWeight(1, 3)
      ..setPacing(ScenePacing.even)
      ..setTransition(SceneTransition.cut);
    final r = ReelRecipe.fromJson(
        ReelRecipe.capture(s, trimMs: 12345).toJson());
    expect(r.reciterId, 'husary');
    expect(r.surah, 36);
    expect(r.startAyah, 1);
    expect(r.endAyah, 3);
    expect(r.scenes, ['sky_pexels_01', 'image:/tmp/own.jpg', 'desert_pexels_01']);
    expect(r.sceneWeights, [1, 3, 1]);
    expect(r.multiScene, isTrue);
    expect(r.layout, ReelLayout.letterbox);
    expect(r.roundedCorners, isFalse);
    expect(r.backdrop, LetterboxBackdrop.colour);
    expect(r.backdropArgb, 0xFFF3EADA);
    expect(r.textArgb, 0xFFEEC96B);
    expect(r.textScale, 1.2);
    expect(r.preset, TextPreset.glow);
    expect(r.overlayAlign, 0.8);
    expect(r.wordHighlight, isFalse);
    expect(r.pacing, ScenePacing.even);
    expect(r.transition, SceneTransition.cut);
    expect(r.trimMs, 12345);
    // The style step's own decisions. Both translation faces travel,
    // not just the one this reel printed: switching the edition after
    // reopening must land on what the user chose for that script.
    expect(r.accentArgb, 0xFF9CC7F5);
    expect(r.verseFace, VerseFace.scheherazade);
    expect(r.latinFace, TranslationFace.cormorant);
    expect(r.arabicScriptFace, TranslationFace.nastaliq);
    expect(r.effects.look, ReelLook.golden);
    expect(r.effects.warmth, closeTo(0.4, 1e-9));
    expect(r.effects.vignette, closeTo(0.6, 1e-9));
    expect(r.effects.fade, isTrue);
  });

  test('the inks and a dragged dedication survive the round trip', () {
    final s = CreationState()
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..setVerseInk(VerseInk.ember)
      ..setAccentInk(VerseInk.frost)
      ..setDedication(const Dedication(
          kind: DedicationKind.sadaqah, name: 'Fatima'))
      ..setDedicationAt(const Offset(0.3, 0.2));
    final json = ReelRecipe.capture(s).toJson();
    final r = ReelRecipe.fromJson(json);
    expect(r.verseInk, VerseInk.ember);
    expect(r.accentInk, VerseInk.frost);
    // The bases travel too, for a build that knows no inks.
    expect(r.textArgb, VerseInk.ember.base);
    expect(r.accentArgb, VerseInk.frost.base);
    expect(r.dedicationAt, const Offset(0.3, 0.2));

    final back = CreationState();
    r.applyStyling(back, reciters.first);
    expect(back.verseInk, VerseInk.ember);
    expect(back.accentInk, VerseInk.frost);
    expect(back.textArgb, VerseInk.ember.base);
    expect(back.dedicationAt, const Offset(0.3, 0.2));

    // A flat colour takes the ink off; a new reel takes the place of
    // the line off with the line.
    back.setTextColor(0xFF9FE8C9);
    expect(back.verseInk, VerseInk.none);
    back.startNewReel();
    expect(back.dedicationAt, isNull);
  });

  test('a reel with no ink and an unmoved line writes no new keys', () {
    final s = CreationState()
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..setDedication(const Dedication(name: 'Aisha'));
    final json = ReelRecipe.capture(s).toJson();
    expect(json.containsKey('verseInk'), isFalse);
    expect(json.containsKey('accentInk'), isFalse);
    expect(json.containsKey('dedicationAt'), isFalse);
    final r = ReelRecipe.fromJson(json);
    expect(r.verseInk, VerseInk.none);
    expect(r.dedicationAt, isNull);
  });

  test('a recipe written before the style step opens as the defaults', () {
    final r = ReelRecipe.fromJson({
      'reciterId': 'alafasy',
      'surah': 1,
      'startAyah': 1,
      'endAyah': 7,
      'scenes': ['sky_pexels_01'],
      'sceneWeights': [1],
      'textArgb': 0xFFFFFFFF,
    });
    expect(r.accentArgb, accentOnDark);
    expect(r.verseFace, VerseFace.uthmani);
    expect(r.latinFace, TranslationFace.inter);
    expect(r.arabicScriptFace, TranslationFace.plex);
    expect(r.effects, ReelEffects.off);
    expect(r.effects.isNeutral, isTrue);

    // And applying it leaves the state on those defaults rather than
    // on whatever the last reel of this session was set to.
    final s = CreationState()
      ..setVerseFace(VerseFace.lateef)
      ..setEffects(const ReelEffects(look: ReelLook.noir));
    r.applyStyling(s, reciters.first);
    expect(s.verseFace, VerseFace.uthmani);
    expect(s.effects, ReelEffects.off);
  });

  test('applying it puts the state back, ink last', () {
    const r = ReelRecipe(
      reciterId: 'alafasy',
      surah: 2,
      startAyah: 255,
      endAyah: 255,
      scenes: ['sky_pexels_01', 'desert_pexels_01'],
      sceneWeights: [2, 1],
      multiScene: true,
      pacing: ScenePacing.perAyah,
      transition: SceneTransition.fade,
      layout: ReelLayout.letterbox,
      roundedCorners: true,
      backdrop: LetterboxBackdrop.colour,
      backdropArgb: 0xFFFFFFFF, // white band …
      preset: TextPreset.minimal,
      textArgb: 0xFF9FE8C9, // … under a mint verse the user chose
      textScale: 0.9,
      overlayAlign: 0.3,
      wordHighlight: true,
      accentArgb: 0xFFD07C4A, // … and a copper accent, also a choice
    );
    final s = CreationState();
    r.applyStyling(s, reciters.first);
    r.applyScenes(s, const [still, still2]);
    expect(s.reciter!.id, 'alafasy');
    expect(s.surah, 2);
    expect(s.startAyah, 255);
    expect(s.layout, ReelLayout.letterbox);
    expect(s.backdropArgb, 0xFFFFFFFF);
    // The white band would have flipped a default ink to dark; the
    // recipe's own mint must stand.
    expect(s.textArgb, 0xFF9FE8C9);
    // Same for the accent: the pale band re-derives a default gold,
    // and the recipe's copper has to be the last word on it too.
    expect(s.accentArgb, 0xFFD07C4A);
    expect(s.scenes.map((b) => b.id), ['sky_pexels_01', 'desert_pexels_01']);
    expect(s.sceneWeights, [2, 1]);
    expect(s.multiScene, isTrue);
    expect(s.backgroundChosen, isTrue);
    expect(s.overlayAlign, 0.3);
    expect(s.textPreset, TextPreset.minimal);
  });

  test('a matched run comes back on the verses it was matched for', () {
    const r = ReelRecipe(
      reciterId: 'alafasy',
      surah: 78,
      startAyah: 6,
      endAyah: 14,
      scenes: ['a', 'gone', 'b'],
      sceneWeights: [1, 1, 1],
      sceneAnchors: [SceneAnchor(7), SceneAnchor(9), SceneAnchor(14, 3)],
      multiScene: true,
      pacing: ScenePacing.perLine,
      transition: SceneTransition.fade,
      layout: ReelLayout.fullFrame,
      roundedCorners: false,
      backdrop: LetterboxBackdrop.colour,
      backdropArgb: 0xFF000000,
      preset: TextPreset.glow,
      textArgb: 0xFFFFFFFF,
      textScale: 1,
      overlayAlign: 0.5,
      wordHighlight: true,
    );
    final back = ReelRecipe.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
    expect(back.sceneAnchors, r.sceneAnchors);

    // The middle scenery could not be had: its verse goes to the one
    // before, and the third keeps its own.
    final s = CreationState();
    back.applyScenes(s, const [still, still2], from: const [0, 2]);
    expect(s.sceneAnchors, const [SceneAnchor(7), SceneAnchor(14, 3)]);

    // A run picked by hand writes no anchors and reads back none.
    const plain = ReelRecipe(
      reciterId: 'alafasy',
      surah: 1,
      startAyah: 1,
      endAyah: 7,
      scenes: ['a'],
      sceneWeights: [1],
      multiScene: false,
      pacing: ScenePacing.perAyah,
      transition: SceneTransition.fade,
      layout: ReelLayout.fullFrame,
      roundedCorners: false,
      backdrop: LetterboxBackdrop.colour,
      backdropArgb: 0xFF000000,
      preset: TextPreset.glow,
      textArgb: 0xFFFFFFFF,
      textScale: 1,
      overlayAlign: 0.5,
      wordHighlight: true,
    );
    expect(plain.toJson().containsKey('sceneAnchors'), isFalse);
    expect(ReelRecipe.fromJson(plain.toJson()).sceneAnchors, isEmpty);
  });

  test('reopening a reel in the ink it started in leaves the ink free',
      () {
    // A reel made in the default white over a scenery, reopened. The
    // recipe keeps the colours, not whether anyone chose them; read as
    // chosen, the white stayed white for the rest of the session, and
    // the next reel on an ivory band came out white on near-white.
    const r = ReelRecipe(
      reciterId: 'alafasy',
      surah: 1,
      startAyah: 1,
      endAyah: 7,
      scenes: ['sky_pexels_01'],
      sceneWeights: [1],
      multiScene: false,
      pacing: ScenePacing.perAyah,
      transition: SceneTransition.fade,
      layout: ReelLayout.fullFrame,
      roundedCorners: false,
      backdrop: LetterboxBackdrop.blur,
      backdropArgb: 0xFF000000,
      preset: TextPreset.classic,
      textArgb: inkOnDark,
      textScale: 1,
      overlayAlign: 0.5,
      wordHighlight: true,
    );
    final s = CreationState();
    r.applyStyling(s, reciters.first);
    expect(s.textArgb, inkOnDark);
    s
      ..setLayout(ReelLayout.letterbox)
      ..setBackdropColor(0xFFF6F1E6); // ivory
    expect(s.onLightGround, isTrue);
    expect(s.textArgb, inkOnLight);
    expect(s.accentArgb, accentOnLight);
  });

  test('the colour reset is not a choice of white', () {
    final s = CreationState()
      ..setTextColor(0xFF9FE8C9)
      ..resetColours()
      ..setLayout(ReelLayout.letterbox)
      ..setBackdropColor(0xFFF6F1E6);
    expect(s.textArgb, inkOnLight);
  });

  test('a reel saved before recipes existed cannot be edited, and loads',
      () {
    final reel = SavedReel.fromJson({
      'id': '1',
      'fileName': 'reel_1.mp4',
      'reciterName': 'x',
      'surahName': 'Al-Fatiha',
      'startAyah': 1,
      'endAyah': 7,
      'gradientArgb': [1, 2],
      'createdAt': '2026-01-01T00:00:00.000',
    });
    expect(reel.canEdit, isFalse);
    expect(reel.copyWith(inGallery: true).recipe, isNull);
  });

  test('unknown enum names fall back rather than throw', () {
    final r = ReelRecipe.fromJson({
      'reciterId': 'alafasy',
      'surah': 1,
      'startAyah': 1,
      'endAyah': 1,
      'layout': 'hologram',
      'preset': 'neon',
    });
    expect(r.layout, ReelLayout.fullFrame);
    expect(r.preset, TextPreset.classic);
    expect(r.scenes, isEmpty);
  });

  test('lines, motion and the surah title survive the round trip', () {
    final s = CreationState()
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..setVerseLines(2)
      ..setMotion(const VerseMotion(
          arrival: VerseArrival.rise, thread: true, light: true))
      ..setSurahTitle(true)
      ..setSurahTitleAt(const Offset(0.4, 0.2));
    final json = ReelRecipe.capture(s).toJson();
    final r = ReelRecipe.fromJson(json);
    expect(r.verseLines, 2);
    expect(r.motion,
        const VerseMotion(arrival: VerseArrival.rise, thread: true, light: true));
    expect(r.surahTitle, isTrue);
    expect(r.surahTitleAt, const Offset(0.4, 0.2));

    final back = CreationState();
    r.applyStyling(back, reciters.first);
    expect(back.verseLines, 2);
    expect(back.motion.light, isTrue);
    expect(back.surahTitle, isTrue);
    expect(back.surahTitleAt, const Offset(0.4, 0.2));
  });

  test('a reel saved before them opens whole, still and untitled', () {
    final r = ReelRecipe.fromJson({
      'reciterId': 'alafasy',
      'surah': 1,
      'startAyah': 1,
      'endAyah': 7,
      'scenes': ['sky_pexels_01'],
      'sceneWeights': [1],
      'textArgb': 0xFFFFFFFF,
    });
    expect(r.verseLines, 0);
    expect(r.motion, VerseMotion.none);
    expect(r.surahTitle, isFalse);
    final s = CreationState()
      ..setMotion(const VerseMotion(arrival: VerseArrival.fade))
      ..setSurahTitle(true);
    r.applyStyling(s, reciters.first);
    expect(s.motion, VerseMotion.none);
    expect(s.surahTitle, isFalse);
    expect(s.verseLines, 0);
    // And a recipe writes none of it when there is none.
    final json = ReelRecipe.capture(s).toJson();
    expect(json.containsKey('verseLines'), isFalse);
    expect(json.containsKey('motion'), isFalse);
    expect(json.containsKey('surahTitle'), isFalse);
  });
}
