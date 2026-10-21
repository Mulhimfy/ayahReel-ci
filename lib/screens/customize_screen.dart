import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/quran_verses.dart';
import '../data/scene_catalog.dart';
import '../data/settings_service.dart';
import '../data/verse_lines.dart';
import '../data/verse_motion.dart';
import '../data/verse_numbering.dart';
import '../l10n/l10n.dart';
import '../render/ayah_rasterizer.dart';
import '../render/verse_planner.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/glow_button.dart' show QuietButton;
import '../widgets/illumination.dart' show SealGlyph;
import '../widgets/motion_picker.dart' show MotionPresetCard;
import '../widgets/surah_title.dart';
import '../widgets/verse_stage.dart';

/// Settings → Customize: how every reel is made, on a page of its own.
///
/// The set-once choices about the reels themselves — how a long verse
/// appears, whether the scenery follows its lines, how the verse moves
/// and whether each word lights, the surah's name, the verse numbers,
/// the video's quality. They dropped from the Settings row as a menu,
/// then opened under it as a panel; both had to describe what each
/// choice does. A page has room to show it instead: a reel plays at its
/// head — Ayat al-Kursi, recited at an even pace, in the reel's own
/// verse card — and every change below plays there at once.
///
/// What Settings keeps is read by every new reel (see
/// [CreationState.startNewReel]); the motion and the word highlight are
/// the reel flow's own preferences, the same ones the style step sets,
/// which carry from reel to reel and launch to launch (`LastChoices`).
class CustomizeScreen extends StatelessWidget {
  const CustomizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: A11yHeader(child: Text(l.customizeTitle, style: t.titleMedium)),
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<AppSettings>(
          valueListenable: SettingsService.state,
          builder: (context, s, _) => ListenableBuilder(
            listenable: creationState,
            builder: (context, _) => _Page(settings: s),
          ),
        ),
      ),
    );
  }

  /// Read fresh at every change: the page stays open across them, and a
  /// settings value it was built with may already be stale.
  static void update(AppSettings Function(AppSettings s) change) {
    HapticFeedback.selectionClick();
    SettingsService.update(change(SettingsService.state.value));
  }

  /// Whether everything on the page is what a new install has.
  static bool isDefault(AppSettings s, CreationState c) =>
      s.verseLines == VerseLines.preferred &&
      s.scenesFollowLines &&
      !s.surahTitle &&
      s.verseNumbering == VerseNumbering.off &&
      !s.highQualityVideo &&
      c.motion == VerseMotion.standard &&
      c.wordHighlight;

  /// Everything on the page back to what a new install has, and nothing
  /// else in Settings.
  static void reset() {
    HapticFeedback.mediumImpact();
    SettingsService.update(SettingsService.state.value.copyWith(
      verseLines: VerseLines.preferred,
      scenesFollowLines: true,
      surahTitle: false,
      verseNumbering: VerseNumbering.off,
      highQualityVideo: false,
    ));
    creationState
      ..setMotion(VerseMotion.standard)
      ..setWordHighlight(true);
  }
}

class _Page extends StatelessWidget {
  final AppSettings settings;

