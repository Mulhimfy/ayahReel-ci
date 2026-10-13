import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/models.dart';
import '../data/settings_service.dart';
import '../data/quran_repository.dart';
import '../data/reel_duration.dart';
import '../data/reel_limits.dart';
import '../data/series_library.dart';
import '../data/user_audio_service.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/glow_button.dart';
import '../widgets/step_dots.dart';
import '../widgets/surah_picker_sheet.dart';
import 'align_screen.dart';
import 'background_screen.dart';

/// Screen 2 of 4. One decision: which verses.
/// Any of the 114 surahs via a searchable picker; the user reads the
/// actual verse text while choosing — tap an ayah to start the run,
/// then tap its neighbours to grow it one ayah at a time, or hold an
/// ayah further off to reach it in one gesture.
class VersesScreen extends StatefulWidget {
  /// Opens with the range already in [creationState] selected and
  /// scrolled into view, instead of on nothing. The verse of the day
  /// and a series reel both arrive knowing their verses; the screen
  /// then exists so the user can *adjust* them, not choose them.
  final bool preselect;

  const VersesScreen({super.key, this.preselect = false});

  @override
  State<VersesScreen> createState() => _VersesScreenState();
}

class _VersesScreenState extends State<VersesScreen> {
  /// The reel's length cap, from [ReelLimits]. Enforced here against
  /// the clock — the recitation's own timings when they are on the
  /// device, [ReelDuration]'s estimate when they are not — and
  /// re-checked exactly in the preview. The ayah-count bound is the
  /// floor under both, for the beat before the surah's text has
  /// loaded and there is nothing to estimate from.
  static const maxReelMs = ReelLimits.maxReelMs;
  static const maxReelAyahs = ReelLimits.maxReelAyahs;

  // The surah last worked in — unless the voice just chosen never
  // recorded it, when the screen opens where every voice starts.
  int _surah = creationState.reciter?.hasSurah(creationState.surah) == false
      ? 1
      : creationState.surah;

  /// The picked run, always contiguous: both null (nothing picked
  /// yet) or both set, with `_end >= _start`.
  int? _start;
  int? _end;

  List<Ayah>? _ayahs;
  String? _loadError;

  final _list = ScrollController();

  /// Whether the preselected run still has to be scrolled into view —
  /// once, the first time the list has verses to scroll to.
  bool _revealPending = false;

  /// Laid-out height of one verse tile plus its gap, for the first
  /// jump towards a preselected ayah. Tiles vary with the verse's
  /// length, so this is an estimate: it lands near enough for the
  /// tile to be built, and [_selectedKey] then says where it really
  /// is. On its own it used to land a verse or two off, and the user
  /// was left scrolling to a selection the screen had promised to
  /// show them.
  static const _tileEstimate = 128.0;

