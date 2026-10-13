import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import '../data/dedication.dart';
import '../data/models.dart';
import '../data/reel_effects.dart';
import '../data/settings_service.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';

/// Designed looks for the verse card. Each is a coherent set of
/// choices; the raw slider/swatches still fine-tune on top.
enum TextPreset {
  classic, // divider, standard shadows — the original look
  glow, // soft colored glow behind the text, no divider
  minimal, // smaller, clean, no divider
}

/// How the background occupies the 9:16 frame.
enum ReelLayout {
  /// The scenery fills the whole frame, cropped to 9:16. The original.
  fullFrame,

  /// The scenery keeps its own shape as a card floating in the frame,
  /// top and bottom cropped away — which is what buys the verse a band
  /// of its own to sit in instead of lying over the picture.
  letterbox,
}

/// How several sceneries divide one reel.
enum ScenePacing {
  /// Cuts land on ayah boundaries: with one scene per ayah that is a
  /// scene per verse, with fewer each scene carries a run of verses.
  /// The default, because the recitation already has joints and a cut
  /// on one reads as intended where a cut mid-word reads as a fault.
  perAyah,

  /// Equal slices of the reel, wherever they fall.
  even,
}

/// How one scene gives way to the next.
enum SceneTransition {
  /// Straight cut on the boundary.
  cut,

  /// Crossfade across the boundary. [sceneFadeMs] long in both the
  /// preview and the export.
  fade,
}

/// Length of a [SceneTransition.fade], in milliseconds. Long enough to
/// read as deliberate, short enough that a scene is still mostly
/// itself.
const sceneFadeMs = 500;

/// What fills the band above and below a letterbox card.
enum LetterboxBackdrop {
  /// A flat colour — black by default, which is what the format looks
  /// like in the wild.
  colour,

  /// The scenery again, filled to the frame and blurred, so the card
  /// sits in its own light rather than in a void.
  blur,
}

/// Backdrop colours offered for [LetterboxBackdrop.colour]. Black
/// leads because it is the default and the look people recognise; the
/// rest are chosen to sit under the verse without fighting it.
const letterboxBackdropSwatches = [
  0xFF000000, // black
  0xFFFFFFFF, // white
  0xFF14181D, // charcoal — the app's own surface
  0xFFF3EADA, // ivory
  0xFF0E2A22, // deep green
  0xFF101A2E, // night blue
];

/// Every colour the verse and the accent can be set to.
///
/// Four rows of six, and the order is the point: it runs light
/// neutrals, dark neutrals, warm, cool, so a user scanning for "a
/// warmer gold" finds it next to the gold rather than four rows away.
///
/// Chosen to stay legible on the two grounds a verse ever sits on —
/// scenery under the scrim, which is dark, and a letterbox band, which
/// may be either. That is why the dark neutrals are in here at all:
/// white ink on ivory is the one combination the app goes out of its
/// way to prevent, and the way out of it is a colour, not a warning.
///
/// Every one of them is named for a screen reader; see
/// [L10n.colourName], which fails a test if one is not.
const versePalette = <int>[
  // light neutrals
  0xFFFFFFFF, 0xFFF3EADA, 0xFFEADFC8, 0xFFD7DEE6, 0xFFA9B2BD, 0xFF5C6673,
  // dark neutrals, then the two golds
  0xFF15181C, 0xFF000000, 0xFFEEC96B, 0xFFD4A947, 0xFFE8A33D, 0xFFD07C4A,
  // warm
  0xFFC96A5A, 0xFFF5A8B8, 0xFFF3C9C2, 0xFFB98AB5, 0xFFBFD4B4, 0xFF5FBF9B,
  // cool
  0xFF9FE8C9, 0xFF5BC0C6, 0xFF9CC7F5, 0xFF6FA8E8, 0xFFA9A7F0, 0xFFC9B8F5,
];

/// The two inks the app falls back to when nobody has chosen a colour.
const inkOnDark = 0xFFFFFFFF;
const inkOnLight = 0xFF15181C;