  const _Page({required this.settings});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final s = settings;
    final c = creationState;
    final lines = s.verseLines > VerseLines.whole;
    const update = CustomizeScreen.update;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
      children: [
        Text(
          l.customizeIntro,
          style: t.bodyMedium?.copyWith(
              fontSize: 13, height: 1.4, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        _ReelPreview(settings: s),
        const SizedBox(height: 20),

        // ---- long verses, and the scenery that follows their lines ----
        _Section(
          title: l.longVersesTitle,
          note: l.longVersesNote,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ChoiceTile(
                    title: l.versesWhole,
                    note: l.versesWholeNote,
                    chosen: !lines,
                    art: const _LinesArt(byLine: false),
                    onTap: () => update((x) => x.copyWith(verseLines: 0)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ChoiceTile(
                    title: l.versesLines,
                    note: l.versesLinesNote,
                    chosen: lines,
                    art: _LinesArt(byLine: true, animate: lines),
                    onTap: () => update((x) => x.copyWith(
                        verseLines: x.verseLines > 0
                            ? x.verseLines
                            : VerseLines.preferred)),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !lines
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.linesAtOnce,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            for (final n in VerseLines.choices) ...[
                              const SizedBox(width: 8),
                              _CountChip(
                                n: n,
                                label: l.linesCount(n),
                                chosen: s.verseLines == n,
                                onTap: () =>
                                    update((x) => x.copyWith(verseLines: n)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l.linesTimingNote,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const _Rule(),
                        _Label(l.scenesChangeTitle, note: l.scenesChangeNote),
                        const SizedBox(height: 10),
                        _Segmented(
                          options: [l.scenesEveryLine, l.scenesEveryVerse],
                          chosen: s.scenesFollowLines ? 0 : 1,
                          onPick: (i) => update(
                              (x) => x.copyWith(scenesFollowLines: i == 0)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ---- how the verse moves, and the word that lights ------------
        _Section(
          title: l.motionTitle,
          note: l.customizeMotionNote,
          children: [
            _FullBleed(
              child: SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: MotionPreset.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final p = MotionPreset.values[i];
                    return MotionPresetCard(
                      preset: p,
                      selected: MotionPreset.of(c.motion) == p,
                      // A default for reels to come, whose voices are not
                      // chosen yet: every look is on offer, and a voice
                      // without word timing plays the part it can.
                      enabled: true,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        c.setMotion(p.motion);
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.motionFollowsWords,
              style: const TextStyle(
                  fontSize: 11, height: 1.35, color: AppColors.textSecondary),
            ),
            const _Rule(),
            _SwitchLine(
              icon: Icons.auto_awesome_rounded,
              title: l.highlightRecitedWord,
              note: l.wordHighlightNote,
              value: c.wordHighlight,
              onChanged: (on) {
                HapticFeedback.selectionClick();
                c.setWordHighlight(on);
              },
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ---- what else the reel carries ----------------------------------
        _Section(
          title: l.customizeOnReel,
          children: [
            _SwitchLine(
              icon: Icons.menu_book_rounded,
              title: l.surahNameTitle,
              note: l.surahNameNote,
              value: s.surahTitle,
              onChanged: (on) => update((x) => x.copyWith(surahTitle: on)),
            ),
            const _Rule(),
            _Label(l.verseNumbersTitle, note: l.verseNumbersNote),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in VerseNumbering.values)
                  _WordChip(
                    label: l.verseNumberingLabel(v),
                    chosen: s.verseNumbering == v,
                    onTap: () => update((x) => x.copyWith(verseNumbering: v)),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

        _Section(
          title: l.customizeVideo,
          children: [
            _SwitchLine(
              icon: Icons.videocam_outlined,
              title: l.highQualityVideo,
              note: l.highQualityNote,
              value: s.highQualityVideo,
              onChanged: (on) =>
                  update((x) => x.copyWith(highQualityVideo: on)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Center(
          child: QuietButton(
            label: l.customizeReset,
            icon: Icons.refresh_rounded,
            onPressed: CustomizeScreen.isDefault(s, c)
                ? null
                : () {
                    CustomizeScreen.reset();
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(toast(l.customizeResetDone,
                          tone: ToastTone.done));
                  },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// The reel at the head of the page
// ---------------------------------------------------------------------

/// A reel playing Ayat al-Kursi with the page's choices: the real verse
/// card through the reel's own [VerseStage], cut into lines as a reel
/// cuts it, moving as the chosen motion moves, the surah's name above it
/// when it is on. The recitation is a stand-in, every letter as long as
/// the next (see [VersePlanner.demo]), so only the timing is invented.
class _ReelPreview extends StatefulWidget {
  final AppSettings settings;

  const _ReelPreview({required this.settings});

  @override
  State<_ReelPreview> createState() => _ReelPreviewState();
}

class _ReelPreviewState extends State<_ReelPreview>
    with SingleTickerProviderStateMixin {
  /// A beat between the end of the verse and its start again.
  static const _restMs = 1100;

  late final AnimationController _c = AnimationController(vsync: this);
  final _clock = ValueNotifier<int>(0);

  String? _key;
  Ayah? _ayah;
  ({
    List<VerseUnit> units,
    List<HighlightSpan> spans,
    List<(int, int)?> times,
    int verseMs,
  })? _demo;
  Recitation? _rec;
  List<Ayah> _ayahs = const [];

  /// The stand-in's word windows and token windows, by verse, kept as
  /// long as the cut: [VerseStage] starts its own caches over whenever
  /// it is handed different ones.
  Map<int, List<HighlightSpan>> _words = const {};
  Map<int, List<(int, int)?>> _times = const {};
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final d = _c.duration?.inMilliseconds ?? 0;
      _clock.value = (_c.value * d).round();
    });
    _plan();
    _restart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still != _still) {
      _still = still;
      _restart();
    }
  }

  @override
  void didUpdateWidget(covariant _ReelPreview old) {
    super.didUpdateWidget(old);
    // A choice that moves a line starts the verse over, so its effect
    // is seen from the first line rather than caught halfway.
    if (_plan()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restart();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _clock.dispose();
    super.dispose();
  }

  VerseLook get _look {
    final s = widget.settings;
    final c = creationState;
    return VerseLook(
      textScale: c.textScale,
      preset: c.textPreset,
      typography: c.typography,
      edition: s.translation,
      numbering: s.verseNumbering,
      showTranslation: !s.verseTranslationOff,
      ink: c.verseInk,
      surah: 2,
    );
  }

  /// Cuts the verse again if anything a line answers to has changed.
  /// Answers whether it did.
  bool _plan() {
    final s = widget.settings;
    final look = _look;
    final key = '${s.verseLines}|${look.key}';
    if (key == _key) return false;
    _key = key;
    final v = quranVerses.firstWhere(
        (v) => v.surah == 2 && v.startAyah == 255,
        orElse: () => quranVerses.first);
    final ayah = Ayah(
      number: v.startAyah,
      arabic: v.arabic,
      translation: v.translationIn(s.translation),
    );
    final demo = VersePlanner.demo(ayah: ayah, lines: s.verseLines, look: look);
    _ayah = ayah;
    _demo = demo;
    _rec = Recitation(
      reciterId: 'demo',
      surah: v.surah,
      audioPath: '',
      timings: [AyahTiming(ayah.number, 0, demo.verseMs)],
    );
    _ayahs = List.filled(ayah.number, ayah);
    _words = {ayah.number: demo.spans};
    _times = {ayah.number: demo.times};
    _c.duration = Duration(milliseconds: demo.verseMs + _restMs);
    return true;
  }

  void _restart() {
    if (_still) {
      // Held on the first line, its light halfway across, for a phone
      // that asks for less motion.
      _c.stop();
      final d = _c.duration?.inMilliseconds ?? 1;
      final first = _demo?.units.first;
      final mid = first == null ? 0 : (first.startMs + first.endMs) ~/ 2;
      _c.value = (mid / d).clamp(0.0, 1.0);
      return;
    }
    _c
      ..value = 0
      ..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final s = widget.settings;
    final c = creationState;
    final demo = _demo;
    final ayah = _ayah;
    final rec = _rec;
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth * 0.58, 236.0).floorToDouble();
      final h = (w * 16 / 9).floorToDouble();
      final frame = Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.075),
          border: Border.all(color: AppColors.stroke),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.07),
              blurRadius: 40,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(w * 0.075),
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Ground(scene: c.background, width: w),
                if (s.surahTitle)
                  Align(
                    alignment: const Alignment(0, -0.76),
                    child: SurahTitleLine(
                      surah: 2,
                      width: w,
                      edition: s.translation,
                    ),
                  ),
                if (demo != null && ayah != null && rec != null)
                  Align(
                    alignment: Alignment(0, c.overlayAlign * 2 - 1),
                    child: VerseStage(
                      clock: _clock,
                      units: demo.units,
                      ayahs: _ayahs,
                      recitation: rec,
                      motion: c.motion,
                      words: _words,
                      highlight: c.wordHighlight,
                      wordTimes: _times,
                      width: w,
                      textColor: Color(c.textArgb),
                      accent: Color(c.accentArgb),
                      ink: c.verseInk,
                      accentInk: c.accentInk,
                      textScale: c.textScale,
                      preset: c.textPreset,
                      onLight: false,
                      translation: s.translation,
                      numbering: s.verseNumbering,
                      showTranslation: !s.verseTranslationOff,
                      surah: 2,
                      verseFace: c.verseFace,
                      translationFace: c.typography.translation,
                      onHeight: (_) {},
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      return Column(
        children: [
          Semantics(
            image: true,
            label: l.a11yCustomizePreview,
            child: ExcludeSemantics(child: Center(child: frame)),
          ),
          const SizedBox(height: 10),
          ExcludeSemantics(
            child: Text(
              l.customizePreviewCaption,
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(
                fontSize: 11.5,
                letterSpacing: 0.2,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The scenery the user last chose, as the preview's ground: the
/// catalog's own small thumbnail of it, or a photo of their own decoded
/// small, under the reel's scrim — and the night below when there is
/// none, or a clip of their own, which there is no still of.
class _Ground extends StatelessWidget {
  final ReelBackground? scene;
  final double width;

  const _Ground({required this.scene, required this.width});

  @override
  Widget build(BuildContext context) {
    final b = scene;
    if (b == null) return const _NightGround();
    final decodeW = (width * MediaQuery.devicePixelRatioOf(context)).round();
    Widget fallback(BuildContext _, Object __, StackTrace? ___) =>
        const SizedBox.shrink();
    Widget? picture;
    final thumb = b.isUserFile ? null : SceneCatalog.byId(b.id)?.thumbAsset;
    if (thumb != null) {
      picture = Image.asset(thumb,
          fit: BoxFit.cover, excludeFromSemantics: true, errorBuilder: fallback);
    } else if (b.isImage && b.imageAsset.isNotEmpty) {
      picture = Image.asset(b.imageAsset,
          fit: BoxFit.cover,
          cacheWidth: decodeW,
          excludeFromSemantics: true,
          errorBuilder: fallback);
    } else if (b.isDeviceFile && b.fileIsImage) {
      picture = Image.file(File(b.filePath!),
          fit: BoxFit.cover,
          cacheWidth: decodeW,
          excludeFromSemantics: true,
          errorBuilder: fallback);
    }
    if (picture == null) return const _NightGround();
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(b.gradientArgb[0]), Color(b.gradientArgb[1])],
            ),
          ),
        ),
        picture,
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AyahRasterizer.scrimGradient),
        ),
      ],
    );
  }
}

/// The ground the preview's verse sits on: a night going to dawn, with
/// the glow of the light low in the frame — dark enough under the verse
/// for the reel's white ink, as darkened scenery is.
class _NightGround extends StatelessWidget {
  const _NightGround();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1726), Color(0xFF18202E), Color(0xFF33261A)],
            stops: [0, 0.58, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 1.15),
              radius: 0.95,
              colors: [Color(0x40E8A93A), Color(0x00E8A93A)],
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------
// The page's parts
// ---------------------------------------------------------------------

/// One group of choices, in the card Settings draws its rows in.
class _Section extends StatelessWidget {
  final String title;
  final String? note;
  final List<Widget> children;

  const _Section({required this.title, this.note, required this.children});

  static const _radius = BorderRadius.all(Radius.circular(22));

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const side = EdgeInsets.symmetric(horizontal: 16);
    // Clipped to its own corners, and the edge drawn over what it holds:
    // a strip that scrolls sideways runs to the card's edge and under
    // it, rather than stopping short of it at the padding.
    return ClipRRect(
      borderRadius: _radius,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: _radius,
          border: Border.all(color: AppColors.stroke.withValues(alpha: 0.9)),
        ),
        child: ColoredBox(
          color: AppColors.surface.withValues(alpha: 0.84),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: side,
                  child: _heading(l),
                ),
                const SizedBox(height: 14),
                for (final c in children)
                  c is _FullBleed ? c.child : Padding(padding: side, child: c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(L10n l) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SealGlyph(size: 7, color: Color(0x99D4A947)),
              const SizedBox(width: 8),
              Expanded(
                // A heading, read in its own case: capitals are for
                // the eye, and some readers spell an all-caps word out.
                child: Semantics(
                  header: true,
                  label: title,
                  excludeSemantics: true,
                  child: Text(
                    l.arabicScript ? title : title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: l.arabicScript ? 0 : 1.2,
                      color: AppColors.gold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
            ),
          ],
        ],
      );
}

/// A part of a [_Section] laid edge to edge, past the section's padding:
/// a strip that scrolls sideways, which carries its own.
class _FullBleed extends StatelessWidget {
  final Widget child;

  const _FullBleed({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// A choice's name inside a section, with a line under it.
class _Label extends StatelessWidget {
  final String text;
  final String? note;

  const _Label(this.text, {this.note});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 3),
          Text(
            note!,
            style: const TextStyle(
                fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// A hairline between the parts of a section.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppColors.stroke.withValues(alpha: 0),
              AppColors.stroke,
              AppColors.stroke.withValues(alpha: 0),
            ]),
          ),
        ),
      );
}

/// One of two large choices, drawn rather than described.
class _ChoiceTile extends StatelessWidget {
  final String title;
  final String note;
  final bool chosen;
  final Widget art;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.title,
    required this.note,
    required this.chosen,
    required this.art,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
          decoration: BoxDecoration(
            color: chosen
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.surfaceRaised.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: chosen ? AppColors.gold : AppColors.stroke,
              width: chosen ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 30, height: 54, child: art),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                        color: chosen
                            ? AppColors.goldBright
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      note,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A phone's frame with a verse in it, in shapes: the whole verse small
/// and at once, or a line of it large, the next coming on after.
class _LinesArt extends StatefulWidget {
  final bool byLine;
  final bool animate;

  const _LinesArt({required this.byLine, this.animate = false});

  @override
  State<_LinesArt> createState() => _LinesArtState();
}

class _LinesArtState extends State<_LinesArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LinesArt old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.animate || still) {
      _c
        ..stop()
        ..value = 0.3;
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
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(painter: _LinesPainter(_c, widget.byLine)),
      );
}

class _LinesPainter extends CustomPainter {
  final Animation<double> t;
  final bool byLine;

  _LinesPainter(this.t, this.byLine) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.width * 0.2));
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF233046), Color(0xFF32261A)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.stroke);
    final w = size.width, h = size.height;
    void bar(double y, double share, double thick, double a) {
      final bw = w * share;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(w / 2, y), width: bw, height: thick),
            Radius.circular(thick / 2)),
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }

    if (!byLine) {
      // The whole verse at once, small.
      const shares = [0.7, 0.62, 0.7, 0.5, 0.58];
      for (var i = 0; i < shares.length; i++) {
        bar(h * (0.32 + i * 0.09), shares[i], h * 0.035, 0.8);
      }
      return;
    }
    // One line at a time, large, the next coming on after it.
    final p = t.value;
    final second = p > 0.5;
    final local = second ? (p - 0.5) * 2 : p * 2;
    final fadeIn = (local / 0.18).clamp(0.0, 1.0);
    final fadeOut = ((1 - local) / 0.15).clamp(0.0, 1.0);
    final a = math.min(fadeIn, fadeOut) * 0.92;
    bar(h * 0.5, second ? 0.62 : 0.74, h * 0.075, a);
    // The light passing along it, as the default motion does.
    final lit = (local - 0.18) / 0.62;
    if (lit > 0 && lit < 1) {
      final bw = w * (second ? 0.62 : 0.74);
      final x = w / 2 + bw / 2 - bw * lit;
      canvas.drawCircle(
        Offset(x, h * 0.5),
        h * 0.05,
        Paint()
          ..color = AppColors.goldBright.withValues(alpha: a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.03),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) => old.byLine != byLine;
}

/// "1 line", "2 lines", "3 lines", drawn as the number alone.
class _CountChip extends StatelessWidget {
  final int n;
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  const _CountChip({
    required this.n,
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: chosen
                ? AppColors.gold.withValues(alpha: 0.18)
                : AppColors.surfaceRaised,
            border: Border.all(
              color: chosen ? AppColors.gold : AppColors.stroke,
              width: chosen ? 1.4 : 1,
            ),
          ),
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: chosen ? AppColors.goldBright : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of choices that share one track.
class _Segmented extends StatelessWidget {
  final List<String> options;
  final int chosen;
  final ValueChanged<int> onPick;

  const _Segmented({
    required this.options,
    required this.chosen,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == chosen,
                inMutuallyExclusiveGroup: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == chosen
                          ? AppColors.gold.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      options[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            i == chosen ? FontWeight.w600 : FontWeight.w400,
                        color: i == chosen
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
    );
  }
}

/// A chip for one of several choices: the verse numbers.
class _WordChip extends StatelessWidget {
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  const _WordChip({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: chosen
                ? AppColors.gold.withValues(alpha: 0.16)
                : AppColors.surfaceRaised.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: chosen ? AppColors.gold : AppColors.stroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
              color: chosen ? AppColors.goldBright : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// An on/off choice with a line under its name saying what it does.
class _SwitchLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchLine({
    required this.icon,
    required this.title,
    required this.note,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      toggled: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: value
                      ? AppColors.goldBright
                      : AppColors.gold.withValues(alpha: 0.62)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      note,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: _Pill(value: value, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small switch Settings draws everywhere: a pill and a thumb.
class _Pill extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Pill({required this.value, required this.onChanged});

  static const _w = 34.0;
  static const _h = 19.0;
  static const _thumb = 13.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: _w,
        height: _h,
        padding: const EdgeInsets.all((_h - _thumb) / 2),
        decoration: BoxDecoration(
          color: value ? AppColors.gold : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(_h / 2),
          border: Border.all(
            color: value ? AppColors.gold : AppColors.stroke,
            width: 0.8,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            width: _thumb,
            height: _thumb,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? const Color(0xFF14100A) : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
