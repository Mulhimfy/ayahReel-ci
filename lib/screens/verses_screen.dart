import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../data/live_recitation.dart';
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
import '../widgets/app_toast.dart';
import '../widgets/glow_button.dart';
import '../widgets/how_to_sheet.dart';
import '../widgets/recitation_deck.dart';
import '../widgets/step_dots.dart';
import '../widgets/surah_picker_sheet.dart';
import 'align_screen.dart';
import 'background_screen.dart';

/// Screen 2 of 4. One decision: which verses.
/// Any of the 114 surahs, found from a search field that is open from
/// the start at the head of the screen; the user reads the actual verse
/// text while choosing — tap the first verse, then the last, and
/// everything between is chosen (see [_VersesScreenState._tap]).
///
/// And hears it: the surah plays in the chosen voice from the moment
/// the screen opens (see [LiveRecitation] and [RecitationDeck]). The
/// verse being recited is lit in the list, word by word for the voices
/// whose word timings are known, and the list follows it; a pull of the
/// line or a tap on it moves the voice and the light together, and so
/// does a verse's number. Choosing and hearing are two gestures: a tap
/// on a verse chooses it and leaves the voice alone, a tap on its
/// number plays it and leaves the choice alone.
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

class _VersesScreenState extends State<VersesScreen>
    with WidgetsBindingObserver {
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

  /// The list's own box, to ask whether a tile is wholly in view.
  final _listKey = GlobalKey();

  /// The surah, playing. Null for a recording the user brought in: it
  /// has no verses to follow until the timing screen has placed them.
  LiveRecitation? _live;

  /// The ayah a pull of the line would land on, while it is pulled.
  int? _previewAyah;

  /// The ayah the list last went to meet.
  int? _followed;

  /// When the user last moved the list by hand: for a few seconds after
  /// that the list is theirs, and the voice moving on does not take it
  /// back — unless they moved the voice themselves, which says where
  /// they want to be.
  DateTime _handScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _followUntil = DateTime.fromMillisecondsSinceEpoch(0);

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  /// The heading folds away once the list is scrolled into, to give the
  /// verses its room, and comes back at the top.
  bool _folded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The verses the last reel was made of, when the screen opens on
    // their surah: a reel begun again starts where the last one was,
    // and a tap anywhere else starts a new run (with an undo).
    if (widget.preselect ||
        (creationState.rangeChosen && _surah == creationState.surah)) {
      _start = creationState.startAyah;
      _end = creationState.endAyah;
      _revealPending = true;
    }
    final r = creationState.reciter;
    if (r != null && !r.isUserAudio) {
      _live = LiveRecitation()..addListener(_onLive);
    }
    _searchFocus.addListener(_onSearchFocus);
    _list.addListener(_onListScroll);
    _loadAyahs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live
      ?..removeListener(_onLive)
      ..dispose();
    _searchFocus.dispose();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  /// The voice stops when the app does: nothing else would stop it, as
  /// it plays without audio focus (see [LiveRecitation]).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _live?.pause();
    }
  }

  bool get _searching => _searchFocus.hasFocus || _query.isNotEmpty;

  void _onSearchFocus() {
    if (mounted) setState(() {});
  }

  void _onListScroll() {
    if (!_list.hasClients) return;
    final o = _list.offset;
    // Two thresholds, so the fold cannot flutter at one of them.
    final fold = _folded ? o > 8 : o > 56;
    if (fold != _folded) setState(() => _folded = fold);
  }

  bool _onScrollNote(ScrollNotification n) {
    if ((n is ScrollStartNotification && n.dragDetails != null) ||
        (n is ScrollUpdateNotification && n.dragDetails != null)) {
      _handScrolledAt = DateTime.now();
    }
    return false;
  }

  // ---- the voice --------------------------------------------------

  /// Plays the surah on screen, from [from] — the run's first ayah when
  /// there is a run, the top otherwise.
  void _openLive({int? from}) {
    final live = _live;
    final r = creationState.reciter;
    final ayahs = _ayahs;
    if (live == null || r == null || ayahs == null || !r.hasSurah(_surah)) {
      return;
    }
    _followed = null;
    unawaited(live.open(r, _surah, ayahs, from: from ?? _start ?? 1));
  }

  void _onLive() {
    if (!mounted) return;
    final live = _live!;
    // The deck, the lit tile, and the list's place.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
    final a = live.ayah;
    if (a != _followed && live.status != LiveStatus.idle) {
      _followed = a;
      _follow(a);
    }
  }

  /// The listener moved the voice: the list goes with it.
  void _userMovedVoice() {
    _followUntil = DateTime.now().add(const Duration(seconds: 2));
  }

  void _onPreviewAyah(int? a) {
    if (a == _previewAyah) return;
    setState(() => _previewAyah = a);
    if (a != null) {
      _userMovedVoice();
      _follow(a);
    }
  }

  /// Goes to meet ayah [a] in the list, unless the user has the list in
  /// hand.
  void _follow(int a) {
    final now = DateTime.now();
    final held = now.difference(_handScrolledAt) < const Duration(seconds: 4);
    if (held && now.isAfter(_followUntil)) return;
    if (_searching) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bringIntoView(a));
  }

  /// Scrolls ayah [a] into view — only as far as it takes, and not at
  /// all when it is already in full view, so a tap on a verse never
  /// moves the list under the finger. A tile not built yet is stepped
  /// towards, a frame at a time, until it is.
  void _bringIntoView(int a, [int pass = 0]) {
    if (!mounted || !_list.hasClients) return;
    final ctx = _keyFor(a).currentContext;
    if (ctx != null) {
      if (!_fullyShown(ctx)) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.14,
          duration: const Duration(milliseconds: 560),
          curve: Curves.easeInOutCubic,
        );
      }
      return;
    }
    final at = _estimateOffset(a);
    if (at == null || pass >= 4) return;
    void again() => WidgetsBinding.instance.endOfFrame
        .then((_) => _bringIntoView(a, pass + 1));
    if (pass == 0) {
      _list
          .animateTo(at,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOutCubic)
          .then((_) => again());
    } else {
      _list.jumpTo(at);
      again();
    }
  }

  /// Whether the tile at [ctx] is wholly inside the list's window.
  bool _fullyShown(BuildContext ctx) {
    final box = ctx.findRenderObject();
    final frame = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || frame is! RenderBox || !box.attached) {
      return false;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: frame).dy;
    return top >= -1 && top + box.size.height <= frame.size.height + 1;
  }

  /// Where the list would have to be for ayah [a] to sit a little below
  /// its top, worked out from the nearest tile that is built — the way
  /// [_settleOnSelected] steps towards a selection.
  double? _estimateOffset(int a) {
    final ayahs = _ayahs;
    if (ayahs == null || !_list.hasClients) return null;
    final max = _list.position.maxScrollExtent;
    final frame = _listKey.currentContext?.findRenderObject();
    final n = ayahs.length;
    for (var k = 1; k < n; k++) {
      for (final m in [a - k, a + k]) {
        if (m < 1 || m > n) continue;
        final box = _keyFor(m).currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || frame is! RenderBox) {
          continue;
        }
        final top = box.localToGlobal(Offset.zero, ancestor: frame).dy;
        final tile = box.size.height + 10;
        return (_list.offset + top + (a - m) * tile - 40).clamp(0.0, max);
      }
    }
    return ((a - 1) * _tileEstimate - 40).clamp(0.0, max);
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
    if (_ayahs != null) {
      // After this frame: the voice's first word is a notification, and
      // this can run inside initState.
      final opened = _surah;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _surah == opened) _openLive();
      });
      return;
    }
    final requested = _surah;
    try {
      final ayahs = await QuranRepository.ayahsOf(requested);
      if (mounted && _surah == requested) {
        setState(() => _ayahs = ayahs);
        _openLive();
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
    if (picked == null || !mounted) return;
    _applyPick(picked);
  }

  /// A pick from the search at the head of the screen: the search
  /// closes, and the surah opens where the sheet's pick would.
  void _pickFromSearch(SurahPick picked) {
    _endSearch();
    _applyPick(picked);
  }

  /// Enter in the search field takes the first surah it names.
  void _submitSearch(String q) {
    final pq = SurahPickerSheet.parse(q);
    final off = creationState.reciter?.missingSurahs ?? const <int>{};
    final hits = SurahPickerSheet.surahsMatching(pq)
        .where((s) => !off.contains(s.number))
        .toList();
    if (q.trim().isEmpty || hits.isEmpty) {
      _endSearch();
      return;
    }
    _pickFromSearch(
        SurahPick(hits.first, ayah: pq.ayah, endAyah: pq.endAyah));
  }

  void _endSearch() {
    _search.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _query = '';
      // The list comes back from the top; so does the heading.
      _folded = false;
    });
  }

  void _applyPick(SurahPick picked) {
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
    if (!sameSurah) {
      // Nothing of the old surah stays on the line while the new one's
      // verses load.
      _live?.clear();
      _loadAyahs();
    } else if (a != null) {
      // The surah on screen already: the voice goes to the ayah.
      _userMovedVoice();
      _live?.seekAyah(a);
    }
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

  /// How a tap chooses, with one thing to remember — the first verse,
  /// then the last:
  ///
  /// * nothing chosen: the run starts on the verse tapped;
  /// * one verse chosen: a tap on another takes everything between, as
  ///   far as a reel can run; a tap on the same one lets it go;
  /// * a run: its first or last verse drops off, a verse inside ends it
  ///   there, the verse just outside either end joins it, and a verse
  ///   further off starts a new run on itself — a far passage is a
  ///   scroll and two taps away, where it used to be a walk back to the
  ///   top to undo the old run first. The toast that says so can put
  ///   the old run back.
  ///
  /// The run never has a hole in it: a reel that skips an ayah recites
  /// the Quran wrong. Choosing never moves the voice; the verse's
  /// number does that ([_listenFrom]).
  void _tap(int n) {
    final s = _start;
    final e = _end;
    if (s == null || e == null) {
      _select(n, n);
      return;
    }
    if (s == e) {
      if (n == s) {
        _clear();
      } else {
        _reach(n);
      }
      return;
    }
    if (n == s) {
      _select(s + 1, e);
    } else if (n == e) {
      _select(s, e - 1);
    } else if (n > s && n < e) {
      _select(s, n);
    } else if (n == s - 1 || n == e + 1) {
      final grownStart = math.min(n, s);
      final grownEnd = math.max(n, e);
      if (!_fits(grownStart, grownEnd)) {
        _refuse(L10n.of(context).reelCapReached);
        return;
      }
      _select(grownStart, grownEnd);
    } else {
      _startAgain(n, was: (s, e));
    }
  }

  /// Hold an ayah to reach it in one gesture: the run stretches (or
  /// pulls back) to end at [n], carrying everything in between with
  /// it, so a long passage does not cost one tap per ayah — and a run
  /// can grow by more than a verse without starting again.
  void _extendTo(int n) {
    if (_start == null || _end == null) {
      _select(n, n, strong: true);
      return;
    }
    _reach(n, strong: true);
  }

  /// Stretches the run to [n], everything between included. Reaching
  /// past what fits in a reel stops at the last ayah that does, and
  /// says so.
  void _reach(int n, {bool strong = false}) {
    final s = _start!;
    final e = _end!;
    if (n >= s && n <= e) {
      _select(s, n, strong: strong);
      return;
    }
    final forward = n > e;
    final capped = forward ? _lastFitting(s, n) : _firstFitting(n, e);
    if (forward) {
      _select(s, capped, strong: strong);
    } else {
      _select(capped, e, strong: strong);
    }
    if (capped != n) _say(L10n.of(context).reelCapReached);
  }

  /// Lets the whole run go: the cross by the run's name, or a tap on a
  /// run of one.
  void _clear() {
    HapticFeedback.selectionClick();
    setState(() {
      _start = null;
      _end = null;
    });
  }

  /// A tap far from the run starts a new one there. The old run is one
  /// tap away, on the toast.
  void _startAgain(int n, {required (int, int) was}) {
    _select(n, n);
    final l = L10n.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(toast(
        l.versesStartedAgain(n),
        duration: const Duration(seconds: 3),
        actionLabel: l.undo,
        onAction: () {
          if (mounted) _select(was.$1, was.$2);
        },
      ));
  }

  /// Brings the run back into view, from its name under the list.
  void _showRun() {
    final s = _start;
    if (s == null) return;
    HapticFeedback.selectionClick();
    _handScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
    _bringIntoView(s);
  }

  /// A verse's number plays it: the voice goes to the start of that
  /// verse and sounds — or, on the verse it is sounding, pauses. The
  /// one way the list moves the voice; choosing never does.
  void _listenFrom(int n) {
    final live = _live;
    if (live == null || live.ayahCount == 0) return;
    HapticFeedback.selectionClick();
    if (live.ayah == n && live.wantsPlay) {
      live.pause();
      return;
    }
    _userMovedVoice();
    live.playAyah(n);
  }

  /// The "?" in the corner: the rules of [_tap], in five lines.
  void _howTo() {
    final l = L10n.of(context);
    const gold = AppColors.goldBright;
    showHowTo(
      context,
      title: l.versesHowToTitle,
      steps: [
        (
          const CustomPaint(size: Size(18, 10), painter: _RunGlyph()),
          l.versesHowToRange,
        ),
        (
          const Text('±',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: gold)),
          l.versesHowToEdges,
        ),
        (
          const Icon(Icons.refresh_rounded, size: 17, color: gold),
          l.versesHowToRestart,
        ),
        (
          const Icon(Icons.touch_app_rounded, size: 17, color: gold),
          l.versesHowToHold,
        ),
        (
          const CustomPaint(
              size: Size(16, 16), painter: _PlayMark(pause: false, lit: true)),
          l.versesHowToListen,
        ),
      ],
    );
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
      ..showSnackBar(toast(message, duration: const Duration(seconds: 2)));
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
    // The next screens have voices of their own.
    _live?.pause();
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
    final searching = _searching;
    final live = _live;
    return PopScope(
      // Back closes the search before it leaves the screen.
      canPop: !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: const BackButton(color: AppColors.textSecondary),
          title:
              StepDots(current: WizardSteps.verses, total: WizardSteps.total),
          actions: [
            HowToButton(label: l.versesHowToTitle, onTap: _howTo),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: LayoutBuilder(
              builder: (context, box) {
                // A short screen gives the verses the heading's room
                // from the start.
                final fold = searching || _folded || box.maxHeight < 560;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Fold(
                      folded: fold,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            A11yHeader(
                                child: Text(l.chooseTheVerses,
                                    style: t.headlineMedium)),
                            const SizedBox(height: 6),
                            Text(l.tapFirstThenLast, style: t.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                    // Open from the start, over the surah: no tap to
                    // find it.
                    _SearchBar(
                      controller: _search,
                      focus: _searchFocus,
                      hint: l.searchSurahHint,
                      clearLabel: l.clear,
                      onChanged: (v) => setState(() => _query = v),
                      onSubmitted: _submitSearch,
                      onClear: _endSearch,
                    ),
                    const SizedBox(height: 12),
                    if (searching)
                      Expanded(
                        child: SurahSearchResults(
                          query: _query,
                          unavailable:
                              creationState.reciter?.missingSurahs ?? const {},
                          onPick: _pickFromSearch,
                        ),
                      )
                    else ...[
                      if (live != null)
                        RecitationDeck(
                          live: live,
                          info: info,
                          reciter: creationState.reciter,
                          onOpenSurah: _pickSurah,
                          onPreviewAyah: _onPreviewAyah,
                          onUserMove: _userMovedVoice,
                        )
                      else
                        _SurahSelector(info: info, onTap: _pickSurah),
                      const SizedBox(height: 12),
                      Expanded(child: _buildList(t)),
                      const SizedBox(height: 10),
                      // What is chosen, by name: far verses are chosen
                      // out of sight of each other, and this is where
                      // the whole run can be seen, found and let go.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: hasSelection
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _RunChip(
                                  label: l.ayahRange(_start!, _end!),
                                  onShow: _showRun,
                                  onClear: _clear,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      // The cap, said where the choosing happens. It used
                      // to be said in the preview, after the download, by
                      // trimming the selection — which is the same
                      // information arriving too late to be a choice.
                      if (_overCap) ...[
                        // Live: it arrives on its own when the timings
                        // land, and shuts the button — the reader has to
                        // hear why.
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
                  ],
                );
              },
            ),
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
    final live = _live;
    final status = live?.status ?? LiveStatus.idle;
    final heard = status != LiveStatus.idle;
    // The ayah lit as the one being recited: where a pull would land
    // while the line is pulled, and where the voice is otherwise.
    final lit = _previewAyah ?? (heard ? live?.ayah : null);
    final sounding = heard &&
        _previewAyah == null &&
        (status == LiveStatus.playing || status == LiveStatus.loading);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNote,
      child: ListView.separated(
        key: _listKey,
        controller: _list,
        itemCount: ayahs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final a = ayahs[i];
          final selected = _inRange(a.number);
          final isEdge = a.number == _start || a.number == _end;
          final reciting = a.number == lit;
          final here = reciting && _previewAyah == null;
          return _VerseTile(
            key: _keyFor(a.number),
            ayah: a,
            selected: selected,
            edge: isEdge,
            reciting: reciting,
            // The light that moves with the voice is for the ayah the
            // voice is really on, not a pull's landing.
            live: reciting && _previewAyah == null ? live : null,
            sounding: reciting && sounding,
            listening: here && (live?.wantsPlay ?? false),
            onTap: () => _tap(a.number),
            onLongPress: () => _extendTo(a.number),
            onListen: live == null ? null : () => _listenFrom(a.number),
          );
        },
      ),
    );
  }
}

/// The surah, for a recitation the user brought: nothing plays here,
/// so the bar is only its name and the way into the full picker.
class _SurahSelector extends StatelessWidget {
  final SurahInfo info;
  final VoidCallback onTap;
  const _SurahSelector({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: SurahTitleButton(
        info: info,
        subtitle: l.versesCount(info.ayahCount),
        onTap: onTap,
      ),
    );
  }
}

/// The run, by name, under the list: a tap on the name brings it back
/// into view, the cross lets it go.
class _RunChip extends StatelessWidget {
  final String label;
  final VoidCallback onShow;
  final VoidCallback onClear;

  const _RunChip({
    required this.label,
    required this.onShow,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: A11yTap(
            label: label,
            hint: l.a11yShowsChosenVerses,
            onTap: onShow,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onShow,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Container(
                  key: ValueKey(label),
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.45)),
                  ),
                  // As wide as the words, not the row.
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.goldBright,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        A11yTap(
          label: l.clear,
          onTap: onClear,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClear,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.stroke),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 15, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
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

  /// The voice is on this ayah — or a pull of the line would land on it.
  final bool reciting;

  /// The recitation, when the voice is really here: what the light
  /// across the tile and the ring round its number are read from.
  final LiveRecitation? live;

  /// And is sounding it, so the light moves.
  final bool sounding;

  /// The voice is here and wants to sound: the number's mark is a pause.
  final bool listening;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Plays the verse, from its number; null when there is nothing to
  /// play it with.
  final VoidCallback? onListen;

  const _VerseTile({
    super.key,
    required this.ayah,
    required this.selected,
    required this.edge,
    required this.reciting,
    required this.live,
    required this.sounding,
    required this.listening,
    required this.onTap,
    required this.onLongPress,
    required this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // One button per verse: its number, the verse, its meaning, and
    // whether it is in the run. The hint spells out the two gestures.
    // The number is a button of its own, which plays the verse.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: l.ayahRange(ayah.number, ayah.number),
      hint: l.a11yVerseTileHint,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.gold.withValues(alpha: edge ? 0.16 : 0.08)
            : reciting
                ? AppColors.surfaceRaised
                : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? AppColors.gold
              : reciting
                  ? AppColors.goldBright
                      .withValues(alpha: sounding ? 0.85 : 0.5)
                  : AppColors.stroke,
          width: edge ? 1.6 : (reciting ? 1.3 : 1),
        ),
        // A halo while the voice is in this verse; none at all otherwise,
        // not even a transparent one — every tile would pay for its blur.
        boxShadow: reciting && sounding
            ? [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.26),
                  blurRadius: 24,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: onLongPress,
          child: _ReciteLight(
            live: live,
            sounding: sounding,
            builder: (words, frame) => Padding(
            // The number's button reaches past its disc, to a size a
            // thumb finds; the padding gives back what it takes.
            padding: const EdgeInsetsDirectional.fromSTEB(7, 5, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Medallion(
                  number: ayah.number,
                  selected: selected,
                  live: live,
                  frame: frame,
                  listening: listening,
                  onListen: onListen,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _verse(words),
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

  /// The verse, with the words the voice is on lit in gold — for the
  /// voices whose word timings are known.
  Widget _verse(({int start, int end})? words) {
    final style = AppTheme.quran(size: 20, color: AppColors.textPrimary);
    if (words == null) {
      return Text(
        ayah.arabic,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        style: style,
      );
    }
    final tokens = ayah.arabic.split(' ');
    final lit = style.copyWith(
      color: AppColors.goldBright,
      shadows: [
        Shadow(color: AppColors.gold.withValues(alpha: 0.55), blurRadius: 14),
      ],
    );
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < tokens.length; i++)
          TextSpan(
            text: i == 0 ? tokens[i] : ' ${tokens[i]}',
            style: i >= words.start && i < words.end ? lit : null,
          ),
      ]),
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      style: style,
    );
  }
}

/// A verse's number, and its play button. A tap here sounds the verse;
/// a tap anywhere else on the tile chooses it. A small mark at the
/// number's foot says so — play, or pause on the verse the voice is
/// sounding — and while the voice is in this verse a ring round the
/// number fills as the verse goes.
class _Medallion extends StatelessWidget {
  final int number;
  final bool selected;
  final LiveRecitation? live;
  final Listenable? frame;
  final bool listening;
  final VoidCallback? onListen;

  const _Medallion({
    required this.number,
    required this.selected,
    required this.live,
    required this.frame,
    required this.listening,
    required this.onListen,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final ring = frame;
    final disc = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
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
                child: Text(
                  '$number',
                  style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? const Color(0xFF14100A) : AppColors.gold,
                  ),
                ),
              ),
              // How far into the verse the voice is, round its number.
              if (ring != null)
                Positioned(
                  left: -4,
                  top: -4,
                  right: -4,
                  bottom: -4,
                  child: IgnorePointer(
                    child: CustomPaint(painter: _RingPainter(live!, ring)),
                  ),
                ),
              if (onListen != null)
                PositionedDirectional(
                  end: -5,
                  bottom: -4,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size(15, 15),
                      painter: _PlayMark(pause: listening, lit: ring != null),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final tap = onListen;
    if (tap == null) return ExcludeSemantics(child: disc);
    return A11yTap(
      label: listening ? l.pause : l.a11yListenFrom(number),
      onTap: tap,
      child: GestureDetector(
        key: ValueKey('listen-$number'),
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: disc,
      ),
    );
  }
}

/// The small play — or pause — mark at the foot of a verse's number,
/// and in the "?" sheet beside the line that explains it.
class _PlayMark extends CustomPainter {
  final bool pause;

  /// The voice is in this verse: the mark burns brighter.
  final bool lit;

  const _PlayMark({required this.pause, required this.lit});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // A rim in the tile's own colour parts it from the number's disc.
    canvas.drawCircle(c, r, Paint()..color = AppColors.surface);
    canvas.drawCircle(c, r - 1.4,
        Paint()..color = lit ? AppColors.goldBright : AppColors.gold);
    final ink = Paint()..color = const Color(0xFF14100A);
    if (pause) {
      for (final dx in [-r * 0.24, r * 0.24]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: c.translate(dx, 0), width: r * 0.26, height: r * 0.86),
            Radius.circular(r * 0.13),
          ),
          ink,
        );
      }
    } else {
      // Play points right in every language, as it does on any player.
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * 0.26, c.dy - r * 0.44)
          ..lineTo(c.dx + r * 0.48, c.dy)
          ..lineTo(c.dx - r * 0.26, c.dy + r * 0.44)
          ..close(),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_PlayMark old) => old.pause != pause || old.lit != lit;
}

