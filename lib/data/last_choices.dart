import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../state/creation_state.dart';
import 'debug_log.dart';
import 'fatiha_data.dart' show reciters;
import 'models.dart';
import 'quran_repository.dart';
import 'reel_recipe.dart';
import 'scene_catalog.dart';
import 'verse_motion.dart';
import 'whole_file.dart';

/// The choices the last reel was made with, kept from one launch to the
/// next.
///
/// [CreationState] lives as long as the process, so within one run of
/// the app the voice, the surah and verses, the scenery and every
/// choice of taste (the faces, the colours, the grade, the motion)
/// already carried from one reel to the next. Closing the app dropped
/// all of it: the next launch opened the verse picker on Al-Fatiha,
/// with no voice chosen and the style in the app's own defaults. This
/// writes those choices down as they change and puts them back at
/// launch, so a reel begun tomorrow starts where today's ended.
///
/// What is kept is what [CreationState.startNewReel] keeps. What that
/// clears for each new reel — the dedication, how several sceneries are
/// paced and blended — is not written at all, and what Settings decides
/// for every reel (the lines, the surah's name) stays Settings'.
abstract final class LastChoices {
  static Future<void>? _restoring;
  static Timer? _pending;
  static String? _written;
  static CreationState? _watched;

  /// How long the choices have to stay put before they are written: a
  /// drag of the verse or a slide of the text size changes them many
  /// times a second, and only where they end up matters.
  static const settle = Duration(milliseconds: 700);

  /// Where the file is kept; a test points this at its own folder.
  @visibleForTesting
  static Directory? debugDir;

  /// Puts the last choices back onto [s] — once, however often it is
  /// asked — and from then on writes them down whenever they change.
  static Future<void> init(CreationState s) => _restoring ??= _start(s);

