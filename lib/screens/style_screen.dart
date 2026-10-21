import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../data/band_glow.dart';
import '../data/media_aspect.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/reel_effects.dart';
import '../data/scene_catalog.dart';
import '../data/settings_service.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../data/verse_lines.dart';
import '../data/verse_motion.dart';
import '../l10n/l10n.dart';
import '../render/ayah_rasterizer.dart';
import '../render/letterbox_layout.dart';
import '../data/word_align_service.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/ayah_overlay.dart';
import '../widgets/band_glow_ground.dart';
import '../widgets/colour_picker.dart';
import '../widgets/glow_button.dart';
import '../widgets/ink_swatch.dart';
import '../widgets/measure_height.dart';
import '../widgets/motion_picker.dart';
import '../widgets/reel_finish.dart';
import '../widgets/reel_watermark.dart';
import '../widgets/surah_title.dart';
import '../widgets/verse_stage.dart';
import '../widgets/step_dots.dart';
import 'background_screen.dart';
import 'preview_screen.dart';

/// The style step: everything about how a reel *looks* that is not
/// what is in the picture.
///
/// It sits between the scenery and the reel, and the placement is the
/// whole argument for the screen. Half of what is decided here answers
/// to the scenery — a verse colour is chosen against the ground it
/// will sit on, a grade against the light already in the frame — so it
/// cannot come earlier. And all of it describes the reel the next
/// screen plays, so it should not come later, where a user watching
/// their reel would have to stop watching it to change the type.
///
/// **Nothing plays here.** The frame is a still, deliberately: a
/// running video is the worst possible ground for judging a typeface,
/// because the letters never sit on the same pixels twice. It also
/// costs no decoder for any scenery in the app's own library — the
/// poster every scene ships is exactly the still this wants.
///
/// Three panels under one frame rather than everything at once. There
/// are three unrelated decisions here — the faces, the two colours,
/// the grade — and a row deep enough to hold all of them is a row
/// nobody reads.
class StyleScreen extends StatefulWidget {
  /// Where a reopened reel had been cut. The style step has nothing to
  /// do with a trim — that handle lives on the preview, which is the
  /// only screen that knows how long the recitation runs — so this is
  /// carried through and handed on.
  final int? initialTrimMs;

  /// Whether the scenery picker is the screen underneath this one.
  ///
  /// True on the way through the wizard, and false when a saved reel
  /// was reopened — that lands here straight off My Reels. It is what
  /// "Add sceneries" on the reel screen has to know: with a picker
  /// below, this screen gets out of the way; without one, popping
  /// would abandon the whole reopened session and leave the user back
  /// in the library.
  final bool sceneryBelow;

  const StyleScreen({
    super.key,
    this.initialTrimMs,
    this.sceneryBelow = true,
  });

  @override
  State<StyleScreen> createState() => _StyleScreenState();
}

/// Which panel is open under the frame.
enum _Panel { type, colour, effects, motion }

/// Which of the reel's colours the palette is setting: the verse's, and
/// — on a wide card — the band's around it. The accent is the motion's
/// colour, set on the motion panel.
enum _Target { verse, backdrop }

class _StyleScreenState extends State<StyleScreen> {
  _Panel _panel = _Panel.type;
  _Target _target = _Target.verse;

  /// Bumped by [_reset], and nothing else.
  ///
  /// The effects panel remembers which rows have their slider out,
  /// which is a thing only it knows and only a switch changes — see
  /// [_EffectsPanelState]. Reset has to close them all, and there is
  /// no honest way for the panel to infer that from the values alone:
  /// "everything went to zero" is also what dragging the last open
  /// slider to the middle looks like. So reset gives the panel a new
  /// key, which is the framework's own way of saying "start again".
  int _resets = 0;

  /// The verse the still frame is set with — the first of the chosen
  /// range. Loaded from the cache the verses screen already filled;
  /// fetched only if somehow it did not.
  List<Ayah>? _ayahs;