/// And the two accents — the rule under the verse and the lit word.
/// Bright gold reads on darkened scenery; on ivory it barely reads at
/// all, so a pale band takes the deeper one. Same literals as
/// [AppColors.goldBright] and [AppColors.gold], kept here because this
/// file must not depend on the widget layer.
const accentOnDark = 0xFFEEC96B;
const accentOnLight = 0xFFD4A947;

/// True when [argb] is pale enough that white would disappear into it —
/// the white and ivory backdrop swatches, and nothing else.
bool isLightSurface(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  // Rec. 709 relative luminance, close enough for a light/dark call.
  final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  return lum > 0.55;
}

/// Verse ink that stays legible on [backgroundArgb]. Used when the
/// letterbox backdrop changes underneath a verse colour that would
/// disappear into it — white text on a white band is not a choice
/// anyone means to make.
int legibleInkOn(int backgroundArgb) =>
    isLightSurface(backgroundArgb) ? inkOnLight : inkOnDark;

/// True when the verse sits on a pale band rather than on scenery.
///
/// The watermark asked this too until it moved onto the letterbox card;
/// there is no band under it any more, in either format.
///
/// Only the letterbox format puts them on a flat colour at all —
/// full frame always darkens the picture with the scrim, and a blurred
/// backdrop is darkened by the same amount the exporter's `eq` applies.
/// So this is the one case where the app's white-ink-with-a-black-
/// shadow defaults are exactly backwards, and everything that draws on
/// that band asks this before it picks a colour.
///
/// A free function rather than a getter on the state, because the
/// exporter works from the styling it was handed, not from whatever the
/// singleton holds by the time an encode starts.
bool isLightGround({
  required ReelLayout layout,
  required LetterboxBackdrop backdrop,
  required int backdropArgb,
}) =>
    layout == ReelLayout.letterbox &&
    backdrop == LetterboxBackdrop.colour &&
    isLightSurface(backdropArgb);

/// Which reel of which series the wizard is making, when it is making
/// one. Set by the series screen on the way into the wizard and read
/// by the preview when the export lands, so the series can tick the
/// reel off. Cleared by [CreationState.startNewReel], which every
/// other way into the wizard calls.
@immutable
class SeriesTarget {
  final String seriesId;
  final int reelIndex;
  const SeriesTarget(this.seriesId, this.reelIndex);
}

/// Single source of truth for the reel being created.
/// Kept deliberately tiny: reciter + background is the entire decision
/// space of the MVP.
class CreationState extends ChangeNotifier {
  Reciter? _reciter;
  ReelBackground? _background;

  SeriesTarget? _seriesTarget;

  /// The series reel this wizard run belongs to, if any.
  SeriesTarget? get seriesTarget => _seriesTarget;

  void setSeriesTarget(SeriesTarget? t) {
    _seriesTarget = t;
    notifyListeners();
  }

  /// Whether [_background] is something somebody actually picked, as
  /// opposed to the stand-in the scenery screen seeds so the renderer
  /// always has a picture. Both leave a non-null background, so the
  /// background alone cannot tell them apart — and the picker needs to,
  /// because it opens on the tab holding the chosen scenery.
  bool _backgroundChosen = false;
  final List<ReelBackground> _scenes = [];

  /// One per scene, always the same length as [_scenes]. A heavier
  /// scene takes a bigger share of what it is competing for — see
  /// [sceneWeights].
  final List<int> _sceneWeights = [];
  bool _multiScene = false;
  ScenePacing _pacing = ScenePacing.perAyah;
  SceneTransition _transition = SceneTransition.fade;
  int _surah = 1;
  int _startAyah = 1;
  int _endAyah = 7;
  double _overlayAlign = 0.5;
  int _textArgb = 0xFFFFFFFF;
  int _accentArgb = 0xFFEEC96B;
  VerseInk _verseInk = VerseInk.none;
  VerseInk _accentInk = VerseInk.none;

  /// Whether the two colours above were *chosen*, rather than being
  /// the ones the app started them on.
  ///
  /// [_ensureLegibleInk] used to answer this by asking whether the
  /// colour was one of the four default literals — which worked for
  /// exactly as long as those four were not offered anywhere. The
  /// style step's palette offers all of them: white, near-black and
  /// both golds are ordinary swatches now, so a user who deliberately
  /// picked charcoal had it silently rewritten to white the next time
  /// they touched the frame format.
  bool _inkChosen = false;
  bool _accentChosen = false;
  double _textScale = 1.0;
  TextPreset _textPreset = TextPreset.classic;
  VerseFace _verseFace = VerseFace.uthmani;
  TranslationFace _latinFace = TranslationFace.inter;
  TranslationFace _arabicScriptFace = TranslationFace.plex;
  ReelEffects _effects = ReelEffects.off;