  /// A key per built tile, by ayah number, so the reveal can ask a
  /// tile where it actually is — the selected one when it is built,
  /// and the nearest built one when it is not, to step from.
  final _tileKeys = <int, GlobalKey>{};
  GlobalKey _keyFor(int ayah) => _tileKeys.putIfAbsent(ayah, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    if (widget.preselect) {
      _start = creationState.startAyah;
      _end = creationState.endAyah;
      _revealPending = true;
    }
    _loadAyahs();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  /// Puts the preselected run on screen, a little below the top so
  /// the verse before it shows where the run begins.
  ///
  /// Two moves. The first is a jump by estimate, which gets the list
  /// building tiles in the right neighbourhood; the second, a frame
  /// later, asks the first selected tile where it actually landed and
  /// scrolls it to the top of the viewport. Repeated a couple of
  /// times because the tiles built by the first correction can move
  /// the target again.
  void _revealSelection() {
    if (!_revealPending) return;
    final s = _start;
    if (s == null) return;
    _revealPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_list.hasClients) return;
      final at = ((s - 1) * _tileEstimate - 40)
          .clamp(0.0, _list.position.maxScrollExtent);
      _list.jumpTo(at);
      WidgetsBinding.instance.addPostFrameCallback((_) => _settleOnSelected());
    });
  }

  /// Settles the list on the selected tile, or steps towards it.
  ///
  /// The jump by estimate can land a long way off on a long surah —
  /// Al-Baqarah's tiles average well under the estimate, so a jump to
  /// verse 255 used to overshoot by screens, find no selected tile
  /// built there, and give up. Now a miss is a step: the nearest
  /// built tile says where the list is and how tall a tile really is,
  /// and the next jump closes most of the gap. A few passes bring the
  /// selection into the built window, where ensureVisible finishes.
  void _settleOnSelected([int pass = 0]) {
    if (!mounted || !_list.hasClients) return;
    final s = _start;
    final ayahs = _ayahs;
    if (s == null || ayahs == null) return;
    void again() {
      if (pass < 10) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _settleOnSelected(pass + 1));
      }
    }

    final ctx = _keyFor(s).currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.06);
      // The tiles built by this move can shift the target again.
      if (pass < 2 || pass == 10) return;
      again();
      return;
    }
    final n = ayahs.length;
    for (var k = 1; k < n; k++) {
      for (final m in [s - k, s + k]) {
        if (m < 1 || m > n) continue;
        final c = _keyFor(m).currentContext;
        if (c == null) continue;
        final box = c.findRenderObject();
        final tile = (box is RenderBox ? box.size.height : _tileEstimate) + 10;
        final at = (_list.offset + (s - m) * tile)
            .clamp(0.0, _list.position.maxScrollExtent);
        _list.jumpTo(at);
        again();
        return;
      }
    }
  }

  Future<void> _loadAyahs() async {
    setState(() {
      _ayahs = QuranRepository.ayahsIfCached(_surah);
      _loadError = null;
    });
    if (_ayahs != null) return;
    final requested = _surah;
    try {
      final ayahs = await QuranRepository.ayahsOf(requested);
      if (mounted && _surah == requested) {
        setState(() => _ayahs = ayahs);
      }
    } catch (_) {
      if (mounted && _surah == requested) {
        setState(() => _loadError = L10n.current.surahLoadError);
      }
    }
  }

  Future<void> _pickSurah() async {
    final picked = await showSurahPicker(context,
        unavailable: creationState.reciter?.missingSurahs ?? const {});
    if (picked == null) return;
    final a = picked.ayah;
    if (a == null &&
        picked.number == _surah &&
        picked.number == creationState.surah) {
      return;
    }
    HapticFeedback.selectionClick();
    final sameSurah = picked.number == _surah;
    setState(() {
      _surah = picked.number;
      // A search that named an ayah opens on it, selected, and the
      // list scrolls there; one that only named the surah opens at
      // the top with nothing chosen.
      _start = a;
      _end = a == null ? null : (picked.endAyah ?? a);
      _revealPending = a != null;
      if (!sameSurah) _ayahs = null;
    });
    creationState.selectSurah(picked.number);
    if (a != null) creationState.selectRange(a, picked.endAyah ?? a);
    // Another surah is another reel: whatever series this one was
    // opened from, it no longer stands for that reel of it.
    creationState.setSeriesTarget(null);
    if (!sameSurah) _loadAyahs();
  }

  /// How long the run [s]..[e] will run, and whether that is measured
  /// or estimated.
  ///
  /// Measured whenever this recitation's timings are already on the
  /// device — coming back from the preview, or a second reel from the
  /// same surah. Estimated otherwise, from the verses' own text: see
  /// [ReelDuration]. Null only before the surah's text has loaded,
  /// which is also before anything can be tapped.
  ({int ms, bool exact})? _lengthOf(int s, int e) {
    final r = creationState.reciter;
    final rec =
        r == null ? null : QuranRepository.recitationIfCached(r.id, _surah);
    if (rec != null && rec.covers(s, e)) {
      return (ms: rec.timing(e).endMs - rec.timing(s).startMs, exact: true);
    }
    // An upload has no pace to estimate from: how long these verses run
    // is a property of one recording, not of the text, and until the
    // timing screen has placed them nobody knows it. Better to say
    // nothing than to quote a stranger's reading back at the user.
    if (r != null && r.isUserAudio) return null;
    final ayahs = _ayahs;
    if (ayahs == null) return null;
    return (
      ms: ReelDuration.estimateMs(
        ayahs,
        startAyah: s,
        endAyah: e,
        pace: r?.pace ?? 1.0,
      ),
      exact: false,
    );
  }

  /// Whether the run [s]..[e] still fits one reel.
  ///
  /// The clock decides, measured or estimated — the picker used to let
  /// anything through while the timings were unknown, which is exactly
  /// the case that matters: the first reel from a surah is the one
  /// nobody has downloaded yet, and it was the preview that cut it
  /// back, long after the choosing was over. The ayah bound stays as
  /// the floor under both, for the moment before the text has loaded.
  bool _fits(int s, int e) {
    if (e - s + 1 > maxReelAyahs) return false;
    final len = _lengthOf(s, e);
    return len == null || len.ms <= maxReelMs;
  }

  /// The current run is longer than a reel may be.
  ///
  /// Reachable even though every tap is refused past the cap: the
  /// timings can *arrive* under a selection made against an estimate —
  /// the prefetch lands, or the user comes back from the preview — and
  /// the real ones can be longer. The banner is the answer, and it
  /// holds the Continue button shut until the run is back inside.
  bool get _overCap => _start != null && _end != null && !_fits(_start!, _end!);

  /// Cuts the run back to the last ayah that fits, from the banner.
  void _trimToFit() {
    final s = _start;
    final e = _end;
    if (s == null || e == null) return;
    _select(s, _lastFitting(s, e), strong: true);
  }

  /// The run is built one ayah at a time: the first tap opens it, each
  /// later tap on the ayah just above or just below extends it, and a
  /// tap inside drops that ayah along with everything after it.
  /// A tap that would leave a gap is refused — a reel that skips an
  /// ayah recites the Quran wrong, so it must not be reachable.
  void _tap(int n) {
    final s = _start;
    final e = _end;
    if (s == null || e == null) {
      _select(n, n);
      return;
    }
    if (n >= s && n <= e) {
      // Tapping the run's first ayah leaves nothing selected.
      if (n == s) {
        HapticFeedback.selectionClick();
        setState(() {
          _start = null;
          _end = null;
        });
      } else {
        _select(s, n - 1);
      }
      return;
    }
    if (n != s - 1 && n != e + 1) {
      _refuse(L10n.of(context).ayahsMustFollowOn);
      return;
    }
    final grownStart = n < s ? n : s;
    final grownEnd = n > e ? n : e;
    if (!_fits(grownStart, grownEnd)) {
      _refuse(L10n.of(context).reelCapReached);
      return;
    }
    _select(grownStart, grownEnd);
  }

  /// Hold an ayah to reach it in one gesture: the run stretches (or
  /// pulls back) to end at [n], carrying everything in between with
  /// it, so a long passage does not cost one tap per ayah. The run
  /// still has no holes in it — that is the point of taking the whole
  /// span rather than the ayah alone.
  ///
  /// Reaching past what fits in a reel stops at the last ayah that
  /// does, and says so; a tap in the same spot is refused outright,
  /// because a tap only ever asks for the one next ayah.
  void _extendTo(int n) {
    final s = _start;
    final e = _end;
    if (s == null || e == null) {
      _select(n, n, strong: true);
      return;
    }
    if (n >= s && n <= e) {
      // Held inside the run: it ends where the finger landed.
      _select(s, n, strong: true);
      return;
    }
    final forward = n > e;
    final capped = forward ? _lastFitting(s, n) : _firstFitting(n, e);
    if (forward) {
      _select(s, capped, strong: true);
    } else {
      _select(capped, e, strong: true);
    }
    if (capped != n) _say(L10n.of(context).reelCapReached);
  }

  /// Furthest end at or before [wanted] that still fits, growing
  /// forward from [s]. Both walkers stop at the opposite edge, so the
  /// run never comes back empty.
  int _lastFitting(int s, int wanted) {
    var e = wanted;
    while (e > s && !_fits(s, e)) {
      e--;
    }
    return e;
  }

  /// Earliest start at or after [wanted] that still fits, growing
  /// backward from [e].
  int _firstFitting(int wanted, int e) {
    var s = wanted;
    while (s < e && !_fits(s, e)) {
      s++;
    }
    return s;
  }

  /// [strong] is for the long-press: it moves more of the run than a
  /// tap does, so it confirms with a firmer bump.
  void _select(int s, int e, {bool strong = false}) {
    if (strong) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _start = s;
      _end = e;
    });
    // The surah on screen can differ from the reel's: a voice that never
    // recorded the reel's surah opens the picker on Al-Fatiha instead.
    // The range is of the surah the user is looking at.
    if (creationState.surah != _surah) creationState.selectSurah(_surah);
    creationState.selectRange(s, e);
  }

  /// A refused tap gets its own bump, not the selection click every
  /// accepted tap makes — the hand knows before the eye reads.
  void _refuse(String message) {
    HapticFeedback.lightImpact();
    _say(message);
  }

  /// One snackbar at a time: taps on a far-off ayah come in bursts.
  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  bool _inRange(int n) => _start != null && n >= _start! && n <= _end!;

  /// What the Continue button says the run comes to.
  ///
  /// A length either way — measured when the recitation is on the
  /// device, estimated from the verses themselves when it is not. The
  /// verse count it used to fall back to answered a question nobody
  /// was asking: the reel is bounded by minutes, so minutes are what
  /// someone choosing needs to watch.
  String _lengthLabel(L10n l) {
    final s = _start;
    if (creationState.reciter == null || s == null) return '';
    final len = _lengthOf(s, _end!);
    if (len == null) return l.versesCount(_end! - s + 1);
    return len.exact ? l.reelLength(len.ms) : l.reelLengthAbout(len.ms);
  }

  void _continue() {
    final r = creationState.reciter;
    // A series reel whose run the user moved: the plan follows them,
    // so the day's card reads back the verses they chose rather than
    // the ones the planner dealt.
    final target = creationState.seriesTarget;
    final s = _start, e = _end;
    if (target != null && s != null && e != null) {
      SeriesLibrary.setReelRange(
        target.seriesId,
        target.reelIndex,
        startAyah: s,
        endAyah: e,
        estimateMs: ReelDuration.estimateMs(
          _ayahs ?? const [],
          startAyah: s,
          endAyah: e,
          pace: r?.pace ?? 1.0,
        ),
      );
    }
    // An uploaded recitation goes by way of the timing screen: nothing
    // downstream can draw a verse until it knows which second of the
    // recording that verse is. Every other voice already has an exact
    // table waiting for it, so it goes straight on.
    final upload = UserAudioService.current;
    if (r != null && r.isUserAudio && upload != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AlignScreen(audio: upload)),
      );
      return;
    }
    // Warm the audio cache now: by the time the user has picked a
    // background, the recitation is often already assembled.
    if (r != null) {
      QuranRepository.prefetchRecitation(
        r,
        _surah,
        startAyah: creationState.startAyah,
        endAyah: creationState.endAyah,
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BackgroundScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final info = QuranRepository.surahInfo(_surah);
    final hasSelection = _start != null;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: StepDots(current: WizardSteps.verses, total: WizardSteps.total),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              A11yHeader(child: Text(l.chooseTheVerses, style: t.headlineMedium)),
              const SizedBox(height: 6),
              Text(l.tapAyahsInOrder, style: t.bodyMedium),
              const SizedBox(height: 16),
              _SurahSelector(info: info, onTap: _pickSurah),
              const SizedBox(height: 14),
              Expanded(child: _buildList(t)),
              const SizedBox(height: 14),
              // The cap, said where the choosing happens. It used to be
              // said in the preview, after the download, by trimming
              // the selection — which is the same information arriving
              // too late to be a choice.
              if (_overCap) ...[
                // Live: it arrives on its own when the timings land,
                // and shuts the button — the reader has to hear why.
                A11yLive(child: _CapBanner(onTrim: _trimToFit)),
                const SizedBox(height: 10),
              ],
              GlowButton(
                label: hasSelection
                    ? l.continueWith(_lengthLabel(l))
                    : l.continueLabel,
                icon: Icons.arrow_forward_rounded,
                onPressed: hasSelection && !_overCap ? _continue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(TextTheme t) {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 42, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(_loadError!, textAlign: TextAlign.center, style: t.bodyMedium),
            const SizedBox(height: 14),
            QuietButton(
              label: L10n.of(context).tryAgain,
              icon: Icons.refresh_rounded,
              onPressed: _loadAyahs,
            ),
          ],
        ),
      );
    }
    final ayahs = _ayahs;
    if (ayahs == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }
    _revealSelection();
    return ListView.separated(
      controller: _list,
      itemCount: ayahs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = ayahs[i];
        final selected = _inRange(a.number);
        final isEdge = a.number == _start || a.number == _end;
        return _VerseTile(
          key: _keyFor(a.number),
          ayah: a,
          selected: selected,
          edge: isEdge,
          onTap: () => _tap(a.number),
          onLongPress: () => _extendTo(a.number),
        );
      },
    );
  }
}

