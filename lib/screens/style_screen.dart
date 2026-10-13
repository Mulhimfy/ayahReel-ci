import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../data/media_aspect.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/reel_effects.dart';
import '../data/scene_catalog.dart';
import '../data/settings_service.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../l10n/l10n.dart';
import '../render/ayah_rasterizer.dart';
import '../render/letterbox_layout.dart';
import '../data/word_align_service.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/ayah_overlay.dart';
import '../widgets/glow_button.dart';
import '../widgets/ink_swatch.dart';
import '../widgets/measure_height.dart';
import '../widgets/reel_finish.dart';
import '../widgets/reel_watermark.dart';
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
enum _Panel { type, colour, effects }

/// Which of the reel's two colours the palette is setting.
enum _Target { verse, accent }

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
        s.resetColours();
      case _Panel.effects:
        s.setEffects(ReelEffects.off);
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
              // The panel takes a fixed share and scrolls inside it;
              // the frame takes what is left. The other way round —
              // a frame sized to the screen and a panel taking the
              // remainder — leaves a phone with a short screen showing
              // half a row of swatches and no way to know there are
              // more.
              final panelH = (box.maxHeight * 0.40).clamp(180.0, 272.0);
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
                            child: _Stage(ayah: _ayah, aspect: _aspect),
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

  Widget _panelBody(L10n l) => switch (_panel) {
        _Panel.type => _TypePanel(ayah: _ayah),
        _Panel.colour => _ColourPanel(
            target: _target,
            onTarget: (t) => _tap(() => setState(() => _target = t)),
            wordHighlight: creationState.reciter != null &&
                WordAlignService.supports(creationState.reciter!),
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

  const _Stage({required this.ayah, this.aspect});

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
        final verse = MeasureHeight(
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

/// A small heading inside a panel, with an optional line under it.
class _PanelHeading extends StatelessWidget {
  final String title;
  final String? body;

  const _PanelHeading(this.title, {this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          A11yHeader(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 3),
            Text(
              body!,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.35, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 10),
      children: [
        _PanelHeading(l.styleVerseFace),
        SizedBox(
          height: _FaceCard.twoLineHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: VerseFace.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = VerseFace.values[i];
              return _FaceCard(
                specimen: f.specimen,
                label: f.label,
                // Its own line height: the marks under a Quran face
                // reach well below the letters, and a line set any
                // tighter puts them on the name beneath.
                style: AppTheme.quran(size: 16, face: f)
                    .copyWith(color: AppColors.textPrimary),
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
        // Headed by the edition's own name rather than the word
        // "translation": somebody setting an Urdu line should see اردو
        // over the row that decides how their Urdu looks.
        _PanelHeading('${l.styleTranslationFace} · ${edition.nativeName}'),
        SizedBox(
          // A Latin face is named in itself, one line; an Arabic-script
          // one needs its Latin name under its specimen, as the verse's.
          height: edition.arabicScript
              ? _FaceCard.twoLineHeight
              : _FaceCard.oneLineHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: faces.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = faces[i];
              return _FaceCard(
                specimen: f.specimen,
                label: f.label,
                // Latin names sit on one tight line; an Arabic-script
                // specimen keeps its own height, for the same reason as
                // the verse's (Nastaliq reaches furthest of all).
                style: f.arabicScript
                    ? AppTheme.translation(size: 13.5, face: f)
                        .copyWith(color: AppColors.textPrimary)
                    : AppTheme.translation(size: 14.5, face: f)
                        .copyWith(color: AppColors.textPrimary, height: 1.3),
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
        _PanelHeading(l.styleSize),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
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
              const ExcludeSemantics(
                child: Text('Aa',
                    style:
                        TextStyle(fontSize: 17, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
  static const twoLineHeight = 58.0;

  /// A name set in its own face.
  static const oneLineHeight = 40.0;

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
          width: named ? null : 92,
          constraints: named ? const BoxConstraints(minWidth: 64) : null,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: named ? 14 : 6),
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
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
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

/// A small pill with a selected state — the presets, and the colour
/// panel's two targets.
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.16)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color:
                  selected ? AppColors.goldBright : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Colour
// ---------------------------------------------------------------------

/// One palette, two targets.
///
/// The verse and the accent draw on the same colours, so they are one
/// panel with a switch at the top rather than two. The switch shows
/// what each target is set to right now, so which of the reel's two
/// colours a tap is about to change is never a guess.
///
/// Under it, two kinds of colour. The luminous inks come first, each
/// shown as a word written in it over the reel's own ground: an ink is
/// light as much as colour, and a disc of it says little about what it
/// does to letters. Then the flat colours, one family to a row —
/// neutrals, warm, cool — so a warmer gold is found beside the gold.
class _ColourPanel extends StatelessWidget {
  final _Target target;
  final ValueChanged<_Target> onTarget;

  /// Whether the voice being set has a word to light as it is recited.
  final bool wordHighlight;

  const _ColourPanel({
    required this.target,
    required this.onTarget,
    required this.wordHighlight,
  });

  /// The flat palette, one family to a row. Sliced rather than listed
  /// again, so the palette stays the one place its colours are named.
  static List<List<int>> get _families => [
        versePalette.sublist(0, 8), // neutrals, light to dark
        versePalette.sublist(8, 16), // the golds, then warm
        versePalette.sublist(16, 24), // greens, then blues and violets
      ];

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    final verse = target == _Target.verse;
    final ink = verse ? s.verseInk : s.accentInk;
    final argb = verse ? s.textArgb : s.accentArgb;
    // Named for the target as well as the colour. The two sets of
    // swatches are otherwise identical to a reader, so without it
    // there is no way to know which of the reel's two colours a tap is
    // about to overwrite.
    final section = verse ? l.styleVerseColour : l.styleAccentColour;
    final inks = VerseInk.ordered(onLight: s.onLightGround);
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _TargetSwitch(target: target, onTap: onTarget),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(
            verse
                ? l.styleVerseColourBody
                // A voice the app cannot follow word by word has no
                // recited word to colour; saying so would be a claim
                // the frame never shows.
                : wordHighlight
                    ? l.styleAccentBody
                    : l.styleAccentRuleBody,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11.5, height: 1.35, color: AppColors.textSecondary),
          ),
        ),
        _PanelHeading(l.styleLuminous),
        SizedBox(
          height: _InkTile.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: inks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _InkTile(
              ink: inks[i],
              section: section,
              selected: ink == inks[i],
              onTap: () {
                HapticFeedback.selectionClick();
                if (verse) {
                  s.setVerseInk(inks[i]);
                } else {
                  s.setAccentInk(inks[i]);
                }
              },
            ),
          ),
        ),
        _PanelHeading(l.styleSolid),
        LayoutBuilder(
          builder: (context, box) {
            // Eight to a row on any phone: the targets narrow before a
            // family is ever broken across two lines.
            final cell = math.min(44.0, (box.maxWidth - 28) / 8);
            return Column(
              children: [
                for (final family in _families)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in family)
                        SizedBox(
                          width: cell,
                          height: 42,
                          child: _Swatch(
                            argb: c,
                            section: section,
                            selected: ink.isNone && argb == c,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (verse) {
                                s.setTextColor(c);
                              } else {
                                s.setAccentColor(c);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The two targets, side by side, each wearing the colour it is set to
/// and its name.
class _TargetSwitch extends StatelessWidget {
  final _Target target;
  final ValueChanged<_Target> onTap;

  const _TargetSwitch({required this.target, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    Widget half(_Target t) {
      final verse = t == _Target.verse;
      final ink = verse ? s.verseInk : s.accentInk;
      final argb = verse ? s.textArgb : s.accentArgb;
      final on = target == t;
      final label = verse ? l.styleVerseColour : l.styleAccentColour;
      final name = ink.isNone ? l.colourName(argb) : l.inkName(ink);
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
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 10),
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
                  if (ink.isNone)
                    _SolidDisc(argb: argb, size: 22)
                  else
                    InkDisc(ink: ink, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: on
                                ? AppColors.goldBright
                                : AppColors.textPrimary,
                          ),
                        ),
                        ExcludeSemantics(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.25,
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
          half(_Target.accent),
        ],
      ),
    );
  }
}

/// One luminous ink: a word written in it, over a small window of the
/// ground the verse will actually sit on, and its name.
class _InkTile extends StatelessWidget {
  static const height = 86.0;
  static const _width = 70.0;

  final VerseInk ink;
  final String section;
  final bool selected;
  final VoidCallback onTap;

  const _InkTile({
    required this.ink,
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = creationState;
    final onLight = s.onLightGround;
    final name = l.inkName(ink);
    return A11yTap(
      label: '$section${l.comma} ${l.a11yInkSwatch(ink)}',
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _width,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 60,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: selected ? AppColors.gold : AppColors.stroke,
                    width: selected ? 1.6 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const _Ground(),
                      Center(
                        child: InkSpecimen(
                          text: 'نور',
                          ink: ink,
                          // Short leading: one word, no marks above it,
                          // in a window a third the height of a line
                          // box.
                          style: AppTheme.quran(size: 25, face: s.verseFace)
                              .copyWith(height: 1.25),
                          halo: onLight
                              ? Color(legibleInkOn(ink.base))
                              : Colors.black,
                          // Half again the verse's own proportion: at
                          // 25px the true one is a glow a pixel or two
                          // wide, and the tile is here to show the
                          // light.
                          scale: 25 / 64 * 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              ExcludeSemantics(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.goldBright
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the verse sits on, in miniature: the band's flat colour in a
/// letterbox reel, otherwise the scenery under the scrim that darkens
/// it for the verse.
class _Ground extends StatelessWidget {
  const _Ground();

  @override
  Widget build(BuildContext context) {
    final s = creationState;
    if (s.layout == ReelLayout.letterbox &&
        s.backdrop == LetterboxBackdrop.colour) {
      return ColoredBox(color: Color(s.backdropArgb));
    }
    final b = s.background;
    final grad = b?.gradientArgb ?? const [0xFF1B2735, 0xFF0B0F14];
    final poster = b == null || b.isUserFile
        ? null
        : SceneCatalog.byId(b.id)?.thumbAsset;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(grad[0]), Color(grad[1])],
            ),
          ),
        ),
        if (poster != null)
          Image.asset(poster,
              fit: BoxFit.cover,
              cacheWidth: 160,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
      ],
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

/// A flat colour with a finger's worth of target around it. Chosen, it
/// is ringed in gold with a gap, so the ring never reads as part of the
/// colour.
class _Swatch extends StatelessWidget {
  final int argb;

  /// Which of the reel's two colours this row is setting.
  final String section;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.argb,
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return A11yTap(
      label: '$section${l.comma} ${l.a11yColourSwatch(argb)}',
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.gold : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: _SolidDisc(argb: argb, size: 26),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Effects
// ---------------------------------------------------------------------

/// The looks, then the five things that ride on top of one.
class _EffectsPanel extends StatefulWidget {
  /// What the rows are drawn from. See the call site for why this is
  /// passed in rather than read off the singleton.
  final ReelEffects effects;

  const _EffectsPanel({super.key, required this.effects});

  @override
  State<_EffectsPanel> createState() => _EffectsPanelState();
}

class _EffectsPanelState extends State<_EffectsPanel> {
  /// Which rows have their slider out.
  ///
  /// Held here rather than read back off the value, which is what it
  /// used to be. Warmth and vibrance run from cool to warm through
  /// zero, and zero is both the middle of the track and the easiest
  /// value to land on mid-drag — so "open when the value is not zero"
  /// tore the slider out from under the user's finger the moment they
  /// crossed the centre, collapsed the row, and flipped its own switch
  /// off. The toggle opens the row; the slider sets the amount, and
  /// nothing is unusual about setting it to none.
  late final Set<String> _open = {
    for (final row in _rows(widget.effects))
      if (row.$2 != 0) row.$1,
  };

  /// Name and current value of every row, in the order they are shown.
  static List<(String, double)> _rows(ReelEffects e) => [
        ('warmth', e.warmth),
        ('vibrance', e.vibrance),
        ('vignette', e.vignette),
        ('grain', e.grain),
      ];

  void _toggle(String row, bool on, void Function(double) set) {
    HapticFeedback.selectionClick();
    setState(() => on ? _open.add(row) : _open.remove(row));
    set(on ? _defaults[row]! : 0);
  }

  /// Where a row lands when it is switched on: a strength somebody
  /// would actually have chosen, rather than zero and a row that looks
  /// broken.
  static const _defaults = {
    'warmth': 0.5,
    'vibrance': 0.4,
    'vignette': 0.5,
    'grain': 0.4,
  };

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
    return ListView(
      padding: const EdgeInsets.only(bottom: 14),
      children: [
        _PanelHeading(l.styleLook, body: l.styleEffectsBody),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: ReelLook.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final look = ReelLook.values[i];
              return _LookCard(
                look: look,
                gradient: grad,
                selected: e.look == look,
                onTap: () {
                  HapticFeedback.selectionClick();
                  s.setEffects(e.copyWith(look: look));
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // First of the switches. At the foot of the list it sat under
        // four rows, below the fold of a short panel, and any slider
        // opened above it pushed it further down. It has no slider of
        // its own, so up here it never moves the rows under it.
        _EffectRow(
          icon: Icons.gradient_rounded,
          label: l.effectFade,
          on: e.fade,
          onToggle: (on) {
            HapticFeedback.selectionClick();
            s.setEffects(e.copyWith(fade: on));
          },
        ),
        _EffectRow(
          icon: Icons.wb_sunny_outlined,
          label: l.effectWarmth,
          on: _open.contains('warmth'),
          value: e.warmth,
          min: -1,
          onChanged: (v) => s.setEffects(e.copyWith(warmth: v)),
          onToggle: (on) => _toggle(
              'warmth', on, (v) => s.setEffects(e.copyWith(warmth: v))),
        ),
        _EffectRow(
          icon: Icons.palette_outlined,
          label: l.effectVibrance,
          on: _open.contains('vibrance'),
          value: e.vibrance,
          min: -1,
          onChanged: (v) => s.setEffects(e.copyWith(vibrance: v)),
          onToggle: (on) => _toggle(
              'vibrance', on, (v) => s.setEffects(e.copyWith(vibrance: v))),
        ),
        _EffectRow(
          icon: Icons.vignette_outlined,
          label: l.effectVignette,
          on: _open.contains('vignette'),
          value: e.vignette,
          onChanged: (v) => s.setEffects(e.copyWith(vignette: v)),
          onToggle: (on) => _toggle(
              'vignette', on, (v) => s.setEffects(e.copyWith(vignette: v))),
        ),
        _EffectRow(
          icon: Icons.grain_rounded,
          label: l.effectGrain,
          on: _open.contains('grain'),
          value: e.grain,
          note: l.styleGrainNote,
          onChanged: (v) => s.setEffects(e.copyWith(grain: v)),
          onToggle: (on) =>
              _toggle('grain', on, (v) => s.setEffects(e.copyWith(grain: v))),
        ),
      ],
    );
  }
}

/// One look, shown as the reel's own colours put through it.
class _LookCard extends StatelessWidget {
  final ReelLook look;
  final List<int> gradient;
  final bool selected;
  final VoidCallback onTap;

  const _LookCard({
    required this.look,
    required this.gradient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final name = l.lookName(look.name);
    final swatch = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 78,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox.expand(
                    child: ReelFinish.graded(
                      ReelEffects(look: look),
                      swatch,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
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

/// One effect: a name, a switch, and — once it is on — the one slider
/// that says how much of it.
///
/// A row each rather than a wall of sliders. Every one of these is off
/// by default and reads as off, so the panel opens saying "the picture
/// as it was" rather than asking five questions at once; and switching
/// one on gives it a strength somebody would actually have chosen,
/// instead of landing on zero and looking broken.
class _EffectRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;

  /// Null for an effect that is a switch and nothing else.
  final double? value;
  final double min;
  final String? note;
  final ValueChanged<double>? onChanged;

  /// What the switch does. Always given — the row does not decide for
  /// itself what turning an effect on means, because whether the row
  /// is open is not the same question as whether its value is zero.
  final ValueChanged<bool>? onToggle;

  const _EffectRow({
    required this.icon,
    required this.label,
    required this.on,
    this.value,
    this.min = 0,
    this.note,
    this.onChanged,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final pct = value == null ? null : (value! * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(icon,
                    size: 17,
                    color: on ? AppColors.goldBright : AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color:
                          on ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (on && pct != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ExcludeSemantics(
                      child: Text(
                        '$pct%',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                Transform.scale(
                  scale: 0.78,
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
          if (on && value != null) ...[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 1.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
              ),
              // Merged, so the name lands on the slider's own node
              // rather than beside it: unmerged, a reader announces
              // "Warmth" and then, separately, "50 percent, slider".
              // The size slider in the type panel has always done it
              // this way.
              child: MergeSemantics(
                child: Semantics(
                  label: label,
                  child: Slider(
                  value: value!.clamp(min, 1.0),
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
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(27, 0, 8, 6),
                child: Text(
                  note!,
                  style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      color: AppColors.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
