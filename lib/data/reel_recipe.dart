import 'dart:ui' show Offset;

import '../state/creation_state.dart';
import 'models.dart';
import 'dedication.dart';
import 'reel_effects.dart';
import 'verse_font.dart';
import 'verse_ink.dart';
import 'verse_motion.dart';

/// Everything that went into a reel, so it can be opened again and
/// changed rather than rebuilt from the first screen.
///
/// The library used to keep only what a reel *was* — voice, surah,
/// verses — which is enough to replay it and not enough to edit it:
/// the sceneries, the frame, the verse's colour and size and place
/// were all gone the moment the export finished. This is the rest of
/// it. Stored beside the entry as plain JSON, absent on reels made
/// before it existed, and applied back onto [CreationState] in one
/// call.
///
/// Sceneries are kept by id for the library's own, and by path for a
/// photo or clip the user brought in. A library scenery that is no
/// longer on the device is fetched again on the way back in; a user
/// file that has gone is dropped, and the reel opens on what is left.
class ReelRecipe {
  final String reciterId;
  final int surah;
  final int startAyah;
  final int endAyah;

  /// One entry per scenery, in order: a catalog id, or `image:<path>`
  /// / `video:<path>` for the user's own.
  final List<String> scenes;
  final List<int> sceneWeights;
  final bool multiScene;
  final ScenePacing pacing;
  final SceneTransition transition;
  final ReelLayout layout;
  final bool roundedCorners;
  final LetterboxBackdrop backdrop;
  final int backdropArgb;
  final TextPreset preset;
  final int textArgb;
  final int accentArgb;

  /// The luminous inks, when the verse or the accent was in one. The
  /// two colours above hold their bases either way, so a build that
  /// does not know an ink still opens the reel in a colour near it.
  final VerseInk verseInk;
  final VerseInk accentInk;
  final double textScale;
  final double overlayAlign;
  final bool wordHighlight;

  /// The three faces: the verse's, and the translation's on either
  /// script. Both of the latter travel, not just the one this reel
  /// happened to print, so reopening a reel and switching the edition
  /// lands on what the user actually chose for that script.
  final VerseFace verseFace;
  final TranslationFace latinFace;
  final TranslationFace arabicScriptFace;

  /// What the picture was graded and finished with.
  final ReelEffects effects;

  /// Who the reel was made for. Stored as the intention and the name
  /// rather than as the finished sentence, so a reel dedicated in
  /// English and reopened in Arabic prints an Arabic dedication.
  final Dedication dedication;

  /// Where the dedication line was dragged to, as fractions of the
  /// frame; null for its place at the foot.
  final Offset? dedicationAt;

  /// Where the reel was cut, in milliseconds from the start of the
  /// selection; null for the whole of it.
  final int? trimMs;

  /// How the reel showed its long verses (see `VerseLines`), what its
  /// verse did as it was recited, and whether — and where — it carried
  /// the surah's name. Absent on every reel made before them, which
  /// showed each verse whole, still, and untitled.
  final int verseLines;
  final VerseMotion motion;
  final bool surahTitle;
  final Offset? surahTitleAt;

  const ReelRecipe({
    required this.reciterId,
    required this.surah,
    required this.startAyah,
    required this.endAyah,
    required this.scenes,
    required this.sceneWeights,
    required this.multiScene,
    required this.pacing,
    required this.transition,
    required this.layout,
    required this.roundedCorners,
    required this.backdrop,
    required this.backdropArgb,
    required this.preset,
    required this.textArgb,
    required this.textScale,
    required this.overlayAlign,
    required this.wordHighlight,
    this.accentArgb = accentOnDark,
    this.verseInk = VerseInk.none,
    this.accentInk = VerseInk.none,
    this.verseFace = VerseFace.uthmani,
    this.latinFace = TranslationFace.inter,
    this.arabicScriptFace = TranslationFace.plex,
    this.effects = ReelEffects.off,
    this.dedication = Dedication.none,
    this.dedicationAt,
    this.trimMs,
    this.verseLines = 0,
    this.motion = VerseMotion.none,
    this.surahTitle = false,
    this.surahTitleAt,
  });

  static const _imagePrefix = 'image:';
  static const _videoPrefix = 'video:';

  static String sceneRef(ReelBackground b) => b.isUserFile
      ? '${b.fileIsImage ? _imagePrefix : _videoPrefix}${b.filePath}'
      : b.id;