  /// The scenery's own shape, for a letterbox card. Null holds the
  /// full-frame look for that beat rather than laying out a card that
  /// would then have to be reshaped — the same thing the preview does.
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _ayahs = QuranRepository.ayahsIfCached(creationState.surah);
    if (_ayahs == null) _loadVerses();
    if (creationState.layout == ReelLayout.letterbox) _resolveAspect();
  }

  Future<void> _loadVerses() async {
    try {
      final a = await QuranRepository.ayahsOf(creationState.surah);
      if (mounted) setState(() => _ayahs = a);
    } catch (_) {
      // The next screen is where a missing surah is reported and
      // retried; here it just means the frame is set with nothing.
    }
  }

  Future<void> _resolveAspect() async {
    final b = creationState.background;
    if (b == null) return;
    _aspect = MediaAspect.cached(b);
    if (_aspect != null) {
      setState(() {});
      return;
    }
    final a = await MediaAspect.of(b);
    if (mounted) setState(() => _aspect = a);
  }

  /// The verse on the still frame: the first of the range, or a stand-in
  /// while the surah is still coming down.
  Ayah get _ayah {
    final list = _ayahs;
    final i = creationState.startAyah - 1;
    if (list != null && i >= 0 && i < list.length) return list[i];
    return const Ayah(number: 1, arabic: 'بِسْمِ ٱللَّهِ', translation: '');
  }

  void _tap(VoidCallback change) {
    HapticFeedback.selectionClick();
    change();
  }

  /// The band is the wide card's alone: on a full frame the palette is
  /// the verse's again, whatever was last open.
  _Target get _shownTarget =>
      _target == _Target.backdrop && creationState.layout != ReelLayout.letterbox
          ? _Target.verse
          : _target;

  void _openPanel(_Panel p) {
    if (_panel == p) return;
    HapticFeedback.selectionClick();
    setState(() => _panel = p);
  }

  /// Puts this panel's decisions back to the app's own defaults, and
  /// only this panel's: a reset button that quietly took the grade off
  /// with the typeface would be a button nobody dares press.
  void _reset() {
    HapticFeedback.mediumImpact();
    setState(() => _resets++);
    final s = creationState;
    switch (_panel) {
      case _Panel.type:
        s
          ..setVerseFace(VerseFace.uthmani)
          ..setTranslationFace(TranslationFace.inter)
          ..setTranslationFace(TranslationFace.plex)
          ..setTextScale(1.0)
          ..setTextPreset(TextPreset.classic);
      case _Panel.colour:
        // The verse's colour, and the band back to the scenery blurred.
        s.resetVerseColour();
        if (s.layout == ReelLayout.letterbox) {
          s.setBackdrop(LetterboxBackdrop.blur);
        }
      case _Panel.effects:
        s.setEffects(ReelEffects.off);
      case _Panel.motion:
        s
          ..setMotion(VerseMotion.standard)
          ..resetAccent();
    }
  }

  Future<void> _next() async {
    final asked = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(initialTrimMs: widget.initialTrimMs),
      ),
    );
    // "Add sceneries" on the reel screen means the scenery picker,
    // which is behind this screen rather than behind that one. The
    // preview pops with the request and this gets out of its way, so
    // the button lands where it has always landed instead of on the
    // typeface.
    if (asked != PreviewScreen.addScenes || !mounted) return;
    if (widget.sceneryBelow) {
      Navigator.of(context).pop();
      return;
    }
    // Nothing below to get out of the way of — a reopened reel came
    // here straight from the library. So the picker is opened *in*
    // this screen's place: forward from there is the picker, the style
    // step and the reel, and back from it is the library the user
    // came from.
    unawaited(Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const BackgroundScreen()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: StepDots(current: WizardSteps.style, total: WizardSteps.total),
      ),
      body: SafeArea(
        top: false,
        // Every control on this screen writes straight to the one
        // object that holds the reel, and reads back from it — no
        // local copies. The preview can change the same values and be
        // popped back onto this screen, and a screen holding its own
        // idea of the verse colour would then be showing the wrong
        // one.
        child: ListenableBuilder(
          listenable: creationState,
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) {
              // The panel takes a fixed share, and every panel is laid
              // out to fit it whole — no row below the fold, nothing to
              // scroll to — on the smallest phone; the frame takes what
              // is left. The other way round — a frame sized to the
              // screen and a panel taking the remainder — leaves a phone
              // with a short screen showing half a row of swatches.
              final panelH = (box.maxHeight * 0.40).clamp(206.0, 256.0);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        A11yHeader(
                          child: Text(l.styleTitle, style: t.headlineMedium),
                        ),
                        const SizedBox(height: 4),
                        Text(l.styleBody, style: t.bodyMedium, maxLines: 2),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Semantics(
                            container: true,
                            label: l.a11yStyleStage,
                            child: _Stage(
                              ayah: _ayah,
                              aspect: _aspect,
                              // The motion plays on the frame while its
                              // panel is open; the other panels judge
                              // type and colour on a still.
                              motion: _panel == _Panel.motion
                                  ? creationState.motion
                                  : null,
                              hasWords: _hasWords,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PanelTabs(
                    current: _panel,
                    onTap: _openPanel,
                    onReset: _reset,
                  ),
                  SizedBox(
                    height: panelH,
                    child: _panelBody(l),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    child: GlowButton(
                      label: l.previewMyReel,
                      icon: Icons.auto_awesome_rounded,
                      onPressed: _next,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Whether the chosen voice has word timing: what the trail and the
  /// unveil need.
  bool get _hasWords =>
      creationState.reciter != null &&
      WordAlignService.supports(creationState.reciter!);

  Widget _panelBody(L10n l) => switch (_panel) {
        _Panel.type => _TypePanel(ayah: _ayah),
        _Panel.colour => _ColourPanel(
            target: _shownTarget,
            onTarget: (t) => _tap(() => setState(() => _target = t)),
          ),
        // Handed the value it draws rather than reaching for it.
        // Not a style point: a panel that takes nothing can be built
        // `const`, and a const widget is one Flutter is entitled to
        // skip rebuilding entirely — which it does, leaving every
        // switch in here showing the state the panel opened on while
        // the reel underneath it changes.
        _Panel.effects => _EffectsPanel(
            key: ValueKey(_resets),
            effects: creationState.effects,
          ),
        _Panel.motion => SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: MotionPicker(
              motion: creationState.motion,
              hasWords: _hasWords,
              onChanged: creationState.setMotion,
              heading: false,
              tint: AyahOverlay.lightTintOf(
                  Color(creationState.accentArgb), creationState.accentInk),
              below: MotionColourRow(
                accentArgb: creationState.accentArgb,
                accentInk: creationState.accentInk,
                onLight: creationState.onLightGround,
                onColour: creationState.setAccentColor,
                onInk: creationState.setAccentInk,
                onGold: creationState.resetAccent,
              ),
            ),
          ),
      };
}

// ---------------------------------------------------------------------
// The still frame
// ---------------------------------------------------------------------

/// The reel, held still: the scenery under whatever grade is on, the
/// scrim, the vignette, the verse card, the mark, the grain.
///
/// Same layers in the same order as the preview and the exporter — see
/// [ReelFinish], which is where that order is written down once.
class _Stage extends StatefulWidget {
  final Ayah ayah;
  final double? aspect;

  /// The motion to play on the verse, looping; null for the still.
  final VerseMotion? motion;
  final bool hasWords;

  const _Stage({
    required this.ayah,
    this.aspect,
    this.motion,
    this.hasWords = false,
  });

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  /// Only ever created for a clip the user brought in themselves.
  /// Everything from the app's own library has a poster bundled, which
  /// is this exact still at no cost at all — see [_picture].
  VideoPlayerController? _video;

  /// Laid-out height of the verse card.
  ///
  /// In full frame the mark hangs off the card's bottom edge rather
  /// than the frame's, so without this the stage drew it at the floor
  /// of the frame while the preview and the exported file put it
  /// directly under the verse — a gap of a good tenth of the frame on
  /// the one screen whose whole premise is that what you see is the
  /// file.
  double? _cardHeight;

  void _onCardHeight(double h) {
    if (_cardHeight == h) return;
    // Reported during layout, which is too late to set state in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _cardHeight = h);
    });
  }

  @override
  void initState() {
    super.initState();
    _openUserClip();
  }

  Future<void> _openUserClip() async {
    final b = creationState.background;
    if (b == null || !b.isUserFile || b.fileIsImage) return;
    final c = VideoPlayerController.file(File(b.filePath!));
    try {
      await c.initialize();
      // Initialized is not always painted: a seek to the top is what
      // makes the first frame appear on a decoder that has not been
      // asked to play. It is never asked to play — that is the point
      // of this screen.
      await c.seekTo(Duration.zero);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
    } catch (_) {
      await c.dispose();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  /// The scenery as a still.
  ///
  /// Every scene in the app's library ships a poster inside the app,
  /// so the overwhelmingly common case draws instantly, offline, and
  /// without touching a hardware decoder. A photo out of the user's
  /// gallery is the file itself; a clip out of it is the one case that
  /// needs a decoder, paused on its first frame.
  Widget _picture(ReelBackground b) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(b.gradientArgb[0]), Color(b.gradientArgb[1])],
        ),
      ),
    );
    Widget? top;
    if (b.isUserFile) {
      final v = _video;
      top = b.fileIsImage
          ? Image.file(File(b.filePath!),
              fit: BoxFit.cover, excludeFromSemantics: true)
          : (v != null && v.value.size.width > 0
              ? FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: v.value.size.width,
                    height: v.value.size.height,
                    child: VideoPlayer(v),
                  ),
                )
              : null);
    } else {
      final poster = SceneCatalog.byId(b.id)?.thumbAsset;
      top = poster != null
          ? Image.asset(poster, fit: BoxFit.cover, excludeFromSemantics: true)
          : (b.isImage && b.imageAsset.isNotEmpty
              ? Image.asset(b.imageAsset,
                  fit: BoxFit.cover, excludeFromSemantics: true)
              : (b.isDeviceFile && b.fileIsImage
                  ? Image.file(File(b.filePath!),
                      fit: BoxFit.cover, excludeFromSemantics: true)
                  : null));
    }
    return Stack(
      fit: StackFit.expand,
      children: [gradient, if (top != null) top],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = creationState;
    final effects = s.effects;
    final b = s.background;
    final geo = s.layout == ReelLayout.letterbox && widget.aspect != null
        ? LetterboxGeometry.of(widget.aspect!)
        : null;
    final onLight = s.onLightGround;
    final picture = b == null
        ? const ColoredBox(color: AppColors.surface)
        : ReelFinish.graded(effects, _picture(b));
    final vignette = ReelFinish.vignette(effects);
    final grain = ReelFinish.grain(effects);
    final translation = SettingsService.state.value.translation;

    return LayoutBuilder(
      builder: (context, box) {
        final scale = box.maxWidth / LetterboxGeometry.frameW;
        final motion = widget.motion;
        final verse = motion != null && !motion.isNone
            ? _MotionVerse(
                ayah: widget.ayah,
                motion: motion.forVoice(hasWords: widget.hasWords),
                highlight: s.wordHighlight && widget.hasWords,
                width: box.maxWidth,
                onHeight: _onCardHeight,
              )
            : MeasureHeight(
          onChange: _onCardHeight,
          child: AyahOverlay(
            ayah: widget.ayah,
            width: box.maxWidth,
            textColor: Color(s.textArgb),
            accent: Color(s.accentArgb),
            ink: s.verseInk,
            accentInk: s.accentInk,
            textScale: s.textScale,
            preset: s.textPreset,
            onLight: onLight,
            translation: translation,
            surah: s.surah,
            verseFace: s.verseFace,
            translationFace: s.typography.translation,
            // The first word, lit. The accent panel says it colours
            // "the word as it is recited", and a still frame that
            // never lights one leaves half of that claim unshown —
            // which is also what hid the case where the accent is so
            // near the verse's own colour that it gives way.
            highlightTokens: widget.ayah.arabic.trim().isEmpty
                ? null
                : (start: 0, end: 1),
          ),
        );

        // Where the mark goes, in the export's own coordinates — the
        // same arithmetic the preview and the exporter run. Null in
        // letterbox, where the mark answers to the card and not to the
        // verse, and null until the card has laid out once.
        final cardH = _cardHeight;
        final verseBottom = geo != null || cardH == null
            ? null
            : (LetterboxGeometry.frameH -
                        cardH * LetterboxGeometry.frameW / box.maxWidth) *
                    s.overlayAlign +
                cardH * LetterboxGeometry.frameW / box.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (geo == null) ...[
              picture,
              const DecoratedBox(
                decoration:
                    BoxDecoration(gradient: AyahRasterizer.scrimGradient),
              ),
            ] else ...[
              if (s.backdrop == LetterboxBackdrop.colour)
                ColoredBox(color: Color(s.backdropArgb))
              else if (s.backdrop == LetterboxBackdrop.glow)
                BandGlowGround(glow: s.bandGlow, box: geo)
              else
                // The blurred backdrop, straight rather than through
                // the preview's shrink-and-upscale trick: that exists
                // to keep a *playing* video at 60fps, and there is
                // nothing playing here. One blur, once, on a still.
                ColorFiltered(
                  colorFilter: ColorFilter.matrix(BackdropTone.colorMatrix),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: 72 * scale,
                      sigmaY: 72 * scale,
                      tileMode: TileMode.clamp,
                    ),
                    child: picture,
                  ),
                ),
              Positioned(
                left: geo.cardX * scale,
                top: geo.cardY * scale,
                width: geo.cardW * scale,
                height: geo.cardH * scale,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                      s.roundedCorners ? LetterboxGeometry.radius * scale : 0),
                  child: picture,
                ),
              ),
            ],
            if (vignette != null) Positioned.fill(child: vignette),
            if (geo == null)
              Positioned.fill(
                child: OverflowBox(
                  alignment: Alignment(0, s.overlayAlign * 2 - 1),
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: verse,
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                top: geo.bandTop * scale,
                height: geo.bandHeight * scale,
                child: OverflowBox(
                  alignment: Alignment(0, s.overlayAlign * 2 - 1),
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: verse,
                ),
              ),
            if (s.surahTitle)
              Positioned.fill(
                child: ReelSurahTitle(
                  width: box.maxWidth,
                  surah: s.surah,
                  edition: translation,
                  at: s.surahTitleAt,
                  scale: s.surahTitleScale,
                  letterbox: geo,
                  onLight: ReelDedication.onLightAt(
                      s.surahTitleAt ?? ReelSurahTitle.defaultCentre(geo),
                      onLightGround: onLight,
                      letterbox: geo),
                ),
              ),
            ReelWatermark(
              width: box.maxWidth,
              letterbox: geo,
              verseBottom: verseBottom,
            ),
            if (grain != null) Positioned.fill(child: grain),
          ],
        );
      },
    );
  }
}