  static Future<void> _start(CreationState s) async {
    try {
      final f = await _file();
      if (f.existsSync()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) {
          final r = ReelRecipe.fromJson(j);
          apply(r, s, band: (j['lc'] as int? ?? 1) >= version);
          _written = jsonEncode(j);
          unawaited(_seatScenery(r, s));
        }
      }
    } catch (e) {
      rlog('last choices: not restored ($e)');
    }
    _watched = s..addListener(_changed);
  }

  /// [r]'s lasting choices onto [s], in the order [ReelRecipe] puts a
  /// reopened reel's back: the frame and the backdrop before the two
  /// colours, since a backdrop re-derives the colours nobody chose, and
  /// the flat colours before the inks, since a flat colour takes an ink
  /// off.
  /// What [snapshot] writes as `lc`. 2 since the wide card's band
  /// started on the blur (2026-10-21): a file written before that holds
  /// the old default (black) whether or not anybody chose it, so its
  /// band is not put back.
  static const version = 2;

  @visibleForTesting
  static void apply(ReelRecipe r, CreationState s, {bool band = true}) {
    for (final v in reciters) {
      if (v.id == r.reciterId) {
        s.selectReciter(v);
        break;
      }
    }
    final surah = r.surah.clamp(1, 114);
    final count = QuranRepository.surahInfo(surah).ayahCount;
    final start = r.startAyah.clamp(1, count);
    s
      ..selectSurah(surah)
      ..selectRange(start, r.endAyah.clamp(start, count))
      ..setLayout(r.layout)
      ..setRoundedCorners(r.roundedCorners);
    if (band) {
      s.setBackdrop(r.backdrop);
      if (r.backdrop == LetterboxBackdrop.colour) {
        s.setBackdropColor(r.backdropArgb);
      } else if (r.backdrop == LetterboxBackdrop.glow) {
        s.setBandGlow(r.bandGlow);
      }
    }
    s
      ..setTextPreset(r.preset)
      ..setTextScale(r.textScale)
      ..setOverlayAlign(r.overlayAlign)
      ..setWordHighlight(r.wordHighlight)
      ..setVerseFace(r.verseFace)
      ..setTranslationFace(r.latinFace)
      ..setTranslationFace(r.arabicScriptFace)
      ..setEffects(r.effects)
      ..setMotion(_offered(r.motion))
      ..setSurahTitleLook(r.surahTitleLook)
      ..restoreColours(r.textArgb, r.accentArgb)
      ..setVerseInk(r.verseInk)
      ..setAccentInk(r.accentInk);
  }

  /// [m], unless it is one of the two looks the motion panel no longer
  /// offers — a plain fade ("Breathe") and a rise ("Rise"), which users
  /// could not see do anything — which a new reel starts on the light
  /// instead. A reel saved with one still plays it; only the next reel
  /// is not made with it.
  static VerseMotion _offered(VerseMotion m) =>
      m == const VerseMotion(arrival: VerseArrival.fade) ||
              m == const VerseMotion(arrival: VerseArrival.rise)
          ? VerseMotion.standard
          : m;

  /// The last scenery back in place, when it is still on the device and
  /// nothing has been picked since launch: a library scene that has
  /// been cleared from the cache is not fetched for this, and a photo
  /// that has been deleted is let go.
  /// The library scenery the last reel was made on, whether or not its
  /// file is still on the phone: what Customize's reel shows (its poster
  /// is all that needs) when the reel itself has no scenery yet because
  /// the file was cleared from the cache.
  static Scene? lastScene;

  static Future<void> _seatScenery(ReelRecipe r, CreationState s) async {
    if (r.scenes.isEmpty) return;
    final ref = r.scenes.first;
    ReelBackground? b;
    if (ReelRecipe.isFileRef(ref)) {
      final path = ReelRecipe.filePathOf(ref);
      if (File(path).existsSync()) {
        b = ReelBackground.deviceFile(
          id: 'custom_${path.hashCode.toRadixString(16)}',
          name: ReelRecipe.isImageRef(ref) ? 'Your photo' : 'Your video',
          filePath: path,
          fileIsImage: ReelRecipe.isImageRef(ref),
        );
      }
    } else {
      await SceneCatalog.load();
      final scene = SceneCatalog.byId(ref);
      if (scene != null) {
        lastScene = scene;
        if (scene.bundled) {
          b = SceneCatalog.background(scene);
        } else {
          final file = await SceneCatalog.cachedFile(scene);
          if (file != null) b = SceneCatalog.background(scene, file: file);
        }
      }
    }
    if (b == null || s.background != null) return;
    s.selectBackground(b);
  }

  /// What is written: a [ReelRecipe] of the lasting choices alone.
  @visibleForTesting
  static Map<String, dynamic> snapshot(CreationState s) {
    final j = ReelRecipe.capture(s).toJson();
    // A reel's own shape, cleared for every new one, and what Settings
    // decides for every reel: none of it is a last choice.
    for (final k in const [
      'dedication',
      'dedicationAt',
      'trimMs',
      'pacing',
      'transition',
      'multiScene',
      'sceneWeights',
      'verseLines',
      'surahTitle',
      'surahTitleAt',
      'surahTitleScale',
    ]) {
      j.remove(k);
    }
    final scenes = (j['scenes'] as List?) ?? const [];
    j['scenes'] = scenes.isEmpty ? const <String>[] : [scenes.first];
    // An upload's stand-in voice can't be found again by its id.
    if (s.reciter?.isUserAudio ?? false) j['reciterId'] = '';
    j['lc'] = version;
    return j;
  }

  static void _changed() {
    _pending?.cancel();
    _pending = Timer(settle, () => unawaited(flush()));
  }

  /// Writes the choices now, if they changed since they were last
  /// written. The app calls this as it goes to the background, so a
  /// change made in the last moment before it was closed is kept.
  static Future<void> flush() async {
    _pending?.cancel();
    _pending = null;
    final s = _watched;
    if (s == null) return;
    final text = jsonEncode(snapshot(s));
    if (text == _written) return;
    _written = text;
    try {
      await writeWhole(await _file(), text);
    } catch (e) {
      rlog('last choices: not written ($e)');
    }
  }

  static Future<File> _file() async {
    final dir = debugDir ?? await getApplicationSupportDirectory();
    return File('${dir.path}/last_choices.json');
  }

  /// Forgets everything, as a fresh process would.
  @visibleForTesting
  static void debugReset() {
    _pending?.cancel();
    _pending = null;
    _watched?.removeListener(_changed);
    _watched = null;
    _restoring = null;
    _written = null;
  }
}