  /// Whether [ref] names a file the user brought in, and what kind.
  static bool isFileRef(String ref) =>
      ref.startsWith(_imagePrefix) || ref.startsWith(_videoPrefix);
  static bool isImageRef(String ref) => ref.startsWith(_imagePrefix);
  static String filePathOf(String ref) => ref.startsWith(_imagePrefix)
      ? ref.substring(_imagePrefix.length)
      : ref.substring(_videoPrefix.length);

  /// What the creation state holds right now, plus the preview's own
  /// trim, which lives nowhere else.
  factory ReelRecipe.capture(CreationState s, {int? trimMs}) => ReelRecipe(
        reciterId: s.reciter?.id ?? '',
        surah: s.surah,
        startAyah: s.startAyah,
        endAyah: s.endAyah,
        scenes: [for (final b in s.scenes) sceneRef(b)],
        sceneWeights: s.sceneWeights,
        multiScene: s.multiScene,
        pacing: s.pacing,
        transition: s.transition,
        layout: s.layout,
        roundedCorners: s.roundedCorners,
        backdrop: s.backdrop,
        backdropArgb: s.backdropArgb,
        preset: s.textPreset,
        textArgb: s.textArgb,
        accentArgb: s.accentArgb,
        verseInk: s.verseInk,
        accentInk: s.accentInk,
        verseFace: s.verseFace,
        latinFace: s.latinFace,
        arabicScriptFace: s.arabicScriptFace,
        effects: s.effects,
        dedication: s.dedication,
        dedicationAt: s.dedication.isEmpty ? null : s.dedicationAt,
        textScale: s.textScale,
        overlayAlign: s.overlayAlign,
        wordHighlight: s.wordHighlight,
        trimMs: trimMs,
        verseLines: s.verseLines,
        motion: s.motion,
        surahTitle: s.surahTitle,
        surahTitleAt: s.surahTitle ? s.surahTitleAt : null,
      );

  Map<String, dynamic> toJson() => {
        'reciterId': reciterId,
        'surah': surah,
        'startAyah': startAyah,
        'endAyah': endAyah,
        'scenes': scenes,
        'sceneWeights': sceneWeights,
        'multiScene': multiScene,
        'pacing': pacing.name,
        'transition': transition.name,
        'layout': layout.name,
        'roundedCorners': roundedCorners,
        'backdrop': backdrop.name,
        'backdropArgb': backdropArgb,
        'preset': preset.name,
        'textArgb': textArgb,
        'accentArgb': accentArgb,
        if (!verseInk.isNone) 'verseInk': verseInk.name,
        if (!accentInk.isNone) 'accentInk': accentInk.name,
        'verseFace': verseFace.name,
        'latinFace': latinFace.name,
        'arabicScriptFace': arabicScriptFace.name,
        'effects': effects.toJson(),
        if (dedication.isNotEmpty) 'dedication': dedication.toJson(),
        if (dedication.isNotEmpty && dedicationAt != null)
          'dedicationAt': [dedicationAt!.dx, dedicationAt!.dy],
        'textScale': textScale,
        'overlayAlign': overlayAlign,
        'wordHighlight': wordHighlight,
        'trimMs': trimMs,
        if (verseLines > 0) 'verseLines': verseLines,
        if (!motion.isNone) 'motion': motion.toJson(),
        if (surahTitle) 'surahTitle': true,
        if (surahTitle && surahTitleAt != null)
          'surahTitleAt': [surahTitleAt!.dx, surahTitleAt!.dy],
      };