/// A run, drawn for the "?" sheet: two verses and everything between.
class _RunGlyph extends CustomPainter {
  const _RunGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final r = size.height * 0.28;
    final gold = Paint()..color = AppColors.goldBright;
    canvas.drawLine(
      Offset(r, y),
      Offset(size.width - r, y),
      Paint()
        ..color = AppColors.gold.withValues(alpha: 0.75)
        ..strokeWidth = r * 1.1
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(r, y), r, gold);
    canvas.drawCircle(Offset(size.width - r, y), r, gold);
  }

  @override
  bool shouldRepaint(_RunGlyph old) => false;
}

/// What follows the voice inside the verse it is on: a wash of light
/// across the tile from where the verse begins (its right, as it is
/// read) to where the voice has got, a thread of gold along its foot,
/// the ring round its number, and the words lit as they are recited.
///
/// Every frame while the voice sounds — painted, not rebuilt: the
/// verse itself is laid out again only when the lit words change.
class _ReciteLight extends StatefulWidget {
  final LiveRecitation? live;
  final bool sounding;
  final Widget Function(({int start, int end})? words, Listenable? frame)
      builder;

  const _ReciteLight({
    required this.live,
    required this.sounding,
    required this.builder,
  });

  @override
  State<_ReciteLight> createState() => _ReciteLightState();
}

