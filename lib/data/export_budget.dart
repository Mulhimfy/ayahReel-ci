import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';

/// How much of the phone an export may ask for: how many verse cards
/// one FFmpeg pass holds, how many threads it runs on, and whether the
/// preview renders the reel before anyone has asked for it.
///
/// An export is FFmpeg running inside this app's own process, and what
/// it costs is set by the reel, not by the phone. Measured on FFmpeg 8
/// with the renderer's own graph: about 350 MB before a single verse is
/// drawn, and 12 to 17 MB more for every verse card in the pass — 360
/// MB with one card, 585 MB with sixteen, 850 MB with forty. Word
/// highlighting, on unless the user turns it off, draws a card per
/// word, so an ordinary reel holds dozens of them, and one pass was
/// allowed up to 130. On a phone with 3 or 4 GB, shared with
/// the preview and whatever else the phone keeps open, that encode is
/// what the system kills: the app vanishes in the middle of a save, or
/// FFmpeg is refused memory and the save fails. The people this hit
/// had never finished a reel at all.
///
/// So an export is sized to the phone before its first encode, rather
/// than after a failed one — and a phone that loses an export anyway
/// is planned smaller from then on (see [PhoneBudget]).
enum ExportBudget {
  /// The reel exactly as the plan lays it out, a thread per core, and a
  /// silent render ahead of Share — what every phone got before this.
  roomy,

  /// A phone of 4 GB or less, a 32-bit build, or a phone that already
  /// lost one export with the app.
  tight,

  /// A phone of 3 GB or less, or one that lost an export even when it
  /// was planned tight.
  tightest,

  /// A phone that lost a save even on [tightest], on x264: the encoder
  /// is handed 720x1280 instead of 1080x1920, and a pass holds half the
  /// cards. Never what a phone starts on; only what a loss there earns
  /// ([PhoneBudget.lasting]), or this run's step down from [tightest]
  /// after an encode died there, which used to fail the save outright
  /// (2026-10-15 and 10-16 notes: "tightest … the render process died",
  /// and a 1.8 GB phone that died in a tightest pass).
  smallest;

  /// One step smaller, for a phone that has just shown it needed it.
  ExportBudget get tighter => values[(index + 1).clamp(0, values.length - 1)];

  /// Whether its software encodes run lean x264 (see
  /// `VideoRenderer.leanX264`): [tightest] and [smallest].
  bool get lean => index >= tightest.index;

  /// Whether the encoder is handed 720x1280: [smallest] only.
  bool get small => this == smallest;

  /// Whether the preview may encode the reel while the user is still
  /// looking at it.
  ///
  /// That render runs beside the preview's own video decoders, which a
  /// foreground export hands back before it starts. It is the most
  /// memory this app ever asks for at once, and on a small phone it is
  /// what got the app killed while the user was only picking a colour.
  /// There, the reel is rendered when Save or Share asks for it, behind
  /// the progress bar, with the decoders already let go.
  bool get rendersAhead => this == roomy;
}

/// What this phone can afford, worked out once and remembered.
///
/// Two things decide it. What the phone is: its memory, read off
/// `/proc/meminfo`, and whether the app runs as 32-bit code, where the
/// whole process has about 3 GB of address space for Flutter, the
/// preview's decoders and FFmpeg together. And what the phone has
/// done: an export that was running when the app died — the system's
/// low-memory killer, as a rule, which leaves no error behind for
/// anyone to catch — moves every later export on this phone one step
/// down, for good.
abstract final class PhoneBudget {
  /// Below this much memory a phone starts [ExportBudget.tight]. A
  /// phone sold as 4 GB reports 3.4 to 3.8 of it; one sold as 6 GB
  /// reports 5.4 and up.
  static const tightBelowKb = 4600 * 1024;

  /// Below this, [ExportBudget.tightest]: phones sold as 3 GB or less.
  static const tightestBelowKb = 3200 * 1024;

  /// The file that remembers a phone's lost exports, and whether one
  /// is under way right now.
  static const fileName = 'export_budget.json';

  /// Where [fileName] lives; null is the app support folder. Tests
  /// point it at a temporary one.
  @visibleForTesting
  static String? debugRoot;