/// The verse on the still frame, playing a motion on a loop: the real
/// card, through the reel's own [VerseStage], on a stand-in recitation
/// whose words are spaced by their letters. So what the panel shows is
/// what the reel does — only the timing is invented.
class _MotionVerse extends StatefulWidget {
  final Ayah ayah;
  final VerseMotion motion;
  final bool highlight;
  final double width;
  final ValueChanged<double> onHeight;

  const _MotionVerse({
    required this.ayah,
    required this.motion,
    required this.highlight,
    required this.width,
    required this.onHeight,
  });

  @override
  State<_MotionVerse> createState() => _MotionVerseState();
}

class _MotionVerseState extends State<_MotionVerse>
    with SingleTickerProviderStateMixin {
  /// How long the verse is "recited", and the loop it plays in: a beat
  /// of rest before it comes round again.
  static const _unitMs = 4600;
  static const _loopMs = 5300;

  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: _loopMs));
  final _clock = ValueNotifier<int>(0);

  late Recitation _rec;
  late List<VerseUnit> _units;
  late List<Ayah> _ayahs;
  late Map<int, List<HighlightSpan>> _words;
  late Map<int, List<(int, int)?>> _times;

  @override
  void initState() {
    super.initState();
    _plan();
    _c.addListener(() => _clock.value = (_c.value * _loopMs).round());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c
        ..stop()
        ..value = 0.55;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MotionVerse old) {
    super.didUpdateWidget(old);
    if (old.ayah.arabic != widget.ayah.arabic ||
        old.ayah.number != widget.ayah.number) {
      _plan();
    }
  }

  /// A stand-in recitation of the verse: its words one after another
  /// from a tenth of the way in to near the end, each taking its share
  /// of the letters, with a breath between.
  void _plan() {
    final n = widget.ayah.number;
    _rec = Recitation(
      reciterId: 'demo',
      surah: creationState.surah,
      audioPath: '',
      timings: [AyahTiming(n, 0, _unitMs)],
    );
    _units = [VerseUnit(n, null, 0, _unitMs)];
    _ayahs = List.filled(n, widget.ayah);
    final tokens = VerseText.tokens(widget.ayah.arabic);
    final letters = [for (final t in tokens) VerseText.letters(t)];
    final total = letters.fold<int>(0, (a, b) => a + b);
    const from = _unitMs * 0.1, to = _unitMs * 0.86;
    final times = List<(int, int)?>.filled(tokens.length, null);
    final spans = <HighlightSpan>[];
    var done = 0;
    for (var k = 0; k < tokens.length; k++) {
      if (letters[k] == 0) {
        if (k > 0) times[k] = times[k - 1];
        continue;
      }
      final a = (from + (to - from) * done / (total == 0 ? 1 : total)).round();
      done += letters[k];
      final b = (from + (to - from) * done / (total == 0 ? 1 : total)).round();
      times[k] = (a, a + ((b - a) * 0.86).round());
      // A word's window runs to the next word, as the highlight's do.
      var end = k + 1;
      while (end < tokens.length && letters[end] == 0) {
        end++;
      }
      spans.add(HighlightSpan(a, b, k, end));
    }
    // Gap-filled to the verse's end, as the real windows are.
    if (spans.isNotEmpty) {
      final last = spans.removeLast();
      spans.add(HighlightSpan(last.startMs, _unitMs, last.tokenStart, last.tokenEnd));
    }
    _words = {n: spans};
    _times = {n: times};
  }

  @override
  void dispose() {
    _c.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = creationState;
    final settings = SettingsService.state.value;
    return VerseStage(
      clock: _clock,
      units: _units,
      ayahs: _ayahs,
      recitation: _rec,
      motion: widget.motion,
      words: _words,
      highlight: widget.highlight,
      wordTimes: _times,
      width: widget.width,
      textColor: Color(s.textArgb),
      accent: Color(s.accentArgb),
      ink: s.verseInk,
      accentInk: s.accentInk,
      textScale: s.textScale,
      preset: s.textPreset,
      onLight: s.onLightGround,
      translation: settings.translation,
      numbering: settings.verseNumbering,
      showTranslation: !settings.verseTranslationOff,
      surah: s.surah,
      verseFace: s.verseFace,
      translationFace: s.typography.translation,
      onHeight: widget.onHeight,
    );
  }
}