class _ReciteLightState extends State<_ReciteLight>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _onFrame());
  final _frame = _Ping();
  ({int start, int end})? _words;

  @override
  void initState() {
    super.initState();
    _words = widget.live?.litWords;
    _sync();
  }

  @override
  void didUpdateWidget(_ReciteLight old) {
    super.didUpdateWidget(old);
    _words = widget.live?.litWords;
    _sync();
  }

  void _sync() {
    final run = widget.live != null && widget.sounding;
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  void _onFrame() {
    _frame.ping();
    final w = widget.live?.litWords;
    if (w != _words) setState(() => _words = w);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    return CustomPaint(
      painter: live == null ? null : _WashPainter(live, _frame),
      child: widget.builder(_words, live == null ? null : _frame),
    );
  }
}

/// A listenable that only ever says "paint again".
class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _WashPainter extends CustomPainter {
  final LiveRecitation live;
  _WashPainter(this.live, Listenable frame) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final p = live.ayahProgress;
    if (p <= 0 || size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(16)));
    // The verse is read from the right: the light grows leftwards.
    final x = w * (1 - p);
    final wash = Rect.fromLTRB(x, 0, w, h);
    canvas.drawRect(
      wash,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.gold.withValues(alpha: 0.11),
            AppColors.gold.withValues(alpha: 0.04),
          ],
        ).createShader(wash),
    );
    final front = Rect.fromLTRB(x - 26, 0, x, h);
    canvas.drawRect(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.gold.withValues(alpha: 0),
            AppColors.gold.withValues(alpha: 0.11),
          ],
        ).createShader(front),
    );
    final thread = Rect.fromLTRB(x, h - 2.4, w, h);
    canvas.drawRect(
      thread,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.goldBright,
            AppColors.gold.withValues(alpha: 0.35),
          ],
        ).createShader(thread),
    );
    canvas.drawCircle(
      Offset(x, h - 1.2),
      3.4,
      Paint()
        ..color = AppColors.goldBright
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WashPainter old) => !identical(old.live, live);
}