  /// Stands in for the phone's memory and word size in tests.
  @visibleForTesting
  static int? debugMemKb;
  @visibleForTesting
  static bool? debug32Bit;

  static ExportBudget? _hardware;
  static int? _memKb;
  static bool _is32Bit = false;
  static int _losses = 0;

  /// Of [_losses], the ones that died while the device's own encoder
  /// (MediaCodec) was running: see [hardwareTrusted].
  static int _hwLosses = 0;

  /// Of [_losses], the ones lost inside an x264 encode on a lean budget
  /// ([ExportBudget.lean]): the phone showed that even [ExportBudget.tightest]
  /// asks for more than it has, so it plans [ExportBudget.smallest].
  /// Counted only where the loss was told with its budget, or the budget
  /// can be inferred (see [load]); a hardware death or one while the
  /// cards were drawn says nothing about what an x264 encode costs.
  static int _leanLosses = 0;

  /// The budget the save under way encodes at, written beside its stage
  /// so the next launch knows what a loss was lost at. Set by the
  /// renderer when it plans and when it steps down.
  static ExportBudget? _budget;

  /// Whether this run's peak memory reading was started over when the
  /// export began, so that a lost export's peak is its own.
  static bool _peakIsSave = false;

  /// Encodes that died in the render process while the app lived on:
  /// saves that would once have closed the app. Told in the note, so
  /// the shelter can be seen working (see [renderDied]).
  static int _survived = 0;

  /// The render process's pid while a save's encodes run there, so its
  /// memory is read beside the app's. Set by the renderer.
  static int? renderPid;
  static ExportBudget _floor = ExportBudget.roomy;
  static Future<void>? _loaded;
  static bool _lostUntold = false;

  /// Whether an export the user waits on is under way, and whether the
  /// app is out of sight while it runs — see [appHidden].
  static bool _running = false;
  static bool _hidden = false;

  /// Where the export in progress has got to, and the memory last read
  /// while it ran — written beside the running mark, so a save the app
  /// dies in says at the next launch where it died and how big the app
  /// had grown. See [exportStage].
  static String? _stage;
  static Map<String, int> _mem = const {};
  static Timer? _sampler;

  /// What the last lost export left behind, for the feedback note:
  /// " (pass 3/7, 8 cards; app 690 MB, 720 MB at most; phone 180 MB
  /// free)". Empty when nothing was recorded.
  static String _lostDetail = '';
  static String get lostDetail => _lostDetail;

  /// The budget for the next export. Before [load] has finished it
  /// knows the phone but not its history, which can only err roomy.
  static ExportBudget get now => lasting.atLeast(_floor);

  /// [now] without this run's own step-downs ([outOfMemory]): what the
  /// next launch plans, so what a reel's cache key may answer to.
  static ExportBudget get lasting => budgetFor(
      hardware: _hardware ??= _readHardware(),
      losses: _losses,
      leanLosses: _leanLosses);

  /// Whether the device's own video encoder may take this phone's
  /// exports.
  ///
  /// MediaCodec is several times faster than x264, and on most phones
  /// it is simply the better encoder. But it runs vendor code that the
  /// app can't see into, inside the same process, and a save that died
  /// in it was seen with the app at 305 MB and the phone 443 MB short
  /// of full (2026-10-11): not a phone out of memory, an encoder that
  /// took the app down with it. The six-frame probe passes on such a
  /// phone every launch, and every save after it dies the same way. So
  /// one death inside a hardware encode retires it on this phone for
  /// good, and so do two deaths anywhere — the second loss already
  /// says the fast path isn't safe enough here. Slower, but a save
  /// that finishes.
  static bool get hardwareTrusted => _hwLosses == 0 && _losses < 2;

  /// The budget a phone like this, with this many lost exports, gets.
  /// Losses step it down as far as [ExportBudget.tightest]; only a loss
  /// on a lean budget ([leanLosses]) takes it to
  /// [ExportBudget.smallest]. An old loss, from before the render
  /// process or in a hardware encode, doesn't make every reel softer.
  @visibleForTesting
  static ExportBudget budgetFor({
    required ExportBudget hardware,
    required int losses,
    int leanLosses = 0,
  }) {
    final i = hardware.index + losses;
    final b = ExportBudget.values[i.clamp(0, ExportBudget.tightest.index)];
    return b == ExportBudget.tightest && leanLosses > 0
        ? ExportBudget.smallest
        : b;
  }

