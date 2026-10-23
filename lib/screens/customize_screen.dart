import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/offline_pack.dart';
import '../data/quran_verses.dart';
import '../data/scene_catalog.dart';
import '../data/settings_service.dart';
import '../data/verse_lines.dart';
import '../data/verse_motion.dart';
import '../data/verse_font.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
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
import '../widgets/offline_sheet.dart';
import '../widgets/surah_title.dart';
import '../widgets/verse_stage.dart';
import '../widgets/scene_poster_image.dart';

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

  /// The reel's sceneries turning over line by line, when they do.
  @visibleForTesting
  static const groundKey = ValueKey('customize-ground');

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
      s.basmala &&
      !s.surahTitle &&
      s.verseNumbering == VerseNumbering.mark &&
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
      basmala: true,
      surahTitle: false,
      verseNumbering: VerseNumbering.mark,
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
    final sections = <Widget>[
        Text(
          l.customizeIntro,
          style: t.bodyMedium?.copyWith(
              fontSize: 13, height: 1.4, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),

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
            // Every look in one row, all in view: the cards narrow on a
            // small phone rather than run off its edge.
            _FullBleed(
              child: LayoutBuilder(
                builder: (context, box) {
                  const pad = 16.0, gap = 8.0;
                  final n = MotionPreset.values.length;
                  final w = ((box.maxWidth - 2 * pad - gap * (n - 1)) / n)
                      .clamp(52.0, 88.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: pad),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < n; i++) ...[
                          if (i > 0) const SizedBox(width: gap),
                          MotionPresetCard(
                            preset: MotionPreset.values[i],
                            width: w,
                            selected:
                                MotionPreset.of(c.motion) == MotionPreset.values[i],
                            // A default for reels to come, whose voices are
                            // not chosen yet: every look is on offer, and a
                            // voice without word timing plays the part it can.
                            enabled: true,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              c.setMotion(MotionPreset.values[i].motion);
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                },
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
            _SwitchLine(
              icon: Icons.auto_stories_outlined,
              title: l.basmalaTitle,
              note: l.basmalaNote,
              value: s.basmala,
              onChanged: (on) => update((x) => x.copyWith(basmala: on)),
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
            const SizedBox(height: 10),
            // What the choice puts on a reel, in one small line: the end
            // of Ayat al-Kursi with whatever the choice adds lit gold.
            _NumberingSample(
              numbering: s.verseNumbering,
              edition: s.translation,
              face: c.verseFace,
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
        const SizedBox(height: 14),

        // ---- everything a reel needs from the network, kept -------------
        _Section(
          title: l.offlineSection,
          children: [
            ValueListenableBuilder<OfflineProgress>(
              valueListenable: OfflinePack.state,
              builder: (context, run, _) => _NavLine(
                icon: Icons.download_rounded,
                title: l.offlineTitle,
                note: run.running
                    ? l.offlineRunning((run.fraction * 100).floor())
                    : l.offlineRowNote,
                busy: run.running,
                onTap: () {
                  HapticFeedback.selectionClick();
                  showOfflineSheet(context);
                },
              ),
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
    ];
    // The reel stays in view while the choices under it scroll: it is
    // what every one of them is seen on. It gives up half its height as
    // the page moves, never more, and is drawn whole at every size.
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth * 0.58, 236.0).floorToDouble();
      final h = (w * 16 / 9).floorToDouble();
      return CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _PreviewHeader(
              settings: s,
              frameW: w,
              frameH: h,
              caption: l.customizePreviewCaption,
              a11yLabel: l.a11yCustomizePreview,
            ),
          ),
          // One column, not a lazy list: five sections are cheap to lay
          // out at once, and an exact length keeps the end of the page
          // where the finger left it (an estimated one shrank under the
          // pinned reel mid-scroll).
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sections,
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The reel at the head of the page, pinned: full size at the top, half
/// its height once the page has scrolled, the caption under it fading
/// as it shrinks. Opaque, so the choices pass under it rather than
/// through it.
class _PreviewHeader extends SliverPersistentHeaderDelegate {
  final AppSettings settings;
  final double frameW;
  final double frameH;
  final String caption;
  final String a11yLabel;

  _PreviewHeader({
    required this.settings,
    required this.frameW,
    required this.frameH,
    required this.caption,
    required this.a11yLabel,
  });

  static const _top = 4.0;
  static const _bottom = 10.0;
  static const _captionH = 24.0;

  /// How small the reel gets: half, still big enough to read a line.
  static const _least = 0.5;

  @override
  double get maxExtent => _top + frameH + _captionH + _bottom;

  @override
  double get minExtent => _top + frameH * _least + _bottom;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final room = maxExtent - minExtent;
    final k = room <= 0 ? 0.0 : (shrinkOffset / room).clamp(0.0, 1.0);
    final scale = 1 - (1 - _least) * k;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bg,
        // A hairline once the page runs under it, so the edge reads.
        border: Border(
          bottom: BorderSide(
            color: AppColors.stroke.withValues(alpha: k * 0.9),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: _top),
          Semantics(
            image: true,
            label: a11yLabel,
            child: ExcludeSemantics(
              child: SizedBox(
                width: frameW * scale,
                height: frameH * scale,
                child: FittedBox(
                  child: SizedBox(
                    width: frameW,
                    height: frameH,
                    child: _ReelPreview(
                        settings: settings, width: frameW, height: frameH),
                  ),
                ),
              ),
            ),
          ),
          if (k < 1)
            Expanded(
              child: Opacity(
                opacity: (1 - k * 2).clamp(0.0, 1.0),
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ExcludeSemantics(
                    child: Text(
                      caption,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            letterSpacing: 0.2,
                            color: AppColors.textSecondary,
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

  // The reel also answers to the reel flow's own choices (the motion,
  // the highlight), which are not in [settings]: every rebuild of the
  // page is passed on.
  @override
  bool shouldRebuild(covariant _PreviewHeader old) => true;
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
  final double width;
  final double height;

  const _ReelPreview(
      {required this.settings, required this.width, required this.height});

  @override
  State<_ReelPreview> createState() => _ReelPreviewState();
}

class _ReelPreviewState extends State<_ReelPreview>
    with SingleTickerProviderStateMixin {
  /// A beat between the end of the verse and its start again.
  static const _restMs = 1100;

  late final AnimationController _c = AnimationController(vsync: this);
  final _clock = ValueNotifier<int>(0);

  /// The line on screen, by its place in the cut: what the scenery
  /// turns over on when it follows the lines. Moves only when the line
  /// does, so the ground is rebuilt a few times a verse, not every frame.
  final _line = ValueNotifier<int>(0);

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
      final units = _demo?.units;
      if (units != null && units.isNotEmpty) {
        _line.value = VerseUnit.indexAt(units, _clock.value);
      }
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
    _line.dispose();
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
    final s = widget.settings;
    final c = creationState;
    final demo = _demo;
    final ayah = _ayah;
    final rec = _rec;
    final w = widget.width;
    final h = widget.height;
    // The scenery turns over at every line when it follows them — as a
    // reel's does — and stays put for the verse when it doesn't.
    final perLine = s.scenesFollowLines &&
        s.verseLines > VerseLines.whole &&
        (demo?.units.length ?? 0) > 1;
    final grounds = _grounds(c, perLine ? demo!.units.length : 1, w);
    return Container(
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
              if (grounds.length < 2)
                grounds.first
              else
                ValueListenableBuilder<int>(
                  valueListenable: _line,
                  builder: (_, line, __) => AnimatedSwitcher(
                    key: CustomizeScreen.groundKey,
                    duration: const Duration(milliseconds: 450),
                    child: KeyedSubtree(
                      key: ValueKey(line % grounds.length),
                      child: grounds[line % grounds.length],
                    ),
                  ),
                ),
              if (s.surahTitle)
                Align(
                  alignment: const Alignment(0, -0.76),
                  child: SurahTitleLine(
                    surah: 2,
                    width: w,
                    edition: s.translation,
                    look: c.surahTitleLook,
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
  }

  /// The grounds the demo deals out, [n] of them at most: the reel's own
  /// run of sceneries when it has more than one, else the scenery last
  /// chosen and, after it, the first of its tab's — every one of them a
  /// poster the app ships, so the page never waits on the network. A
  /// scenery of the user's own is one ground, with the shipped ones
  /// after it.
  List<Widget> _grounds(CreationState c, int n, double w) {
    final run = c.scenes;
    if (run.length > 1) {
      return [
        for (final b in run.take(math.max(1, n))) _Ground(scene: b, width: w),
      ];
    }
    final first = c.background;
    final out = <Widget>[_Ground(scene: first, width: w)];
    if (n < 2) return out;
    final own = first == null ? null : SceneCatalog.byId(first.id);
    // Portrait sceneries only: the preview is a full frame, with no
    // letterbox for a wide one to sit in.
    final tab = own != null && !own.wide ? own.tab : 'sky';
    for (final sc in SceneCatalog.inTab(tab)) {
      if (out.length >= math.min(n, 6)) break;
      if (sc.id == first?.id || sc.wide) continue;
      out.add(_Poster(scene: sc));
    }
    return out;
  }
}

/// A scenery from the catalog, drawn from the poster the app ships for
/// it, under the reel's scrim.
class _Poster extends StatelessWidget {
  final Scene scene;

  const _Poster({required this.scene});

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(scene.gradientArgb[0]),
                  Color(scene.gradientArgb[1]),
                ],
              ),
            ),
          ),
          ScenePosterImage(scene),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AyahRasterizer.scrimGradient),
          ),
        ],
      );
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
    final thumb = b.isUserFile ? null : SceneCatalog.byId(b.id);
    if (thumb != null) {
      picture = ScenePosterImage(thumb);
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

/// The end of Ayat al-Kursi as a reel card ends it, with whatever the
/// verse-number choice adds: the numbered sign after the last word, the
/// reference under it, both, or neither. What was just added glows in
/// and settles, so a tap on a chip shows what that chip did.
class _NumberingSample extends StatelessWidget {
  final VerseNumbering numbering;
  final VerseTranslation edition;
  final VerseFace face;

  const _NumberingSample({
    required this.numbering,
    required this.edition,
    required this.face,
  });

  /// The last words of 2:255.
  static const _tail = 'وَهُوَ ٱلْعَلِىُّ ٱلْعَظِيمُ';

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final verse = AppTheme.quran(size: 17, face: face, color: Colors.white);
    final mark = ayahEndMark(face, 255);
    final markStyle = AppTheme.quran(size: 17, face: mark.face);
    final ref = verseReferenceLine(2, 255, edition);
    return Semantics(
      label: l.a11yNumberingSample(l.verseNumberingLabel(numbering)),
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.stroke.withValues(alpha: 0.7)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [...previous, if (current != null) current],
          ),
          child: Column(
            key: ValueKey(numbering),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: '… $_tail'),
                  if (numbering.showsMark)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _Lit(
                        child: Text(
                          '\u00A0${mark.text}',
                          textDirection: TextDirection.rtl,
                          style: verse.copyWith(
                            fontFamily: markStyle.fontFamily,
                            fontFamilyFallback: markStyle.fontFamilyFallback,
                            fontSize: markStyle.fontSize,
                            color: AppColors.goldBright,
                          ),
                        ),
                      ),
                    ),
                ]),
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: verse.copyWith(height: 1.5),
              ),
              if (numbering.showsReference && ref.isNotEmpty)
                _Lit(
                  child: Text(
                    ref,
                    textAlign: TextAlign.center,
                    textDirection: edition.direction,
                    style: AppTheme.translation(
                      size: 11,
                      arabic: edition.arabicScript,
                      color: AppColors.goldBright,
                    ).copyWith(
                      fontStyle: FontStyle.normal,
                      letterSpacing: edition.arabicScript ? 0 : 1.0,
                    ),
                  ),
                ),
              if (numbering == VerseNumbering.off)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l.numberingNothingAdded,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glows in gold once, then settles: how [_NumberingSample] points at
/// what a choice just added.
class _Lit extends StatelessWidget {
  final Widget child;

  const _Lit({required this.child});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (_, glow, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: AppColors.goldBright.withValues(alpha: 0.45 * glow),
              blurRadius: 14 * glow,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// A choice that opens something, with a line under its name saying
/// what it does — or how far it has got.
class _NavLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;
  final bool busy;
  final VoidCallback onTap;

  const _NavLine({
    required this.icon,
    required this.title,
    required this.note,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.goldBright),
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
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: busy
                            ? AppColors.goldBright
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary),
            ],
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