  /// Who this reel is being made for, if anybody. Kept on the reel
  /// rather than in Settings: a dedication belongs to one reel, and
  /// the next one is for somebody else or for nobody.
  Dedication _dedication = Dedication.none;

  /// Where the dedication line was dragged to; see [dedicationAt].
  Offset? _dedicationAt;
  bool _wordHighlight = true;
  ReelLayout _layout = ReelLayout.fullFrame;
  bool _roundedCorners = true;
  LetterboxBackdrop _backdrop = LetterboxBackdrop.colour;
  int _backdropArgb = 0xFF000000;

  Reciter? get reciter => _reciter;

  /// True when the reel is being built on a recording the user
  /// uploaded rather than on one of the app's voices. The wizard grows
  /// a step when it is — see [WizardSteps].
  bool get usesUserAudio => _reciter?.isUserAudio ?? false;

  /// The reel's scenery — the first scene when there are several.
  /// Everything that only ever needed one picture (the poster, the
  /// letterbox card's shape, the picker's opening state) still reads
  /// this and is unaffected by the rest.
  ReelBackground? get background => _background;

  /// True once a scenery has been picked — by the user, or by a
  /// featured template on their behalf. False while the only thing in
  /// [background] is the stand-in seeded by the picker itself.
  bool get backgroundChosen => _backgroundChosen;

  /// Every scenery this reel runs through, in the order they were
  /// picked. One entry unless the picker is in multi-scene mode, and
  /// empty only while the picker is open with everything unticked —
  /// which is the one state its own button is shut in.
  List<ReelBackground> get scenes => List.unmodifiable(_scenes);

  /// Whether the picker is choosing several sceneries. Stays true while
  /// only one is picked — that is the state of having just turned it
  /// on, not a reason to hide the controls it opened.
  bool get multiScene => _multiScene;

  /// How much room each scene takes, relative to the others: 1 is an
  /// even hand, 2 is twice its neighbours' share. Always as long as
  /// [scenes].
  List<int> get sceneWeights => List.unmodifiable(_sceneWeights);

  /// How several sceneries divide the reel. See [ScenePacing].
  ScenePacing get pacing => _pacing;

  /// How one scene gives way to the next. See [SceneTransition].
  SceneTransition get transition => _transition;

  /// Whether this reel actually runs through more than one scenery —
  /// which is what every consumer downstream of the picker cares
  /// about, rather than what mode the picker is in.
  bool get hasMultipleScenes => _scenes.length > 1;

  int get surah => _surah;

  /// 1-based, inclusive.
  int get startAyah => _startAyah;
  int get endAyah => _endAyah;

  /// Vertical position of the verse overlay: 0 = top, 0.5 = center,
  /// 1 = bottom. Shared by live preview and exporter.
  double get overlayAlign => _overlayAlign;

  /// Verse text color as ARGB. Kept as an int so the render cache key
  /// and FFmpeg pipeline never depend on Color identity.
  int get textArgb => _textArgb;

  /// Multiplier on the base verse text size, 0.7–1.5.
  double get textScale => _textScale;

  /// The reel's second colour: the rule under the verse, and the word
  /// lit as it is recited. Gold until somebody says otherwise.
  int get accentArgb => _accentArgb;

  /// The luminous ink the verse is drawn in, or [VerseInk.none] for the
  /// flat [textArgb]. While one is set, [textArgb] holds its
  /// [VerseInk.base].
  VerseInk get verseInk => _verseInk;

  /// The same for the accent, with [accentArgb] holding its base.
  VerseInk get accentInk => _accentInk;

  /// The face the Arabic is set in.
  VerseFace get verseFace => _verseFace;

