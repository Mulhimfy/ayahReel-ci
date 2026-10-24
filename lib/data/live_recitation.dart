import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'audio_position.dart';
import 'debug_log.dart';
import 'models.dart';
import 'qul_words.dart';
import 'recitation_service.dart';
import 'reel_duration.dart';
import 'word_align_service.dart';

/// Where the live recitation stands.
enum LiveStatus {
  /// Nothing opened yet.
  idle,

  /// Fetching the ayah it is about to play, or the one it was moved to.
  loading,
  playing,
  paused,

  /// The ayah could not be had: no network, or a host that refused.
  failed,
}

/// The recitation that plays at the head of the verse picker: the surah
/// the reel is being cut from, in the voice just chosen, from the ayah
/// the screen opens on — and the verse list follows it.
///
/// It plays ayah by ayah, each one a local file or a window of one (see
/// [RecitationService.liveClip]), fetching the next few ahead of the
/// voice. The timeline is the whole surah: exact where the ayahs have
/// been measured — all of it at once for a surah-file voice, whose table
/// arrives before the audio does — and estimated from the text
/// elsewhere ([ReelDuration]) until the files land.
///
/// **One platform player, for the app's life.** Creating and disposing
/// players per screen is the churn that wedges Android's media stack
/// (see the preview screen's player), so every verse picker borrows the
/// same one, and the last to open it owns it. Every call on it is
/// timed, and one that hangs or errors swaps in a fresh player.
///
/// The position is a stopwatch anchored at every start and seek, and
/// checked against the player about once a second: the list and the
/// line read it every frame, and the platform is never asked that often
/// (see [PositionPolling]).
class LiveRecitation extends ChangeNotifier {
  /// Off under `flutter test`, where no plugin answers: the line and the
  /// list still draw, nothing plays.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  // ---- the shared player --------------------------------------------

  static AudioPlayer? _shared;
  static LiveRecitation? _owner;

  /// Every call on the player waits for the one before it, so a seek and
  /// an ayah change arriving together reach the platform in the order
  /// they were made.
  static Future<void> _chain = Future.value();

  static const _wait = Duration(seconds: 6);

  static AudioPlayer get _player => _shared ??= _make();