  /// Whether a save's [stage] is inside an FFmpeg encode: a pass, the
  /// one pass of a short reel, or the join. Not the cards, the hardware
  /// probe or the planning before them.
  @visibleForTesting
  static bool inEncode(String? stage) =>
      stage != null &&
      (stage.contains('pass') || stage.startsWith('join'));

  /// What the phone itself allows, before anything has gone wrong on
  /// it. Memory that can't be read counts as plenty: an unknown phone
  /// keeps the export it always had.
  @visibleForTesting
  static ExportBudget hardwareBudget({int? memKb, bool is32Bit = false}) {
    if (memKb != null && memKb < tightestBelowKb) return ExportBudget.tightest;
    if (is32Bit || (memKb != null && memKb < tightBelowKb)) {
      return ExportBudget.tight;
    }
    return ExportBudget.roomy;
  }

  /// Whether [version] — `Platform.version`, which ends with the target
  /// it was built for, `on "android_arm64"` — names 32-bit Android.
  /// Read off the string rather than asked of dart:ffi, so nothing here
  /// leans on native code a patch may not be able to reach.
  @visibleForTesting
  static bool is32BitBuild(String version) =>
      RegExp(r'"android_(arm|ia32)"').hasMatch(version);

  /// `MemTotal` out of a `/proc/meminfo`, in kB; null if it isn't there.
  @visibleForTesting
  static int? memTotalKb(String meminfo) => kbField(meminfo, 'MemTotal');