  /// The face the translation is set in, kept per script rather than
  /// per reel: somebody reading English in Cormorant still wants
  /// Nastaliq the day they switch the edition to Urdu, and Cormorant
  /// back when they switch it out. Which of the two is in force is
  /// decided by the edition, not by this object — see [typography].
  TranslationFace get latinFace => _latinFace;
  TranslationFace get arabicScriptFace => _arabicScriptFace;

  /// The pair of faces this reel is typeset in, for the edition
  /// Settings currently names.
  ReelTypography get typography => ReelTypography.of(
        verse: _verseFace,
        latin: _latinFace,
        arabicScript: _arabicScriptFace,
        edition: SettingsService.state.value.translation,
      );

  /// What the picture is graded and finished with. [ReelEffects.off]
  /// until somebody turns something on, and every path downstream
  /// skips the whole feature while it is.
  ReelEffects get effects => _effects;
  Dedication get dedication => _dedication;

  /// Where the dedication line's centre sits on the frame, as fractions
  /// of its width and height. Null is where it starts, at the foot of
  /// the frame. See [ReelDedication].
  Offset? get dedicationAt => _dedicationAt;

  /// A flat verse colour, which takes the verse out of any ink it was
  /// in.
  void setTextColor(int argb) {
    _textArgb = argb;
    _verseInk = VerseInk.none;
    _inkChosen = true;
    notifyListeners();
  }

  void setAccentColor(int argb) {
    _accentArgb = argb;
    _accentInk = VerseInk.none;
    _accentChosen = true;
    notifyListeners();
  }

  /// Puts a saved reel's two colours back, after its frame and
  /// backdrop.
  ///
  /// The recipe keeps the colours but not whether anyone chose them,
  /// and [setTextColor] would call them chosen: reopening any reel —
  /// even one in the white it started in — then stopped the ink
  /// following the ground for the rest of the session, and the next
  /// reel on an ivory band came out white on near-white. So a colour
  /// that is exactly what this ground gives an unchosen one is taken
  /// as unchosen; anything else was a decision and stands.
  void restoreColours(int text, int accent) {
    _textArgb = text;
    _verseInk = VerseInk.none;
    _inkChosen = text != (onLightGround ? inkOnLight : inkOnDark);
    _accentArgb = accent;
    _accentInk = VerseInk.none;
    _accentChosen = accent != (onLightGround ? accentOnLight : accentOnDark);
    notifyListeners();
  }

  /// Both colours back to what the ground gives them, and free to
  /// follow it again — the reset, which is not a choice of white.
  void resetColours() {
    _verseInk = VerseInk.none;
    _accentInk = VerseInk.none;
    _inkChosen = false;
    _accentChosen = false;
    _ensureLegibleInk();
    notifyListeners();
  }

  /// Draws the verse in [ink], or back in its flat colour for
  /// [VerseInk.none]. An ink is a choice of colour like any swatch, so
  /// the flat colour becomes its base and the ground no longer rewrites
  /// it — see [_ensureLegibleInk].
  void setVerseInk(VerseInk ink) {
    if (_verseInk == ink) return;
    _verseInk = ink;
    if (!ink.isNone) {
      _textArgb = ink.base;
      _inkChosen = true;
    }
    notifyListeners();
  }

  void setAccentInk(VerseInk ink) {
    if (_accentInk == ink) return;
    _accentInk = ink;
    if (!ink.isNone) {
      _accentArgb = ink.base;
      _accentChosen = true;
    }
    notifyListeners();
  }

  void setVerseFace(VerseFace f) {
    if (_verseFace == f) return;
    _verseFace = f;
    notifyListeners();
  }

  /// Seats [f] on whichever of the two script slots it belongs to, so
  /// the other one is left exactly as it was.
  void setTranslationFace(TranslationFace f) {
    if (f.arabicScript) {
      if (_arabicScriptFace == f) return;
      _arabicScriptFace = f;
    } else {
      if (_latinFace == f) return;
      _latinFace = f;
    }
    notifyListeners();
  }

  void setDedication(Dedication d) {
    if (_dedication == d) return;
    _dedication = d;
    notifyListeners();
  }

  void setDedicationAt(Offset? at) {
    if (_dedicationAt == at) return;
    _dedicationAt = at;
    notifyListeners();
  }

  void setEffects(ReelEffects e) {
    if (_effects == e) return;
    _effects = e;
    notifyListeners();
  }