class _RingPainter extends CustomPainter {
  final LiveRecitation live;
  _RingPainter(this.live, Listenable frame) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppColors.gold.withValues(alpha: 0.2),
    );
    final p = live.ayahProgress;
    if (p <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * p,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.goldBright,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => !identical(old.live, live);
}

/// The search, open at the head of the screen from the start. Tapping
/// it lists every surah; typing narrows them and finds verses by their
/// words; Enter takes the first surah it names.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final String clearLabel;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.clearLabel,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focus]),
      builder: (context, _) {
        final open = focus.hasFocus || controller.text.isNotEmpty;
        return TextField(
          controller: controller,
          focusNode: focus,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.search,
          style: t.bodyMedium
              ?.copyWith(color: AppColors.textPrimary, fontSize: 15.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: t.bodyMedium,
            prefixIcon: Icon(Icons.search_rounded,
                color: open ? AppColors.gold : AppColors.textSecondary),
            suffixIcon: open
                ? IconButton(
                    tooltip: clearLabel,
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: onClear,
                  )
                : null,
            filled: true,
            fillColor: AppColors.surfaceRaised,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: AppColors.gold.withValues(alpha: 0.6), width: 1.2),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
    );
  }
}

/// Folds its child away to nothing, and back: the heading, when the
/// verses or the search need its room.
class _Fold extends StatelessWidget {
  final bool folded;
  final Widget child;
  const _Fold({required this.folded, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: folded ? 0 : 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => ExcludeSemantics(
        excluding: v == 0,
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: v,
            child: Opacity(opacity: v, child: child),
          ),
        ),
      ),
      child: child,
    );
  }
}