  /// One `Name:   1234 kB` line of a /proc file, in kB.
  @visibleForTesting
  static int? kbField(String text, String name) {
    final m = RegExp('^$name:\\s+(\\d+)\\s*kB', multiLine: true)
        .firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// The app's memory now and at its highest, and what the phone has
  /// left, in MB — Android only; elsewhere, nothing. Read off /proc,
  /// which needs no native code a patch could not reach.
  static Map<String, int> _memoryNow() {
    if (!Platform.isAndroid) return const {};
    try {
      final status = File('/proc/self/status').readAsStringSync();
      final meminfo = File('/proc/meminfo').readAsStringSync();
      final rss = kbField(status, 'VmRSS');
      final peak = kbField(status, 'VmHWM');
      final free = kbField(meminfo, 'MemAvailable');
      // FFmpeg's own share, where it runs in the render process.
      int? renderRss;
      int? renderPeak;
      final pid = renderPid;
      if (pid != null) {
        try {
          final r = File('/proc/$pid/status').readAsStringSync();
          renderRss = kbField(r, 'VmRSS');
          renderPeak = kbField(r, 'VmHWM');
        } catch (_) {}
      }
      return {
        if (rss != null) 'rssMb': rss ~/ 1024,
        if (peak != null) 'peakMb': peak ~/ 1024,
        if (free != null) 'freeMb': free ~/ 1024,
        if (renderRss != null) 'renderMb': renderRss ~/ 1024,
        if (renderPeak != null) 'renderPeakMb': renderPeak ~/ 1024,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Starts the app's peak memory reading (`VmHWM`) over from what it
  /// holds now, so a lost save's note gives the save's own high-water
  /// mark. Without it the peak was the whole run's: a 1079 MB peak on a
  /// save that died at 305 MB (2026-10-11) could have been the scenery
  /// grid's, long before. Linux lets a process do this to itself, by
  /// writing 5 to its `clear_refs`; where Android refuses, the peak
  /// stays the run's and the note doesn't claim otherwise.
  static bool _restartPeak() {
    if (!Platform.isAndroid) return false;
    try {
      File('/proc/self/clear_refs').writeAsStringSync('5', flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The words a lost export's record comes to; see [lostDetail].
  @visibleForTesting
  static String describeLoss(Map<String, dynamic> j) {
    // Where it died, and on what budget (written since 2026-10-17).
    final stage = [
      if (j['stage'] is String) j['stage'] as String,
      if (j['budget'] is String) j['budget'] as String,
    ].join(', ');
    final rss = j['rssMb'] as int?;
    final peak = j['peakMb'] as int?;
    final free = j['freeMb'] as int?;
    final render = j['renderMb'] as int?;
    final renderPeak = j['renderPeakMb'] as int?;
    final app = [
      if (rss != null) 'app $rss MB',
      if (peak != null)
        '$peak MB at most${j['peakIsSave'] == true ? ' in the save' : ''}',
    ].join(', ');
    final parts = [
      if (stage.isNotEmpty) stage,
      if (app.isNotEmpty) app,
      if (render != null)
        'render $render MB'
            '${renderPeak != null ? ', $renderPeak MB at most' : ''}',
      if (free != null) 'phone $free MB free',
    ];
    return parts.isEmpty ? '' : ' (${parts.join('; ')})';
  }

  static ExportBudget _readHardware() {
    int? memKb = debugMemKb;
    if (memKb == null && Platform.isAndroid) {
      try {
        memKb = memTotalKb(File('/proc/meminfo').readAsStringSync());
      } catch (e) {
        rlog('budget: no /proc/meminfo: $e');
      }
    }
    final is32 = debug32Bit ?? is32BitBuild(Platform.version);
    _memKb = memKb;
    _is32Bit = is32;
    final b = hardwareBudget(memKb: memKb, is32Bit: is32);
    rlog('budget: ${memKb == null ? "memory unknown" : "${memKb ~/ 1024} MB"}'
        '${is32 ? ", 32-bit" : ""} -> ${b.name}');
    return b;
  }

  /// One line for a bug report: how this phone's exports are planned,
  /// and what decided it.
  static String get summary {
    final b = now;
    return [
      b.name,
      if (_memKb != null) '${_memKb! ~/ 1024} MB',
      if (_is32Bit) '32-bit',
      if (_losses > 0) '$_losses lost',
      if (_survived > 0) '$_survived survived',
      if (!hardwareTrusted) 'x264 only',
    ].join(', ');
  }

  /// Reads what earlier runs left. An export still marked as under way
  /// is one the app died in the middle of: it is counted, and the mark
  /// cleared. Safe to call more than once; every caller gets the same
  /// load.
  static Future<void> load() => _loaded ??= _load();

  static Future<void> _load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      _losses = (j['lost'] as int?) ?? 0;
      _hwLosses = (j['hwLost'] as int?) ?? 0;
      _leanLosses = (j['leanLost'] as int?) ?? 0;
      _survived = (j['survived'] as int?) ?? 0;
      if (j['running'] == true) {
        if (j['hidden'] == true) {
          // Out of sight when it died: Android reclaims a backgrounded
          // app on any phone, and a swipe out of the recents list ends
          // it too. Neither says anything about what an export costs,
          // so neither may shrink every export after it for good — nor
          // be told as the phone running short of memory, which is
          // what the notice says.
          rlog('budget: the last export died with the app out of sight '
              '— not counted');
        } else {
          final stage = j['stage'] as String?;
          final hardware = stage?.contains('hardware') ?? false;
          // What the save ran at: told since 2026-10-17. Before that,
          // at least what this phone was planned for good, since a save
          // only ever runs at that or smaller.
          final at = ExportBudget.values.asNameMap()[j['budget']] ?? lasting;
          if (!hardware && inEncode(stage) && at.lean) _leanLosses++;
          _losses++;
          if (hardware) _hwLosses++;
          _lostUntold = true;
          _lostDetail = describeLoss(j);
          rlogError('export', 'the last export died with the app '
              '($_losses lost on this phone) — planning smaller from now on');
        }
        _write(f, running: false);
      }
    } catch (e) {
      rlog('budget: unreadable history: $e');
    }
  }

  /// Whether the last run died in the middle of an export and nobody
  /// has said so yet. True once per such death: whoever asks is the one
  /// who tells the user, so the second asker hears false.
  ///
  /// On a phone short of memory that death is the system killing the
  /// app, which leaves no message behind — the app is simply gone, and
  /// the next launch opens as if nothing happened. This is the only
  /// place the app can still say what it was.
  static bool takeLostExport() {
    final lost = _lostUntold;
    _lostUntold = false;
    return lost;
  }

  /// Marks an export as under way, before its encode can start
  /// allocating — the mark has to be on disk by the time the system
  /// might kill the app for what the encode asked for.
  static Future<void> exportStarted() async {
    await load();
    _running = true;
    _hidden = false;
    _stage = 'starting';
    _peakIsSave = _restartPeak();
    _mem = _memoryNow();
    _sampler?.cancel();
    // A pass can run for a minute, and the memory climbs inside it:
    // read it again every few seconds, not only between stages.
    if (Platform.isAndroid) {
      _sampler = Timer.periodic(
          const Duration(seconds: 3), (_) => unawaited(_sample()));
    }
    try {
      final f = await _file();
      await _queue(() async => _write(f, running: true));
    } catch (e) {
      rlog('budget: could not mark the export: $e');
    }
  }

  /// The export the user was waiting on is over, however it ended.
  /// Where the foreground export has got to: "cards", "pass 3/7, 8
  /// cards", "join". Recorded with the memory at that moment; nothing
  /// while no foreground export is running.
  static void exportStage(String stage) {
    if (!_running) return;
    _stage = stage;
    unawaited(_sample());
  }

  /// The budget the save's encodes run at from here: set when the
  /// renderer plans, and again when it steps down. Kept for a render
  /// the user is not waiting on yet too, so a Save that joins it knows.
  static void exportPlanned(ExportBudget budget) {
    _budget = budget;
    if (_running) unawaited(_sample());
  }

  /// The encode the save has just started runs in the app's own
  /// process, not the render process: told in the stage (", in the
  /// app"), since a lost save there is the app's own memory, and on a
  /// phone whose render process works that should never happen.
  static void encodeInApp() {
    final stage = _stage;
    if (!_running || stage == null || stage.endsWith(_inApp)) return;
    _stage = '$stage$_inApp';
    unawaited(_sample());
  }

  static const _inApp = ', in the app';

  /// A reading every few seconds, written without waiting on the disk:
  /// an fsync on the UI thread every 3 s, on a budget phone's storage
  /// already busy with the encode, stalled the progress bar. A process
  /// kill loses nothing written without one; only the phone losing
  /// power would, and then the save is lost anyway.
  static Future<void> _sample() async {
    if (!_running) return;
    _mem = _memoryNow();
    try {
      final f = await _file();
      // In turn with the marks, so an older reading can't land over the
      // export's end and leave it running on disk.
      await _queue(() async {
        // Ended while it waited: the cleared mark stays.
        if (!_running) return;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(_json(running: true, hidden: _hidden));
        await tmp.rename(f.path);
      });
    } catch (_) {}
  }

  static Future<void> _writes = Future.value();

  /// Runs [write] after every write queued before it.
  static Future<void> _queue(Future<void> Function() write) {
    final next = _writes.then((_) => write());
    _writes = next.catchError((_) {});
    return next;
  }

  static Future<void> exportEnded() async {
    _running = false;
    _hidden = false;
    _sampler?.cancel();
    _sampler = null;
    _stage = null;
    _budget = null;
    _mem = const {};
    try {
      final f = await _file();
      await _queue(() async => _write(f, running: false));
    } catch (e) {
      rlog('budget: could not clear the mark: $e');
    }
  }

  /// The app went out of sight ([hidden]) or came back while an export
  /// was under way. A death while it was out of sight is not counted
  /// as a lost export: see [load].
  static Future<void> appHidden(bool hidden) async {
    if (!_running || hidden == _hidden) return;
    _hidden = hidden;
    try {
      final f = await _file();
      // Leaving is when Android kills an app: the mark goes down now,
      // not behind a reading still on its way to a busy disk. That
      // reading may land over it a moment later, and the queued write
      // below puts it back after.
      if (hidden && _running) {
        _write(f, running: true, hidden: true, tmp: '${f.path}.hide');
      }
      await _queue(() async {
        if (_running) _write(f, running: true, hidden: _hidden);
      });
    } catch (e) {
      rlog('budget: could not mark the export hidden: $e');
    }
  }

  /// An encode died in the render process, and the app lived.
  ///
  /// What a lost save used to be — the system killing the encode for
  /// memory, or the device encoder crashing — except that the app is
  /// still here to plan the save again. The phone is planned as a lost
  /// save would plan it, from now on: the encode showed what this phone
  /// can't afford. The caller has already ruled out a death with the
  /// app away (`VideoRenderer.reclaimedAway`), the one judge of that, so
  /// it isn't judged again here by another account of the app's state.
  ///
  /// Only for a save the user waits on, as a lost save is: the eager
  /// render runs beside the preview's decoders, the most memory the app
  /// asks for, and a death there is answered for the session (the
  /// retry plans smaller, which stops rendering ahead) rather than
  /// slowing every later save on the phone for good. Except a device
  /// encoder that [crashed] there (Android's record says so): that is
  /// the encoder's doing wherever it ran, and it is retired as a save's
  /// death would retire it, or every launch probes it, loses it and
  /// encodes the reel again on x264.
  static Future<void> renderDied({
    required bool hardware,
    bool crashed = false,
  }) async {
    await load();
    _survived++;
    if (_running) {
      _losses++;
      if (hardware) _hwLosses++;
      // An x264 encode that died on a lean budget: even tightest asks
      // too much here (see [ExportBudget.smallest]).
      if (!hardware && (_budget?.lean ?? false)) _leanLosses++;
    } else if (hardware && crashed) {
      _hwLosses++;
    }
    rlog('budget: an encode died in the render process '
        '(${hardware ? "hardware" : "x264"}; $_survived so far)'
        '${_running ? ' — planning smaller from now on' : hardware && crashed ? ', the device encoder crashed — x264 from now on' : ', not a save anyone waited on'}');
    try {
      final f = await _file();
      await _queue(() async => _write(f, running: _running, hidden: _hidden));
    } catch (e) {
      rlog('budget: could not record it: $e');
    }
  }

  /// FFmpeg was refused memory: every later encode in this run plans one
  /// step smaller. Not remembered across launches — it was answered with
  /// a retry, not a dead app — unlike a lost export.
  static void outOfMemory(ExportBudget at) {
    _floor = at.tighter.atLeast(_floor);
  }

  static Future<File> _file() async {
    final root = debugRoot;
    if (root != null) return File('$root/$fileName');
    return _known ??=
        File('${(await getApplicationSupportDirectory()).path}/$fileName');
  }

  static File? _known;

  /// Whole or not at all, and still at once: this is written as the app
  /// goes to the background, where a kill mid-write left an empty file,
  /// read at the next launch as no losses at all.
  /// [tmp] names the file it is written to first, for a write made
  /// outside the queue, beside one in it that may be writing its own.
  static void _write(File f,
      {required bool running, bool hidden = false, String? tmp}) {
    final t = File('${tmp ?? f.path}.tmp');
    t.writeAsStringSync(_json(running: running, hidden: hidden), flush: true);
    t.renameSync(f.path);
  }

  static String _json({required bool running, bool hidden = false}) =>
      jsonEncode({
          'lost': _losses,
          if (_hwLosses > 0) 'hwLost': _hwLosses,
          if (_leanLosses > 0) 'leanLost': _leanLosses,
          if (_survived > 0) 'survived': _survived,
          'running': running,
          if (hidden) 'hidden': true,
          if (running && _stage != null) 'stage': _stage,
          if (running && _budget != null) 'budget': _budget!.name,
          if (running) ..._mem,
          if (running && _peakIsSave) 'peakIsSave': true,
        });

  /// Waits for every write asked for so far to land; tests only.
  @visibleForTesting
  static Future<void> debugFlush() async {
    // A reading finds the file before it joins the queue.
    await Future<void>.delayed(Duration.zero);
    await _writes;
  }

  /// Forgets everything; tests only.
  @visibleForTesting
  static void reset() {
    _hardware = null;
    _memKb = null;
    _is32Bit = false;
    _losses = 0;
    _hwLosses = 0;
    _leanLosses = 0;
    _budget = null;
    _peakIsSave = false;
    _survived = 0;
    renderPid = null;
    _floor = ExportBudget.roomy;
    _loaded = null;
    _lostUntold = false;
    _running = false;
    _hidden = false;
    _sampler?.cancel();
    _sampler = null;
    _stage = null;
    _mem = const {};
    _lostDetail = '';
    _writes = Future.value();
    _known = null;
  }
}

extension on ExportBudget {
  ExportBudget atLeast(ExportBudget other) =>
      index >= other.index ? this : other;
}