  void setTextScale(double v) {
    _textScale = v.clamp(0.7, 1.5);
    notifyListeners();
  }

  /// Designed look applied to the verse card.
  TextPreset get textPreset => _textPreset;

  /// Whether the recited word lights up (when timing data exists for
  /// the chosen voice).
  bool get wordHighlight => _wordHighlight;

  void setTextPreset(TextPreset p) {
    _textPreset = p;
    notifyListeners();
  }

  void setWordHighlight(bool on) {
    _wordHighlight = on;
    notifyListeners();
  }

  /// How the scenery fills the frame. See [ReelLayout].
  ReelLayout get layout => _layout;

  /// Whether a letterbox card's corners are rounded. Ignored in
  /// [ReelLayout.fullFrame].
  bool get roundedCorners => _roundedCorners;

  /// What fills the band above and below a letterbox card.
  LetterboxBackdrop get backdrop => _backdrop;

  /// The flat backdrop colour, when [backdrop] is
  /// [LetterboxBackdrop.colour].
  int get backdropArgb => _backdropArgb;

  /// Whether the verse and watermark currently sit on a pale band.
  /// See [isLightGround].
  bool get onLightGround => isLightGround(
        layout: _layout,
        backdrop: _backdrop,
        backdropArgb: _backdropArgb,
      );

  void setLayout(ReelLayout l) {
    if (_layout == l) return;
    _layout = l;
    // The verse's ground changes with the frame: entering letterbox
    // puts it on the backdrop, leaving it puts it back on the darkened
    // picture. Either way the ink has to answer to what it now sits on.
    _ensureLegibleInk();
    notifyListeners();
  }

  void setRoundedCorners(bool on) {
    _roundedCorners = on;
    notifyListeners();
  }

  void setBackdrop(LetterboxBackdrop b) {
    _backdrop = b;
    _ensureLegibleInk();
    notifyListeners();
  }

  void setBackdropColor(int argb) {
    _backdropArgb = argb;
    _backdrop = LetterboxBackdrop.colour;
    _ensureLegibleInk();
    notifyListeners();
  }

  /// Keeps the verse readable when the ground underneath it changes.
  ///
  /// Only touches a colour nobody has chosen: white is where the ink
  /// starts, so it may flip to dark on a light backdrop and back, and
  /// the accent does the same between its two golds — the swap the
  /// card used to make for itself before the colour was something a
  /// user could set. A verse somebody set to gold, or to rose, or to
  /// the very same white off the palette, is a decision and stands.
  ///
  /// Which is why this asks [_inkChosen] rather than asking whether
  /// the colour happens to be one of the default literals: those four
  /// are ordinary swatches in the style step's palette, so the literal
  /// stopped being able to tell a default from a decision.
  void _ensureLegibleInk() {
    if (!_accentChosen) {
      _accentArgb = onLightGround ? accentOnLight : accentOnDark;
    }
    if (!_inkChosen) {
      _textArgb = onLightGround ? inkOnLight : inkOnDark;
    }
  }

  void selectSurah(int n) {
    _surah = n;
    notifyListeners();
  }