// ---------------------------------------------------------------------
// The panel switcher
// ---------------------------------------------------------------------

/// Three tabs and a reset, on one line above the panel.
///
/// A segmented control rather than a [TabBar]: the panels below are
/// not pages to swipe between — swiping sideways over a row of
/// swatches is how you scroll it, not how you leave it.
class _PanelTabs extends StatelessWidget {
  final _Panel current;
  final ValueChanged<_Panel> onTap;
  final VoidCallback onReset;

  const _PanelTabs({
    required this.current,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    String name(_Panel p) => switch (p) {
          _Panel.type => l.styleTabType,
          _Panel.colour => l.styleTabColour,
          _Panel.effects => l.styleTabEffects,
          _Panel.motion => l.styleTabMotion,
        };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Row(
                children: [
                  for (final p in _Panel.values)
                    Expanded(
                      child: A11yTap(
                        label: name(p),
                        selected: current == p,
                        onTap: () => onTap(p),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onTap(p),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: current == p
                                  ? AppColors.gold.withValues(alpha: 0.16)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              name(p),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: current == p
                                    ? AppColors.goldBright
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          A11yTap(
            label: l.styleReset,
            onTap: onReset,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReset,
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.restart_alt_rounded,
                    size: 19, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [name] with its first letter a capital, for a heading: the colours'
/// names are written to be read inside a sentence.
String _cap(String name) =>
    name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

/// A one-line heading inside a panel: what the row under it sets, and
/// what it is set to now.
class _MiniHeading extends StatelessWidget {
  final String title;
  final String? value;

  const _MiniHeading(this.title, {this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
      child: A11yHeader(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: title.toUpperCase()),
            if (value != null)
              TextSpan(
                text: '  ·  $value',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: AppColors.textPrimary,
                ),
              ),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A panel's controls, all of them in view: laid out to fit the panel's
/// height on the smallest phone the app runs on. The scroll view is only
/// a net for a screen smaller still, or type set larger than the app's
/// own; on every phone the panel was laid out for, nothing moves.
class _PanelBody extends StatelessWidget {
  final List<Widget> children;

  const _PanelBody({required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

// ---------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------

/// The two face rows, the size, and the three designed looks for the
/// card itself.
class _TypePanel extends StatelessWidget {
  final Ayah ayah;

  const _TypePanel({required this.ayah});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    final edition = SettingsService.state.value.translation;
    final faces =
        TranslationFace.forScript(arabicScript: edition.arabicScript);
    return _PanelBody(
      children: [
        _MiniHeading(l.styleVerseFace, value: s.verseFace.label),
        SizedBox(
          height: _FaceCard.arabicHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: VerseFace.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final f = VerseFace.values[i];
              return _FaceCard(
                specimen: f.specimen,
                label: f.label,
                style: AppTheme.quran(size: 13, face: f)
                    .copyWith(color: AppColors.textPrimary, height: 1.5),
                direction: TextDirection.rtl,
                selected: s.verseFace == f,
                section: l.styleVerseFace,
                onTap: () {
                  HapticFeedback.selectionClick();
                  s.setVerseFace(f);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // Headed by the edition's own name rather than the word
        // "translation": somebody setting an Urdu line should see اردو
        // over the row that decides how their Urdu looks.
        _MiniHeading('${l.styleTranslationFace} · ${edition.nativeName}',
            value: s.typography.translation.label),
        SizedBox(
          // A Latin face is named in itself, one line; an Arabic-script
          // one needs its Latin name under its specimen, as the verse's.
          height: edition.arabicScript
              ? _FaceCard.arabicHeight
              : _FaceCard.latinHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: faces.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final f = faces[i];
              return _FaceCard(
                specimen: f.specimen,
                label: f.label,
                style: f.arabicScript
                    ? AppTheme.translation(size: 13, face: f)
                        .copyWith(color: AppColors.textPrimary, height: 1.5)
                    : AppTheme.translation(size: 14, face: f)
                        .copyWith(color: AppColors.textPrimary, height: 1.25),
                direction: edition.direction,
                selected: s.typography.translation == f,
                section: l.styleTranslationFace,
                onTap: () {
                  HapticFeedback.selectionClick();
                  s.setTranslationFace(f);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              const ExcludeSemantics(
                child: Text('Aa',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ),
              Expanded(
                child: MergeSemantics(
                  child: Semantics(
                    label: l.a11yTextSize,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 1.5,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 11),
                      ),
                      child: SizedBox(
                        height: 30,
                        child: Slider(
                          value: s.textScale,
                          min: 0.7,
                          max: 1.5,
                          activeColor: AppColors.gold,
                          inactiveColor: AppColors.surfaceRaised,
                          semanticFormatterCallback: (v) =>
                              '${(v * 100).round()}%',
                          onChanged: s.setTextScale,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const ExcludeSemantics(
                child: Text('Aa',
                    style:
                        TextStyle(fontSize: 17, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // The card's three designed looks: how the letters stand off the
        // scenery — a shadow, a glow, or nothing but the letters. Type,
        // not motion: they change how the verse is set, not what it does.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          // Shrunk rather than cut where three long names in a large type
          // would run off the edge.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in TextPreset.values) ...[
                _Chip(
                  label: switch (p) {
                    TextPreset.classic => l.presetClassic,
                    TextPreset.glow => l.presetGlow,
                    TextPreset.minimal => l.presetMinimal,
                  },
                  selected: s.textPreset == p,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    s.setTextPreset(p);
                  },
                ),
                if (p != TextPreset.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          ),
        ),
      ],
    );
  }
}

/// One face, set in itself.
///
/// The specimen is the only honest way to show a typeface, and it is
/// the same phrase on every card of a row so the card shows the
/// difference and nothing else. Under it, the face's name in the app's
/// own font, because a name set in Nastaliq is a specimen, not a label
/// — except where the specimen already is the name: a Latin face shows
/// its name in itself, once, and the card is a single line.
class _FaceCard extends StatelessWidget {
  /// A specimen with the name under it.
  static const arabicHeight = 48.0;

  /// A name set in its own face.
  static const latinHeight = 34.0;

  final String specimen;
  final String label;
  final TextStyle style;
  final TextDirection direction;
  final bool selected;
  final String section;
  final VoidCallback onTap;

  const _FaceCard({
    required this.specimen,
    required this.label,
    required this.style,
    required this.direction,
    required this.selected,
    required this.section,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final named = specimen == label;
    final ink = selected ? AppColors.goldBright : AppColors.textSecondary;
    return A11yTap(
      label: '$section${l.comma} $label',
      selected: selected,
      hint: l.a11ySetsFace,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: named ? null : 80,
          constraints: named ? const BoxConstraints(minWidth: 58) : null,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: named ? 12 : 5),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: named
              ? Text(
                  specimen,
                  maxLines: 1,
                  softWrap: false,
                  style: style.copyWith(
                      color: selected ? AppColors.goldBright : null),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      specimen,
                      textDirection: direction,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      // The specimen is the picture, not the words: a
                      // reader has the face's name from the label.
                      style: style,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        color: ink,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A small pill with a selected state — the presets, and the blur.
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// What a reader hears, when [label] alone would not say what the
  /// chip sets.
  final String? a11yLabel;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.a11yLabel,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: a11yLabel ?? label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.16)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14,
                    color: selected
                        ? AppColors.goldBright
                        : AppColors.textSecondary),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? AppColors.goldBright : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Colour
// ---------------------------------------------------------------------

/// The verse's colour, and on a wide card the band's: every colour in
/// view at once, in two grids that need no scrolling.
///
/// The luminous inks come first, each a disc of its own light; then the
/// flat colours, two rows of twelve in the palette's own order, and any
/// colour mixed at the end. The accent — the lit word, the thread, the
/// light — is the motion's colour now, and is chosen on the motion panel,
/// where what it colours can be seen moving.
class _ColourPanel extends StatelessWidget {
  final _Target target;
  final ValueChanged<_Target> onTarget;

  const _ColourPanel({required this.target, required this.onTarget});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    final wide = s.layout == ReelLayout.letterbox;
    final band = wide && target == _Target.backdrop;
    return _PanelBody(
      children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: _TargetSwitch(target: target, onTap: onTarget),
          )
        else
          _MiniHeading(l.styleVerseColour,
              value: _cap(s.verseInk.isNone
                  ? l.colourName(s.textArgb)
                  : l.inkName(s.verseInk))),
        if (band) ..._band(context) else ..._verse(context),
      ],
    );
  }

  List<Widget> _verse(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    final section = l.styleVerseColour;
    final inks = VerseInk.ordered(onLight: s.onLightGround);
    const flat = versePalette;
    final custom = s.verseInk.isNone &&
        !flat.any((c) => (c & 0xFFFFFF) == (s.textArgb & 0xFFFFFF));
    return [
      _Grid(
        rows: 2,
        children: [
          for (final ink in inks)
            _Cell(
              label: '$section${l.comma} ${l.a11yInkSwatch(ink)}',
              selected: s.verseInk == ink,
              onTap: () => s.setVerseInk(ink),
              child: (size) => InkDisc(ink: ink, size: size),
            ),
        ],
      ),
      const _Divider(),
      _Grid(
        rows: 2,
        children: [
          for (final c in flat)
            _Cell(
              label: '$section${l.comma} ${l.a11yColourSwatch(c)}',
              selected: s.verseInk.isNone && s.textArgb == c,
              onTap: () => s.setTextColor(c),
              child: (size) => _SolidDisc(argb: c, size: size),
            ),
          // Any colour the palette does not hold, mixed and kept.
          _Cell.raw(
            child: (size) => CustomColourCircle(
              size: size,
              current: s.textArgb,
              chosen: custom,
              onPick: s.setTextColor,
            ),
          ),
        ],
      ),
    ];
  }

  /// The wide card's band: the scenery blurred, a luminous ground, a
  /// flat colour, or any colour mixed.
  List<Widget> _band(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    final section = l.styleBackdropColour;
    final blurred = s.backdrop == LetterboxBackdrop.blur;
    final glowing = s.backdrop == LetterboxBackdrop.glow;
    final flat = s.backdrop == LetterboxBackdrop.colour;
    return [
      _MiniHeading(l.styleLuminous,
          value: glowing ? l.bandGlowName(s.bandGlow) : null),
      _Grid(
        rows: 2,
        cell: 44,
        children: [
          for (final g in BandGlow.values)
            _Cell(
              label: '$section${l.comma} ${l.bandGlowName(g)}',
              selected: glowing && s.bandGlow == g,
              onTap: () => s.setBandGlow(g),
              child: (size) => _GlowDisc(glow: g, size: size),
            ),
        ],
      ),
      const _Divider(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Chip(
                label: l.backdropBlur,
                a11yLabel: '$section${l.comma} ${l.backdropBlur}',
                icon: Icons.blur_on_rounded,
                selected: blurred,
                onTap: () {
                  HapticFeedback.selectionClick();
                  s.setBackdrop(LetterboxBackdrop.blur);
                },
              ),
              const SizedBox(width: 8),
              for (final c in letterboxBackdropSwatches)
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: _Ringed(
                      label: '$section${l.comma} ${l.a11yColourSwatch(c)}',
                      selected: flat && s.backdropArgb == c,
                      onTap: () => s.setBackdropColor(c),
                      child: _SolidDisc(argb: c, size: 24),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              CustomColourCircle(
                size: 24,
                current: s.backdropArgb,
                chosen: flat &&
                    !letterboxBackdropSwatches.contains(s.backdropArgb),
                onPick: s.setBackdropColor,
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

/// A thin rule between a panel's two grids.
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        color: AppColors.stroke.withValues(alpha: 0.6),
      );
}

/// Swatches in [rows] rows that share the panel's width evenly, as many
/// to a row as it takes: every one in view, none scrolled to.
class _Grid extends StatelessWidget {
  final int rows;
  final List<_Cell> children;

  /// The widest a cell grows on a wide phone.
  final double cell;

  const _Grid({required this.rows, required this.children, this.cell = 34});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 16.0;
        final perRow = (children.length / rows).ceil();
        final w = math.min(cell, (box.maxWidth - 2 * pad) / perRow);
        final h = math.min(cell, w + 4);
        final disc = (math.min(w, h) - 7).clamp(14.0, 40.0);
        return Column(
          children: [
            for (var r = 0; r < rows; r++)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = r * perRow;
                      i < math.min(children.length, (r + 1) * perRow);
                      i++)
                    SizedBox(
                      width: w,
                      height: h,
                      child: Center(child: children[i].child(disc)),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// One swatch in a [_Grid]: a disc of colour with a finger's worth of
/// target around it, ringed in gold with a gap when it is the one.
class _Cell {
  final Widget Function(double size) child;

  _Cell({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Widget Function(double size) child,
  }) : child = ((size) => _Ringed(
              label: label,
              selected: selected,
              onTap: onTap,
              child: child(size),
            ));

  /// A cell that is its own control, as the mixed colour's circle is.
  _Cell.raw({required this.child});
}

class _Ringed extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _Ringed({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.gold : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A luminous ground as a disc: its gradient and its light, as the band
/// is painted.
class _GlowDisc extends StatelessWidget {
  final BandGlow glow;
  final double size;

  const _GlowDisc({required this.glow, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Color(glow.glow).withValues(alpha: 0.4),
              blurRadius: size * 0.35,
            ),
          ],
        ),
        child: ClipOval(child: BandGlowGround(glow: glow)),
      );
}

/// The targets, side by side, each wearing the colour it is set to and
/// its name: the verse, and the wide card's band.
class _TargetSwitch extends StatelessWidget {
  final _Target target;
  final ValueChanged<_Target> onTap;

  const _TargetSwitch({required this.target, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    Widget half(_Target t) {
      final band = t == _Target.backdrop;
      final on = target == t;
      final label = band ? l.styleBackdropColour : l.styleVerseColour;
      final String name;
      final Widget disc;
      if (band) {
        switch (s.backdrop) {
          case LetterboxBackdrop.blur:
            name = l.backdropBlur;
            disc = const Icon(Icons.blur_on_rounded,
                size: 20, color: AppColors.textSecondary);
          case LetterboxBackdrop.glow:
            name = l.bandGlowName(s.bandGlow);
            disc = _GlowDisc(glow: s.bandGlow, size: 20);
          case LetterboxBackdrop.colour:
            name = _cap(l.colourName(s.backdropArgb));
            disc = _SolidDisc(argb: s.backdropArgb, size: 20);
        }
      } else {
        name = _cap(s.verseInk.isNone
            ? l.colourName(s.textArgb)
            : l.inkName(s.verseInk));
        disc = s.verseInk.isNone
            ? _SolidDisc(argb: s.textArgb, size: 20)
            : InkDisc(ink: s.verseInk, size: 20);
      }
      return Expanded(
        child: A11yTap(
          label: label,
          selected: on,
          onTap: () => onTap(t),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: on
                    ? AppColors.gold.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: on
                      ? AppColors.gold.withValues(alpha: 0.6)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  disc,
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: on
                                  ? AppColors.goldBright
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        ExcludeSemantics(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              height: 1.2,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          half(_Target.verse),
          const SizedBox(width: 3),
          half(_Target.backdrop),
        ],
      ),
    );
  }
}

/// A flat colour as a disc, with a little light across its face so it
/// reads as a pigment rather than a hole in the panel.
class _SolidDisc extends StatelessWidget {
  final int argb;
  final double size;

  const _SolidDisc({required this.argb, required this.size});

  @override
  Widget build(BuildContext context) {
    final light = isLightSurface(argb);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: [
            Color.alphaBlend(
                Colors.white.withValues(alpha: light ? 0.35 : 0.22),
                Color(argb)),
            Color(argb),
          ],
        ),
        border: Border.all(
          color: (light ? Colors.black : Colors.white)
              .withValues(alpha: 0.14),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------

/// The looks, then the switches that ride on top of one, and the one
/// slider that says how much of the effect last switched on.
class _EffectsPanel extends StatefulWidget {
  /// What the switches are drawn from. See the call site for why this
  /// is passed in rather than read off the singleton.
  final ReelEffects effects;

  const _EffectsPanel({super.key, required this.effects});

  @override
  State<_EffectsPanel> createState() => _EffectsPanelState();
}

class _EffectsPanelState extends State<_EffectsPanel> {
  /// Which of the effects with an amount are on.
  ///
  /// Held here rather than read back off the value, which is what it
  /// used to be. Warmth and vibrance run from cool to warm through
  /// zero, and zero is both the middle of the track and the easiest
  /// value to land on mid-drag — so "on when the value is not zero"
  /// tore the slider out from under the user's finger the moment they
  /// crossed the centre, and flipped its own switch off. The switch
  /// turns an effect on; the slider sets the amount, and nothing is
  /// unusual about setting it to none.
  late final Set<String> _open = {
    for (final row in _rows(widget.effects))
      if (row.$2 != 0) row.$1,
  };

  /// The effect the slider is setting: the one last switched on, or
  /// last tapped while on.
  late String? _focus = _open.isEmpty ? null : _open.first;

  /// Name and current value of every effect with an amount, in order.
  static List<(String, double)> _rows(ReelEffects e) => [
        ('warmth', e.warmth),
        ('vibrance', e.vibrance),
        ('vignette', e.vignette),
        ('grain', e.grain),
      ];

  /// Where an effect lands when it is switched on: a strength somebody
  /// would actually have chosen, rather than zero and a switch that
  /// looks broken.
  static const _defaults = {
    'warmth': 0.5,
    'vibrance': 0.4,
    'vignette': 0.5,
    'grain': 0.4,
  };

  double _value(ReelEffects e, String row) => switch (row) {
        'warmth' => e.warmth,
        'vibrance' => e.vibrance,
        'vignette' => e.vignette,
        _ => e.grain,
      };

  ReelEffects _with(ReelEffects e, String row, double v) => switch (row) {
        'warmth' => e.copyWith(warmth: v),
        'vibrance' => e.copyWith(vibrance: v),
        'vignette' => e.copyWith(vignette: v),
        _ => e.copyWith(grain: v),
      };

  void _toggle(String row, bool on) {
    HapticFeedback.selectionClick();
    final s = creationState;
    setState(() {
      if (on) {
        _open.add(row);
        _focus = row;
      } else {
        _open.remove(row);
        if (_focus == row) _focus = _open.isEmpty ? null : _open.last;
      }
    });
    s.setEffects(_with(widget.effects, row, on ? _defaults[row]! : 0));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    final e = widget.effects;
    // Each look's chip is the *reel's own* colours put through it,
    // taken off the chosen scenery's measured gradient. A row of
    // identical stock swatches would say what the grade does to some
    // other picture.
    final grad = s.background?.gradientArgb ?? const [0xFF1B2735, 0xFFC79A5B];
    String name(String row) => switch (row) {
          'warmth' => l.effectWarmth,
          'vibrance' => l.effectVibrance,
          'vignette' => l.effectVignette,
          _ => l.effectGrain,
        };
    IconData icon(String row) => switch (row) {
          'warmth' => Icons.wb_sunny_outlined,
          'vibrance' => Icons.palette_outlined,
          'vignette' => Icons.vignette_outlined,
          _ => Icons.grain_rounded,
        };
    final focus = _focus != null && _open.contains(_focus) ? _focus : null;
    return _PanelBody(
      children: [
        _LookGrid(
          gradient: grad,
          chosen: e.look,
          onPick: (look) {
            HapticFeedback.selectionClick();
            s.setEffects(e.copyWith(look: look));
          },
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            const pad = 16.0, gap = 6.0;
            final w = (box.maxWidth - 2 * pad - gap) / 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: pad),
              child: Wrap(
                spacing: gap,
                runSpacing: 4,
                children: [
                  // First of the switches: it has no slider of its own,
                  // and up here it is in view on the shortest panel.
                  _EffectToggle(
                    width: w,
                    icon: Icons.gradient_rounded,
                    label: l.effectFadeShort,
                    a11yLabel: l.effectFade,
                    on: e.fade,
                    onToggle: (on) {
                      HapticFeedback.selectionClick();
                      s.setEffects(e.copyWith(fade: on));
                    },
                  ),
                  // The wide card's corners: a finish like the others,
                  // and one to try against them.
                  if (s.layout == ReelLayout.letterbox)
                    _EffectToggle(
                      width: w,
                      icon: Icons.rounded_corner_rounded,
                      label: l.roundedCorners,
                      on: s.roundedCorners,
                      onToggle: (on) {
                        HapticFeedback.selectionClick();
                        s.setRoundedCorners(on);
                      },
                    ),
                  for (final (row, _) in _rows(e))
                    _EffectToggle(
                      width: w,
                      icon: icon(row),
                      label: name(row),
                      on: _open.contains(row),
                      focused: focus == row,
                      onFocus: _open.contains(row) && focus != row
                          ? () {
                              HapticFeedback.selectionClick();
                              setState(() => _focus = row);
                            }
                          : null,
                      onToggle: (on) => _toggle(row, on),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 32,
          child: focus == null
              ? Center(
                  child: Text(
                    l.styleEffectAmountHint,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                )
              : _EffectSlider(
                  label: name(focus),
                  value: _value(e, focus),
                  min: focus == 'warmth' || focus == 'vibrance' ? -1 : 0,
                  onChanged: (v) => s.setEffects(_with(e, focus, v)),
                ),
        ),
      ],
    );
  }
}

/// The looks, four to a row and all in view: each a chip of the reel's
/// own colours put through it, with its name over them.
class _LookGrid extends StatelessWidget {
  final List<int> gradient;
  final ReelLook chosen;
  final ValueChanged<ReelLook> onPick;

  const _LookGrid({
    required this.gradient,
    required this.chosen,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 16.0, gap = 6.0;
        const perRow = 4;
        final w = (box.maxWidth - 2 * pad - gap * (perRow - 1)) / perRow;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: pad),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final look in ReelLook.values)
                _LookChip(
                  width: w,
                  look: look,
                  name: l.lookName(look.name),
                  gradient: gradient,
                  selected: chosen == look,
                  onTap: () => onPick(look),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One look: the reel's own colours put through it, its name over them.
class _LookChip extends StatelessWidget {
  final double width;
  final ReelLook look;
  final String name;
  final List<int> gradient;
  final bool selected;
  final VoidCallback onTap;

  const _LookChip({
    required this.width,
    required this.look,
    required this.name,
    required this.gradient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final swatch = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(gradient[0]), Color(gradient[1])],
        ),
      ),
    );
    return A11yTap(
      label: '${l.styleLook}${l.comma} $name',
      selected: selected,
      hint: l.a11yAppliesLook,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: 26,
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.stroke,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ReelFinish.graded(ReelEffects(look: look), swatch),
                ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        name,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? AppColors.goldBright
                              : Colors.white,
                          shadows: const [
                            Shadow(color: Color(0xAA000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// One effect: an icon, a name and its switch, half the panel wide.
/// Tapping the name of one that is on puts the slider on it.
class _EffectToggle extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;

  /// What a reader hears, when [label] is a short form of it.
  final String? a11yLabel;
  final bool on;

  /// Whether the slider under the switches is setting this one.
  final bool focused;
  final VoidCallback? onFocus;
  final ValueChanged<bool> onToggle;

  const _EffectToggle({
    required this.width,
    required this.icon,
    required this.label,
    required this.on,
    required this.onToggle,
    this.focused = false,
    this.onFocus,
    this.a11yLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 32,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 0, 0),
      decoration: BoxDecoration(
        color: focused
            ? AppColors.gold.withValues(alpha: 0.10)
            : AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: focused
              ? AppColors.gold.withValues(alpha: 0.55)
              : AppColors.stroke.withValues(alpha: 0.7),
        ),
      ),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onFocus ?? () => onToggle(!on),
                child: Row(
                  children: [
                    Icon(icon,
                        size: 16,
                        color:
                            on ? AppColors.goldBright : AppColors.textSecondary),
                    const SizedBox(width: 7),
                    Expanded(
                      // A short name on the row, the whole one read out.
                      child: Semantics(
                        label: a11yLabel,
                        excludeSemantics: a11yLabel != null,
                        child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: on
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Transform.scale(
              scale: 0.72,
              child: Switch(
                value: on,
                activeThumbColor: AppColors.gold,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onToggle,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The one slider: how much of the effect it is on.
class _EffectSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final ValueChanged<double> onChanged;

  const _EffectSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 74,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.goldBright,
                ),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 1.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
              ),
              // Merged, so the name lands on the slider's own node rather
              // than beside it: unmerged, a reader announces "Warmth" and
              // then, separately, "50 percent, slider".
              child: MergeSemantics(
                child: Semantics(
                  label: label,
                  child: Slider(
                    value: value.clamp(min, 1.0),
                    min: min,
                    max: 1,
                    activeColor: AppColors.gold,
                    inactiveColor: AppColors.surfaceRaised,
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
          ),
          ExcludeSemantics(
            child: SizedBox(
              width: 38,
              child: Text(
                '$pct%',
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
