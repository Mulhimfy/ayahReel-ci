import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/audio_position.dart';
import '../data/debug_log.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/reel_limits.dart';
import '../data/user_audio_service.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/glow_button.dart';
import '../widgets/step_dots.dart';
import 'background_screen.dart';

/// The step that only exists for an uploaded recitation: saying where
/// each chosen verse falls inside it.
///
/// For the app's own voices this screen has no reason to exist — their
/// audio is assembled out of one-ayah files, so the timing table is a
/// running total of measured durations and cannot be wrong. An upload
/// is one continuous recording with nothing in it to count, and every
/// screen after this one (the verse card's cues, the scene cuts, the
/// export) reads the same table. So it is built here, once: proposed by
/// [UserAudioService.plan], then handed to the user to correct in the
/// only way that can settle it — by listening.
///
/// Three ways to correct it, in the order they cost the user anything:
/// drag a boundary on the waveform; play up to a verse and say it
/// starts here; or tap along with the whole recitation from the top.
class AlignScreen extends StatefulWidget {
  final UserAudio audio;

  const AlignScreen({super.key, required this.audio});

  @override
  State<AlignScreen> createState() => _AlignScreenState();
}

class _AlignScreenState extends State<AlignScreen>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();

  final int _surah = creationState.surah;
  final int _startAyah = creationState.startAyah;
  final int _endAyah = creationState.endAyah;

  int get _count => _endAyah - _startAyah + 1;

  List<Ayah>? _ayahs;

  /// One more than there are verses: the run's start, every boundary
  /// between two verses, and the run's end.
  List<int> _marks = const [];

  List<double>? _peaks;

  /// True while the audio is being read for its silences and its
  /// envelope — the one wait on this screen.
  bool _working = true;

  int _positionMs = 0;
  bool _playing = false;

  /// The verse whose start the fine controls act on, 0-based within the
  /// run. Always a real verse: the first one until the user picks
  /// another.
  int _selected = 0;

  /// Boundary being dragged on the waveform, as an index into [_marks];
  /// null when nothing is being dragged.
  int? _dragging;

  /// Times the user has tapped, in tap-along mode. Non-null only while
  /// that mode is running.
  List<int>? _taps;

  final _listController = ScrollController();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.setReleaseMode(ReleaseMode.stop);
    // Same reason as every other player in this app: Android's async
    // audio-focus grant can be lost and leave a player that reports
    // itself playing over silence.
    _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        audioFocus: AndroidAudioFocus.none,
      ),
    ));
    // 50 ms, not once a frame: see [PositionPolling]. The playhead this
    // feeds is drawn over a waveform, and 20 steps a second reads as
    // continuous movement without a binder call on every vsync.
    _player.pollPositionEvery(const Duration(milliseconds: 50));
    _posSub = _player.onPositionChanged.listen((d) {
      if (!mounted) return;
      setState(() => _positionMs = d.inMilliseconds);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playing = false);
    });
    _boot();
  }

  /// Playback pauses with the app. The player holds no audio focus (see
  /// initState), so nothing else would pause it, and an hour-long
  /// upload kept sounding from behind the home screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_playing) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player.pause().catchError((_) {});
      setState(() => _playing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final ayahs = await QuranRepository.ayahsOf(_surah);
      if (!mounted) return;
      setState(() => _ayahs = ayahs);
      await _player.setSourceDeviceFile(widget.audio.audioPath);
      // The envelope is only ever drawn, so it must not hold the
      // placement up: whichever finishes first is shown first.
      unawaited(_loadPeaks());
      await _autoPlace(ayahs);
    } catch (_) {
      if (!mounted) return;
      // Nothing here can be retried usefully — an even spread is still
      // a starting point, and every control on the screen edits it.
      setState(() {
        _working = false;
        if (_marks.isEmpty) _marks = _evenMarks();
      });
    }
  }

  Future<void> _loadPeaks() async {
    final p = await UserAudioService.peaks(
      widget.audio.audioPath,
      durationMs: widget.audio.durationMs,
    );
    if (!mounted || p == null) return;
    setState(() => _peaks = p);
  }

  /// Listens to the file and places every verse in it. Also the "place
  /// them again" button, which is what a user reaches for after
  /// changing their mind about a hand edit.
  Future<void> _autoPlace(List<Ayah> ayahs) async {
    setState(() => _working = true);
    final gaps = await UserAudioService.detectSilenceFor(
      widget.audio.audioPath,
      wanted: _count,
    );
    if (!mounted) return;
    final timings = UserAudioService.plan(
      ayahs: ayahs,
      startAyah: _startAyah,
      endAyah: _endAyah,
      durationMs: widget.audio.durationMs,
      silences: gaps,
    );
    // What the placement actually did, in one line: how much silence
    // was heard and where the first verses landed. The only way to
    // tell a bad upload from a bad placement after the fact.
    rlog('align: ${timings.length} verses from ${gaps.length} gaps — '
        '${timings.take(12).map((t) => '${t.ayah}@${t.startMs}').join(' ')}'
        '${timings.length > 12 ? ' …' : ''}');
    setState(() {
      _marks = UserAudioService.marksOf(timings);
      _working = false;
      _taps = null;
      _selected = 0;
    });
  }

  List<int> _evenMarks() {
    final d = widget.audio.durationMs;
    return [for (var i = 0; i <= _count; i++) d * i ~/ _count];
  }

  // ---- playback -----------------------------------------------------

  Future<void> _seek(int ms) async {
    final at = ms.clamp(0, widget.audio.durationMs);
    setState(() => _positionMs = at);
    await _player.seek(Duration(milliseconds: at));
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.resume();
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _playFrom(int ms) async {
    await _seek(ms);
    if (!_playing) {
      await _player.resume();
      if (mounted) setState(() => _playing = true);
    }
  }

  // ---- editing ------------------------------------------------------

  /// Moves boundary [i], keeping every verse at least
  /// [UserAudioService.minAyahMs] long on both sides of it.
  void _moveMark(int i, int ms) {
    if (i < 0 || i >= _marks.length) return;
    const gap = UserAudioService.minAyahMs;
    final low = i == 0 ? 0 : _marks[i - 1] + gap;
    final high =
        i == _marks.length - 1 ? widget.audio.durationMs : _marks[i + 1] - gap;
    if (high < low) return;
    final next = List<int>.from(_marks);
    next[i] = ms.clamp(low, high);
    setState(() => _marks = next);
  }

  /// "This verse starts here": the boundary in front of the selected
  /// verse goes to wherever the recording has got to.
  void _startSelectedHere() {
    HapticFeedback.selectionClick();
    _moveMark(_selected, _positionMs);
  }

  void _nudgeSelected(int byMs) {
    HapticFeedback.selectionClick();
    _moveMark(_selected, _marks[_selected] + byMs);
  }

  void _select(int i) {
    setState(() => _selected = i);
    _playFrom(_marks[i]);
  }

  // ---- tap along ------------------------------------------------------

  /// The first verse is taken as starting where the recording does,
  /// so the first tap is the one where the second verse begins. A
  /// lead-in to trim is what the arrows under the pad are for.
  Future<void> _startTapAlong() async {
    HapticFeedback.selectionClick();
    if (_count <= 1) {
      _applyTaps(const [0]);
      return;
    }
    setState(() => _taps = <int>[0]);
    await _playFrom(0);
  }

  /// Records the moment the next verse begins.
  void _tapNow() {
    final taps = _taps;
    if (taps == null) return;
    HapticFeedback.selectionClick();
    const gap = UserAudioService.minAyahMs;
    final at = taps.isEmpty
        ? _positionMs
        : (_positionMs < taps.last + gap ? taps.last + gap : _positionMs);
    final next = [...taps, at];
    if (next.length >= _count) {
      _applyTaps(next);
      return;
    }
    setState(() => _taps = next);
  }

  /// Moves the tap just made, without leaving the run.
  ///
  /// A tap lands a beat late far more often than it lands on the wrong
  /// verse, and the whole point of tapping along is that the recording
  /// keeps playing — so the fix has to be here, on the last tap, and
  /// not something to go hunting for in the list afterwards.
  void _nudgeLastTap(int byMs) {
    final taps = _taps;
    if (taps == null || taps.isEmpty) return;
    HapticFeedback.selectionClick();
    const gap = UserAudioService.minAyahMs;
    final i = taps.length - 1;
    final low = i == 0 ? 0 : taps[i - 1] + gap;
    final next = List<int>.from(taps);
    next[i] = (next[i] + byMs).clamp(low, widget.audio.durationMs);
    setState(() => _taps = next);
  }

  /// Ends tap-along early, keeping what was tapped.
  void _finishTapAlong() {
    final taps = _taps;
    if (taps == null) return;
    _applyTaps(taps);
  }

  /// Turns the taps into marks. Verses the user did not reach keep the
  /// share of what is left that their own letters ask for — the same
  /// model [UserAudioService.plan] proposes from, applied to the tail
  /// rather than the whole file, so stopping early costs only accuracy
  /// past the last tap.
  void _applyTaps(List<int> taps) {
    _player.pause();
    final ayahs = _ayahs;
    final marks = List<int>.from(_marks.isEmpty ? _evenMarks() : _marks);
    for (var i = 0; i < taps.length && i < marks.length; i++) {
      marks[i] = taps[i];
    }
    final done = taps.length;
    if (done == _count) {
      // Every verse was tapped, so the run ends where the recording
      // does — there is nothing after the last verse but run-out.
      marks[_count] = widget.audio.durationMs;
    } else if (done > 0 && ayahs != null) {
      // Stopped early. The verses not reached share out what is left,
      // by the same letter-count model the automatic placement
      // proposes from — measured from the last verse the user *did*
      // mark, so the tail hangs off a real time rather than a guess.
      final rest = UserAudioService.marksOf(UserAudioService.plan(
        ayahs: ayahs,
        startAyah: _startAyah + done - 1,
        endAyah: _endAyah,
        durationMs: widget.audio.durationMs,
        silences: const [],
      ));
      final span = rest.last - rest.first;
      final from = taps.last;
      final room = widget.audio.durationMs - from;
      for (var j = 1; j < rest.length; j++) {
        final share = span <= 0
            ? j / (rest.length - 1)
            : (rest[j] - rest.first) / span;
        marks[done - 1 + j] = from + (room * share).round();
      }
    }
    final fixed = UserAudioService.timingsFrom(marks, _startAyah,
        endMs: widget.audio.durationMs);
    setState(() {
      _marks = UserAudioService.marksOf(fixed);
      _taps = null;
      _playing = false;
      _selected = 0;
    });
  }

  // ---- leaving --------------------------------------------------------

  void _continue() {
    _player.stop();
    final timings = UserAudioService.timingsFrom(_marks, _startAyah,
        endMs: widget.audio.durationMs);
    // The hard length cap, the same one the verse picker and the
    // preview hold: an upload can be an hour of recitation whatever
    // the selection was.
    final from = timings.first.startMs;
    var last = timings.length - 1;
    while (last > 0 && timings[last].endMs - from > ReelLimits.maxReelMs) {
      last--;
    }
    final kept = timings.sublist(0, last + 1);
    final endAyah = kept.last.ayah;
    if (endAyah != _endAyah) {
      creationState.selectRange(_startAyah, endAyah);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(toast(
          L10n.of(context).timingTrimmedToAyah(endAyah),
          duration: const Duration(seconds: 3),
        ));
    }
    UserAudioService.register(
      audio: widget.audio,
      surah: _surah,
      timings: kept,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BackgroundScreen()),
    );
  }

  // ---- build -----------------------------------------------------------

  /// The verse the playhead is inside, 0-based within the run; -1
  /// before the run starts or after it ends.
  int get _atVerse {
    for (var i = 0; i < _marks.length - 1; i++) {
      if (_positionMs >= _marks[i] && _positionMs < _marks[i + 1]) return i;
    }
    return -1;
  }

  String _arabicOf(int index) {
    final ayahs = _ayahs;
    final n = _startAyah + index;
    if (ayahs == null || n - 1 < 0 || n - 1 >= ayahs.length) return '';
    return ayahs[n - 1].arabic;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final ready = _marks.length == _count + 1;
    final tapping = _taps != null;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          color: AppColors.textSecondary,
          onPressed: () {
            _player.stop();
            Navigator.of(context).pop();
          },
        ),
        title: StepDots(current: WizardSteps.align, total: WizardSteps.total),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              A11yHeader(child: Text(l.matchTheVerses, style: t.headlineMedium)),
              const SizedBox(height: 6),
              // The line changes as tap-along starts, and it is the
              // instructions for what to do next.
              A11yLive(
                child: Text(
                  tapping ? l.tapAlongBody : l.matchTheVersesBody,
                  style: t.bodyMedium,
                ),
              ),
              const SizedBox(height: 14),
              _WaveStrip(
                peaks: _peaks,
                // During a tap-along run the strip draws the taps, not
                // the run they will become. It used to draw [_marks]
                // throughout, which a tap-along never touches — so the
                // two chevrons moved the last tap by a quarter-second
                // and every gold line on the strip stayed exactly where
                // it was. That is what "the arrows don't work" was: the
                // arrows worked, and the only picture of what they act
                // on was of something else.
                marks: tapping ? _taps! : _marks,
                tapping: tapping,
                durationMs: widget.audio.durationMs,
                positionMs: _positionMs,
                selected: _selected,
                busy: _working,
                onSeek: _seek,
                onMarkDragStart: (i) => setState(() {
                  _dragging = i;
                  if (i < _count) _selected = i;
                }),
                onMarkDrag: (ms) {
                  final i = _dragging;
                  if (i != null) _moveMark(i, ms);
                },
                onMarkDragEnd: () {
                  HapticFeedback.selectionClick();
                  setState(() => _dragging = null);
                },
              ),
              const SizedBox(height: 10),
              _Transport(
                playing: _playing,
                positionMs: _positionMs,
                durationMs: widget.audio.durationMs,
                onToggle: _togglePlay,
                onRewind: () => _seek(_positionMs - 5000),
              ),
              const SizedBox(height: 12),
              if (_working)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.gold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        A11yLive(
                          child: Text(l.listeningToYourAudio,
                              style: t.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                )
              else if (tapping)
                Expanded(child: _tapAlongPanel(t, l))
              else if (ready)
                Expanded(child: _verseList(t, l)),
              if (!_working && !tapping && ready) ...[
                const SizedBox(height: 10),
                _fineTune(t, l),
              ],
              const SizedBox(height: 12),
              GlowButton(
                label: tapping ? l.tapAlongFinish : l.continueLabel,
                icon: tapping ? Icons.check_rounded : Icons.arrow_forward_rounded,
                onPressed: _working
                    ? null
                    : tapping
                        ? _finishTapAlong
                        : (ready ? _continue : null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The run, verse by verse, with the slice of the recording each one
  /// currently owns. Tapping a row selects it and plays from its start,
  /// which is how a wrong placement is heard rather than guessed at.
  Widget _verseList(TextTheme t, L10n l) {
    final at = _atVerse;
    return ListView.separated(
      controller: _listController,
      itemCount: _count,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final selected = i == _selected;
        final playing = i == at;
        return Semantics(
          container: true,
          button: true,
          selected: selected,
          hint: l.a11yPlaysFromVerse,
          child: Material(
          color: selected ? AppColors.surfaceRaised : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _select(i),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.gold
                      : playing
                          ? AppColors.gold.withValues(alpha: 0.35)
                          : AppColors.stroke,
                  width: selected ? 1.4 : 1,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Semantics(
                      label: '${l.verseLabel} ${_startAyah + i}',
                      excludeSemantics: true,
                      child: Text(
                        '${_startAyah + i}',
                        style: t.titleSmall?.copyWith(
                          color: selected
                              ? AppColors.gold
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l.clock(_marks[i])} – ${l.clock(_marks[i + 1])}',
                          style: t.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _arabicOf(i),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: AppTheme.quran(
                            size: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    playing
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                    color: playing
                        ? AppColors.gold
                        : AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  /// The controls that act on the selected verse's start, plus the two
  /// ways to start over.
  Widget _fineTune(TextTheme t, L10n l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.dragTheHandles, style: t.bodySmall),
        const SizedBox(height: 8),
        Row(
          children: [
            _MiniButton(
              icon: Icons.chevron_left_rounded,
              semanticLabel: l.a11yQuarterEarlier,
              onTap: () => _nudgeSelected(-250),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniButton(
                icon: Icons.my_location_rounded,
                label: '${l.verseLabel} ${_startAyah + _selected} · '
                    '${l.startsHere}',
                hint: l.a11yMarksVerseStart,
                onTap: _startSelectedHere,
              ),
            ),
            const SizedBox(width: 8),
            _MiniButton(
              icon: Icons.chevron_right_rounded,
              semanticLabel: l.a11yQuarterLater,
              onTap: () => _nudgeSelected(250),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MiniButton(
                icon: Icons.auto_fix_high_rounded,
                label: l.placeThemAgain,
                onTap: () {
                  final a = _ayahs;
                  if (a != null) _autoPlace(a);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniButton(
                icon: Icons.touch_app_rounded,
                label: l.tapAlong,
                onTap: _startTapAlong,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Tap-along: the recording runs from the top and the user marks each
  /// verse as it begins. Slower than the automatic placement and always
  /// right, which is why it is the way out of every hard case.
  Widget _tapAlongPanel(TextTheme t, L10n l) {
    final taps = _taps ?? const [];
    final next = _startAyah + taps.length;
    return Column(
      children: [
        const Spacer(),
        Text(
          '${l.verseLabel} $next',
          style: t.titleMedium?.copyWith(color: AppColors.gold),
        ),
        const SizedBox(height: 10),
        Text(
          _arabicOf(taps.length.clamp(0, _count - 1)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.quran(size: 20, color: AppColors.textPrimary),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            container: true,
            button: true,
            child: Material(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _tapNow,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.gold, width: 1.4),
                ),
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Column(
                  children: [
                    const Icon(Icons.touch_app_rounded,
                        color: AppColors.gold, size: 26),
                    const SizedBox(height: 8),
                    Text(l.tapAlongNext(next), style: t.titleSmall),
                    const SizedBox(height: 4),
                    Text('${taps.length} / $_count', style: t.bodySmall),
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // The same three controls the list below has, on the one thing
        // they can act on here: the tap just made. Left and right move
        // it a quarter-second either way; the middle one throws the run
        // away and starts it from the top.
        //
        // The clock is not decoration. Nothing else on this panel shows
        // where a tap landed, so the arrows moved the mark and the
        // screen said nothing back — which is indistinguishable from
        // two dead buttons, and is exactly what they were taken for.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l.moveTheLastTap,
              style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (taps.isNotEmpty) ...[
              Text(
                '  ·  ',
                style:
                    t.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              Text(
                l.clock(taps.last),
                style: t.bodySmall?.copyWith(
                  color: AppColors.goldBright,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _MiniButton(
              icon: Icons.chevron_left_rounded,
              semanticLabel: l.a11yQuarterEarlier,
              onTap: taps.isEmpty ? null : () => _nudgeLastTap(-250),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniButton(
                icon: Icons.restart_alt_rounded,
                label: l.placeThemAgain,
                onTap: _startTapAlong,
              ),
            ),
            const SizedBox(width: 8),
            _MiniButton(
              icon: Icons.chevron_right_rounded,
              semanticLabel: l.a11yQuarterLater,
              onTap: taps.isEmpty ? null : () => _nudgeLastTap(250),
            ),
          ],
        ),
        const Spacer(),
      ],
    );
  }
}

/// Play/pause, a three-second step back, and the clock.
class _Transport extends StatelessWidget {
  final bool playing;
  final int positionMs;
  final int durationMs;
  final VoidCallback onToggle;
  final VoidCallback onRewind;

  const _Transport({
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.onToggle,
    required this.onRewind,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Row(
      children: [
        _MiniButton(
          icon: Icons.replay_5_rounded,
          semanticLabel: l.a11yBackFive,
          onTap: onRewind,
        ),
        const SizedBox(width: 8),
        _MiniButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          semanticLabel: playing ? l.pause : l.play,
          onTap: onToggle,
          accent: true,
        ),
        const Spacer(),
        // The playhead's clock is read on request, never announced:
        // it moves twenty times a second.
        Semantics(
          label: l.a11yPlaybackPosition,
          child: Text(
            '${l.clock(positionMs)} / ${l.clock(durationMs)}',
            style: t.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String? label;

  /// What a screen reader calls a button that shows only its glyph.
  /// A button with a [label] is called by that.
  final String? semanticLabel;

  /// What the reader says a double tap does.
  final String? hint;

  /// Null is a button with nothing to act on — it stays where it is,
  /// dimmed, rather than appearing the moment it becomes usable.
  final VoidCallback? onTap;

  final bool accent;

  const _MiniButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.semanticLabel,
    this.hint,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final off = onTap == null;
    return Semantics(
      container: true,
      button: true,
      enabled: !off,
      label: label == null ? semanticLabel : null,
      hint: hint,
      child: Material(
      color: accent
          ? AppColors.gold.withValues(alpha: 0.16)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: off
                  ? AppColors.stroke.withValues(alpha: 0.5)
                  : accent
                      ? AppColors.gold
                      : AppColors.stroke,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? 12 : 14,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: off
                    ? AppColors.gold.withValues(alpha: 0.35)
                    : AppColors.gold,
              ),
              if (label != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      color: off
                          ? AppColors.textSecondary.withValues(alpha: 0.6)
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// The recording drawn as one strip, with the verse boundaries on it.
///
/// The envelope is the thing that makes a boundary correctable by eye:
/// the breaths between verses are visible as troughs, so a handle
/// sitting in the middle of a word is obvious without playing anything.
/// It is also optional — when the peaks could not be read the strip
/// draws flat and every control still works, because they all act on
/// times, not on pixels.
class _WaveStrip extends StatelessWidget {
  final List<double>? peaks;
  final List<int> marks;

  /// Mid tap-along: [marks] is the taps made so far rather than the
  /// finished run, so it is short, it grows, and the last of them is
  /// the one the chevrons move. Nothing on it may be dragged — the
  /// indices are taps, and the drag handlers move verse boundaries.
  final bool tapping;

  final int durationMs;
  final int positionMs;
  final int selected;
  final bool busy;
  final ValueChanged<int> onSeek;
  final ValueChanged<int> onMarkDragStart;
  final ValueChanged<int> onMarkDrag;
  final VoidCallback onMarkDragEnd;

  const _WaveStrip({
    required this.peaks,
    required this.marks,
    required this.tapping,
    required this.durationMs,
    required this.positionMs,
    required this.selected,
    required this.busy,
    required this.onSeek,
    required this.onMarkDragStart,
    required this.onMarkDrag,
    required this.onMarkDragEnd,
  });

  /// How close a finger has to land to a handle to take hold of it.
  static const _grabPx = 22.0;

  int _msAt(double dx, double width) =>
      (durationMs * (dx / width)).round().clamp(0, durationMs);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // To a reader the strip is a timeline it can move through a
        // second at a time; the handles are reached through the verse
        // list and the fine controls under it, which are buttons.
        return A11yAdjustable(
          label: l.a11yRecordingTimeline,
          value: '${l.clock(positionMs)} / ${l.clock(durationMs)}',
          hint: l.a11yRecordingTimelineHint,
          onIncrease: busy ? null : () => onSeek(positionMs + 1000),
          onDecrease: busy ? null : () => onSeek(positionMs - 1000),
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            if (!busy) onSeek(_msAt(d.localPosition.dx, w));
          },
          onHorizontalDragStart: (d) {
            if (busy || tapping || marks.isEmpty) return;
            final x = d.localPosition.dx;
            var best = -1;
            var bestPx = _grabPx;
            for (var i = 0; i < marks.length; i++) {
              final px = (marks[i] / durationMs * w - x).abs();
              if (px < bestPx) {
                bestPx = px;
                best = i;
              }
            }
            if (best >= 0) onMarkDragStart(best);
          },
          onHorizontalDragUpdate: (d) {
            if (busy || tapping) return;
            onMarkDrag(_msAt(d.localPosition.dx, w));
          },
          onHorizontalDragEnd: (_) {
            if (!busy && !tapping) onMarkDragEnd();
          },
          child: SizedBox(
            height: 96,
            width: double.infinity,
            child: CustomPaint(
              painter: _WavePainter(
                peaks: peaks,
                marks: marks,
                tapping: tapping,
                durationMs: durationMs,
                positionMs: positionMs,
                selected: selected,
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double>? peaks;
  final List<int> marks;

  /// See [_WaveStrip.tapping]. Mid-run the marks are taps: there is no
  /// selected verse to shade, nothing past the last tap is settled
  /// enough to dim, and the last mark is the one the chevrons move —
  /// so it is drawn as the one that is live.
  final bool tapping;

  final int durationMs;
  final int positionMs;
  final int selected;

  _WavePainter({
    required this.peaks,
    required this.marks,
    required this.tapping,
    required this.durationMs,
    required this.positionMs,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.drawRRect(r, Paint()..color = AppColors.surface);
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.stroke,
    );
    canvas.save();
    canvas.clipRRect(r);

    double x(int ms) =>
        durationMs <= 0 ? 0 : size.width * (ms / durationMs);

    // The slice belonging to the selected verse, so the handle being
    // dragged is read against the verse it moves.
    if (!tapping && marks.length > selected + 1) {
      canvas.drawRect(
        Rect.fromLTRB(x(marks[selected]), 0, x(marks[selected + 1]), size.height),
        Paint()..color = AppColors.gold.withValues(alpha: 0.10),
      );
    }

    // The envelope. Flat bars when it could not be read: the strip is
    // still a timeline, and every handle on it still drags.
    final env = peaks;
    final mid = size.height / 2;
    final bars = env?.length ?? 96;
    final bw = size.width / bars;
    final bar = Paint()..color = AppColors.textSecondary.withValues(alpha: 0.45);
    for (var i = 0; i < bars; i++) {
      final v = env == null ? 0.12 : env[i];
      final h = (v * (size.height * 0.42)).clamp(1.0, size.height * 0.46);
      canvas.drawRect(
        Rect.fromLTWH(i * bw, mid - h, bw * 0.72, h * 2),
        bar,
      );
    }

    // Everything outside the run is not part of the reel: dim it, so a
    // lead-in left in by mistake is visible as one.
    if (marks.isNotEmpty) {
      final dim = Paint()..color = AppColors.bg.withValues(alpha: 0.55);
      canvas.drawRect(Rect.fromLTRB(0, 0, x(marks.first), size.height), dim);
      // Only once the run has an end. Mid tap-along everything after
      // the last tap is still to come, and dimming it would say the
      // opposite.
      if (!tapping && marks.length >= 2) {
        canvas.drawRect(
            Rect.fromLTRB(x(marks.last), 0, size.width, size.height), dim);
      }
    }

    // The boundaries, each with a grip at the top so it reads as
    // something to be moved.
    final line = Paint()
      ..color = AppColors.gold
      ..strokeWidth = 1.6;
    // Mid tap-along the last mark is the live one — the only thing the
    // chevrons act on — so it is brighter and thicker than the taps
    // already behind it. Without that the strip shows a row of
    // identical lines and gives no clue which one is moving.
    final live = Paint()
      ..color = AppColors.goldBright
      ..strokeWidth = 2.6;
    for (var i = 0; i < marks.length; i++) {
      final last = tapping && i == marks.length - 1;
      final px = x(marks[i]);
      canvas.drawLine(Offset(px, 0), Offset(px, size.height),
          last ? live : line);
      canvas.drawCircle(
        Offset(px, 9),
        last ? 6.5 : 5,
        Paint()..color = last ? AppColors.goldBright : AppColors.gold,
      );
    }

    // The playhead, drawn last so it is never lost behind a boundary.
    final px = x(positionMs);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = AppColors.textPrimary
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.positionMs != positionMs ||
      old.selected != selected ||
      old.tapping != tapping ||
      old.peaks != peaks ||
      !identical(old.marks, marks);
}