  /// An `[x, y]` pair of fractions, or null for anything else.
  static Offset? _offset(Object? v) {
    if (v is! List || v.length != 2) return null;
    final x = v[0], y = v[1];
    if (x is! num || y is! num) return null;
    return Offset(x.toDouble().clamp(0.0, 1.0), y.toDouble().clamp(0.0, 1.0));
  }

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  factory ReelRecipe.fromJson(Map<String, dynamic> j) => ReelRecipe(
        reciterId: j['reciterId'] as String? ?? '',
        surah: j['surah'] as int? ?? 1,
        startAyah: j['startAyah'] as int? ?? 1,
        endAyah: j['endAyah'] as int? ?? 1,
        scenes: ((j['scenes'] as List?) ?? const []).cast<String>(),
        sceneWeights: ((j['sceneWeights'] as List?) ?? const []).cast<int>(),
        multiScene: j['multiScene'] as bool? ?? false,
        pacing: _enum(ScenePacing.values, j['pacing'], ScenePacing.perAyah),
        transition: _enum(
            SceneTransition.values, j['transition'], SceneTransition.fade),
        layout: _enum(ReelLayout.values, j['layout'], ReelLayout.fullFrame),
        roundedCorners: j['roundedCorners'] as bool? ?? true,
        backdrop: _enum(
            LetterboxBackdrop.values, j['backdrop'], LetterboxBackdrop.colour),
        backdropArgb: j['backdropArgb'] as int? ?? 0xFF000000,
        preset: _enum(TextPreset.values, j['preset'], TextPreset.classic),
        textArgb: j['textArgb'] as int? ?? 0xFFFFFFFF,
        // Absent on every reel made before the style step existed, and
        // those reels were all typeset in the defaults and graded not
        // at all — which is exactly what these fall back to.
        accentArgb: j['accentArgb'] as int? ?? accentOnDark,
        verseInk: VerseInk.fromName(j['verseInk'] as String?),
        accentInk: VerseInk.fromName(j['accentInk'] as String?),
        verseFace: VerseFace.fromName(j['verseFace'] as String?),
        latinFace: TranslationFace.fromName(j['latinFace'] as String?,
            arabicScript: false),
        arabicScriptFace: TranslationFace.fromName(
            j['arabicScriptFace'] as String?,
            arabicScript: true),
        effects:
            ReelEffects.fromJson(j['effects'] as Map<String, dynamic>?),
        dedication: Dedication.fromJson(
            (j['dedication'] as Map?)?.cast<String, dynamic>()),
        dedicationAt: _offset(j['dedicationAt']),
        textScale: (j['textScale'] as num?)?.toDouble() ?? 1.0,
        overlayAlign: (j['overlayAlign'] as num?)?.toDouble() ?? 0.5,
        wordHighlight: j['wordHighlight'] as bool? ?? true,
        trimMs: j['trimMs'] as int?,
        verseLines: ((j['verseLines'] as num?)?.toInt() ?? 0).clamp(0, 3),
        motion: VerseMotion.fromJson(
            (j['motion'] as Map?)?.cast<String, dynamic>()),
        surahTitle: j['surahTitle'] as bool? ?? false,
        surahTitleAt: _offset(j['surahTitleAt']),
      );

  /// Puts everything but the sceneries back onto [s]. The sceneries
  /// need files, which need I/O, which is the reopener's job — see
  /// `ReelReopener`; it hands the resolved backgrounds to [applyScenes].
  void applyStyling(CreationState s, Reciter reciter) {
    s
      ..startNewReel()
      ..selectReciter(reciter)
      ..selectSurah(surah)
      ..selectRange(startAyah, endAyah)
      ..setLayout(layout)
      ..setRoundedCorners(roundedCorners)
      ..setBackdrop(backdrop)
      ..setTextPreset(preset)
      ..setTextScale(textScale)
      ..setOverlayAlign(overlayAlign)
      ..setWordHighlight(wordHighlight)
      ..setPacing(pacing)
      ..setTransition(transition)
      ..setVerseFace(verseFace)
      ..setTranslationFace(latinFace)
      ..setTranslationFace(arabicScriptFace)
      ..setEffects(effects)
      ..setDedication(dedication)
      ..setDedicationAt(dedicationAt)
      ..setVerseLines(verseLines)
      ..setMotion(motion)
      ..setSurahTitle(surahTitle)
      ..setSurahTitleAt(surahTitleAt);
    if (backdrop == LetterboxBackdrop.colour) s.setBackdropColor(backdropArgb);
    // After the backdrop: setting the backdrop re-derives a default
    // ink and a default accent, and the recipe's own colours have to
    // be the last word.
    s.restoreColours(textArgb, accentArgb);
    // After the flat colours, which take any ink off.
    s
      ..setVerseInk(verseInk)
      ..setAccentInk(accentInk);
  }

  /// Seats the resolved sceneries, in the recipe's order, with their
  /// weights. [from] is where each one stood in [scenes]: one that
  /// couldn't be had is skipped, and the weights after it must not
  /// slide onto its neighbours.
  void applyScenes(CreationState s, List<ReelBackground> resolved,
      {List<int>? from}) {
    if (resolved.isEmpty) return;
    s.selectBackground(resolved.first);
    if (resolved.length > 1) {
      s.setMultiScene(true);
      for (final b in resolved.skip(1)) {
        s.toggleScene(b, limit: resolved.length);
      }
    } else if (multiScene) {
      s.setMultiScene(true);
    }
    for (var i = 0; i < resolved.length; i++) {
      final at = from == null ? i : from[i];
      if (at < sceneWeights.length) s.setSceneWeight(i, sceneWeights[at]);
    }
  }
}