  static AudioPlayer _make() {
    final p = AudioPlayer();
    // Nothing reads its position stream; see the class comment.
    p.stopPollingPosition();
    // ReleaseMode.stop keeps the platform player alive between files,
    // and focus 'none' starts playback synchronously: with focus, the
    // start can wait on a grant that never comes (the preview screen
    // learned this as a "playing" but silent player).
    unawaited(p.setReleaseMode(ReleaseMode.stop).catchError((_) {}));
    unawaited(p
        .setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
          ),
        ))
        .catchError((_) {}));
    p.onPlayerComplete.listen(
      (_) {
        if (identical(p, _shared)) _owner?._completed();
      },
      onError: (Object _) {},
    );
    // Platform errors have to be heard here: unheard, they surface as
    // unhandled exceptions while the player quietly stops answering.
    p.eventStream.listen((_) {}, onError: (Object e) {
      rlog('live: platform error $e');
      if (identical(p, _shared)) _owner?._playerBroke();
    });
    return p;
  }

  /// Abandons a player that has stopped answering. The old one is let
  /// go without waiting: awaiting a wedged player hangs.
  static void _replacePlayer() {
    final old = _shared;
    _shared = null;
    _loaded = null;
    _chain = Future.value();
    if (old != null) unawaited(old.dispose().catchError((_) {}));
    // The spare goes with it: whatever wedged one may have reached both.
    final spare = _spareShared;
    _spareShared = null;
    _spareLoaded = null;
    _spareChain = Future.value();
    _cuedAyah = null;
    _cuedClip = null;
    if (spare != null) unawaited(spare.dispose().catchError((_) {}));
  }

  /// The file the player holds, so moving within it is a seek and not
  /// a new source.
  static String? _loaded;

  static Future<T> _run<T>(Future<T> Function(AudioPlayer p) op) {
    final run = _chain.then((_) => op(_player).timeout(_wait));
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  // ---- the second player ---------------------------------------------

  /// The next ayah, set up and waiting on a second player of its own —
  /// loaded, seeked, paused — so that moving on to it is a start and not
  /// a load. The two trade places at every ayah (see [_advance]), and
  /// like the first this one lives as long as the app: created once,
  /// never thrown away while it answers.
  static AudioPlayer? _spareShared;
  static AudioPlayer get _spare => _spareShared ??= _make();
  static String? _spareLoaded;
  static Future<void> _spareChain = Future.value();

  /// Which ayah of the owner's surah the spare is cued at, and with what.
  static int? _cuedAyah;
  static LiveClip? _cuedClip;

  static Future<T> _runSpare<T>(Future<T> Function(AudioPlayer p) op) {
    final run = _spareChain.then((_) => op(_spare).timeout(_wait));
    _spareChain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  // ---- what is open --------------------------------------------------

  Reciter? _reciter;
  int _surah = 0;
  List<Ayah> _text = const [];

  /// How long each ayah runs (index ayah - 1), whether that is measured
  /// yet, and where each starts on the surah's timeline.
  List<int> _dur = const [];
  List<bool> _exact = const [];
  List<int> _start = const [];

  final _clips = <int, LiveClip>{};

  /// Bumped on every open: an answer for a surah no longer open is
  /// dropped on arrival.
  int _session = 0;

  /// Bumped on every move — open, seek, ayah change, pause, close — so
  /// the awaited half of a superseded one gives up.
  int _gen = 0;

  LiveStatus _status = LiveStatus.idle;
  int _ayah = 1;

  /// Whether the listener means it to be playing: true through a fetch,
  /// which is what the play button shows.
  bool _wantPlay = false;

  /// The clip sounding, or about to.
  LiveClip? _clip;

  /// Where in [_ayah] to be, while its clip is still on its way.
  int _pendingMs = 0;

  /// The file position at the last anchor, and the time since it.
  int _anchorMs = 0;
  final _clock = Stopwatch();

  Timer? _tick;
  int _ticks = 0;

  /// Fresh players tried since the last good start: one, then the
  /// failure is shown rather than retried for ever.
  int _retries = 0;

  /// Fires a breath before the ayah ends, to start the cued one.
  Timer? _handoff;

  Map<int, List<WordSpan>>? _spans;
  final _windows = <int, List<HighlightSpan>>{};

  // ---- reading it ----------------------------------------------------

  LiveStatus get status => _status;
  Reciter? get reciter => _reciter;
  int get surah => _surah;
  int get ayahCount => _dur.length;

  /// The ayah sounding (or being fetched to sound).
  int get ayah => _ayah;

  /// The listener's intent: the play button shows pause while this is
  /// on, through a fetch as well as through the sound.
  bool get wantsPlay => _wantPlay;

  bool get busy => _status == LiveStatus.loading;

  /// The whole surah, in milliseconds — estimated in part until
  /// [timelineExact].
  int get totalMs => _dur.isEmpty ? 0 : _start.last + _dur.last;

  bool get timelineExact => !_exact.contains(false);

  /// Where each ayah starts on the timeline, by ayah - 1.
  List<int> get ayahStarts => _start;

  /// Where in the current file the voice is.
  int get _filePos => _anchorMs + _clock.elapsedMilliseconds;

  /// How far into the current ayah, in milliseconds.
  int get _inAyah {
    final c = _clip;
    if (c == null || _dur.isEmpty) return _pendingMs;
    return (_filePos - c.fromMs).clamp(0, _dur[_ayah - 1]);
  }

  /// The voice's place on the surah's timeline.
  int get positionMs => _dur.isEmpty ? 0 : _start[_ayah - 1] + _inAyah;

  /// How far through the current ayah, 0 to 1.
  double get ayahProgress {
    if (_dur.isEmpty) return 0;
    final d = _dur[_ayah - 1];
    return d <= 0 ? 0 : (_inAyah / d).clamp(0.0, 1.0);
  }

  /// The ayah at [ms] on the timeline.
  int ayahAt(int ms) {
    if (_start.isEmpty) return 1;
    var lo = 0, hi = _start.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_start[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  /// The words of the current ayah the voice is on, as display tokens of
  /// its text split on spaces — for the voices whose word timings are
  /// released (see [WordAlignService]); null for every other.
  ({int start, int end})? get litWords {
    final spans = _spans;
    final c = _clip;
    if (spans == null || c == null || _status == LiveStatus.loading) {
      return null;
    }
    final a = _ayah;
    if (!spans.containsKey(a) && _reciter != null &&
        QulWords.supports(_reciter!)) {
      _clipWords(a, c);
      return null;
    }
    final w = _windows[a] ??= _windowsOf(a, c, spans);
    if (w.isEmpty) return null;
    final ms = _inAyah;
    for (final s in w) {
      if (ms >= s.startMs && ms < s.endMs) {
        return (start: s.tokenStart, end: s.tokenEnd);
      }
    }
    return null;
  }

  /// The ayahs whose words have been asked for, this session, and the
  /// line they wait in: each placing measures a clip's loudness, and the
  /// listen fetches a few clips ahead of the voice.
  final _askedWords = <int>{};
  Future<void> _wordsQueue = Future<void>.value();

  /// Places a QUL-timed voice's words on the clip of ayah [a], once.
  void _clipWords(int a, LiveClip c) {
    final r = _reciter;
    if (r == null || !_askedWords.add(a)) return;
    final session = _session;
    _wordsQueue = _wordsQueue.then((_) async {
      if (session != _session) return;
      final spans = await WordAlignService.loadClip(r, _surah, c, _text);
      if (session != _session || spans == null || spans.isEmpty) return;
      (_spans ??= {})[a] = spans;
      _windows.remove(a);
      notifyListeners();
    }).catchError((Object e) {
      rlog('live: words for $_surah:$a — $e');
    });
  }

  /// An ayah's word [spans], which count from its own window, in the
  /// time of the clip that plays it, which counts from where the clip
  /// starts — past the silence at the head of a per-ayah file. Unmoved,
  /// every word of such a voice was lit as late as that silence is long.
  @visibleForTesting
  static List<WordSpan> inClip(List<WordSpan> spans, LiveClip c) {
    final shift = c.windowMs - c.fromMs;
    if (shift == 0) return spans;
    return [
      for (final s in spans)
        WordSpan(s.startWord, s.endWord, s.startMs + shift, s.endMs + shift),
    ];
  }

  List<HighlightSpan> _windowsOf(
      int a, LiveClip c, Map<int, List<WordSpan>> spans) {
    final raw = spans[a];
    if (raw == null || _text.length < a) return const [];
    final placed = {a: inClip(raw, c)};
    final plan = WordAlignService.highlightPlan(
      recitation: Recitation(
        reciterId: _reciter?.id ?? '',
        surah: _surah,
        audioPath: c.path,
        timings: [AyahTiming(a, 0, c.durationMs)],
      ),
      ayahs: _text,
      spansByAyah: placed,
      startAyah: a,
      endAyah: a,
      // One ayah's words, however many: the cap is the export's.
      maxOverlays: 1 << 20,
    );
    return plan?[a] ?? const [];
  }

  // ---- driving it ----------------------------------------------------

  /// Opens [surah] in [reciter]'s voice at ayah [from], [text] being the
  /// surah's verses, and plays it unless told not to.
  Future<void> open(
    Reciter reciter,
    int surah,
    List<Ayah> text, {
    int from = 1,
    bool play = true,
  }) async {
    final session = ++_session;
    final gen = ++_gen;
    _reciter = reciter;
    _surah = surah;
    _text = text;
    _clips.clear();
    _spans = null;
    _windows.clear();
    _askedWords.clear();
    final n = text.length;
    _dur = [
      for (var a = 1; a <= n; a++)
        ReelDuration.estimateMs(text,
            startAyah: a, endAyah: a, pace: reciter.pace),
    ];
    _exact = List.filled(n, false);
    // The bundled Al-Fatiha, or a whole surah a reel already assembled:
    // one file holds it all, its table is exact, and nothing needs
    // fetching.
    final whole = surah == 1 && reciter.hasBundledFatiha
        ? null
        : RecitationService.cached(reciter.id, surah);
    if (surah == 1 && reciter.hasBundledFatiha) {
      for (final w in reciter.timings!) {
        if (w.ayah >= 1 && w.ayah <= n) {
          _dur[w.ayah - 1] = w.durationMs;
          _exact[w.ayah - 1] = true;
        }
      }
    } else if (whole != null &&
        whole.covers(1, n) &&
        File(whole.audioPath).existsSync()) {
      for (final w in whole.timings) {
        if (w.ayah > n) break;
        _clips[w.ayah] = LiveClip(w.ayah, whole.audioPath, w.startMs, w.endMs,
            originMs: whole.originMs);
        _dur[w.ayah - 1] = w.durationMs;
        _exact[w.ayah - 1] = true;
      }
    }
    _index();
    _ayah = from.clamp(1, math.max(1, n));
    _clip = null;
    _pendingMs = 0;
    _anchorMs = 0;
    _clock
      ..stop()
      ..reset();
    _wantPlay = play && enabled;
    _status = enabled ? LiveStatus.loading : LiveStatus.paused;
    notifyListeners();
    if (!enabled || n == 0) return;
    unawaited(_measure(session));
    unawaited(_loadWords(session));
    if (gen != _gen) return;
    await _go(_ayah, 0);
  }

  /// Empties the line for a surah about to open: nothing timed, nothing
  /// lit, and the voice stopped.
  void clear() {
    ++_session;
    ++_gen;
    _wantPlay = false;
    _stopTicking();
    _clock
      ..stop()
      ..reset();
    _anchorMs = 0;
    _pendingMs = 0;
    _clip = null;
    _clips.clear();
    _dur = const [];
    _exact = const [];
    _start = const [];
    _spans = null;
    _windows.clear();
    _askedWords.clear();
    _ayah = 1;
    _status = LiveStatus.idle;
    notifyListeners();
    if (identical(_owner, this) && _shared != null) {
      unawaited(_run((p) => p.pause()).catchError((_) {}));
    }
  }

  void toggle() => _wantPlay ? pause() : play();

  Future<void> play() async {
    if (!enabled || _dur.isEmpty) return;
    if (_status == LiveStatus.playing) return;
    _wantPlay = true;
    _retries = 0;
    final c = _clip;
    // At the very end, play means again from the top.
    final atEnd = _ayah == _dur.length && _inAyah >= _dur.last - 50;
    // Anything but a plain pause — a failure, a fetch called off, a
    // player another screen has used since — starts again at the place.
    if (atEnd || c == null || _loaded != c.path || !identical(_owner, this)) {
      notifyListeners();
      await _go(atEnd ? 1 : _ayah, atEnd ? 0 : _inAyah);
      return;
    }
    final gen = ++_gen;
    _status = LiveStatus.loading;
    notifyListeners();
    try {
      await _run((p) => p.resume());
    } catch (e) {
      if (gen == _gen) _broke('resume', e);
      return;
    }
    if (gen != _gen) return;
    _clock.start();
    _status = LiveStatus.playing;
    _startTicking();
    notifyListeners();
    _prefetch();
    _cueNext();
  }

  Future<void> pause() async {
    ++_gen;
    _wantPlay = false;
    _handoff?.cancel();
    _handoff = null;
    if (_status == LiveStatus.playing) _freeze();
    if (_status == LiveStatus.playing || _status == LiveStatus.loading) {
      _status = LiveStatus.paused;
    }
    _stopTicking();
    notifyListeners();
    if (identical(_owner, this) && _shared != null) {
      try {
        await _run((p) => p.pause());
      } catch (_) {}
    }
  }

  /// Moves [deltaMs] along the timeline: the ten seconds either way.
  Future<void> skip(int deltaMs) => seekTo(positionMs + deltaMs);

  /// Moves to [ms] on the surah's timeline, and goes on playing from
  /// there if it was playing.
  Future<void> seekTo(int ms) async {
    if (_dur.isEmpty) return;
    final int last = math.max(0, totalMs - 1);
    final int t = ms.clamp(0, last);
    final a = ayahAt(t);
    await _go(a, t - _start[a - 1]);
  }

  /// To the start of [ayah].
  Future<void> seekAyah(int ayah) async {
    if (_dur.isEmpty) return;
    await _go(ayah.clamp(1, _dur.length), 0);
  }

  /// To the start of [ayah], sounding: the number on a verse in the
  /// picker, which plays it whether or not the voice was playing.
  Future<void> playAyah(int ayah) async {
    if (_dur.isEmpty) return;
    _wantPlay = enabled;
    _retries = 0;
    await _go(ayah.clamp(1, _dur.length), 0);
  }

  /// Silences the player and lets it go: for when the screen leaves.
  Future<void> close() async {
    ++_session;
    ++_gen;
    _wantPlay = false;
    _stopTicking();
    _clock.stop();
    if (_status != LiveStatus.idle) _status = LiveStatus.paused;
    _dropCue();
    if (identical(_owner, this)) {
      _owner = null;
      if (_spareShared != null) {
        unawaited(_runSpare((p) => p.stop()).catchError((_) {}));
        _spareLoaded = null;
      }
      if (_shared != null) {
        try {
          await _run((p) => p.stop());
        } catch (_) {}
        _loaded = null;
      }
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }

  // ---- inside --------------------------------------------------------

  void _own() {
    if (identical(_owner, this)) return;
    _owner?._lostPlayer();
    _owner = this;
    _dropCue();
  }

  /// Another verse picker took the player: this one stops where it is.
  void _lostPlayer() {
    ++_gen;
    _wantPlay = false;
    _freeze();
    _stopTicking();
    if (_status != LiveStatus.idle) _status = LiveStatus.paused;
    notifyListeners();
  }

  /// Stops the clock where the voice is.
  void _freeze() {
    _anchorMs = _filePos;
    _clock
      ..stop()
      ..reset();
  }

  void _index() {
    final s = List<int>.filled(_dur.length, 0);
    var t = 0;
    for (var i = 0; i < _dur.length; i++) {
      s[i] = t;
      t += _dur[i];
    }
    _start = s;
  }

  /// Takes a measured length in for ayah [a]. The place on the timeline
  /// of everything after it moves; the place inside the ayah sounding
  /// does not.
  void _measured(int a, int ms) {
    if (a < 1 || a > _dur.length || ms <= 0) return;
    if (_exact[a - 1] && _dur[a - 1] == ms) return;
    _dur[a - 1] = ms;
    _exact[a - 1] = true;
    _index();
  }

  /// The timeline, exact wherever it can be before the audio arrives.
  Future<void> _measure(int session) async {
    final r = _reciter;
    if (r == null) return;
    try {
      final table = await RecitationService.liveTable(r, _surah);
      if (session != _session) return;
      if (table != null) {
        for (final w in table) {
          if (w.endMs > w.startMs) _measured(w.ayah, w.durationMs);
        }
      } else {
        final known = await RecitationService.liveDurations(r, _surah);
        if (session != _session) return;
        known.forEach(_measured);
      }
      notifyListeners();
    } catch (e) {
      rlog('live: timeline for ${r.id} $_surah — $e');
    }
  }

  Future<void> _loadWords(int session) async {
    final r = _reciter;
    if (r == null || !WordAlignService.supports(r)) return;
    if (QulWords.supports(r)) {
      // Placed on each clip as it is heard: see [_clipWords].
      _spans = {};
      notifyListeners();
      return;
    }
    final spans = await WordAlignService.load(r, _surah);
    if (session != _session || spans == null) return;
    _spans = spans;
    _windows.clear();
    notifyListeners();
  }

  Future<LiveClip> _clipFor(int a) async {
    final have = _clips[a];
    if (have != null) return have;
    final r = _reciter!;
    final session = _session;
    final clip = await RecitationService.liveClip(r, _surah, a);
    if (session == _session) {
      _clips[a] = clip;
      if (clip.durationMs > 0 &&
          (!_exact[a - 1] || _dur[a - 1] != clip.durationMs)) {
        _measured(a, clip.durationMs);
        notifyListeners();
      }
    }
    return clip;
  }

  /// The ayah sounding and the few after it, fetched ahead of the voice.
  void _prefetch() {
    if (_reciter == null) return;
    final last = math.min(_dur.length, _ayah + 3);
    for (var a = _ayah; a <= last; a++) {
      if (!_clips.containsKey(a)) _clipFor(a).ignore();
    }
  }

  /// Starts ayah [a], [inAyahMs] into it: fetched if it has to be,
  /// sounded if the listener wants it sounding.
  ///
  /// The place moves at once — the line and the list show the ayah
  /// before a byte of it has come — and the sound follows when it can.
  Future<void> _go(int a, int inAyahMs) async {
    if (_dur.isEmpty || _reciter == null) return;
    final gen = ++_gen;
    _dropCue();
    final wasEstimate = !_exact[a - 1];
    final planned = _dur[a - 1];
    final ready = _clips[a];
    _ayah = a;
    _pendingMs = inAyahMs.clamp(0, planned);
    _clip = null;
    _anchorMs = 0;
    _clock
      ..stop()
      ..reset();
    if (!enabled) {
      // The place moves; there is nothing to sound it with.
      _status = LiveStatus.paused;
      notifyListeners();
      return;
    }
    // Only a fetch shows as one. An ayah already on the disk is a new
    // source or a seek away, too quick to be worth a spinner's flicker.
    if (ready == null) {
      _status = LiveStatus.loading;
      _stopTicking();
    }
    notifyListeners();
    _own();
    if (ready == null && _shared != null) {
      // Not here yet: whatever sounds now is from somewhere else.
      try {
        await _run((p) => p.pause());
      } catch (_) {}
    }
    LiveClip clip;
    try {
      clip = ready ?? await _clipFor(a);
    } catch (e) {
      if (gen != _gen) return;
      rlog('live: ayah $a of $_surah — $e');
      _wantPlay = false;
      _status = LiveStatus.failed;
      notifyListeners();
      return;
    }
    if (gen != _gen) return;
    // A place picked against an estimate keeps its share of the ayah
    // once the real length is known.
    var inAyah = _pendingMs;
    if (wasEstimate && planned > 0 && clip.durationMs > 0) {
      inAyah = (inAyah * clip.durationMs / planned).round();
    }
    final int room = math.max(0, clip.durationMs - 120);
    inAyah = inAyah.clamp(0, room);
    final at = clip.fromMs + inAyah;
    try {
      if (_loaded != clip.path) {
        _loaded = null;
        await _run((p) => p.setSource(DeviceFileSource(clip.path)));
        _loaded = clip.path;
      }
      if (gen != _gen) return;
      await _run((p) => p.seek(Duration(milliseconds: at)));
      if (gen != _gen) return;
      _clip = clip;
      _pendingMs = 0;
      _anchorMs = at;
      if (_wantPlay) {
        await _run((p) => p.resume());
        if (gen != _gen) return;
        _clock.start();
        _status = LiveStatus.playing;
        _retries = 0;
        _startTicking();
      } else {
        _status = LiveStatus.paused;
      }
      notifyListeners();
      _prefetch();
      _cueNext();
    } catch (e) {
      if (gen != _gen) return;
      _broke('ayah $a', e);
    }
  }

  /// Sets the next ayah up on the spare player, so that moving on to it
  /// is a start rather than a load. Only across files: an ayah that goes
  /// on in the same file needs nothing, and only while playing.
  void _cueNext() {
    if (!enabled || !_wantPlay || !identical(_owner, this)) return;
    final cur = _clip;
    final next = _ayah + 1;
    if (cur == null || next > _dur.length) return;
    final n = _clips[next];
    if (n == null) {
      final session = _session;
      _clipFor(next).then((_) {
        if (session == _session && _ayah + 1 == next) _cueNext();
      }).ignore();
      return;
    }
    if (n.path == cur.path) return;
    if (_cuedAyah == next && identical(_cuedClip, n)) return;
    _cuedAyah = null;
    _cuedClip = null;
    final session = _session;
    _runSpare((p) async {
      if (_spareLoaded != n.path) {
        _spareLoaded = null;
        await p.setSource(DeviceFileSource(n.path));
        _spareLoaded = n.path;
      }
      await p.seek(Duration(milliseconds: n.fromMs));
    }).then((_) {
      if (session == _session &&
          _ayah + 1 == next &&
          identical(_owner, this)) {
        _cuedAyah = next;
        _cuedClip = n;
      }
    }, onError: (Object e) {
      rlog('live: cueing ayah $next — $e');
      _spareLoaded = null;
    });
  }

  void _dropCue() {
    _handoff?.cancel();
    _handoff = null;
    _cuedAyah = null;
    _cuedClip = null;
  }

  /// The ayah is at its end and the next is cued: the two players trade
  /// places — the cued one starts, the one that just finished goes quiet
  /// and takes the ayah after. A start on a player that is already set
  /// up takes a few milliseconds, where a load takes the half second
  /// that used to sit between every two ayahs.
  void _advance() {
    final next = _ayah + 1;
    final cue = _cuedClip;
    if (next > _dur.length ||
        _cuedAyah != next ||
        cue == null ||
        _spareShared == null ||
        !identical(_owner, this)) {
      return;
    }
    final gen = ++_gen;
    final was = _shared;
    _shared = _spareShared;
    _spareShared = was;
    final wasLoaded = _loaded;
    _loaded = _spareLoaded;
    _spareLoaded = wasLoaded;
    final wasChain = _chain;
    _chain = _spareChain;
    _spareChain = wasChain;
    _cuedAyah = null;
    _cuedClip = null;
    _ayah = next;
    _clip = cue;
    _pendingMs = 0;
    _anchorMs = cue.fromMs;
    _clock
      ..reset()
      ..start();
    notifyListeners();
    _run((p) => p.resume()).then((_) {}, onError: (Object e) {
      if (gen == _gen) _broke('ayah $next', e);
    });
    if (_spareShared != null) {
      unawaited(_runSpare((p) => p.pause()).catchError((_) {}));
    }
    _prefetch();
    _cueNext();
  }

  /// The file ran out.
  void _completed() {
    if (_status != LiveStatus.playing) return;
    final c = _clip;
    if (c == null) return;
    // The end of a file the player has just been moved off, arriving
    // late: the clip sounding now has barely begun.
    if (_filePos < c.toMs - 1500) return;
    final next = _ayah + 1;
    final n = _clips[next];
    if (n != null && n.path == c.path) {
      // One file holds the rest too, and it has ended: so has the surah.
      _ended();
      return;
    }
    if (next > _dur.length) {
      _ended();
      return;
    }
    unawaited(_go(next, 0));
  }

  /// The last ayah is over: stopped at its end, and the play button
  /// plays it again from the top.
  void _ended() {
    ++_gen;
    _wantPlay = false;
    _clock
      ..stop()
      ..reset();
    final c = _clip;
    if (c != null) _anchorMs = c.toMs;
    _status = LiveStatus.paused;
    _stopTicking();
    notifyListeners();
  }

  /// A call that failed or hung: a fresh player, and the same place —
  /// once. A second failure in a row is shown, with its retry.
  void _broke(String what, Object e) {
    rlog('live: player failed at $what — $e');
    _replacePlayer();
    final place = _inAyah;
    _clip = null;
    _pendingMs = place;
    _stopTicking();
    if (_wantPlay && _retries++ < 1) {
      unawaited(_go(_ayah, place));
      return;
    }
    _wantPlay = false;
    _status = LiveStatus.failed;
    notifyListeners();
  }

  void _playerBroke() {
    if (_status != LiveStatus.playing && _status != LiveStatus.loading) {
      _replacePlayer();
      return;
    }
    _broke('platform event', 'error event');
  }

  void _startTicking() {
    _tick ??= Timer.periodic(const Duration(milliseconds: 120), (_) => _onTick());
  }

  void _stopTicking() {
    _tick?.cancel();
    _tick = null;
  }

  /// Ayah changes inside one file, the drift check, and the net under a
  /// completion event that never came.
  void _onTick() {
    if (_status != LiveStatus.playing) return;
    final c = _clip;
    if (c == null) return;
    final pos = _filePos;
    // Nearly through, with the next ayah waiting on the other player:
    // its start is set for a breath before this one ends, finer than
    // the tick can place it.
    final left = c.toMs - pos;
    if (left <= 450 && _handoff == null && _cuedAyah == _ayah + 1) {
      final gen = _gen;
      _handoff = Timer(Duration(milliseconds: math.max(0, left - 30)), () {
        _handoff = null;
        if (gen == _gen && _status == LiveStatus.playing) _advance();
      });
    }
    if (pos >= c.toMs) {
      final n = _clips[_ayah + 1];
      if (n != null && n.path == c.path) {
        // The same file goes on into the next ayah.
        _ayah++;
        _clip = n;
        notifyListeners();
        _prefetch();
        return;
      }
      // The ayah's sound is over — its end is measured, silence and all
      // — so there is nothing to wait for: on to the next, cued or not.
      if (_handoff == null && n != null) {
        if (_cuedAyah == _ayah + 1) {
          _advance();
        } else if (_ayah < _dur.length) {
          unawaited(_go(_ayah + 1, 0));
        }
        return;
      }
      if (pos > c.toMs + 2500) {
        rlog('live: no completion for ayah $_ayah — moving on');
        _completed();
        return;
      }
    }
    if (++_ticks % 8 == 0) unawaited(_checkDrift());
  }

  /// The stopwatch against the player, about once a second.
  Future<void> _checkDrift() async {
    final gen = _gen;
    Duration? p;
    try {
      p = await _run((pl) => pl.getCurrentPosition());
    } catch (_) {
      return;
    }
    if (p == null || gen != _gen || _status != LiveStatus.playing) return;
    final real = p.inMilliseconds;
    final c = _clip;
    // Zero is what a player says between files; not a drift.
    if (real <= 0 || c == null || real > c.toMs + 400) return;
    if ((real - _filePos).abs() > 150) {
      _anchorMs = real;
      _clock
        ..reset()
        ..start();
    }
  }
}
