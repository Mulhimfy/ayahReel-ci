import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

// Prefixed: the plugin exports an `AppSettings` that clashes with the
// app's own settings model elsewhere; keep the naming consistent.
import 'package:app_settings/app_settings.dart' as os_settings;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../data/audio_position.dart';
import '../data/band_glow.dart';
import '../data/breath_pace.dart';
import '../data/debug_log.dart';
import '../data/dedication.dart';
import '../data/export_budget.dart';
import '../data/feedback_service.dart';
import '../data/gallery_saver.dart';
import '../data/instagram_share.dart';
import '../data/media_aspect.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/recitation_service.dart';
import '../data/trouble.dart';
import '../data/reel_effects.dart';
import '../data/reel_library.dart';
import '../data/reel_limits.dart';
import '../data/reel_recipe.dart';
import '../data/reminder_service.dart';
import '../data/review_prompt.dart';
import '../data/rewards_service.dart';
import '../data/platform_share.dart';
import '../data/settings_service.dart';
import '../data/share_origin.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../data/verse_lines.dart';
import '../data/verse_motion.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
import '../data/whatsapp_share.dart';
import '../data/word_align_service.dart';
import '../l10n/l10n.dart';
import '../render/ayah_rasterizer.dart';
import '../render/letterbox_layout.dart';
import '../render/render_process.dart';
import '../render/scene_plan.dart';
import '../render/verse_planner.dart';
import '../render/video_renderer.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/ayah_overlay.dart' show AyahOverlay;
import '../widgets/band_glow_ground.dart';
import '../widgets/feedback_sheet.dart';
import '../widgets/rate_sheet.dart';
import '../widgets/dedicate_sheet.dart';
import '../widgets/glow_button.dart';
import '../widgets/share_to.dart';
import '../widgets/hashtags_sheet.dart';
import '../widgets/measure_height.dart';
import '../widgets/motion_picker.dart';
import '../widgets/reel_finish.dart';
import '../widgets/reel_watermark.dart';
import '../widgets/shimmer_text.dart';
import '../widgets/resize_frame.dart';
import '../widgets/step_dots.dart';
import '../widgets/surah_title.dart';
import '../widgets/telegram_invite.dart';
import '../widgets/verse_stage.dart';
import '../widgets/verses_milestone.dart';
import 'home_shell.dart';

/// An app Share can hand the finished reel to directly, skipping the
/// OS share sheet. Null anywhere below means the sheet itself.
enum _DirectShare {
  whatsapp,
  instagramReel,
  instagramStory,
  tiktok,
  youtube,
  facebook,
}

/// Screen 4 of 4. The reel plays immediately: this is the aha moment.
/// Verse text is driven live off the same timing table the exporter
/// uses, so what plays here is what renders.
///
/// Text and audio for the chosen surah may need a one-time fetch; a
/// progress state covers that (usually already warmed by the prefetch
/// kicked off on the verses screen).
class PreviewScreen extends StatefulWidget {
  /// What this screen pops with when the user asks for more
  /// sceneries. The scenery picker is two screens back now that the
  /// style step sits between them, so this screen cannot reach it with
  /// a pop of its own: it hands the request to the style step, which
  /// gets out of the way. See [StyleScreen], where it is caught.
  static const addScenes = 'add-scenes';

  /// Where a reopened reel had been cut, so it opens as it was left.
  /// Null for the whole selection, which is what every new reel is.
  final int? initialTrimMs;

  const PreviewScreen({super.key, this.initialTrimMs});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// ONE player for every preview visit, for the app's lifetime.
  /// Creating and disposing a platform player per visit is exactly the
  /// churn that wedges Android's media stack: the second visit's
  /// setSource can hang forever while the first player's teardown is
  /// still in flight. A persistent player sidesteps the whole class of
  /// bugs — each visit just stops it and points it at its own file.
  ///
  /// Not final: when Android's MediaPlayer poisons itself (error -38 —
  /// observed when a loop restart raced app backgrounding), every call
  /// on it times out forever. [_hardResetPlayer] swaps in a fresh one.
  static AudioPlayer _audio = AudioPlayer();
  bool _restarting = false;
  bool _sourceReady = false;
  bool _resetting = false;

  /// Escalation counter for playback recovery: 0 = healthy,
  /// 1 = one simple retry done, next failure triggers a hard reset.
  int _recoverLevel = 0;

  /// Background players, by scene index. A reel runs through as many
  /// sceneries as it has verses, and phones cap how many hardware
  /// decoders exist at once, so only the scene playing and the one
  /// after it are ever held — see [_ensureSceneVideo].
  final Map<int, VideoPlayerController> _sceneVideo = {};

  /// Scenes whose decoder is being brought up right now. A scene can be
  /// asked for twice in the same beat — the loop restart and the next
  /// position event both reach for scene 0 — and two opens of one
  /// scene made two controllers, of which the map kept one and nobody
  /// ever disposed the other. Hardware decoders are the scarcest thing
  /// on the phone; one lost per loop was a preview that went black
  /// after a few laps.
  final Set<int> _opening = {};

  /// Generation of the last scene-length check; see [_checkSceneLengths].
  int _lengthCheck = 0;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _endSub;
  StreamSubscription<dynamic>? _evtSub;

  static const _maxReelMs = ReelLimits.maxReelMs;

  /// How much smaller the blurred letterbox backdrop is drawn than the
  /// frame before being scaled back up; see [_backdropLayers]. The
  /// exporter uses twelve; six keeps a little more of the picture under
  /// the blur at preview size, where the frame is a third of 1080 to
  /// begin with.
  static const _blurShrink = 6.0;

  late final Reciter _reciter = creationState.reciter!;
  late final ReelBackground _background = creationState.background!;

  /// Every scenery this reel runs through, in order. One entry is the
  /// single-background reel, and every path below collapses to what it
  /// always did.
  late final List<ReelBackground> _scenes =
      creationState.scenes.isEmpty ? [_background] : creationState.scenes;

  /// Where each scenery's turn falls. Empty until the recitation is
  /// loaded — the plan is timed off it — and one entry long for a reel
  /// with one scenery, which is what makes everything downstream ask
  /// [_multi] rather than the list's length.
  List<SceneCut> _cuts = const [];
  int _fadeMs = 0;
  int _sceneIndex = 0;

  /// True once the reel really does run through more than one scenery.
  bool get _multi => _cuts.length > 1;

  /// The sceneries the plan actually reaches. They can differ from
  /// [_scenes] by the length trim below: a reel cut short has fewer
  /// verses, and a scene per verse is then fewer scenes.
  List<ReelBackground> get _usedScenes => _cuts.length >= _scenes.length
      ? _scenes
      : _scenes.sublist(0, _cuts.length);

  ScenePacing _pacing = creationState.pacing;
  SceneTransition _transition = creationState.transition;

  /// How much room each scene takes relative to its neighbours; see
  /// [CreationState.sceneWeights]. Held here so a re-plan reads one
  /// list rather than the singleton mid-gesture.
  List<int> _weights = creationState.sceneWeights;

  /// Where the verses' own choice put each scenery, for a matched run;
  /// see [SceneAnchor]. A share given by hand lets them go.
  List<SceneAnchor?> _anchors = creationState.sceneAnchors;

  /// Whether the scene controls are unfolded. Shut by default: a reel
  /// that runs a scene per verse needs nothing said about it.
  bool _scenesOpen = false;

  /// Scenes whose own footage runs out before their turn does. A reel
  /// is never finished by freezing or looping one, so while this is
  /// not empty there is nothing to export — see [_sceneShortfall].
  List<int> _shortScenes = const [];
  late final int _surah = creationState.surah;
  late final int _startAyah = creationState.startAyah;

  /// May be trimmed after the recitation loads: the hard length cap.
  late int _endAyah = creationState.endAyah;

  // Loaded by _boot(); the screen shows a preparing state until then.
  List<Ayah>? _ayahs;
  Recitation? _recitation;

  /// The basmala's card, for a reel that opens a surah on verse 1: Al-
  /// Fatiha 1:1 in the reel's edition. Null for any other reel, and when
  /// the recording came without one (see [Recitation.opensWithBasmala]).
  Ayah? _basmala;
  double _prepProgress = 0;
  String? _prepError;

  /// What kind of failure [_prepError] reports, for its icon and for
  /// whether it asks to be reported. See [Trouble].
  Trouble _prepTrouble = Trouble.device;

  /// Where the reel starts: at the basmala, when it opens a surah on
  /// verse 1 and the recording carries one.
  int get _segStartMs => _recitation!.startOf(_startAyah);
  int get _segEndMs => _recitation!.timing(_endAyah).endMs;

  /// Whether this reel opens on the basmala: from a surah's verse 1, in
  /// any surah but Al-Fatiha (whose verse 1 is the basmala) and At-Tawbah
  /// (which has none), with Settings' basmala on.
  bool get _wantsBasmala =>
      _startAyah == 1 &&
      _surah != 1 &&
      _surah != 9 &&
      !_reciter.isUserAudio &&
      SettingsService.state.value.basmala;

  /// The basmala's card, when the recording carries the basmala.
  Ayah? get _basmalaCard =>
      _recitation?.opensWithBasmala ?? false ? _basmala : null;

  /// Whether this reel can be cut short at all. Only a recording the
  /// user brought in has a length worth trimming: an app voice runs
  /// exactly the verses chosen, and a handle under it reads as a stray
  /// slider that cuts the recitation off mid-ayah.
  bool get _canTrim => _reciter.isUserAudio;

  /// Where the user cut the reel, as a length in milliseconds from the
  /// start of the selection. Null is the whole of it, which is what
  /// every reel starts as — unless it was reopened with a cut in it.
  /// A saved cut on an app voice is dropped rather than honoured: with
  /// no handle on screen there would be nothing to undo it with.
  late int? _trimMs = _canTrim ? widget.initialTrimMs : null;

  /// The whole selection, and what is left of it after the cut.
  int get _fullMs => _segEndMs - _segStartMs;
  int get _reelMs => _trimMs ?? _fullMs;

  /// Where the reel ends now, on the recording's own clock: what
  /// playback loops at, what the scene run is cut to, and what the
  /// export is given.
  int get _reelEndMs => _segStartMs + _reelMs;

  double _overlayAlign = creationState.overlayAlign;

  /// Laid-out height of the verse card, reported by [_MeasureHeight]
  /// out of its own render object. Null until the card first lays out,
  /// which is the only reason the drag below still carries a fallback.
  double? _overlayHeight;
  bool _hasDragged = false;

  /// The verse's colour and luminous ink, and its card's look: the
  /// style step's, one screen back, where they are set against the
  /// scenery rather than over a playing reel.
  final int _textArgb = creationState.textArgb;
  final VerseInk _verseInk = creationState.verseInk;
  double _textScale = creationState.textScale;
  final TextPreset _preset = creationState.textPreset;

  /// Everything the style step settled, fixed for this visit — going
  /// back a screen is how you change any of it, exactly as it is for
  /// the frame format chosen a screen before that.
  late final int _accentArgb = creationState.accentArgb;
  late final VerseInk _accentInk = creationState.accentInk;
  late final ReelTypography _typography = creationState.typography;
  late final ReelEffects _effects = creationState.effects;

  /// Who the reel was made for. Not `late final` like the rest of the
  /// styling: this one is chosen here, on this screen, after the reel
  /// is already on the loop — so it changes while the screen is up,
  /// and changing it is what sends the reel back to the encoder.
  Dedication _dedication = creationState.dedication;

  /// Where the dedication line was dragged to, as fractions of the
  /// frame; null while it is at the foot, where it starts.
  Offset? _dedicationAt = creationState.dedicationAt;

  /// How big the line laid out, which the drag needs to keep the whole
  /// of it on the frame. Reported by the line rather than looked up by
  /// a [GlobalKey]: the line is built inside the frame's
  /// [LayoutBuilder], and moves to a new parent whenever its drag is
  /// switched on or off — see [MeasureSize].
  Size? _dedicationLineSize;

  /// Whether the line is landing on a pale band, which flips its ink.
  bool get _dedicationOnLight => ReelDedication.onLightAt(_dedicationAt,
      onLightGround: _onLight, letterbox: _box);

  /// Moves the line by a finger's [delta], keeping it on the frame.
  void _moveDedication(Offset delta, BoxConstraints box) {
    final w = box.maxWidth, h = box.maxHeight;
    final line = _dedicationLineSize;
    if (line == null || w == 0 || h == 0) return;
    final margin = ReelWatermarkMark.shadowMargin *
        w /
        ReelWatermarkMark.referenceWidth;
    // Where it is now: its dragged place, or its place at the foot.
    final from = _dedicationAt ??
        Offset(
            0.5,
            1 -
                (ReelDedication.frameInset *
                            w /
                            ReelWatermarkMark.referenceWidth +
                        line.height / 2) /
                    h);
    double keep(double v, double half) =>
        half >= 0.5 ? 0.5 : v.clamp(half, 1 - half);
    setState(() => _dedicationAt = Offset(
          keep(from.dx + delta.dx / w, (line.width / 2 + margin) / w),
          keep(from.dy + delta.dy / h, (line.height / 2 + margin) / h),
        ));
  }

  /// The line is burned into the frame, so where it was put changes
  /// the file, exactly as the verse's drag does.
  void _settleDedication() {
    creationState.setDedicationAt(_dedicationAt);
    _restyled();
  }

  void _resetDedication() {
    if (_dedicationAt == null) return;
    HapticFeedback.selectionClick();
    setState(() => _dedicationAt = null);
    _settleDedication();
  }

  /// The dedication as a sentence, in the language the app is in.
  String get _dedicationLine => _dedication.isEmpty
      ? ''
      : L10n.current.dedicationLine(_dedication.kind, _dedication.name);

  /// Who the reel is for. The line is burned into the frame, so
  /// changing it changes the file: the loop stops, the render key
  /// moves, and the next Share or Save encodes it in — which is the
  /// same road every other styling choice on this screen takes.
  Future<void> _dedicate() async {
    final picked =
        await showDedicateSheet(context,
            dedication: _dedication, movable: true);
    if (picked == null || picked == _dedication || !mounted) return;
    setState(() {
      _dedication = picked;
      // Taken off, it takes its place with it; the next one starts at
      // the foot of the frame again.
      if (picked.isEmpty) _dedicationAt = null;
    });
    creationState
      ..setDedication(picked)
      ..setDedicationAt(_dedicationAt);
    _restyled();
  }

  /// The edition printed under the verse, read once. Held rather than
  /// re-read so the card on screen, the cards the exporter rasterizes
  /// and the key they are cached under cannot come from three
  /// different settings snapshots.
  late final VerseTranslation _edition =
      SettingsService.state.value.translation;

  /// The verse numbering, read once, for the same reason as [_edition].
  late final VerseNumbering _numbering =
      SettingsService.state.value.verseNumbering;

  /// Whether the cards carry the translation, read once with the rest.
  late final bool _showTranslation =
      !SettingsService.state.value.verseTranslationOff;

  /// The Settings switch for the higher encoder bitrate, read once so
  /// an eager render and the export it becomes agree on the file.
  late final bool _highQuality =
      SettingsService.state.value.highQualityVideo;

  /// Whether the recitation has actually begun.
  ///
  /// The fade veil answers to this and not only to the clock. A reel
  /// fading in is black at t=0, and t=0 is also what the position
  /// reads for the whole of the preparing state — so without this the
  /// frame went fully black a twentieth of a second after the screen
  /// opened and stayed there, over the spinner, the surah download and
  /// the retry button, on any reel with the fade turned on.
  bool _started = false;

  /// How black the frame is right now, when the reel fades at its
  /// edges. A notifier rather than state: at 50ms a tick this is the
  /// only thing on the screen that has to move, and rebuilding the
  /// whole preview twenty times a second to darken one veil is how a
  /// 60fps preview becomes a 30fps one.
  final ValueNotifier<double> _fadeLevel = ValueNotifier(0);
  Timer? _fadeTicker;

  /// Frame format, fixed for this visit — it is chosen on the scenery
  /// screen, so coming back is how you change it.
  late final ReelLayout _layout = creationState.layout;
  late final bool _rounded = creationState.roundedCorners;
  late final LetterboxBackdrop _backdrop = creationState.backdrop;
  late final int _backdropArgb = creationState.backdropArgb;
  late final BandGlow _bandGlow = creationState.bandGlow;