/// The tappable "current surah" card that opens the full picker.
class _SurahSelector extends StatelessWidget {
  final SurahInfo info;
  final VoidCallback onTap;
  const _SurahSelector({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Semantics(
      container: true,
      button: true,
      hint: l.a11yOpensSurahPicker,
      child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            children: [
              // The surah's number is ornament here; its name is the
              // thing to say.
              ExcludeSemantics(
                child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.12),
                ),
                child: Text('${info.number}',
                    style: t.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.gold,
                    )),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.surahTitle(info), style: t.titleMedium),
                    Text(
                      l.versesCount(info.ayahCount),
                      style: t.bodyMedium?.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              // The title already IS the Arabic name in Arabic mode.
              if (!l.usesArabicNames)
                ExcludeSemantics(
                  child: Text(info.nameArabic,
                      style: AppTheme.quran(
                          size: 18, color: AppColors.textPrimary)),
                ),
              const SizedBox(width: 10),
              const Icon(Icons.unfold_more_rounded,
                  size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Shown under the list when the run is longer than a reel may be,
/// with the one action that fixes it.
///
/// Not a snackbar: a snackbar is for something that just happened, and
/// this is a state the screen is in until it is dealt with. It sits
/// where it does — directly above the button it has shut — so the
/// reason and the consequence are read together.
class _CapBanner extends StatelessWidget {
  final VoidCallback onTrim;
  const _CapBanner({required this.onTrim});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.overReelCap,
              style: t.bodySmall?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onTrim,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.goldBright,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l.trimToFit),
          ),
        ],
      ),
    );
  }
}