  void setOverlayAlign(double v) {
    _overlayAlign = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  void selectReciter(Reciter r) {
    _reciter = r;
    notifyListeners();
  }

  /// Replaces the whole selection with one scenery. The single-scene
  /// path, and what leaving multi-scene mode collapses to.
  void selectBackground(ReelBackground b) {
    _background = b;
    _backgroundChosen = true;
    _scenes
      ..clear()
      ..add(b);
    _sceneWeights
      ..clear()
      ..add(1);
    notifyListeners();
  }

  /// Re-seats [_background] on the run's first scene after the run
  /// itself has changed. A run emptied of every scenery has no chosen
  /// one left to speak of, so [backgroundChosen] goes with it — leaving
  /// it set would let the next stand-in inherit a choice nobody made.
  void _reseatBackground() {
    _background = _scenes.isEmpty ? null : _scenes.first;
    if (_scenes.isEmpty) _backgroundChosen = false;
  }

  /// Puts a scenery in place without it counting as a choice.
  ///
  /// The scenery screen needs a background from the moment it opens —
  /// the preview and the renderer have nowhere to go without one — so
  /// it seeds the first bundled scenery when nobody has picked yet.
  /// That seed used to go through [selectBackground], which made it
  /// indistinguishable from a real pick from the next visit onward:
  /// the picker would find a background, take it for a choice, and open
  /// on its tab — Abstract, because that is what the bundled list
  /// starts with. Every user who had opened the screen once and picked
  /// nothing landed there forever after.
  ///
  /// A seed over an existing choice leaves [backgroundChosen] alone: it
  /// is the same scenery being re-seated, not a choice being undone.
  void seedBackground(ReelBackground b) {
    _background = b;
    _scenes
      ..clear()
      ..add(b);
    _sceneWeights
      ..clear()
      ..add(1);
    notifyListeners();
  }

  /// Gives one scene more or less room than its neighbours. Weights
  /// are small on purpose: this is a nudge, not a duration field.
  void setSceneWeight(int index, int weight) {
    if (index < 0 || index >= _sceneWeights.length) return;
    final w = weight.clamp(1, 3);
    if (_sceneWeights[index] == w) return;
    _sceneWeights[index] = w;
    notifyListeners();
  }

  /// Adds a scenery to the run, or removes it if it is already in
  /// there. Returns false when the pick was refused because the reel
  /// has no room for another scene — see `ScenePlan.maxScenes`.
  ///
  /// The last one out leaves the run empty, which is a state the picker
  /// is allowed to be in: a tick the user cannot untick reads as a
  /// stuck app. What an empty run cannot do is leave — the screen
  /// holds its own button shut until something is picked.
  bool toggleScene(ReelBackground b, {required int limit}) {
    final at = _scenes.indexWhere((s) => s.id == b.id);
    if (at >= 0) {
      _scenes.removeAt(at);
      _sceneWeights.removeAt(at);
      _reseatBackground();
      notifyListeners();
      return true;
    }
    if (_scenes.length >= limit) return false;
    _scenes.add(b);
    // A scene joins on an even footing; giving it more room is a
    // separate decision, made where the reel can be seen.
    _sceneWeights.add(1);
    _background = _scenes.first;
    _backgroundChosen = true;
    notifyListeners();
    return true;
  }

  /// Drops scenes the reel no longer has verses for.
  ///
  /// The verse range can be shortened after a run was picked, and a
  /// reel that takes three scenes must not be holding six — the picker
  /// would be counting "6 of 3". Called when the picker opens, which
  /// is the first moment either number can have changed.
  void trimScenes(int limit) {
    if (_scenes.length <= limit || limit < 1) return;
    _scenes.removeRange(limit, _scenes.length);
    _sceneWeights.removeRange(limit, _sceneWeights.length);
    _reseatBackground();
    notifyListeners();
  }

  /// Drops every scenery [keep] rejects, leaving the rest of the run in
  /// the order it was picked. Answers how many went.
  ///
  /// Empties to no scenery at all when nothing survives — the same
  /// state [toggleScene] leaves behind when the last tick comes off,
  /// and the same screen holds the door shut until something is
  /// picked.
  int dropScenes(bool Function(ReelBackground b) keep) {
    final before = _scenes.length;
    for (var i = _scenes.length - 1; i >= 0; i--) {
      if (keep(_scenes[i])) continue;
      _scenes.removeAt(i);
      _sceneWeights.removeAt(i);
    }
    if (_scenes.length == before) return 0;
    _reseatBackground();
    notifyListeners();
    return before - _scenes.length;
  }

  /// Turns multi-scene picking on or off. Leaving it collapses the run
  /// back to the scenery the reel opens on, so the reel a user sees
  /// after switching off is the one they saw before switching on.
  void setMultiScene(bool on) {
    if (_multiScene == on) return;
    _multiScene = on;
    if (!on && _scenes.length > 1) {
      final first = _scenes.first;
      _scenes
        ..clear()
        ..add(first);
      _sceneWeights
        ..clear()
        ..add(1);
      _background = first;
    }
    notifyListeners();
  }

  void setPacing(ScenePacing p) {
    if (_pacing == p) return;
    _pacing = p;
    notifyListeners();
  }

  void setTransition(SceneTransition t) {
    if (_transition == t) return;
    _transition = t;
    notifyListeners();
  }

  /// Starts a new reel from the app's own defaults.
  ///
  /// This object lives for as long as the process does, so everything
  /// the last reel was given stays set until something sets it again —
  /// which is right for a *preference* (a verse colour, a text size:
  /// chosen once, meant to stick) and wrong for the shape of one
  /// particular reel. Tapping "Even" once made every reel afterwards
  /// open on Even, with the app's own copy still calling per-verse the
  /// default; the same went for the blend, and for a run of a dozen
  /// sceneries carried into a reel the picker was showing as
  /// single-select.
  ///
  /// So the decisions that describe *this* reel are cleared on the way
  /// in, and the ones that describe the user are not. Called from every
  /// place a new reel begins — including the templates, which then set
  /// their own choices on top.
  ///
  /// Everything the style screen settles — the faces, the two colours,
  /// the grade — is on the preference side of that line, for the same
  /// reason the verse colour and size always were: somebody who typeset
  /// one reel in Cormorant over a golden-hour grade did not mean it for
  /// that reel alone.
  void startNewReel() {
    _seriesTarget = null;
    // Where the scenery screen was left belongs to the reel it was left
    // in; a new one opens the screen fresh.
    sceneryTab = null;
    sceneryWide = null;
    sceneryOffset = 0;
    // A dedication is the one styling choice that must NOT carry over.
    // Everything else here is taste and is worth keeping between
    // reels; this is a person's name, and the next reel silently
    // carrying it would put a stranger's grandmother on somebody
    // else's verse.
    _dedication = Dedication.none;
    // And where it was put goes with it: that was a place for one line
    // on one reel.
    _dedicationAt = null;
    _multiScene = false;
    _pacing = ScenePacing.perAyah;
    _transition = SceneTransition.fade;
    // A run collapses to the scenery it opened on rather than emptying:
    // the scenery screen re-seeds from this, and a null background is a
    // state the wizard only ever passes through.
    if (_scenes.length > 1) {
      final first = _scenes.first;
      _scenes
        ..clear()
        ..add(first);
      _sceneWeights
        ..clear()
        ..add(1);
      _background = first;
    }
    notifyListeners();
  }

  /// Where the scenery screen was when it was last left, in this reel:
  /// its tab, its shape of scenery, and how far down the grid. Going
  /// back to the verses and coming forward again builds the screen
  /// anew, and opening it somewhere else read as a run thrown away —
  /// the tiles were still chosen, just not where the user had left
  /// them. Not saved anywhere: the next reel starts fresh.
  String? sceneryTab;
  bool? sceneryWide;
  double sceneryOffset = 0;

  void selectRange(int start, int end) {
    assert(start >= 1 && end >= start);
    _startAyah = start;
    _endAyah = end;
    notifyListeners();
  }
}

/// App-wide instance; an MVP does not need a DI framework.
final creationState = CreationState();

/// Where each screen of the creation flow sits in the run of dots.
///
/// The flow is five screens — voice, verses, scenery, style, reel —
/// until the voice is a recording the user brought in. Then there is a
/// sixth, between the verses and the scenery: an uploaded file has no
/// joints to read, so where its verses fall has to be settled before
/// anything can be drawn over it.
///
/// The numbers live here rather than in the screens because they move
/// together: a step inserted in the middle renumbers every screen after
/// it, and five literals scattered across five files is exactly how one
/// of them gets left behind.
abstract final class WizardSteps {
  /// Whether this reel needs the timing step at all.
  static bool get hasAlign => creationState.usesUserAudio;

  static int get total => hasAlign ? 6 : 5;

  static const voice = 1;
  static const verses = 2;

  /// Only reachable when [hasAlign].
  static const align = 3;

  static int get scenery => hasAlign ? 4 : 3;

  /// Typography, colour and the grade — everything about how the reel
  /// looks that is not what is in the picture. It sits after the
  /// scenery because half of it answers to the scenery (a verse colour
  /// is chosen against the ground it will sit on) and before the reel
  /// because the reel is the thing it describes.
  static int get style => hasAlign ? 5 : 4;

  static int get reel => hasAlign ? 6 : 5;
}