  /// Whether the verse and the watermark are landing on a pale band
  /// rather than on darkened scenery. Fixed for the visit, like the
  /// format it comes from, and read by everything that has to pick a
  /// colour for itself. See [isLightGround].
  late final bool _onLight = isLightGround(
    layout: _layout,
    backdrop: _backdrop,
    backdropArgb: _backdropArgb,
  );

  /// Displayed aspect of the scenery, which is the only thing that
  /// decides a letterbox card's shape. Null until FFprobe answers; the
  /// preview holds the full-frame look for that beat rather than laying
  /// out a card it would then have to reshape.
  double? _srcAspect = creationState.layout == ReelLayout.letterbox
      ? MediaAspect.cached(creationState.background!)
      : null;

  /// The card and band geometry, once the aspect is known.
  LetterboxGeometry? get _box =>
      _layout == ReelLayout.letterbox && _srcAspect != null
          ? LetterboxGeometry.of(_srcAspect!)
          : null;

  late int _ayahIndex = _startAyah - 1;

  /// Word-highlight windows for the selection (null: no data for this
  /// voice, still fetching, or selection too long — card stays whole).
  Map<int, List<HighlightSpan>>? _hlPlan;
  bool _wordHl = creationState.wordHighlight;


  /// The voice's raw word timing, when it has any: what long verses are
  /// cut by, and what the thread and the light follow. Null until it is
  /// in, and for a voice without it.
  Map<int, List<WordSpan>>? _spans;
  bool _spansFailed = false;

  /// Each verse's tokens' recited windows: what the thread and the
  /// light follow, here and in the export. [_trueTimes] where the voice
  /// is word-timed, [_nearTimes] for the verses its timing published
  /// without vouching for them, and [_breathTimes] for the verses
  /// neither has; the truer one wins where several are in. Only the
  /// motions read it: the lit word, the trail, the unveil and the lines'
  /// cuts go by [_spans] alone.
  Map<int, List<(int, int)?>>? _wordTimes;

  /// The windows from [_spans].
  Map<int, List<(int, int)?>>? _trueTimes;

  /// The windows from the voice's near tier (see
  /// [WordAlignService.loadNear]): a verse otherwise crossed at an even
  /// pace, a second and more off where the reciter breathes, followed
  /// instead as a model placed its words.
  Map<int, List<(int, int)?>>? _nearTimes;

  /// The windows the recording's own pauses give the verses nothing
  /// else times (see [BreathPace]): every verse of an upload, and the
  /// few of an app voice that neither tier has.
  Map<int, List<(int, int)?>>? _breathTimes;

  /// [_wordTimes] from its three layers; null while none is in.
  Map<int, List<(int, int)?>>? get _mergedTimes {
    final near = _nearTimes, sure = _trueTimes, breath = _breathTimes;
    if (near == null && breath == null) return sure;
    return {...?breath, ...?near, ...?sure};
  }

  /// The long verses cut into lines, when this reel cuts them; null for
  /// every verse whole. See [VersePlanner].
  VerseLinePlan? _linePlan;
  int _planGen = 0;

  /// What is on screen in turn: whole verses, and the lines of cut ones.
  List<VerseUnit> _units = const [];

  /// What the verse does as it is recited, as chosen on the style step.
  late VerseMotion _motionChoice = creationState.motion;

  /// The motion this reel can run: the trail and the unveil need word
  /// windows, which not every voice has, and a long reel goes without
  /// the light ([VerseMotion.forUnits]).
  VerseMotion get _motion => _motionChoice
      .forVoice(hasWords: _hlPlan != null)
      .forUnits(_units.length);

  /// Where the recitation is, every frame: what the verse on screen and
  /// its motion are drawn at. The position events alone come every
  /// fifth of a second; the same wall-clock interpolation the word
  /// highlight uses fills in between.
  final ValueNotifier<int> _clock = ValueNotifier(0);
  late final Ticker _clockTicker = createTicker((_) => _tickClock());

  /// The surah's name at the head of the reel, and where it was dragged.
  bool _titleOn = creationState.surahTitle;
  Offset? _titleAt = creationState.surahTitleAt;

  /// Player position events arrive only every ~200ms; a word lasts
  /// 300-600ms. The clock interpolates between events with a wall
  /// clock so the highlight lands on the word, not near it.
  Duration _lastPos = Duration.zero;
  final Stopwatch _posClock = Stopwatch();

  /// FFmpeg encode in progress: shows the progress bar.
  bool _rendering = false;

  /// An encode is running, eager or foreground.
  ///
  /// The encode and the preview want the same two scarce things: a
  /// hardware codec slot, and the java heap MediaCodec allocates its
  /// buffer objects out of. When that heap runs out the codec's own
  /// callback thread aborts the process instead of throwing, so while
  /// this is set the scenery keeps one decoder instead of two.
  bool _encoding = false;

  /// A foreground export has taken the scenery's decoders back. Until
  /// it ends no scene opens one again, though the recitation plays on
  /// under the progress bar and its scene changes still ask for them.
  bool _decodersReleased = false;

  /// Whole export flow (render + save/share sheet): disables buttons.
  bool _busy = false;
  double _renderProgress = 0;
  Future<File>? _renderJob;

  /// Pending eager render (see [_scheduleEager]).
  Timer? _eagerTimer;

  /// The styling changed while an export was running, so the render
  /// that export is using is a reel behind. See [_restyled].
  bool _restyledWhileBusy = false;

  /// Path of the render already copied into My Reels, so Share followed
  /// by Save doesn't create a duplicate library entry.
  String? _libraryPath;

  /// The library entry for [_libraryPath], which also carries whether
  /// this reel has already been written to the device gallery.
  SavedReel? _saved;