class _VerseTile extends StatelessWidget {
  final Ayah ayah;
  final bool selected;
  final bool edge;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _VerseTile({
    super.key,
    required this.ayah,
    required this.selected,
    required this.edge,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    // One button per verse: its number, the verse, its meaning, and
    // whether it is in the run. The hint spells out the two gestures,
    // because the long press is the only way a reader has to reach a
    // verse further off.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      hint: l.a11yVerseTileHint,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.gold.withValues(alpha: edge ? 0.16 : 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.gold : AppColors.stroke,
          width: edge ? 1.6 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? AppColors.gold
                        : AppColors.gold.withValues(alpha: 0.10),
                  ),
                  // "Ayah 3", not a bare "3" before the verse.
                  child: Semantics(
                    label: l.ayahRange(ayah.number, ayah.number),
                    excludeSemantics: true,
                    child: Text(
                      '${ayah.number}',
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? const Color(0xFF14100A)
                            : AppColors.gold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        ayah.arabic,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        style: AppTheme.quran(
                          size: 20,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Builder(builder: (context) {
                        // The picker's translation line runs in its own
                        // edition's direction and face, exactly as the
                        // verse card does — otherwise an Urdu line here
                        // would be tofu, and right-aligned text would
                        // sit against the wrong edge.
                        final e = SettingsService.state.value.translation;
                        return Text(
                          ayah.translation,
                          textDirection: e.direction,
                          textAlign:
                              e.rtl ? TextAlign.right : TextAlign.left,
                          style: AppTheme.translation(
                            size: 12.5,
                            arabic: e.arabicScript,
                            color: AppColors.textSecondary,
                          ).copyWith(fontStyle: FontStyle.normal),
                        );
                      }),
                    ],
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