  /// A tenth reel just made (the twentieth, the thirtieth…): its card is
  /// offered once the save is over, in place of the usual asks.
  int? _milestone;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Scene 0 is on screen from the first frame whatever the reel does
    // afterwards; the rest are brought up as their turn approaches.
    _ensureSceneVideo(0);
    _resolveAspect();
    _boot();
  }

  /// Settles the card's shape before anything is rendered with it.
  ///
  /// A run of sceneries takes its shape from the first of them: one
  /// card, one shape, for the whole reel. A card that changed size on
  /// every cut would be a different format each time, not a reel.
  Future<void> _resolveAspect() async {
    if (_layout != ReelLayout.letterbox || _srcAspect != null) return;
    final a = await MediaAspect.of(_background);
    if (mounted) setState(() => _srcAspect = a);
  }

  /// Fetch surah text + recitation (both cached after first use), then
  /// start playback and the eager render.
  Future<void> _boot() async {
    rlog('boot: surah $_surah ayahs $_startAyah-$_endAyah '
        'reciter ${_reciter.id} bg ${_background.id}');
    setState(() {
      _prepError = null;
      _prepTrouble = Trouble.device;
      _prepProgress = 0;
    });
    // The two fetches are reported apart. They fail for different
    // reasons and from different hosts, and one message covering both
    // meant nobody — the user or us — could tell which half of the
    // network was the problem.
    final List<Ayah> ayahs;
    try {
      ayahs = await QuranRepository.ayahsOf(_surah);
      rlog('boot: text ready (${ayahs.length} ayahs)');
      // The basmala a surah opens with, for a reel from its verse 1:
      // Al-Fatiha's first verse, bundled, so it never waits or fails on
      // the network. Without it the reel is the one it always was.
      if (_wantsBasmala) {
        try {
          final fatiha = await QuranRepository.ayahsOf(1);
          if (fatiha.isNotEmpty) _basmala = fatiha.first;
        } catch (e) {
          rlog('boot: no basmala text: $e');
        }
      }
    } catch (e, st) {
      // Kept out of rlog: that is compiled away in release, and a boot
      // that fails on a user's phone is exactly the one nobody can see.
      rlogError('boot: surah text', e, st);
      if (mounted) {
        final trouble = troubleOf(e);
        setState(() {
          _prepTrouble = trouble;
          _prepError = trouble == Trouble.offline
              ? L10n.current.surahLoadError
              : L10n.current.surahTextFailed;
        });
      }
      return;
    }

    final Recitation rec;
    try {
      rec = await QuranRepository.recitation(
        _reciter,
        _surah,
        // Only the chosen range is fetched — previewing a few ayahs of
        // a long surah no longer downloads the whole thing.
        startAyah: _startAyah,
        endAyah: _endAyah,
        basmala: _wantsBasmala && _basmala != null,
        onProgress: (p) {
          if (mounted && _recitation == null) {
            setState(() => _prepProgress = p);
          }
        },
      );
      rlog('boot: recitation ready ${rec.audioPath}');
    } catch (e, st) {
      rlogError('boot: recitation', e, st);
      if (mounted) {
        final l = L10n.current;
        final trouble = troubleOf(e);
        setState(() {
          _prepTrouble = trouble;
          // Told as it is: the connection only when it was the
          // connection. Two bugs on the phone once reached users as
          // "check your connection", and hid there for a release.
          _prepError = e is SurahUnavailable
              ? l.surahNotRecorded(l.reciterName(e.reciter),
                  l.surahTitle(QuranRepository.surahInfo(e.surah)))
              : l.recitationFailed(trouble);
        });
      }
      return;
    }
    if (!mounted) return;

    // Past here nothing touches the network: the cuts are planned, the
    // scenery is opened and playback starts, all of it on this phone
    // with both downloads already in hand. It used to sit inside the
    // same try as the fetch above, so an ffmpeg or player failure —
    // a local one, on a working connection — told the user to check
    // their connection. That is a fault report that sends people to
    // the wrong place and tells us nothing about where it broke.
    try {
      // The hard length cap, now that exact durations are known. The
      // verses screen already trims when timings were cached; this
      // covers first-time downloads.
      // What the recitation actually covers comes first: the fetch
      // stops itself once a selection runs past the cap, so a selection
      // that did can end beyond the last ayah there are timings for.
      var end = _endAyah > rec.lastAyah ? rec.lastAyah : _endAyah;
      // And what the text actually holds: the verse card indexes the
      // surah's list by ayah number, and a fetch that came back short
      // of the range would have been a RangeError on the first frame.
      if (ayahs.length < _startAyah) {
        rlogError('boot: surah text', 'only ${ayahs.length} ayahs for '
            'surah $_surah, needed $_startAyah');
        setState(() {
          _prepTrouble = Trouble.host;
          _prepError = L10n.current.surahTextFailed;
        });
        return;
      }
      if (end > ayahs.length) end = ayahs.length;
      final startMs = rec.startOf(_startAyah);
      while (end > _startAyah &&
          rec.timing(end).endMs - startMs > _maxReelMs) {
        end--;
      }
      final trimmed = end != _endAyah;
      setState(() {
        _ayahs = ayahs;
        _recitation = rec;
        _endAyah = end;
        _units = VerseUnit.of(rec, _startAyah, end, null);
        // A cut carried in from a recipe has to fit the recitation it
        // is now standing on: past the end, or under the handle's own
        // floor, it is no cut at all.
        final t = _trimMs;
        if (t != null && (t >= _fullMs || t < _TrimBar._minMs)) _trimMs = null;
      });
      // The plan needs the recitation's clock, so this is the first
      // moment it can be drawn.
      _replan();
      _checkSceneLengths();
      if (trimmed) {
        ScaffoldMessenger.of(context).showSnackBar(
          toast(
            L10n.current.trimmedToAyah(end),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      _attachListeners();
      _startFadeTicker();
      if (!_clockTicker.isActive) _clockTicker.start();
      _loadHighlight();
      unawaited(_loadNear());
      // Long verses are cut once the voice's word timing is in, when it
      // has any; a voice without it is cut on its pauses straight away.
      unawaited(_replanLines());
      await _prepareSource();
      await _playSegment();
      // Start rendering silently so Share feels instant — but only
      // after playback has visibly begun. Rendering immediately starves
      // the preview of CPU and it takes ages to come alive.
      _scheduleEager();
    } catch (e, st) {
      rlogError('boot: prepare', e, st);
      if (mounted) {
        setState(() {
          _prepTrouble = Trouble.device;
          _prepError = L10n.current.previewError;
        });
      }
    }
  }

  /// (Re)builds the scene timeline and everything that reads it.
  ///
  /// Called when the recitation lands and whenever the pacing changes;
  /// the export is dropped alongside, because a reel whose cuts moved
  /// is a different reel.
  void _replan({bool drop = false}) {
    final rec = _recitation;
    if (rec == null) return;
    final cuts = ScenePlan.cutAt(
      ScenePlan.of(
        sceneCount: _scenes.length,
        recitation: rec,
        startAyah: _startAyah,
        endAyah: _endAyah,
        pacing: _pacing,
        weights: _weights,
        units: _units,
        anchors: _anchors,
      ),
      _reelEndMs,
    );
    setState(() {
      _cuts = cuts;
      _fadeMs = ScenePlan.fadeMsFor(cuts, _transition);
      _sceneIndex = _sceneIndex.clamp(0, cuts.length - 1);
    });
    _ensureSceneVideo(_sceneIndex);
    if (drop) _restyled();
  }

  /// Everything the verse card's layout answers to, as this screen has
  /// it now: what a plan of cut verses is made for.
  VerseLook get _look => VerseLook(
        textScale: _textScale,
        preset: _preset,
        typography: _typography,
        edition: _edition,
        numbering: _numbering,
        showTranslation: _showTranslation,
        ink: _verseInk,
        surah: _surah,
      );

  /// (Re)cuts the long verses into lines for the reel as it now looks.
  ///
  /// A voice with word timing waits for it: cuts are placed on its
  /// words, and a plan made without them would be thrown away a moment
  /// later. Superseded plans stop where they are.
  Future<void> _replanLines() async {
    final rec = _recitation;
    final ayahs = _ayahs;
    if (rec == null || ayahs == null) return;
    final gen = ++_planGen;
    final lines = creationState.verseLines;
    if (lines == VerseLines.whole) {
      _planned.value = (0, 0);
      _applyPlan(null);
      return;
    }
    if (WordAlignService.supports(_reciter) && _spans == null && !_spansFailed) {
      return;
    }
    VerseLinePlan plan;
    try {
      plan = await VersePlanner.plan(
        lines: lines,
        ayahs: ayahs,
        recitation: rec,
        startAyah: _startAyah,
        endAyah: _endAyah,
        look: _look,
        words: _spans,
        // Asked for only when a verse that needs cutting has no word
        // timing — every verse of a voice without it, and the few a
        // voice timed by QUL has none for.
        loudness: () => RecitationService.loudness(rec.audioPath),
        keepGoing: () => mounted && gen == _planGen,
      );
    } catch (e, st) {
      // A plan that fails leaves every verse whole, which is the reel
      // as it always was — never a broken preview.
      rlogError('lines: plan', e, st);
      plan = VerseLinePlan.empty;
    }
    if (!mounted || gen != _planGen) return;
    rlog('lines: ${plan.byAyah.length} verse(s) cut into '
        '${plan.partCount} lines, ${plan.whole} left whole');
    _planned.value = (plan.whole, plan.byAyah.length);
    _applyPlan(plan.isEmpty ? null : plan);
  }

  void _applyPlan(VerseLinePlan? plan) {
    final rec = _recitation;
    if (rec == null) return;
    final changed =
        (plan?.fingerprint ?? '') != (_linePlan?.fingerprint ?? '');
    setState(() {
      _linePlan = plan;
      _units = VerseUnit.of(rec, _startAyah, _endAyah, plan);
    });
    // The scenes may follow the lines, and the export draws them: both
    // are a different reel now.
    if (changed) _replan(drop: true);
    // The pauses' pace reads each line in its own window.
    unawaited(_loadBreaths());
  }

  /// Where the recitation is now, for the verse's motion.
  void _tickClock() {
    final playing = _audio.state == PlayerState.playing;
    final ms = playing
        ? _lastPos.inMilliseconds + _posClock.elapsedMilliseconds
        : _lastPos.inMilliseconds;
    if (_clock.value != ms) _clock.value = ms;
  }

  /// Where the title's centre is: dragged, or its place at the head.
  Offset get _titleCentre => _titleAt ?? ReelSurahTitle.defaultCentre(_box);

  bool get _titleOnLight => ReelDedication.onLightAt(_titleCentre,
      onLightGround: _onLight, letterbox: _box);

  /// How big the title laid out, for keeping it on the frame.
  Size? _titleSize;

  void _moveTitle(Offset delta, BoxConstraints box) {
    final w = box.maxWidth, h = box.maxHeight;
    final size = _titleSize;
    if (size == null || w == 0 || h == 0) return;
    final margin = ReelWatermarkMark.shadowMargin *
        w /
        ReelWatermarkMark.referenceWidth;
    final from = _titleCentre;
    double keep(double v, double half) =>
        half >= 0.5 ? 0.5 : v.clamp(half, 1 - half);
    setState(() => _titleAt = Offset(
          keep(from.dx + delta.dx / w, ((size.width) / 2 + margin) / w),
          keep(from.dy + delta.dy / h, ((size.height) / 2 + margin) / h),
        ));
  }

  /// How far two fingers have sized the title from its own size.
  double _titleScale = creationState.surahTitleScale;

  void _resizeTitle(double scale) {
    final v = scale.clamp(
        CreationState.surahTitleScales.min, CreationState.surahTitleScales.max);
    if (v == _titleScale) return;
    // A tick at its own size on the way through, so a pinch can find it
    // again by feel.
    if ((_titleScale - 1).sign != (v - 1).sign) HapticFeedback.selectionClick();
    setState(() => _titleScale = v);
  }

  void _settleTitle() {
    creationState
      ..setSurahTitleAt(_titleAt)
      ..setSurahTitleScale(_titleScale);
    _restyled();
  }

  void _resetTitle() {
    if (_titleAt == null && _titleScale == 1.0) return;
    HapticFeedback.selectionClick();
    setState(() {
      _titleAt = null;
      _titleScale = 1.0;
    });
    _settleTitle();
  }

  void _toggleTitle() {
    HapticFeedback.selectionClick();
    setState(() {
      _titleOn = !_titleOn;
      if (!_titleOn) {
        _titleAt = null;
        _titleScale = 1.0;
      }
    });
    creationState
      ..setSurahTitle(_titleOn)
      ..setSurahTitleAt(_titleAt)
      ..setSurahTitleScale(_titleScale);
    _restyled();
  }

  /// A motion picked on this screen, from the sheet under the reel.
  void _setMotion(VerseMotion m) {
    if (m == _motionChoice) return;
    setState(() => _motionChoice = m);
    creationState.setMotion(m);
    _restyled();
    // The thread and the light may be on now, and need the pauses.
    unawaited(_loadBreaths());
  }

  /// The motion, as a sheet that leaves the reel playing above it — and
  /// how this reel shows its long verses, chosen the same way.
  Future<void> _pickMotion() => showMotionSheet(
        context,
        motion: _motionChoice,
        hasWords: _hlPlan != null,
        onChanged: _setMotion,
        lines: creationState.verseLines,
        onLines: _setLines,
        planned: _planned,
        tint: AyahOverlay.lightTintOf(Color(_accentArgb), _accentInk),
      );

  /// How this reel's long verses came out, as (shown whole, cut): what
  /// the lines choice in the motion sheet says something about.
  final _planned = ValueNotifier<(int, int)>((0, 0));

  /// Long verses whole or line by line, for this reel. The scenery
  /// follows the lines when Settings says it should and the reel is on
  /// the per-verse pacing it started on.
  void _setLines(int lines) {
    if (lines == creationState.verseLines) return;
    creationState.setVerseLines(lines);
    final follow = SettingsService.state.value.scenesFollowLines;
    if (lines > VerseLines.whole &&
        follow &&
        _pacing == ScenePacing.perAyah) {
      setState(() => _pacing = ScenePacing.perLine);
      creationState.setPacing(ScenePacing.perLine);
    } else if (lines == VerseLines.whole && _pacing == ScenePacing.perLine) {
      setState(() => _pacing = ScenePacing.perAyah);
      creationState.setPacing(ScenePacing.perAyah);
    }
    _restyled();
    unawaited(_replanLines());
  }

  /// Live while the trim handle is moving: the reel on screen is the
  /// length under the finger, but the render is left alone — dropping
  /// and requeueing one per frame of a drag is an encode started and
  /// killed a dozen times.
  void _setTrim(int ms) {
    final next = ms >= _fullMs ? null : ms;
    if (next == _trimMs) return;
    setState(() => _trimMs = next);
    _replan();
  }

  /// The handle was let go: now the reel really is this long, so the
  /// export follows it and the scene lengths are asked again — a cut
  /// is one of the ways a clip that was too short for its turn stops
  /// being too short.
  void _trimSettled() {
    HapticFeedback.selectionClick();
    _restyled();
    _checkSceneLengths();
    if (_lastPos.inMilliseconds >= _reelEndMs) _playSegment();
  }

  /// Which scenes are shorter than the turn the plan gave them.
  ///
  /// Only a video the user brought in can be: a still has no length to
  /// run out of, and a catalog scenery — bundled or downloaded, they
  /// are one library — is authored to loop seamlessly, which is
  /// exactly what makes looping it invisible. See [MediaDuration.of],
  /// which is where that distinction is drawn. Probing is a platform
  /// round trip per file, cached forever after.
  Future<void> _checkSceneLengths() async {
    if (!_multi) {
      if (_shortScenes.isNotEmpty) setState(() => _shortScenes = const []);
      return;
    }
    // Only the latest check may answer. A trim settled and a pacing
    // tap a moment later each start one, each awaits a probe, and the
    // older one landing second would put a stale verdict over the
    // fresh one — and shut the export over a clip that now fits.
    final gen = ++_lengthCheck;
    final cuts = _cuts;
    final short = <int>[];
    for (var i = 0; i < cuts.length && i < _scenes.length; i++) {
      final ms = await MediaDuration.of(_scenes[i]);
      if (gen != _lengthCheck) return;
      if (ms == null) continue;
      // The blend is played out of the clip's own tail, so it has to
      // cover that too. A frame or two of slack: probes round.
      final needs =
          cuts[i].durationMs + (i == cuts.length - 1 ? 0 : _fadeMs) - 70;
      if (ms < needs) short.add(i);
    }
    if (!mounted || listEquals(short, _shortScenes)) return;
    rlog('scenes: ${short.length} clip(s) shorter than their turn');
    setState(() {
      _shortScenes = short;
      // A line that says something is wrong should have the way out of
      // it already open underneath.
      if (short.isNotEmpty) _scenesOpen = true;
    });
  }

  /// (Re)binds this screen's listeners to the current player instance.
  /// Called on boot and again after [_hardResetPlayer] swaps players.
  void _attachListeners() {
    _posSub?.cancel();
    _endSub?.cancel();
    _evtSub?.cancel();
    // Every 66 ms, not once a frame: see [PositionPolling]. That is the
    // cadence the highlight ticker below already runs at, so the scene
    // cut and the loop restart that hang off _syncAyah keep the accuracy
    // they had, and the word highlight is unaffected either way — it
    // interpolates off _posClock between these events.
    _audio.pollPositionEvery(const Duration(milliseconds: 66));
    _posSub = _audio.onPositionChanged.listen((pos) {
      _lastPos = pos;
      _posClock
        ..reset()
        ..start();
      _syncAyah(pos);
    });
    _endSub = _audio.onPlayerComplete.listen((_) => _onComplete());
    // Platform errors must be consumed here: unheard, they surface as
    // unhandled exceptions while the player silently stops responding.
    _evtSub = _audio.eventStream.listen((_) {}, onError: (Object e) {
      rlog('audio: platform error $e — hard reset');
      _hardResetPlayer(thenPlay: true);
    });
  }

  /// End of file reached. Only loop when the app is actually visible:
  /// restarting playback while hidden is what threw MediaPlayer into
  /// its unrecoverable -38 error state (the "preview never plays
  /// again" freeze). When hidden, the lifecycle-resume handler restarts
  /// playback instead.
  void _onComplete() {
    final phase = WidgetsBinding.instance.lifecycleState;
    rlog('audio: complete event (lifecycle $phase)');
    if (phase == AppLifecycleState.resumed) _playSegment();
  }

  /// Abandons a poisoned platform player and starts over with a fresh
  /// one. The old instance is disposed fire-and-forget — awaiting a
  /// wedged player hangs forever.
  Future<void> _hardResetPlayer({bool thenPlay = false}) async {
    if (_resetting) return;
    _resetting = true;
    try {
      rlog('audio: recreating player');
      _sourceReady = false;
      _restarting = false;
      final old = _audio;
      _audio = AudioPlayer();
      _attachListeners();
      unawaited(old.dispose().catchError((_) {}));
      if (_recitation != null) await _prepareSource();
    } finally {
      _resetting = false;
    }
    if (thenPlay && mounted && _sourceReady) await _playSegment();
  }

  /// Points the shared player at this visit's file. Done ONCE per
  /// visit; loops afterwards are seek+resume only, so the platform
  /// player is never torn down and rebuilt mid-preview.
  Future<void> _prepareSource({bool firstTry = true}) async {
    const wait = Duration(seconds: 6);
    try {
      // NO audio focus. With focus enabled, resume() completes but the
      // sound only starts when Android's async focus grant arrives —
      // and on rapid back-and-forth navigation that grant gets lost,
      // leaving a "playing" but silent preview until a screen off/on
      // forces a focus change (the observed freeze). Focus 'none'
      // makes start() synchronous and unconditional.
      await _audio
          .setAudioContext(AudioContext(
            android: const AudioContextAndroid(
              audioFocus: AndroidAudioFocus.none,
            ),
          ))
          .timeout(wait);
      await _audio.stop().timeout(wait);
      await _audio.setReleaseMode(ReleaseMode.stop);
      await _audio
          .setSource(DeviceFileSource(_recitation!.audioPath))
          .timeout(wait);
      _sourceReady = true;
      rlog('audio: source set');
    } catch (e) {
      rlog('audio: setSource failed ($e)'
          '${firstTry ? " — retrying" : ""}');
      if (firstTry && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) return _prepareSource(firstTry: false);
      }
    }
  }

  /// Brings scene [i]'s video up, and the one after it with it.
  ///
  /// Two decoders at a time, never more: a reel may run through thirty
  /// sceneries, and a phone hands out a handful of hardware decoders
  /// before it starts refusing. The next one is readied a scene early
  /// so a cut lands on a first frame rather than on black.
  Future<void> _ensureSceneVideo(int i, {bool firstTry = true}) async {
    if (i < 0 || i >= _scenes.length) return;
    _pruneSceneVideos(i);
    await _openScene(i, firstTry: firstTry);
    // Not while an encode runs: the second decoder is a convenience,
    // and the encode needs the room more than the cut needs a warm
    // first frame.
    if (mounted && i + 1 < _scenes.length && _multi && !_encoding) {
      await _openScene(i + 1, firstTry: firstTry, play: false);
    }
  }

  /// Everything but the scene playing and the one after it gives its
  /// decoder back.
  ///
  /// The scene *before* is the exception: through a blend it is still
  /// on screen, fading out of the frame, and a disposed player fades
  /// out as a black rectangle. So it keeps its decoder until the blend
  /// it is part of is over.
  void _pruneSceneVideos(int keepFrom) {
    final stale = _sceneVideo.keys
        .where((k) => k < keepFrom - 1 || k > keepFrom + 1)
        .toList();
    final gone = <VideoPlayerController>[];
    for (final k in stale) {
      final c = _sceneVideo.remove(k);
      if (c != null) gone.add(c);
    }
    if (gone.isNotEmpty) {
      // Out of the map now, so a scene asked for again gets a fresh
      // decoder; disposed only once the blend it may still be in has
      // played out. The loop restart is the case: the reel jumps from
      // its last scene back to its first, the last scene is stale by
      // the arithmetic above, and disposing it on the spot turned the
      // crossfade back into a black rectangle every lap.
      Future.delayed(Duration(milliseconds: _fadeMs + 300), () {
        for (final c in gone) {
          c.dispose();
        }
      });
    }
    final leaving = keepFrom - 1;
    if (!_sceneVideo.containsKey(leaving)) return;
    Future.delayed(Duration(milliseconds: _fadeMs + 300), () {
      // Still the scene we pruned for: a loop or a fast re-plan may
      // have moved on, and then this is not ours to close.
      if (!mounted || _sceneIndex != keepFrom) return;
      final done = _sceneVideo.remove(leaving);
      if (done == null) return;
      done.dispose();
      setState(() {});
    });
  }

  Future<void> _openScene(int i,
      {bool firstTry = true, bool play = true}) async {
    if (_decodersReleased) return;
    final scene = _scenes[i];
    // Any still — bundled or picked — needs no player; the build shows
    // it with Image.asset/Image.file.
    if (scene.isImage) return;
    final existing = _sceneVideo[i];
    if (existing != null) {
      if (play && !existing.value.isPlaying) existing.play();
      return;
    }
    // Already on its way up: the open in flight will seat it.
    if (!_opening.add(i)) return;
    VideoPlayerController? c;
    var retry = false;
    try {
      c = scene.isDeviceFile
          ? VideoPlayerController.file(File(scene.filePath!))
          : VideoPlayerController.asset(scene.videoAsset);
      await c.initialize().timeout(const Duration(seconds: 6));
      rlog('bgvideo: initialized ${scene.id} (scene $i)');
      c
        ..setLooping(true)
        ..setVolume(0);
      if (play) await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      final started = c;
      setState(() => _sceneVideo[i] = started);
      // Some devices come up paused on the first frame if a decoder
      // was briefly unavailable; nudge once after things settle.
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted &&
            _sceneVideo[i] == started &&
            started.value.isInitialized &&
            !started.value.isPlaying &&
            (play || _sceneIndex == i)) {
          started.play();
        }
      });
    } catch (e) {
      // The scenery grid can still hold its hardware decoders for a
      // beat after navigation; wait for them to release and try once
      // more before settling for the gradient fallback.
      rlog('bgvideo: init failed ($e)${firstTry ? " — retrying" : ""}');
      c?.dispose();
      retry = firstTry;
    } finally {
      _opening.remove(i);
    }
    // Outside the guard, or the retry would find its own scene "already
    // opening" and give up.
    if (retry && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) return _openScene(i, firstTry: false, play: play);
    }
  }

  /// Share sheet / app switch: pause cleanly, resume the chosen
  /// segment from its start when the user comes back. Prevents the
  /// player drifting outside the selected range while unfocused.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    rlog('screen: lifecycle $state');
    // Whether a save the app dies in now is one the phone's memory
    // cost, or one Android reclaimed in the background.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(PhoneBudget.appHidden(true));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(PhoneBudget.appHidden(false));
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // A wedged player rejects this; unheard, that is an unhandled
      // error in the log for every app switch, not a pause.
      _audio.pause().catchError((_) {});
    } else if (state == AppLifecycleState.resumed &&
        _recitation != null) {
      _playSegment();
    } else if (state == AppLifecycleState.resumed &&
        _prepError != null &&
        _prepTrouble == Trouble.offline) {
      // Back from the lock screen or another app to a download the
      // network let down: try it again rather than wait to be asked.
      // A phone locks while its owner watches a progress bar, and the
      // download stops with the app; the connection is usually fine
      // by the time they look again.
      _boot();
    }
  }

  /// [foreground] means the user is watching a progress bar rather than
  /// the preview, so the encode may take every core.
  ///
  /// A Save tapped while the eager render runs used to join it as it
  /// was: two cores held back for the preview, and the preview's
  /// decoders and pictures kept beside the encode. Barely started on
  /// x264, it is started again for the progress bar, which on most
  /// phones finishes sooner than the rest of it at the eager pace
  /// would. Past that, or on the device encoder, whose pace the thread
  /// count doesn't change, it is joined and takes everything a
  /// foreground render takes from its next encode on. Only a render
  /// still running is joined or started over: a finished one is a file,
  /// handed out as it is.
  Future<File> _ensureRender({bool foreground = false}) {
    final job = _renderJob;
    if (job != null && _jobLive && foreground && !_jobForeground) {
      // Not encoding yet (a letterbox render waiting for the source's
      // aspect): it starts as a foreground render, with nothing to lose.
      if (!_encoding) {
        rlog('render: Save takes the eager render before its encode');
        _jobForeground = true;
        return job;
      }
      final n = Platform.numberOfProcessors;
      // The eager pace as a share of the foreground one, by threads.
      final pace = (n - 2).clamp(2, 6) / n.clamp(2, 16);
      if (!VideoRenderer.encodingOnHardware && _jobProgress < 1 - pace) {
        rlog('render: Save during the eager render '
            '(${(_jobProgress * 100).round()}%) — starting it over for it');
        PhoneBudget.exportStage('eager render restarted');
        _dropRender(restart: false);
      } else {
        rlog('render: Save joins the eager render '
            '(${(_jobProgress * 100).round()}%)');
        // Its stages were passed before the save began, so without this
        // a save lost in the rest of its encode reads as "starting".
        PhoneBudget.exportStage(
            'joined the eager render at ${(_jobProgress * 100).round()}%');
        _jobForeground = true;
        _renderProgress = _jobProgress;
        _takeForForeground();
        VideoRenderer.promote();
        return job;
      }
    }
    return _renderJob ??= _startRender(foreground);
  }

  /// Whether a render is still running, whether it is one somebody
  /// waits on, and how far it has got: an eager render reports its
  /// progress too, unseen.
  bool _jobLive = false;
  bool _jobForeground = false;
  double _jobProgress = 0;

  /// What a foreground render takes from the preview for its length.
  void _takeForForeground() {
    _decodersReleased = true;
    _releaseSceneVideos();
    // And the decoded pictures nothing on screen is showing: the image
    // cache keeps every scenery and poster looked at this session, up
    // to its limit, and a phone short of memory needs that room for
    // the encode. What is on screen stays; the rest decodes again
    // when it is next wanted.
    if (PhoneBudget.now != ExportBudget.roomy) {
      PaintingBinding.instance.imageCache.clear();
    }
  }

  /// Hands every scenery decoder back.
  ///
  /// The controllers are disposed a frame later than they leave the
  /// map: a [VideoPlayer] still mounted this frame would be painting a
  /// texture that no longer exists.
  void _releaseSceneVideos() {
    if (_sceneVideo.isEmpty) return;
    final gone = _sceneVideo.values.toList();
    _sceneVideo.clear();
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in gone) {
        c.dispose();
      }
    });
    rlog('bgvideo: released ${gone.length} decoder(s) for the encode');
  }

  Future<File> _startRender(bool foreground) async {
    final gen = ++_jobGen;
    _jobLive = true;
    _jobForeground = foreground;
    _jobProgress = 0;
    try {
      // A letterbox render is shaped by the source's aspect, so it waits
      // for the probe rather than guessing and encoding the wrong card.
      final aspect = _layout == ReelLayout.letterbox
          ? (_srcAspect ??= await MediaAspect.of(_background))
          : 16 / 9;
      // Dropped while it waited, or another render started since: no
      // encode of it is wanted.
      if (_droppedGen == gen || gen != _jobGen) throw const RenderCancelled();
      _encoding = true;
      // A foreground export puts a progress bar over the preview, so
      // nobody is watching the scenery: it gives its decoders back for
      // the length of the encode and takes them again after. An eager
      // render happens while the user is still looking, so there the
      // decoder cap above is the whole of it. Read now, not from
      // [foreground]: a Save may have taken this render while it waited.
      if (_jobForeground) _takeForForeground();
      return await VideoRenderer.render(
        recitation: _recitation!,
        background: _background,
        // One scenery renders exactly as it always did; a run of them
        // takes the multi-scene graph, on the timeline shown here.
        scenes: _multi ? _usedScenes : const [],
        cuts: _multi ? _cuts : const [],
        transition: _transition,
        ayahs: _ayahs!,
        startAyah: _startAyah,
        endAyah: _endAyah,
        trimEndMs: _trimMs == null ? null : _reelEndMs,
        overlayAlign: _overlayAlign,
        textArgb: _textArgb,
        accentArgb: _accentArgb,
        verseInk: _verseInk,
        accentInk: _accentInk,
        textScale: _textScale,
        preset: _preset,
        typography: _typography,
        edition: _edition,
        numbering: _numbering,
        showTranslation: _showTranslation,
        highQuality: _highQuality,
        effects: _effects,
        dedication: _dedicationLine,
        dedicationAt: _dedicationAt,
        highlight: _wordHl ? _hlPlan : null,
        words: _hlPlan,
        wordTimes: _wordTimes,
        lines: _linePlan,
        motion: _motion,
        surahTitle: _titleOn,
        surahTitleAt: _titleAt,
        surahTitleScale: _titleScale,
        surahTitleLook: creationState.surahTitleLook,
        basmala: _basmalaCard,
        layout: _layout,
        roundedCorners: _rounded,
        backdrop: _backdrop,
        backdropArgb: _backdropArgb,
        bandGlow: _bandGlow,
        sourceAspect: aspect,
        foreground: _jobForeground,
        onProgress: (p) {
          if (gen == _jobGen) _jobProgress = p;
          if (mounted && _rendering) setState(() => _renderProgress = p);
        },
      );
    } finally {
      // A render dropped for another one ends after that one started:
      // what it set belongs to the newer one now.
      if (gen == _jobGen) {
        _jobLive = false;
        _encoding = false;
        final took = _jobForeground;
        _jobForeground = false;
        if (took) {
          _decodersReleased = false;
          if (mounted) unawaited(_ensureSceneVideo(_sceneIndex));
        }
      }
    }
  }

  /// Which [_startRender] is the latest, and the last one dropped.
  int _jobGen = 0;
  int _droppedGen = 0;

  Future<void> _playSegment() async {
    // Loop only the chosen ayah range: pause -> seek -> resume on the
    // already-prepared source. No stop/setSource here — rebuilding the
    // source every loop is what used to wedge the player.
    // Gone means gone: the player is shared, and a resume from a screen
    // already closed sounds over whatever the user went back to, with
    // nothing left to stop it.
    if (!mounted || _restarting || _recitation == null) return;
    if (!_sourceReady) {
      rlog('play: source not ready yet, preparing first');
      await _prepareSource();
      if (!mounted || !_sourceReady) return;
    }
    _restarting = true;
    // Timeouts matter: platform calls can hang while the CPU is briefly
    // saturated (an encode winding down). Without them one hung call
    // latched [_restarting] forever and the preview stayed silent for
    // the rest of the visit.
    const wait = Duration(seconds: 4);
    var retry = false;
    try {
      await _audio.pause().timeout(wait);
      await _audio.seek(Duration(milliseconds: _segStartMs)).timeout(wait);
      if (!mounted) return;
      await _audio.resume().timeout(wait);
      rlog('play: playing from ${_segStartMs}ms');
      _recoverLevel = 0;
      // From here the clock means something, so the fade may darken
      // the frame — starting, correctly, at black.
      _started = true;
      // Re-anchor the word-highlight interpolation clock to the seek,
      // so the loop restart can't briefly light a stale word.
      _lastPos = Duration(milliseconds: _segStartMs);
      _posClock
        ..reset()
        ..start();
      if (mounted) {
        setState(() {
          _ayahIndex = _startAyah - 1;
          // A loop restarts the run as well as the recitation; the
          // position events would get there on their own, a fifth of a
          // second into a scene that is not scene one.
          _sceneIndex = 0;
        });
        if (_multi) _ensureSceneVideo(0);
      }
    } on TimeoutException {
      rlog('play: TIMEOUT (recover level $_recoverLevel)');
      retry = true;
    } catch (e) {
      // Player can throw if the app is mid-backgrounding; next lifecycle
      // resume will retry.
      rlog('play: error $e');
    } finally {
      _restarting = false;
    }
    if (retry && mounted) {
      // Escalate: one plain retry, then swap the player out — a
      // timeout usually means MediaPlayer is in its error state and
      // no amount of retrying revives it.
      if (_recoverLevel == 0) {
        _recoverLevel = 1;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _playSegment();
        });
      } else {
        _hardResetPlayer(thenPlay: true);
      }
    }
  }

  /// Finger delta -> alignment delta. Dividing by the free space
  /// (frame height minus overlay height) makes the overlay track the
  /// finger 1:1, because Align places the child at freeSpace * align —
  /// the same formula FFmpeg uses ((H-h)*yFrac), so where the user
  /// drops the verse is exactly where it lands in the exported mp4.
  void _onDragUpdate(DragUpdateDetails d, BoxConstraints box) =>
      _moveVerseBy(d.delta.dy, box);

  /// The text sizes the slider offers, which a pinch keeps to.
  static const _textScales = (min: 0.7, max: 1.5);

  /// Set when the verse's own fingers sized it, so lifting them settles
  /// the size (the lines are cut again for it) and not only the place.
  bool _verseSized = false;

  void _settleVerse() {
    if (_verseSized) {
      _verseSized = false;
      _setTextScale(_textScale, done: true);
    }
    _onDragEnd();
  }

  /// A double tap on the verse: its text back to its own size.
  void _resetTextScale() {
    if (_textScale == 1.0) return;
    HapticFeedback.selectionClick();
    _setTextScale(1.0, done: true);
  }

  void _moveVerseBy(double dy, BoxConstraints box) {
    final overlayH = _overlayHeight ?? box.maxHeight * 0.35;
    final geo = _box;
    // The drag covers whatever the verse is free to move in: the whole
    // frame, or — in letterbox — the band below the card.
    final travel = geo == null
        ? box.maxHeight
        : geo.bandHeight * box.maxWidth / LetterboxGeometry.frameW;
    final free = (travel - overlayH).clamp(1.0, double.infinity);
    setState(() {
      _hasDragged = true;
      _overlayAlign = (_overlayAlign + dy / free).clamp(0.0, 1.0);
    });
  }

  /// Abandons the in-flight render: drops the job AND kills its FFmpeg
  /// session. Leaving the encode running would eat every core and
  /// freeze playback (worst on the second visit to this screen).
  ///
  /// Unless [restart] is false, a fresh eager render is queued for the
  /// new styling. Dropping without requeuing is what made Save slow:
  /// every tweak — and, on voices with word timings, the highlight plan
  /// landing after the first eager render had already started — left
  /// the screen with no render at all, so Save paid for a cold one.
  void _dropRender({bool restart = true}) {
    _eagerTimer?.cancel();
    final old = _renderJob;
    _renderJob = null;
    if (old != null) {
      rlog('render: dropping in-flight render');
      // One still waiting to start its encode stops there.
      _droppedGen = _jobGen;
      VideoRenderer.cancelActive();
      // Nobody awaits an abandoned job; swallow its cancellation error.
      old.catchError((_) => File(''));
    }
    if (restart) _scheduleEager();
  }

  /// Queues the silent render that makes Share/Save instant.
  ///
  /// Delayed rather than immediate for the reason the first one always
  /// was: an encode starting the moment playback does starves the
  /// preview of CPU. The delay doubles as a debounce — dragging the
  /// verse or scrubbing the size slider re-queues instead of kicking
  /// off an encode per frame of the gesture.
  void _scheduleEager() {
    _eagerTimer?.cancel();
    _eagerTimer = Timer(const Duration(seconds: 2), () {
      // _busy means an export is running and owns the render; _renderJob
      // means one is already in flight for the current styling. A reel
      // with a clip too short for its turn has no export to warm up:
      // it is not allowed to finish on a frozen or looping scene, so
      // the encode would only be thrown away.
      if (!mounted ||
          _recitation == null ||
          _busy ||
          _renderJob != null ||
          _shortScenes.isNotEmpty) {
        return;
      }
      // A long reel's encode is minutes of the phone's whole attention.
      // Warming one up silently, on the chance the user taps Share, is
      // a battery bill they never agreed to — so past a few minutes the
      // reel is rendered when it is asked for, behind the progress bar
      // the user is already watching.
      if (_reelMs > ReelLimits.eagerRenderMaxMs) {
        rlog('render: reel too long to pre-render — waiting for export');
        return;
      }
      // Nor on a phone short of memory, where this encode beside the
      // preview's decoders is what the system killed the app for.
      if (!PhoneBudget.now.rendersAhead) {
        rlog('render: ${PhoneBudget.now.name} budget — waiting for export');
        return;
      }
      rlog('render: eager render starting');
      // Nobody awaits it; a cancellation here is expected, not a fault.
      // A failure is forgotten with the job, so Save renders afresh
      // rather than failing at once with this one's stale error.
      final job = _ensureRender();
      job.catchError((Object _) {
        if (identical(_renderJob, job)) _renderJob = null;
        return File('');
      });
    });
  }

  /// The reel on screen is no longer the reel the current render would
  /// produce, so that render is worth nothing — unless someone is
  /// waiting on it.
  ///
  /// Every styling control on this screen stays live during an export,
  /// and dropping the render mid-export is not a no-op: it cancels the
  /// FFmpeg session, the awaiting export catches [RenderCancelled],
  /// and a cancelled render is deliberately silent — it is what
  /// leaving the screen does. So a nudge of the size slider while the
  /// progress bar was running ended the export with no file in the
  /// gallery, no entry in My Reels, and not a word said about either.
  ///
  /// The export owns the render until it is finished: what the user
  /// tapped Save on is the reel they were looking at when they tapped
  /// it. The change shows on screen immediately and takes effect on
  /// the next render, queued the moment the export lets go.
  void _restyled() {
    if (_busy) {
      _restyledWhileBusy = true;
      return;
    }
    _dropRender();
  }

  void _onDragEnd() {
    creationState.setOverlayAlign(_overlayAlign);
    // The eager render used the old position; drop it so the next
    // Share/Save renders at the new one (cache key includes align).
    _restyled();
  }

  /// The screen reader's stand-in for the drag: a tenth of the frame
  /// at a time, settled exactly as a lifted finger settles it.
  void _nudgeOverlay(double by) {
    setState(() {
      _hasDragged = true;
      _overlayAlign = (_overlayAlign + by).clamp(0.0, 1.0);
    });
    _onDragEnd();
  }

  void _setTextScale(double v, {required bool done}) {
    setState(() => _textScale = v);
    if (done) {
      creationState.setTextScale(v);
      _restyled();
      // Bigger type is more lines: the long verses are cut again.
      unawaited(_replanLines());
    }
  }

  /// Drives [_fadeLevel] while the reel fades at its edges.
  ///
  /// Position events arrive every ~200ms and a fade lasts 600, so the
  /// events alone would draw it in three steps. The same wall-clock
  /// interpolation the word highlight uses turns that into a ramp.
  void _startFadeTicker() {
    if (!_effects.fade || _fadeTicker != null) return;
    _fadeTicker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      if (!_started) {
        _fadeLevel.value = 0;
        return;
      }
      final playing = _audio.state == PlayerState.playing;
      final ms = playing
          ? _lastPos.inMilliseconds + _posClock.elapsedMilliseconds
          : _lastPos.inMilliseconds;
      _fadeLevel.value =
          ReelFinish.fadeLevelAt(_effects, ms - _segStartMs, _reelMs);
    });
  }

  void _syncAyah(Duration pos) {
    final rec = _recitation;
    if (rec == null) return;
    final ms = pos.inMilliseconds;
    if (ms >= _reelEndMs) {
      _playSegment();
      return;
    }
    if (_multi) {
      final i = ScenePlan.indexAt(_cuts, ms);
      if (i != _sceneIndex && mounted) {
        setState(() => _sceneIndex = i);
        _ensureSceneVideo(i);
      }
    }
    // Look the playing ayah up by number, not list index: on a
    // range-only recording the table starts at _startAyah, not ayah 1.
    for (final w in rec.timings) {
      if (ms >= w.startMs && ms < w.endMs) {
        if (w.ayah >= _startAyah &&
            w.ayah <= _endAyah &&
            w.ayah - 1 != _ayahIndex &&
            mounted) {
          setState(() => _ayahIndex = w.ayah - 1);
        }
        break;
      }
    }
  }

  /// The voice's near tier for this reel's verses, for the thread and
  /// the light (see [_nearTimes]). Best-effort: without it those verses
  /// are crossed at an even pace, as they always were.
  Future<void> _loadNear() async {
    final rec = _recitation;
    final ayahs = _ayahs;
    if (rec == null || ayahs == null) return;
    final near = await WordAlignService.loadNear(_reciter,
        recitation: rec, ayahs: ayahs);
    if (!mounted || near == null || !identical(rec, _recitation)) return;
    setState(() {
      _nearTimes = VersePlanner.wordTimes(ayahs, near, _startAyah, _endAyah);
      _wordTimes = _mergedTimes;
    });
    // The eager render drew those verses at an even pace.
    if (_motion.thread || _motion.light) _restyled();
  }

  /// What [_breathTimes] was last read for: the recording, the lines and
  /// the verses it covers. The same again is nothing to do.
  String? _breathKey;

  /// The pace of the recording's own pauses for the verses nothing else
  /// times, for the thread and the light (see [_breathTimes]). A voice
  /// with word timing is waited for, so only the verses it leaves out
  /// are read. Best-effort: without it those verses keep the even pace.
  Future<void> _loadBreaths() async {
    final rec = _recitation;
    final ayahs = _ayahs;
    if (rec == null || ayahs == null) return;
    if (!_motion.thread && !_motion.light) return;
    if (WordAlignService.supports(_reciter) &&
        _spans == null &&
        !_spansFailed) {
      return;
    }
    final sure = _trueTimes, near = _nearTimes;
    final plan = _linePlan;
    final wanted = [
      for (var a = _startAyah; a <= _endAyah; a++)
        if (sure?[a] == null && near?[a] == null) a,
    ];
    final key = '${identityHashCode(rec)}|${plan?.fingerprint ?? ''}|'
        '${wanted.join(',')}';
    if (key == _breathKey) return;
    _breathKey = key;
    // What was read for other lines, or other verses, is not for these.
    if (_breathTimes != null) {
      setState(() {
        _breathTimes = null;
        _wordTimes = _mergedTimes;
      });
      _restyled();
    }
    if (wanted.isEmpty) return;
    final env = await RecitationService.loudness(rec.audioPath);
    if (!mounted || env == null || key != _breathKey) return;
    final times = BreathPace.reelTimes(
      env: env,
      recitation: rec,
      ayahs: ayahs,
      startAyah: _startAyah,
      endAyah: _endAyah,
      plan: plan,
      wants: wanted.toSet().contains,
    );
    rlog('breaths: ${times.length} of ${wanted.length} verse(s) paced');
    if (times.isEmpty) return;
    setState(() {
      _breathTimes = times;
      _wordTimes = _mergedTimes;
    });
    // The eager render drew those verses at an even pace.
    _restyled();
  }

  /// Fetches word-timing data for this voice (one-time download shared
  /// by all reciters, cached forever) and derives the highlight plan.
  /// Best-effort: any failure just leaves the whole-ayah card.
  Future<void> _loadHighlight() async {
    if (!WordAlignService.supports(_reciter)) return;
    final spans = await WordAlignService.load(_reciter, _surah,
        recitation: _recitation, ayahs: _ayahs);
    if (!mounted || _recitation == null) return;
    if (spans == null) {
      // No word timing after all: long verses are cut on the pauses.
      _spansFailed = true;
      unawaited(_replanLines());
      return;
    }
    setState(() {
      _spans = spans;
      _trueTimes =
          VersePlanner.wordTimes(_ayahs!, spans, _startAyah, _endAyah);
      _wordTimes = _mergedTimes;
    });
    unawaited(_replanLines());
    final plan = WordAlignService.highlightPlan(
      recitation: _recitation!,
      ayahs: _ayahs!,
      spansByAyah: spans,
      startAyah: _startAyah,
      endAyah: _endAyah,
    );
    if (plan == null) {
      // Too many windows to highlight, but the thread and the light can
      // still follow the words.
      if (_motion.thread || _motion.light) _restyled();
      return;
    }
    rlog('align: highlight ready '
        '(${plan.values.fold<int>(0, (n, l) => n + l.length)} windows)');
    setState(() => _hlPlan = plan);
    // The eager render may already be encoding without the highlight;
    // redo it — unless the user is mid-export, which must not be
    // yanked away (that one reel ships plain).
    if (_wordHl || !_motionChoice.isNone) _restyled();
  }

  void _setPacing(ScenePacing p) {
    if (p == _pacing) return;
    HapticFeedback.selectionClick();
    setState(() => _pacing = p);
    creationState.setPacing(p);
    _replan(drop: true);
    _checkSceneLengths();
  }

  void _setTransition(SceneTransition t) {
    if (t == _transition) return;
    HapticFeedback.selectionClick();
    setState(() {
      _transition = t;
      _fadeMs = ScenePlan.fadeMsFor(_cuts, t);
    });
    creationState.setTransition(t);
    _restyled();
    _checkSceneLengths();
  }

  /// Cycles how much room one scene takes: an even share, double,
  /// triple, back to even.
  ///
  /// No handles and no numbers to type — the segment redraws at its new
  /// width, which is both the control and the readout. Dragging an edge
  /// would be a timeline, and this screen is not one.
  void _cycleWeight(int scene) {
    if (scene < 0 || scene >= _scenes.length) return;
    final now = scene < _weights.length ? _weights[scene] : 1;
    final next = now >= 3 ? 1 : now + 1;
    HapticFeedback.mediumImpact();
    final before = _cuts;
    creationState.setSceneWeight(scene, next);
    setState(() {
      _weights = creationState.sceneWeights;
      _anchors = creationState.sceneAnchors;
    });
    _replan(drop: true);
    _checkSceneLengths();
    // Per-verse cuts land on ayah boundaries, so a reel with a scene
    // for every verse has nothing left to deal: the ribbon reads 2x
    // and the reel is the reel it was. Say the one thing that makes
    // the tap work, and offer it — a control that does nothing and
    // says nothing is the worst of the three.
    if (_pacing != ScenePacing.even && listEquals(before, _cuts)) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(toast(
          L10n.current.extendNeedsEven,
          duration: const Duration(seconds: 3),
          actionLabel: L10n.current.paceEven,
          // The snackbar outlives the screen by a few seconds.
          onAction: () {
              if (mounted) _setPacing(ScenePacing.even);
            },
        ));
    }
  }

  void _setWordHighlight(bool on) {
    setState(() => _wordHl = on);
    creationState.setWordHighlight(on);
    _restyled(); // the export must match what's shown
  }

  String get _surahName => QuranRepository.surahInfo(_surah).nameEnglish;

  /// What to put on screen when an export stopped.
  ///
  /// A [RenderFailed] has already been reduced to a reason, and its
  /// FFmpeg log tail is in the debug log where it belongs: nothing the
  /// encoder prints is of any use to the person holding the phone.
  /// Anything else is an unexpected error, and those still carry their
  /// own text — a bug report is worth more than a tidy sentence.
  static String _exportError(Object e) => switch (e) {
        RenderFailed(kind: RenderFailure.outOfMemory) =>
          L10n.current.exportOutOfMemory,
        RenderFailed(kind: RenderFailure.noSpace) =>
          L10n.current.phoneStorageFull,
        RenderFailed() => L10n.current.exportUnfinished,
        // A verse card or a copy that could not be written for want of
        // room is the same full phone, met one step earlier or later.
        _ when saysOutOfSpace(e) => L10n.current.phoneStorageFull,
        _ => L10n.current.exportFailed(e),
      };

  /// [origin] anchors the iOS share sheet and is measured at tap time,
  /// not here: the render in between can take long enough that relying
  /// on the button still being laid out is not safe. [direct] sends the
  /// reel straight into one app — picked from Share to — instead.
  Future<void> _export({
    required bool shareAfter,
    _DirectShare? direct,
    Rect? origin,
  }) async {
    // Resolved now, while the tree is still laid out and the render has
    // not started — never after the awaits below.
    final shareOrigin = origin ?? shareOriginOf(context);
    // Same reason, and a sharper one: an encode takes half a minute,
    // and a widget on its way out is *deactivated* before it is
    // unmounted. In that window `mounted` still answers true while an
    // ancestor lookup throws, so a guard cannot save a `of(context)`
    // made after the await — only holding the messenger from before it
    // can. ("Looking up a deactivated widget's ancestor is unsafe.")
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _rendering = true;
      _renderProgress = 0;
    });
    final File file;
    // Marked for as long as the user waits on it: if the app dies in
    // between, the next launch knows an export did that here, and plans
    // smaller from then on. See [PhoneBudget].
    await PhoneBudget.exportStarted();
    unawaited(RenderProcess.keepScreenOn(true));
    try {
      // Instant when the eager render (or a previous Save/Share with
      // the same styling) already produced this exact file. When it
      // didn't — first tap, or a styling change dropped it — this is
      // the render the user actually waits on, so it runs unthrottled.
      File made;
      try {
        made = await _ensureRender(foreground: true);
      } on RenderFailed catch (e) {
        // A file the render had made itself (a verse card, the
        // flattened backdrop) gone before FFmpeg opened it: Android
        // clears the cache folder of a nearly full phone whenever it
        // likes. Rendered once more, which makes whatever is missing
        // again; anything else fails as it always did.
        if (!e.detail.contains('No such file or directory')) rethrow;
        rlog('render: an input vanished ($e) — rendering once more');
        _renderJob = null;
        made = await _ensureRender(foreground: true);
      }
      // A render kept from earlier whose file the system has since
      // cleared out of the cache: made again, rather than every Save
      // failing until the styling changes.
      if (!made.existsSync()) {
        _renderJob = null;
        made = await _ensureRender(foreground: true);
      }
      file = made;
    } catch (e, s) {
      _renderJob = null; // allow retry after a failure
      unawaited(PhoneBudget.exportEnded());
      unawaited(RenderProcess.keepScreenOn(false));
      if (!mounted) return;
      setState(() {
        _rendering = false;
        _busy = false;
      });
      // A canceled render (styling changed mid-export, screen left) is
      // not a failure the user needs to hear about.
      if (e is! RenderCancelled) {
        rlogError('render', e, s);
        FeedbackService.noteExportTrouble('render', e);
        // A full phone is not ours to hear about: the sentence already
        // says what fixes it, and it is long enough to need the time.
        final full = (e is RenderFailed && e.kind == RenderFailure.noSpace) ||
            saysOutOfSpace(e);
        messenger.showSnackBar(
          toast(
            full ? L10n.current.phoneStorageFull : _exportError(e),
            tone: ToastTone.problem,
            duration: const Duration(seconds: 8),
            actionLabel: full ? null : L10n.current.reportProblem,
            onAction: _openReport,
          ),
        );
      }
      return;
    }
    unawaited(PhoneBudget.exportEnded());
    unawaited(RenderProcess.keepScreenOn(false));
    if (mounted) setState(() => _rendering = false); // encode is done

    try {
      // Keep a copy inside the app so the reel shows up in My Reels on
      // the next launch, whether the user shared or saved.
      final saved = await _saveToLibrary(file);
      if (!mounted) {
        // Back pressed while the copy was made, after the progress bar
        // had gone: Save still means the gallery. Its messages are
        // already guarded; the share sheet has no screen to open from.
        if (!shareAfter && !(saved?.inGallery ?? false)) {
          await _writeToGallery(file, saved);
        }
        return;
      }
      if (shareAfter) {
        // A dedicated reel is being handed to a person rather than
        // posted to a feed, so it goes with a message written to them
        // — and that message carries the two store links, because a
        // gift nobody can answer with one of their own is a gift that
        // stops where it lands.
        final caption = _dedication.isEmpty
            ? L10n.current.reelShareCaption(_surahName, _reciter.name)
            : L10n.current
                .dedicationShareMessage(_dedication.kind, _dedication.name);
        // Straight into the app the user picked when they picked one;
        // anything that stops the hand-off (app not installed, wrong
        // platform, a platform error) falls back to the share sheet.
        // Instagram gets no caption: its composer asks for one itself,
        // on the screen it opens on.
        var handed = false;
        switch (direct) {
          case _DirectShare.whatsapp:
            handed = await WhatsAppShare.shareVideo(file,
                text: PlatformShare.caption(ShareTarget.whatsapp,
                    line: caption, surahName: _surahName));
            if (!handed && mounted) {
              messenger.showSnackBar(
                toast(
                  L10n.current.whatsappUnavailable,
                  tone: ToastTone.problem,
                ),
              );
            }
          case _DirectShare.instagramReel:
          case _DirectShare.instagramStory:
            // The caption box Instagram opens on is empty: the line and
            // its tags are on the clipboard, one paste away.
            await PlatformShare.copy(PlatformShare.caption(
                ShareTarget.instagramReel,
                line: caption,
                surahName: _surahName));
            handed = direct == _DirectShare.instagramStory
                ? await InstagramShare.shareStoryVideo(file)
                : await InstagramShare.shareReel(file);
            if (mounted) {
              messenger.showSnackBar(
                handed
                    ? toast(L10n.current.shareCaptionCopied,
                        tone: ToastTone.done)
                    : toast(
                        L10n.current.instagramUnavailable,
                        tone: ToastTone.problem,
                      ),
              );
            }
          case _DirectShare.tiktok:
          case _DirectShare.youtube:
          case _DirectShare.facebook:
            final target = switch (direct) {
              _DirectShare.tiktok => ShareTarget.tiktok,
              _DirectShare.facebook => ShareTarget.facebook,
              _ => ShareTarget.youtube,
            };
            final app = target.app(L10n.current);
            final text = PlatformShare.caption(target,
                line: caption, surahName: _surahName);
            await PlatformShare.copy(text);
            if (Platform.isIOS) {
              // iOS hands neither app a video from another app without
              // its own SDK: the reel goes into the library, where the
              // app's picker shows it first, and the app is opened.
              final inGallery = (saved?.inGallery ?? false) ||
                  await _writeToGallery(file, saved);
              handed = inGallery && await PlatformShare.send(target, file);
              if (handed && mounted) {
                messenger.showSnackBar(toast(
                  L10n.current.shareOpenHint(app),
                  tone: ToastTone.done,
                  duration: const Duration(seconds: 9),
                ));
              }
            } else {
              // YouTube reads the title off the hand-off: the caption
              // itself, which is cut to fit a Short's title.
              handed = await PlatformShare.send(target, file,
                  text: text,
                  title: target == ShareTarget.youtube
                      ? text
                      : '$_surahName · ${_reciter.name}');
              if (handed && mounted) {
                messenger.showSnackBar(toast(
                  L10n.current.shareCaptionCopied,
                  tone: ToastTone.done,
                ));
              }
            }
            if (!handed && mounted) {
              messenger.showSnackBar(toast(
                L10n.current.shareAppMissing(app),
                tone: ToastTone.problem,
              ));
            }
          case null:
            break;
        }
        if (!handed) {
          await SharePlus.instance.share(ShareParams(
            files: [XFile(file.path)],
            text: caption,
            sharePositionOrigin: shareOrigin,
          ));
        }
        RewardsService.recordShared();
      } else if (saved != null && saved.inGallery) {
        // The gallery has no overwrite: putting identical bytes a
        // second time leaves "… (1).mp4" next to the first and the
        // folder grows a copy per tap. The reel is already there, so
        // say so rather than write it again — but this app's word is
        // not the last one on what is in the user's gallery. They can
        // delete it there, and then Save did nothing at all, for good.
        // So the offer to write it anyway stays one tap away.
        messenger.showSnackBar(
          toast(
            L10n.current.alreadyInGallery,
            actionLabel: L10n.current.saveAgain,
            onAction: () => _writeToGallery(file, saved),
          ),
        );
      } else if (!await _writeToGallery(file, saved)) {
        return; // the failure has already been reported
      }
      // The tags first: they belong to the post the user is about to
      // write, and everything below belongs to the app.
      if (mounted) {
        await offerHashtagsAfterExport(context, surahName: _surahName);
      }
      // Peak moment: they just finished a reel they liked. This is
      // when the daily-reminder invitation converts — and it
      // self-limits (snoozes on "not now", stops after two declines).
      // It is also the only moment worth spending a rating ask on:
      // see [_offerAfterExport] for how the two share it.
      if (mounted) _offerAfterExport(context);
      unawaited(TelegramInvite.after(TelegramMoment.reel));
    } catch (e, s) {
      // The render already succeeded by here, so this is the share
      // sheet or the gallery write — say which, rather than blaming
      // the export the user watched finish.
      rlogError(shareAfter ? 'reel share' : 'gallery save', e, s);
      FeedbackService.noteExportTrouble(shareAfter ? 'share' : 'save', e);
      if (mounted) {
        messenger.showSnackBar(
          toast(
            shareAfter ? L10n.current.shareFailed(e) : _exportError(e),
            tone: ToastTone.problem,
            duration: const Duration(seconds: 8),
            actionLabel: L10n.current.reportProblem,
            onAction: _openReport,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Whatever was changed while the export held the render, put
        // it into the next one — now that dropping it costs nobody
        // their file. See [_restyled].
        if (_restyledWhileBusy) {
          _restyledWhileBusy = false;
          _dropRender();
        }
      }
    }
  }

  /// The three things allowed to ask the user for something once a
  /// reel has landed — and never two of them on the same reel.
  ///
  /// The order is by what each one costs to postpone:
  ///
  ///  1. **The reminder invitation.** Ours and repeatable, but it is
  ///     the only one that changes what the app does tomorrow, so it
  ///     takes the moment first.
  ///  2. **The rating ask.** Cannot be postponed cheaply — iOS hands
  ///     out three a year and says nothing about whether any of them
  ///     appeared — so it fires on the first export where nothing else
  ///     is on screen.
  ///  3. **The feedback sheet.** Last, because it is entirely ours,
  ///     costs nothing to repeat, and has a permanent Settings row
  ///     behind it either way. It also asks for typing, which is the
  ///     largest thing any of these asks of somebody who just wanted
  ///     to save a reel.
  ///
  /// Whichever one takes the moment, the export is still counted by
  /// all three — a skipped ask slides to the next reel rather than
  /// being spent.
  ///
  /// [ReviewAsk.native] has already happened by the time this sees it.
  /// [ReviewAsk.banner] is ours to put on screen, and only ever
  /// arrives on Android — on iOS nothing of ours may open itself, so
  /// it never comes back. See [ReviewPrompt.decide].
  ///
  /// Deliberately not awaited by the export: all of this outlives the
  /// progress bar, and holding the Save button busy behind a dialog
  /// the user may sit on would make the export look unfinished.
  Future<void> _offerAfterExport(BuildContext context) async {
    // A tenth reel is its own moment: the card of every verse made so
    // far, and nothing else asked of the user this time.
    final milestone = _milestone;
    if (milestone != null) {
      _milestone = null;
      final shown = await offerVersesMilestone(
        context,
        reels: milestone,
        onSee: () {
          // Out of the making of this reel, to the card on the Reels
          // tab: the reel is saved, and the card is where it shows.
          if (!mounted) return;
          Navigator.of(this.context).popUntil((r) => r.isFirst);
          HomeShell.versesRequests.value++;
        },
      );
      if (shown) return;
    }
    if (!context.mounted) return;
    final busy = await ReminderService.offerAfterExport(context);
    final ask = await ReviewPrompt.offerAfterExport(mayAsk: !busy);
    // `native` counts as spent as much as `banner` does: the OS sheet
    // may be on screen right now and nothing here can know.
    final taken = busy || ask != ReviewAsk.none;
    if (ask == ReviewAsk.banner) {
      if (!context.mounted) return;
      await showRateSheet(context);
    }
    if (!await FeedbackService.offerAfterRender(mayAsk: !taken)) return;
    if (!context.mounted) return;
    await showFeedbackSheet(context, source: FeedbackSource.afterRender);
  }

  /// Writes the finished reel into the device gallery and says how it
  /// went. Returns whether it landed.
  ///
  /// Never throws: a gallery write has its own failure modes — access
  /// the OS won't grant, an album path a phone refuses — and each one
  /// needs its own answer. Reporting them as "Export failed" told the
  /// user the render broke, which it hadn't, and offered no way out.
  Future<bool> _writeToGallery(File file, SavedReel? saved) async {
    final result = await GallerySaver.save(
      file,
      name: 'AyahReel $_surahName $_startAyah-$_endAyah',
    );
    if (!result.ok) {
      FeedbackService.noteExportTrouble(
          'gallery ${result.status.name}', result.error ?? '');
    }
    if (!mounted) {
      // Nobody is left to tell, but the library still has to know, or
      // the next Save writes a second copy.
      if (result.ok && saved != null) {
        await ReelLibrary.markInGallery(saved);
      }
      return result.ok;
    }
    final messenger = ScaffoldMessenger.of(context);
    switch (result.status) {
      case GallerySaveStatus.saved:
        if (saved != null) _saved = await ReelLibrary.markInGallery(saved);
        // The captured messenger, not a fresh lookup: marking the
        // library entry is another await, and the same deactivated-
        // ancestor window applies to it.
        messenger.showSnackBar(
          toast(
            saved == null
                // The gallery has it; the app does not. Saying "Saved
                // to Gallery and My Reels" here would be the app
                // telling the user where to find a copy it failed to
                // make.
                ? L10n.current.savedToGalleryOnly
                : L10n.current.savedToGallery(RewardsService.pointsPerReel),
            tone: ToastTone.done,
          ),
        );
        return true;
      case GallerySaveStatus.denied:
        // Nothing the app can do from here: a permission refused for
        // good never prompts again, so settings is the only route.
        rlogError('gallery save', result.error ?? 'access denied',
            StackTrace.current);
        messenger.showSnackBar(toast(
          L10n.current.galleryWriteBlocked,
          tone: ToastTone.problem,
          duration: const Duration(seconds: 8),
          actionLabel: L10n.current.openSettings,
          onAction: _openAppSettings,
        ));
        return false;
      case GallerySaveStatus.failed:
        rlogError(
            'gallery save', result.error ?? 'unknown', StackTrace.current);
        messenger.showSnackBar(
          toast(
            result.outOfSpace
                  ? L10n.current.phoneStorageFull
                  : L10n.current.saveFailed(result.error ?? ''),
            tone: ToastTone.problem,
            duration: const Duration(seconds: 8),
            actionLabel: result.outOfSpace ? null : L10n.current.reportProblem,
            onAction: _openReport,
          ),
        );
        return false;
    }
  }

  /// The Report button on a save that went wrong. It used to say
  /// "report it in Settings → Feedback" instead, which asked someone
  /// whose reel had just failed to find a screen and describe a failure
  /// they could not see the cause of. The sheet opens written, and the
  /// note carries what happened (see [FeedbackService.noteExportTrouble]),
  /// so Report and then Send is the whole of it. A full phone gets no
  /// button: its message already says what fixes it.
  void _openReport() {
    if (mounted) {
      showFeedbackSheet(context, source: FeedbackSource.exportTrouble);
    }
  }

  Future<void> _openAppSettings() async {
    HapticFeedback.selectionClick();
    try {
      // The app's own settings page: media/photos permissions live
      // there on both platforms.
      await os_settings.AppSettings.openAppSettings(
          type: os_settings.AppSettingsType.settings);
    } catch (_) {/* nothing useful to say if the OS refuses */}
  }

  Future<SavedReel?> _saveToLibrary(File file) async {
    if (_libraryPath == file.path) return _saved; // this render already saved
    try {
      final sourceKey = VideoRenderer.sourceKeyOf(file);
      // Whether this reel is new has to be settled before the add,
      // which returns the existing entry for a repeat export.
      final existing = await ReelLibrary.findBySource(sourceKey);
      final isNew = existing == null;
      // Kept from before 2026-10-13 and too heavy to play: this render
      // takes its place, and goes to the gallery again.
      if (existing != null &&
          VideoRenderer.tooHeavyToPlay(
              await ReelLibrary.videoFile(existing), _reelMs) &&
          !VideoRenderer.tooHeavyToPlay(file, _reelMs)) {
        rlog('library: the kept reel is too heavy to play — replaced');
        await ReelLibrary.replaceVideo(existing, file);
      }
      final reel = await ReelLibrary.add(
        video: file,
        sourceKey: sourceKey,
        reciterName: _reciter.name,
        surahName: _surahName,
        startAyah: _startAyah,
        endAyah: _endAyah,
        gradientArgb: _background.gradientArgb,
        // Everything that made this reel, so it can be opened again.
        // The trim lives only on this screen, so it travels with it
        // here rather than through the state.
        recipe: ReelRecipe.capture(creationState, trimMs: _trimMs),
      );
      _libraryPath = file.path;
      _saved = reel;
      // A finished reel = points + streak, once per reel — not once
      // per export of a reel they already have.
      if (isNew) {
        RewardsService.recordReelCreated().then((badge) {
          final made = RewardsService.state.value.reelsMade;
          if (made > 0 && made % 10 == 0) _milestone = made;
          // A milestone reel says so, after the save's own line.
          if (badge == null || !mounted) return;
          final l = L10n.current;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(
            l.badgeEarned(l.badgeName(badge.id)),
            tone: ToastTone.done,
          ));
        });
      }
      return reel;
    } catch (e, s) {
      // Library copy is best-effort; never block the share/save itself.
      // But it is not free either: the copy is a second whole mp4 on a
      // device that may have no room for one, and swallowing that in
      // silence is what leaves someone searching My Reels for a reel
      // the app was never able to keep. So it is logged, and the save
      // says what actually happened — see [_writeToGallery].
      rlogError('library copy', e, s);
      return null;
    }
  }

  @override
  void dispose() {
    rlog('screen: dispose');
    WidgetsBinding.instance.removeObserver(this);
    // Kill any render still running: otherwise going back and re-entering
    // stacks concurrent FFmpeg encodes until the phone freezes. Nothing
    // to requeue — the screen is gone.
    _dropRender(restart: false);
    // The player is shared across visits (see its declaration): stop it
    // and detach this screen's listeners, but never dispose it.
    _posSub?.cancel();
    _endSub?.cancel();
    _evtSub?.cancel();
    _clockTicker.dispose();
    _clock.dispose();
    _fadeTicker?.cancel();
    _fadeLevel.dispose();
    _planned.dispose();
    _audio.stop().catchError((_) {});
    for (final c in _sceneVideo.values) {
      c.dispose();
    }
    _sceneVideo.clear();
    super.dispose();
  }

  /// The scenery playing now, cover-fitted — the same fill FFmpeg's
  /// `scale=…:increase,crop` produces, so an uploaded photo or video
  /// previews exactly as it will export.
  ///
  /// A run of sceneries hands over here exactly as the exporter hands
  /// over: at the same millisecond, over the same [_fadeMs]. A cut is
  /// a blend of nothing, which is what a zero duration switcher is.
  Widget _scenery() {
    // Graded outside the switcher, not inside it: one filter over the
    // crossfade rather than one over each half of it, and a blend of
    // two graded frames is the same picture as a graded blend — which
    // is the same reasoning that lets the exporter scrim a run of
    // scenes before it joins them.
    return ReelFinish.graded(
      _effects,
      AnimatedSwitcher(
        duration: Duration(milliseconds: _fadeMs),
        child: KeyedSubtree(
          key: ValueKey(_sceneIndex),
          child: _sceneryAt(_sceneIndex),
        ),
      ),
    );
  }

  Widget _sceneryAt(int i) {
    final scene = _scenes[i.clamp(0, _scenes.length - 1)];
    final video = _sceneVideo[i];
    final gradient = scene.gradientArgb;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(gradient[0]), Color(gradient[1])],
            ),
          ),
        ),
        if (scene.isImage)
          scene.isDeviceFile
              ? Image.file(File(scene.filePath!),
                  fit: BoxFit.cover, excludeFromSemantics: true)
              : Image.asset(scene.imageAsset,
                  fit: BoxFit.cover, excludeFromSemantics: true)
        else if (video != null)
          // Some devices report a 0x0 size briefly; fall back to a
          // stretch fill until real dimensions arrive.
          video.value.size.width > 0
              ? FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: video.value.size.width,
                    height: video.value.size.height,
                    child: VideoPlayer(video),
                  ),
                )
              : VideoPlayer(video),
      ],
    );
  }

  /// Everything under the verse: full frame it is the scenery plus the
  /// legibility scrim; letterbox it is the backdrop with the card laid
  /// on top, at the geometry the exporter will use.
  List<Widget> _backdropLayers(BoxConstraints box) {
    final geo = _box;
    final vignette = ReelFinish.vignette(_effects);
    if (geo == null) {
      return [
        _scenery(),
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AyahRasterizer.scrimGradient),
        ),
        if (vignette != null) vignette,
      ];
    }
    final s = box.maxWidth / LetterboxGeometry.frameW;
    return [
      if (_backdrop == LetterboxBackdrop.colour)
        ColoredBox(color: Color(_backdropArgb))
      else if (_backdrop == LetterboxBackdrop.glow)
        BandGlowGround(glow: _bandGlow, box: geo)
      else
        // The exporter blurs at a twelfth scale and lets the upscale
        // smooth the rest, which lands around this radius in full-frame
        // pixels; the matrix is the exporter's own, off the one class
        // that owns it, so the band cannot tone differently here.
        //
        // And the preview now does the same trick. The scenery is laid
        // out at a sixth of the frame, blurred there with a sixth of
        // the radius, and scaled back up with bilinear sampling — so
        // the blur runs over a few thousand pixels a frame instead of
        // the whole frame's worth of live video. Same picture, and the
        // one thing on this screen that used to make a 60 fps preview
        // drop to 30 on a mid-range phone.
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.scale(
              scale: _blurShrink,
              alignment: Alignment.topLeft,
              filterQuality: FilterQuality.low,
              child: SizedBox(
                width: box.biggest.width / _blurShrink,
                height: box.biggest.height / _blurShrink,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(BackdropTone.colorMatrix),
                  child: ImageFiltered(
                    // Clamp, not decal: decal samples the outside of the
                    // frame as transparent, so the outer ~200px of every
                    // edge faded toward the void — invisible on a dark
                    // scenery, a grey vignette on a bright one, and
                    // nothing like the export, where gblur extends the
                    // edge pixels instead. Clamp is what FFmpeg does.
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 72 * s / _blurShrink,
                      sigmaY: 72 * s / _blurShrink,
                      tileMode: TileMode.clamp,
                    ),
                    child: _scenery(),
                  ),
                ),
              ),
            ),
          ),
        ),
      Positioned(
        left: geo.cardX * s,
        top: geo.cardY * s,
        width: geo.cardW * s,
        height: geo.cardH * s,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
              _rounded ? LetterboxGeometry.radius * s : 0),
          child: _scenery(),
        ),
      ),
      // Over the whole frame, card and band alike: light falling off
      // at the corners of a film frame does not stop at the edge of
      // the photograph inside it, and the exporter lays exactly this
      // PNG in exactly this place.
      if (vignette != null) Positioned.fill(child: vignette),
    ];
  }

  /// The card's height, and a rebuild if the mark is hanging off it.
  ///
  /// This used to be a number the drag maths read later, so parking it
  /// in a field was enough. In full frame the mark now sits under the
  /// card's bottom edge, so a card that changes height moves something
  /// already on screen. It arrives from [_MeasureHeight] during layout,
  /// which is too late to call setState in — hence the wait for the
  /// frame to finish. Not a loop: the measure only reports on a real
  /// change, and the rebuild does not cause one.
  void _onOverlayHeight(double h) {
    _overlayHeight = h;
    if (_box != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Bottom edge of the verse card in export-frame coordinates — what
  /// the full-frame mark hangs off, and the same arithmetic the
  /// exporter runs on the rasterized card's height.
  ///
  /// Null in letterbox, where the mark answers to the picture and not
  /// to the verse, and null until the card has laid out once.
  double? _verseBottom(BoxConstraints box) {
    if (_box != null) return null;
    final h = _overlayHeight;
    if (h == null) return null;
    final cardH = h * LetterboxGeometry.frameW / box.maxWidth;
    return (LetterboxGeometry.frameH - cardH) * _overlayAlign + cardH;
  }

  /// The verse card, placed where the exporter will place it: anywhere
  /// in the frame when full, anywhere in the band below the card when
  /// letterboxed. Both are an [Alignment] over a box, which is exactly
  /// the arithmetic [LetterboxGeometry.verseTop] mirrors for FFmpeg.
  Widget _verseLayer(BoxConstraints box) {
    final geo = _box;
    final s = box.maxWidth / LetterboxGeometry.frameW;
    // The card is laid out at its own height and placed by the same
    // arithmetic FFmpeg is given — `(box - h) * align`, unclamped —
    // which is what [OverflowBox] does with an infinite height budget
    // and this alignment. A plain Align squeezes instead: the band
    // below a letterbox card is a few hundred pixels tall, and a verse
    // at the largest text size does not fit in it, so the card came
    // back shorter than the export's and Flutter drew the striped
    // overflow bar across the preview. Nothing clips here: a verse
    // taller than its box overhangs exactly as it will in the file,
    // and only the frame's own edge cuts it off.
    final verse = OverflowBox(
      alignment: Alignment(0, _overlayAlign * 2 - 1),
      minHeight: 0,
      maxHeight: double.infinity,
      // The verse takes its own fingers, laid out exactly as it was (no
      // room added round it, so the card sits where the export puts
      // it): one moves it up and down, two or a corner size its text,
      // a double tap puts the size back. Crop marks frame it while it
      // is touched.
      child: ResizableBox(
        scale: _textScale,
        inset: 3,
        onMove: (d) => _moveVerseBy(d.dy, box),
        onResize: _busy
            ? null
            : (v) {
                _verseSized = true;
                _setTextScale(
                    v.clamp(_textScales.min, _textScales.max), done: false);
              },
        onEnd: _settleVerse,
        onDoubleTap: _busy ? null : _resetTextScale,
        child: VerseStage(
        clock: _clock,
        units: _units,
        ayahs: _ayahs!,
        recitation: _recitation!,
        motion: _motion,
        words: _hlPlan,
        highlight: _wordHl,
        wordTimes: _wordTimes,
        width: box.maxWidth,
        translation: _edition,
        numbering: _numbering,
        showTranslation: _showTranslation,
        surah: _surah,
        textColor: Color(_textArgb),
        accent: Color(_accentArgb),
        ink: _verseInk,
        accentInk: _accentInk,
        textScale: _textScale,
        preset: _preset,
        onLight: _onLight,
        verseFace: _typography.verse,
        translationFace: _typography.translation,
        onHeight: _onOverlayHeight,
        basmala: _basmalaCard,
      ),
      ),
    );
    // Positioned either way, even when the verse has the whole frame:
    // handing the Stack a different widget type once FFprobe answers
    // would move the card's element to a new parent mid-flight, and
    // that is the one thing here that can strand a dependency on an
    // InheritedWidget that is going away.
    if (geo == null) return Positioned.fill(child: verse);
    return Positioned(
      left: 0,
      right: 0,
      top: geo.bandTop * s,
      height: geo.bandHeight * s,
      // Nothing clips at the band: a verse taller than it overhangs
      // here exactly as it will in the export, and only the frame's own
      // edge cuts it off.
      child: verse,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _recitation != null && _ayahs != null;
    final l = L10n.of(context);
    // A clip that cannot cover its own turn has no export: the reel
    // would have to freeze or loop it to finish, and it must not.
    final blocked = _shortScenes.isNotEmpty;
    // The straight-to-an-app shortcuts, each only where its hand-off
    // can actually land.
    final grain = ReelFinish.grain(_effects);
    final igOn = InstagramShare.supported &&
        SettingsService.state.value.instagramDirectShare;
    final waOn =
        Platform.isAndroid && SettingsService.state.value.whatsappDirectShare;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: StepDots(current: WizardSteps.reel, total: WizardSteps.total),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: LayoutBuilder(
                      // The frame is a drag to a finger and an
                      // adjustable value to a screen reader: swipe up
                      // or down and the verse moves a tenth of the
                      // frame. What is inside the frame — the verse,
                      // the preparing state and its retry — stays
                      // readable as its own nodes underneath.
                      builder: (_, box) => Semantics(
                        container: true,
                        explicitChildNodes: true,
                        label: l.a11yReelPreview,
                        value: ready
                            ? l.a11yVersePosition(
                                (_overlayAlign * 100).round())
                            : null,
                        // An adjustable value says what a swipe makes
                        // it, or the semantics tree refuses the node.
                        increasedValue: ready
                            ? l.a11yVersePosition(
                                ((_overlayAlign + 0.1) * 100)
                                    .round()
                                    .clamp(0, 100))
                            : null,
                        decreasedValue: ready
                            ? l.a11yVersePosition(
                                ((_overlayAlign - 0.1) * 100)
                                    .round()
                                    .clamp(0, 100))
                            : null,
                        hint: ready ? l.a11yVersePositionHint : null,
                        onIncrease: ready ? () => _nudgeOverlay(0.1) : null,
                        onDecrease: ready ? () => _nudgeOverlay(-0.1) : null,
                        child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate:
                            ready ? (d) => _onDragUpdate(d, box) : null,
                        onVerticalDragEnd: ready ? (_) => _onDragEnd() : null,
                        // The adjust actions above stand in for the
                        // drag; its own would only add a nameless
                        // scrollable under them.
                        excludeFromSemantics: true,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ..._backdropLayers(box),
                            if (ready)
                              _verseLayer(box)
                            else
                              _PrepOverlay(
                                error: _prepError,
                                trouble: _prepTrouble,
                                progress: _prepProgress,
                                onRetry: _boot,
                              ),
                            // The surah's name, where the exporter lays
                            // it. It takes its own drag, as the
                            // dedication does, so a finger on it moves
                            // it and a finger anywhere else still moves
                            // the verse; a double tap puts it back.
                            if (ready && _titleOn)
                              Positioned.fill(
                                child: ReelSurahTitle(
                                  width: box.maxWidth,
                                  surah: _surah,
                                  edition: _edition,
                                  onLight: _titleOnLight,
                                  look: creationState.surahTitleLook,
                                  at: _titleAt,
                                  letterbox: _box,
                                  scale: _titleScale,
                                  onSize: (size) => _titleSize = size,
                                  onDrag: _busy
                                      ? null
                                      : (d) => _moveTitle(d, box),
                                  onResize: _busy ? null : _resizeTitle,
                                  onDragEnd: _settleTitle,
                                  onReset: _resetTitle,
                                ),
                              ),
                            // Same mark the exporter burns in, same
                            // position — the preview never lies. In
                            // full frame that position follows the
                            // verse card, so it moves with the drag
                            // and with every change of ayah.
                            if (ready)
                              ReelWatermark(
                                width: box.maxWidth,
                                letterbox: _box,
                                verseBottom: _verseBottom(box),
                              ),
                            // And the dedication along the bottom
                            // edge, where the exporter lays it — or
                            // wherever it has been dragged to. It
                            // takes its own drag, so a finger on the
                            // line moves the line and a finger
                            // anywhere else still moves the verse.
                            if (ready)
                              ReelDedication(
                                width: box.maxWidth,
                                line: _dedicationLine,
                                onLight: _dedicationOnLight,
                                at: _dedicationAt,
                                onLineSize: (size) =>
                                    _dedicationLineSize = size,
                                onDrag: _busy
                                    ? null
                                    : (d) => _moveDedication(d, box),
                                onDragEnd: _settleDedication,
                                onReset: _resetDedication,
                              ),
                            // The reader has the same advice in the
                            // frame's own hint, so the pill is for
                            // the eye alone. It lifts off the bottom
                            // edge when a dedication is written there,
                            // rather than sit on top of it.
                            if (ready && !_hasDragged)
                              ExcludeSemantics(
                                child: Align(
                                alignment: Alignment(
                                    0, _dedicationLine.isEmpty ? 0.92 : 0.82),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.black
                                        .withValues(alpha: 0.45),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.swap_vert_rounded,
                                          size: 16,
                                          color: AppColors.textSecondary),
                                      const SizedBox(width: 6),
                                      Text(
                                        l.dragToMoveVerse,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                ),
                              ),
                            // Over everything, as the exporter lays
                            // them: a film stock's grain sits on the
                            // type as much as on the picture, and a
                            // reel fading to black takes the verse
                            // with it.
                            if (grain != null) Positioned.fill(child: grain),
                            if (ready && _effects.fade)
                              Positioned.fill(
                                child: ValueListenableBuilder<double>(
                                  valueListenable: _fadeLevel,
                                  builder: (_, level, __) =>
                                      ReelFinish.fade(level),
                                ),
                              ),
                          ],
                        ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
              child: Column(
                children: [
                  // What you do to a finished reel, right under its
                  // edge: the tags it is posted with, the surah's name
                  // on it, how its verses move, and who it was made
                  // for. They wrap on a narrow phone rather than
                  // squeezing. The colours and the type are the style
                  // step's, one screen back, where they are set against
                  // the scenery rather than over a playing reel.
                  Center(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        HashtagsButton(surahName: _surahName),
                        _TitlePill(
                          on: _titleOn,
                          onTap: ready ? _toggleTitle : null,
                        ),
                        _MotionPill(
                          motion: _motionChoice,
                          onTap: ready ? _pickMotion : null,
                        ),
                        _DedicatePill(
                          dedication: _dedication,
                          line: _dedicationLine,
                          onTap: ready ? _dedicate : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // The scene run: one line that says what it does,
                  // and opens onto the two things that can be said
                  // about it. Absent entirely from a reel with one
                  // scenery, which is most of them.
                  if (_multi) ...[
                    _SceneControls(
                      cuts: _cuts,
                      current: _sceneIndex,
                      pacing: _pacing,
                      transition: _transition,
                      open: _scenesOpen,
                      shortScenes: _shortScenes.length,
                      onToggle: () {
                        HapticFeedback.selectionClick();
                        setState(() => _scenesOpen = !_scenesOpen);
                      },
                      onPacing: ready ? _setPacing : null,
                      onTransition: ready ? _setTransition : null,
                      onWeigh: ready ? _cycleWeight : null,
                      weights: _weights,
                      onAddScenes: () =>
                          Navigator.of(context).pop(PreviewScreen.addScenes),
                      hasLines: _linePlan != null,
                      // The reel's length lives under the ribbon: the
                      // scene panel is where this reel's shape is
                      // settled, and where it ends is part of that.
                      fullMs: ready ? _fullMs : 0,
                      reelMs: ready ? _reelMs : 0,
                      onTrim: ready && _canTrim ? _setTrim : null,
                      onTrimEnd: _trimSettled,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      // The two "Aa" are the slider's ends, not words
                      // to read; the slider is named instead, and
                      // says its size as a percentage.
                      const ExcludeSemantics(
                        child: Text('Aa',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        child: MergeSemantics(
                          child: Semantics(
                            label: l.a11yTextSize,
                            child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 1.5,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 11),
                          ),
                          child: Slider(
                            value: _textScale,
                            min: _textScales.min,
                            max: _textScales.max,
                            activeColor: AppColors.gold,
                            inactiveColor: AppColors.surfaceRaised,
                            semanticFormatterCallback: (v) =>
                                '${(v * 100).round()}%',
                            onChanged: ready
                                ? (v) => _setTextScale(v, done: false)
                                : null,
                            onChangeEnd: (v) =>
                                _setTextScale(v, done: true),
                          ),
                        ),
                          ),
                        ),
                      ),
                      const ExcludeSemantics(
                        child: Text('Aa',
                            style: TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                  if (_hlPlan != null) ...[
                    const SizedBox(height: 2),
                    // One switch, named by the line beside it.
                    MergeSemantics(
                      child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l.highlightRecitedWord,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                        const SizedBox(width: 2),
                        // Scaled, not rebuilt: the switch keeps its own
                        // full-size touch target under a smaller paint.
                        Transform.scale(
                          scale: 0.72,
                          child: Switch(
                            value: _wordHl,
                            activeThumbColor: AppColors.gold,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged:
                                ready && !_busy ? _setWordHighlight : null,
                          ),
                        ),
                      ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_rendering) ...[
                    // The encode is the one unavoidable wait in the app.
                    // Rather than apologise for it, it's spent reading
                    // back to the user what they're about to do. Live,
                    // so the wait is announced once as it starts; the
                    // bar under it is not, or every percent would be.
                    A11yLive(
                      child: ShimmerText(
                        text: l.renderingShimmer,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppColors.textSecondary,
                            ),
                        perWord: const Duration(milliseconds: 210),
                        restBetweenPasses: const Duration(milliseconds: 900),
                        glow: 0.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _renderProgress == 0 ? null : _renderProgress,
                        minHeight: 4,
                        backgroundColor: AppColors.surfaceRaised,
                        color: AppColors.gold,
                        semanticsLabel: l.a11yExporting,
                        semanticsValue: _renderProgress == 0
                            ? null
                            : '${(_renderProgress * 100).round()}%',
                      ),
                    ),
                    // A minute-long reel exports in seconds; an hour of
                    // one is minutes of encoding, and a progress bar
                    // that creeps with no explanation reads as a hang.
                    if (_reelMs > ReelLimits.eagerRenderMaxMs) ...[
                      const SizedBox(height: 10),
                      Text(
                        l.longRenderNote,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                  // The share sheet, and beside it Share to: every app a
                  // reel can go straight into, in a panel rising out of
                  // the button, each in its own app's colours. One button
                  // where there were a row of them.
                  Row(
                    children: [
                      Expanded(
                        // Builder so the share sheet's iOS anchor is this
                        // button, measured before the render starts.
                        child: Builder(
                          builder: (buttonContext) => GlowButton(
                            label: l.share,
                            icon: Icons.ios_share_rounded,
                            busy: _rendering,
                            height: 46,
                            dense: true,
                            breathe: true,
                            // A fifth quicker than the house rate: this is
                            // the end of the flow, and the one button left
                            // to press should feel a shade more eager.
                            pulseSpeed: 1.2,
                            onPressed: !ready || _busy || blocked
                                ? null
                                : () => _export(
                                      shareAfter: true,
                                      origin: shareOriginOf(buttonContext),
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ShareToButton(
                          targets: [
                            if (igOn) ...[
                              ShareTarget.instagramReel,
                              ShareTarget.instagramStory,
                            ],
                            ShareTarget.tiktok,
                            ShareTarget.youtube,
                            ShareTarget.facebook,
                            if (waOn) ShareTarget.whatsapp,
                          ],
                          onPick: !ready || _busy || blocked
                              ? null
                              : (t) => _export(
                                    shareAfter: true,
                                    direct: switch (t) {
                                      ShareTarget.instagramReel ||
                                      ShareTarget.instagramPost =>
                                        _DirectShare.instagramReel,
                                      ShareTarget.instagramStory =>
                                        _DirectShare.instagramStory,
                                      ShareTarget.tiktok => _DirectShare.tiktok,
                                      ShareTarget.youtube =>
                                        _DirectShare.youtube,
                                      ShareTarget.facebook =>
                                        _DirectShare.facebook,
                                      ShareTarget.whatsapp =>
                                        _DirectShare.whatsapp,
                                    },
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  QuietButton(
                    label: l.saveToDevice,
                    dense: true,
                    icon: Icons.download_rounded,
                    onPressed: !ready || _busy || blocked
                        ? null
                        : () => _export(shareAfter: false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reel's scene run, in one line.
///
/// Shut, it is a sentence: how many sceneries and how they hand over.
/// Open, it is the two decisions that sentence stands for — how the
/// verses are dealt out, and whether the handover is a cut or a blend —
/// over a ribbon showing where the cuts actually fall, lit on the scene
/// playing now.
///
/// One disclosure, not two: the ribbon opens already sizeable, each
/// segment carrying the share it takes, and a tap on one gives it more.
/// Making that a second mode behind a second icon only hid it.
///
/// Deliberately not an editor. Nothing here is dragged, trimmed or
/// keyframed. A reel is a recitation with a picture behind it, and the
/// moment this screen starts feeling like a timeline it has stopped
/// being that.
class _SceneControls extends StatelessWidget {
  final List<SceneCut> cuts;
  final int current;
  final ScenePacing pacing;
  final SceneTransition transition;
  final bool open;

  /// How many scenes are shorter than their turn. Above zero, this
  /// line stops describing the reel and starts saying what is wrong
  /// with it — it is the only warning the screen has room for.
  final int shortScenes;

  /// What each scene takes relative to its neighbours.
  final List<int> weights;

  final VoidCallback onToggle;
  final ValueChanged<ScenePacing>? onPacing;
  final ValueChanged<SceneTransition>? onTransition;
  final ValueChanged<int>? onWeigh;
  final VoidCallback onAddScenes;

  /// Whether any verse of the reel is cut into lines, which is when a
  /// scene per line is a choice at all.
  final bool hasLines;

  /// The whole selection, and how much of it this reel keeps; see
  /// [_TrimBar]. Null [onTrim] while the recitation is still loading,
  /// and always for an app voice — only the user's own recording can
  /// be cut short.
  final int fullMs;
  final int reelMs;
  final ValueChanged<int>? onTrim;
  final VoidCallback onTrimEnd;

  const _SceneControls({
    required this.cuts,
    required this.current,
    required this.pacing,
    required this.transition,
    required this.open,
    required this.shortScenes,
    required this.weights,
    required this.onToggle,
    required this.onPacing,
    required this.onTransition,
    required this.onWeigh,
    required this.onAddScenes,
    this.hasLines = false,
    required this.fullMs,
    required this.reelMs,
    required this.onTrim,
    required this.onTrimEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final short = shortScenes > 0;
    final summary = short
        ? l.scenesTooShort(shortScenes)
        : l.scenesSummary(
            cuts.length,
            transition == SceneTransition.fade ? l.blendFade : l.blendCut,
          );
    return Column(
      children: [
        // A disclosure to the reader: the line, whether it is open,
        // and that a double tap opens it.
        A11yTap(
          expanded: open,
          hint: l.a11ySceneControlsHint,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (short) ...[
                  const Icon(Icons.error_outline_rounded,
                      size: 13, color: AppColors.gold),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  // This is the one line on the screen that offers to
                  // be opened, so it is the one line that moves: gold,
                  // lit word by word by the same swell the render line
                  // uses. A warning is left still — it is read, not
                  // admired.
                  child: short
                      ? Text(
                          summary,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(
                            fontSize: 11.5,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : ShimmerText(
                          text: summary,
                          style: t.bodySmall!.copyWith(
                            fontSize: 11.5,
                            letterSpacing: 0.3,
                            color: AppColors.gold.withValues(alpha: 0.7),
                          ),
                          perWord: const Duration(milliseconds: 240),
                          restBetweenPasses: const Duration(milliseconds: 1100),
                          glow: 0.5,
                        ),
                ),
                const SizedBox(width: 3),
                _NudgeChevron(open: open),
              ],
            ),
          ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ChipGroup(
                            caption: l.scenePace,
                            children: [
                              if (hasLines) ...[
                                _PresetChip(
                                  label: l.pacePerLine,
                                  selected: pacing == ScenePacing.perLine,
                                  onTap: onPacing == null
                                      ? null
                                      : () => onPacing!(ScenePacing.perLine),
                                ),
                                const SizedBox(width: 8),
                              ],
                              _PresetChip(
                                label: l.pacePerVerse,
                                selected: pacing == ScenePacing.perAyah ||
                                    (!hasLines &&
                                        pacing == ScenePacing.perLine),
                                onTap: onPacing == null
                                    ? null
                                    : () => onPacing!(ScenePacing.perAyah),
                              ),
                              const SizedBox(width: 8),
                              _PresetChip(
                                label: l.paceEven,
                                selected: pacing == ScenePacing.even,
                                onTap: onPacing == null
                                    ? null
                                    : () => onPacing!(ScenePacing.even),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          _ChipGroup(
                            caption: l.sceneBlend,
                            children: [
                              _PresetChip(
                                label: l.blendCut,
                                selected: transition == SceneTransition.cut,
                                onTap: onTransition == null
                                    ? null
                                    : () => onTransition!(SceneTransition.cut),
                              ),
                              const SizedBox(width: 8),
                              _PresetChip(
                                label: l.blendFade,
                                selected: transition == SceneTransition.fade,
                                onTap: onTransition == null
                                    ? null
                                    : () => onTransition!(SceneTransition.fade),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // No second gesture to find: opening the line is
                      // the whole disclosure, and the ribbon arrives
                      // already saying what each scene takes.
                      _SceneRibbon(
                        cuts: cuts,
                        current: current,
                        weights: weights,
                        onTapScene: onWeigh,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.tapForMoreRoom,
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(
                          fontSize: 10,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                      if (onTrim != null) ...[
                        const SizedBox(height: 8),
                        _TrimBar(
                          fullMs: fullMs,
                          reelMs: reelMs,
                          onChange: onTrim!,
                          onEnd: onTrimEnd,
                        ),
                      ],
                      if (short) ...[
                        const SizedBox(height: 6),
                        QuietButton(
                          label: l.addScenes,
                          dense: true,
                          icon: Icons.add_photo_alternate_outlined,
                          onPressed: onAddScenes,
                        ),
                      ],
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The chevron on the scene line. Shut, it rides slowly down and back
/// with a beat of rest between — enough movement to say the line opens,
/// far too little to compete with the reel above it. Open, it turns
/// over and goes still: there is nothing left to find.
class _NudgeChevron extends StatefulWidget {
  final bool open;

  const _NudgeChevron({required this.open});

  @override
  State<_NudgeChevron> createState() => _NudgeChevronState();
}

class _NudgeChevronState extends State<_NudgeChevron>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// The platform asked for reduced motion: the chevron is then just a
  /// chevron.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant _NudgeChevron old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) _sync();
  }

  void _sync() {
    if (widget.open || _still) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          // Down and back over the first two thirds of the cycle, then
          // a rest: a nudge, not a metronome.
          final t = (_c.value / 0.62).clamp(0.0, 1.0);
          final bob = Curves.easeInOut.transform(1 - (t * 2 - 1).abs()) * 3.5;
          return Transform.translate(
            offset: Offset(0, widget.open ? 0 : bob),
            child: child,
          );
        },
        child: AnimatedRotation(
          turns: widget.open ? 0.5 : 0,
          duration: const Duration(milliseconds: 180),
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: widget.open
                ? AppColors.textSecondary
                : AppColors.gold.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// Where the cuts fall, drawn to scale, with the scene playing now lit
/// and each segment saying what it takes. A tap gives one scene more
/// room; nothing here is dragged, trimmed or keyframed — the moment
/// this becomes a timeline it has stopped being a reel.
class _SceneRibbon extends StatelessWidget {
  final List<SceneCut> cuts;
  final int current;

  /// What each scene takes relative to its neighbours, written on the
  /// segments themselves: the readout and the control are one thing.
  final List<int> weights;

  final ValueChanged<int>? onTapScene;

  const _SceneRibbon({
    required this.cuts,
    required this.current,
    required this.weights,
    required this.onTapScene,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      children: [
        for (var i = 0; i < cuts.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            // Flex by length, so a scene holding three verses is drawn
            // three verses wide.
            flex: cuts[i].durationMs,
            // The segment's width is its readout to the eye; to the
            // reader it is a numbered scene with its share said aloud.
            child: A11yTap(
              label: l.a11ySceneSegment(
                  i + 1, i < weights.length ? weights[i] : 1, i == current),
              hint: l.tapForMoreRoom,
              enabled: onTapScene != null,
              onTap: onTapScene == null ? null : () => onTapScene!(i),
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapScene == null ? null : () => onTapScene!(i),
              // A thin bar is nothing to aim at; the touch target is the
              // height of a finger, the paint is not.
              child: SizedBox(
                height: 20,
                child: Center(
                  child: Container(
                    height: 14,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == current
                          ? AppColors.gold
                          : AppColors.gold.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          '${i < weights.length ? weights[i] : 1}\u00d7',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            color: i == current
                                ? const Color(0xFF14100A)
                                : AppColors.gold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The reel's length, and the one place it can be cut.
///
/// A gold line the width of the selection, filled as far as the reel
/// now runs, with the finished length written under the handle. Pull
/// the handle in and the reel ends there: the recitation, the picture
/// and the scene run are all cut to it, in the preview and in the
/// exported file alike.
///
/// It is deliberately the only thing on this screen that can be
/// dragged along the reel's own clock — one cut at the end, no in
/// point, no keyframes. Trimming the front would put the reel out of
/// step with the verse it opens on.
class _TrimBar extends StatelessWidget {
  /// The whole selection, and how much of it the reel keeps.
  final int fullMs;
  final int reelMs;

  /// Live while the handle moves, then once when it is let go.
  final ValueChanged<int> onChange;
  final VoidCallback onEnd;

  /// Shorter than this is not a reel any more, so the handle stops.
  static const _minMs = 3000;

  const _TrimBar({
    required this.fullMs,
    required this.reelMs,
    required this.onChange,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final trimmed = reelMs < fullMs;
    // Time runs left to right whatever the app's language does: this
    // is the recording's own clock, and the reel does not play
    // backwards in Arabic.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final floor = _minMs > fullMs ? fullMs : _minMs;
          final frac =
              fullMs <= 0 ? 1.0 : (reelMs / fullMs).clamp(0.0, 1.0);
          final at = w * frac;
          void setFrom(double dx) {
            if (w <= 0 || fullMs <= 0) return;
            final f = (dx / w).clamp(0.0, 1.0);
            onChange((fullMs * f).round().clamp(floor, fullMs));
          }

          const labelW = 44.0;
          final labelMax = (w - labelW - (trimmed ? labelW : 0))
              .clamp(0.0, w > labelW ? w - labelW : 0.0);
          // A second at a time for the reader, settled as a lifted
          // finger settles it, so the export follows.
          void step(int byMs) {
            onChange((reelMs + byMs).clamp(floor, fullMs));
            onEnd();
          }

          return A11yAdjustable(
            label: l.a11yReelLength,
            value: trimmed
                ? '${l.clock(reelMs)} / ${l.clock(fullMs)}'
                : l.clock(reelMs),
            onIncrease: reelMs >= fullMs ? null : () => step(1000),
            onDecrease: reelMs <= floor ? null : () => step(-1000),
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => setFrom(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => setFrom(d.localPosition.dx),
            onHorizontalDragEnd: (_) => onEnd(),
            onHorizontalDragCancel: onEnd,
            child: SizedBox(
              height: 30,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // What the selection holds, and what is left of it
                  // after the cut: one line, lit as far as the reel
                  // goes and unlit past it.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 6,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 6,
                    child: Container(
                      width: at,
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (at - 5).clamp(0.0, w > 10 ? w - 10 : 0.0),
                    top: 1,
                    child: Container(
                      width: 10,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.35),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The length the reel will be, under the handle that
                  // sets it.
                  Positioned(
                    left: (at - labelW / 2).clamp(0.0, labelMax),
                    top: 16,
                    width: labelW,
                    child: Text(
                      l.clock(reelMs),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                  // Where it would have ended, kept in view so a cut
                  // reel says what it was cut from.
                  if (trimmed)
                    Positioned(
                      right: 0,
                      top: 16,
                      width: labelW,
                      child: Text(
                        l.clock(fullMs),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.1,
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }
}

/// A caption over a pair of chips, so a row of four pills says what its
/// halves are for without a sentence explaining them.
class _ChipGroup extends StatelessWidget {
  final String caption;
  final List<Widget> children;

  const _ChipGroup({required this.caption, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: children),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      selected: selected,
      enabled: onTap != null,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.stroke,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color:
                    selected ? AppColors.goldBright : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ),
      ),
    );
  }
}

/// Shown inside the reel frame while text/audio are fetched, or with a
/// retry action if that failed.
class _PrepOverlay extends StatelessWidget {
  final String? error;
  final Trouble trouble;
  final double progress;
  final VoidCallback onRetry;

  const _PrepOverlay({
    required this.error,
    required this.trouble,
    required this.progress,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The cloud only when it was the connection.
              Icon(
                  switch (trouble) {
                    Trouble.offline => Icons.cloud_off_rounded,
                    Trouble.storage => Icons.storage_rounded,
                    _ => Icons.error_outline_rounded,
                  },
                  size: 40,
                  color: Colors.white70),
              const SizedBox(height: 12),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: Colors.white70)),
              const SizedBox(height: 12),
              QuietButton(
                label: l.tryAgain,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
              // Where to tell us, if Try again keeps failing. Not for a
              // surah the voice never recorded: that is not a fault.
              if (trouble != Trouble.missing) ...[
                const SizedBox(height: 10),
                Text(
                  l.reportInSettings,
                  textAlign: TextAlign.center,
                  style: t.bodySmall
                      ?.copyWith(color: Colors.white54, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: progress == 0 ? null : progress,
              strokeWidth: 3,
              color: AppColors.gold,
              backgroundColor: Colors.white24,
            ),
          ),
          const SizedBox(height: 16),
          // Announced as it appears, so the wait is not a silence.
          // The percentage is left out of the announcement: it moves
          // every few frames, and a reader repeating each step is
          // worse than one that said "preparing" once.
          Semantics(
            liveRegion: progress == 0,
            child: Text(
            progress == 0
                ? l.preparingRecitation
                : l.preparingRecitationPct((progress * 100).round()),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white70),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.firstTimeOnly,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

/// Reports its child's laid-out height, straight out of layout.
///
/// This exists so the verse card needs no [GlobalKey]. The card is
/// built inside a [LayoutBuilder] — that is, during layout — and a
/// GlobalKey inflated there is reparented on a schedule the element
/// tree does not control. Pop the screen while that is in flight and an
/// InheritedWidget can be torn down still holding a dependent, which
/// trips 'package:flutter/src/widgets/framework.dart': Failed assertion:
/// '_dependents.isEmpty': is not true. A render object already knows
/// its size, so nothing has to be looked up by key at all.

/// The surah's name on the reel: on or off, in one tap. It shows on the
/// frame above as it is switched, which is where the user looks.
class _TitlePill extends StatelessWidget {
  final bool on;
  final VoidCallback? onTap;

  const _TitlePill({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return _QuietPill(
      label: l.surahNameTitle,
      semanticsLabel: l.a11ySurahNamePill(on),
      hint: l.a11ySurahNameHint,
      icon: on ? Icons.check_rounded : Icons.add_rounded,
      on: on,
      onTap: onTap,
    );
  }
}

/// The verse's motion: the look's name once one is chosen, and the
/// sheet of them on a tap.
class _MotionPill extends StatelessWidget {
  final VerseMotion motion;
  final VoidCallback? onTap;

  const _MotionPill({required this.motion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final preset = MotionPreset.of(motion);
    final name = motion.isNone
        ? l.styleTabMotion
        : preset == null
            ? l.styleTabMotion
            : l.motionPresetName(preset.name);
    return _QuietPill(
      label: name,
      semanticsLabel: '${l.motionTitle}${l.comma} $name',
      hint: l.a11yMotionPillHint,
      icon: Icons.motion_photos_on_rounded,
      on: !motion.isNone,
      onTap: onTap,
    );
  }
}

/// The small gold-edged pill the reel screen's extras are drawn as.
class _QuietPill extends StatelessWidget {
  final String label;
  final String semanticsLabel;
  final String hint;
  final IconData icon;
  final bool on;
  final VoidCallback? onTap;

  const _QuietPill({
    required this.label,
    required this.semanticsLabel,
    required this.hint,
    required this.icon,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      hint: hint,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: on ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.gold.withValues(alpha: on ? 0.55 : 0.34)),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: AppColors.goldBright),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                          color: on
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Make it for someone", and afterwards the line itself.
///
/// Quiet on purpose, and quieter than the hashtags pill beside it: that
/// one pulses because it is a tip nobody asked for, and two pulsing
/// pills in one row is a row nobody reads. Once a reel has been
/// dedicated the pill stops being an invitation and becomes the
/// dedication, so what is on the frame is also what is on the control
/// that set it.
class _DedicatePill extends StatelessWidget {
  final Dedication dedication;
  final String line;
  final VoidCallback? onTap;

  const _DedicatePill({
    required this.dedication,
    required this.line,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final on = dedication.isNotEmpty;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: on ? l.a11yDedication(line) : l.dedicateRow,
      hint: l.a11yOpensDedication,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: on ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.gold.withValues(alpha: on ? 0.55 : 0.34)),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      on
                          ? (dedication.kind == DedicationKind.sadaqah
                              ? Icons.all_inclusive_rounded
                              : Icons.card_giftcard_rounded)
                          : Icons.card_giftcard_rounded,
                      size: 12,
                      color: AppColors.goldBright,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        on ? line : l.dedicateRow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                          color: on
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
