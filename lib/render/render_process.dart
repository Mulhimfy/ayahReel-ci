import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../data/debug_log.dart';

/// One FFmpeg encode, wherever it runs: in the app, or in the render
/// process ([RenderProcess]).
abstract class EncodeRun {
  /// For the debug log.
  String get name;

  /// Whether it runs on the device's own encoder (MediaCodec).
  bool get hardware;

  /// Null while it runs.
  Future<ReturnCode?> returnCode();

  /// Its log, or as much of it as was kept; empty if it can't be read.
  Future<String> logs();

  Future<void> cancel();

  /// The process it ran in died under it, a crash or a kill, and the
  /// app lived. Never true in the app, which would have died with it.
  bool get died;
}

/// An encode in the app's own process, as every encode used to be.
class LocalRun implements EncodeRun {
  LocalRun(this.session, {required this.hardware});

  final FFmpegSession session;

  @override
  final bool hardware;

  @override
  String get name => 'session ${session.getSessionId()}';

  @override
  Future<ReturnCode?> returnCode() => session.getReturnCode();

  @override
  Future<String> logs() async {
    try {
      return await session.getAllLogsAsString() ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<void> cancel() async {
    final id = session.getSessionId();
    if (id == null) return;
    try {
      await FFmpegKit.cancel(id);
    } catch (_) {}
  }

  @override
  bool get died => false;
}

/// An encode in the render process, followed by polling: its return
/// code and its log's end come back together when it is over.
class RemoteRun implements EncodeRun {
  RemoteRun._(this._id, {required this.hardware});

  final int _id;

  @override
  final bool hardware;

  int? _code;
  String _logs = '';

  @override
  String get name => 'render-process encode $_id';

  @override
  Future<ReturnCode?> returnCode() async {
    final known = _code;
    if (known != null) return ReturnCode(known);
    Map<Object?, Object?>? r;
    try {
      r = await RenderProcess._channel
          .invokeMethod<Map<Object?, Object?>>('poll', {'id': _id});
    } catch (e) {
      // The channel itself broke: the encode can't be followed any more,
      // which is as good as gone.
      r = {'code': RenderProcess.died, 'logs': 'render channel: $e'};
    }
    if (r == null) return null;
    final code = (r['code'] as int?) ?? RenderProcess.died;
    _code = code;
    _logs = (r['logs'] as String?) ?? '';
    return ReturnCode(code);
  }

  @override
  Future<String> logs() async => _logs;

  @override
  Future<void> cancel() async {
    // Followed until it is over: the render process runs one encode at
    // a time, so the next one waits behind this until it stops.
    if (_code == null) RenderProcess._cancelled = this;
    try {
      await RenderProcess._channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  @override
  bool get died => _code == RenderProcess.died;

  /// The render process couldn't run FFmpeg at all: the app runs it.
  bool get unavailable => _code == RenderProcess.unavailable;
}

/// FFmpeg in a process of its own, on Android (RenderService.kt).
///
/// A save that died used to take the app with it: a low-memory kill on
/// a small phone, or the device encoder's vendor code crashing, and the
/// app was simply gone mid-save (EXPORT_MEMORY.md). In a process of its
/// own the encode is what dies — the system is even told to kill it
/// before the app — and the app plans the save again behind the same
/// progress bar: smaller, or on x264.
///
/// Anything the render process can't do, the app does as before: no
/// binding within a few seconds, FFmpeg failing to start there, or a
/// process that keeps dying. Each turns it off for the rest of the run.
abstract final class RenderProcess {
  static const _channel = MethodChannel('ayahreel/render');

  /// RenderService's codes for the encodes that never ran or never
  /// finished.
  static const unavailable = -1001;
  static const died = -1003;

  /// How many deaths one run takes before the app stops sending encodes
  /// there: a process that dies at every start is no shelter, and the
  /// app's own process is where they had always run.
  static const deathLimit = 3;

  static bool _off = !Platform.isAndroid;
  static int _deaths = 0;
  static int? _pid;

  /// Set by a death there until a new process is seen, with the pid of
  /// the one that died: see [awaitRestart].
  static bool _restarting = false;
  static int? _deadPid;

  /// How long a process just seen started gets to load FFmpeg and
  /// answer the app's binding, which RenderClient waits 4 s for.
  @visibleForTesting
  static Duration restartSettle = const Duration(seconds: 2);

  /// Set when [awaitRestart] gave up: the binding that fails after it
  /// is a restart Android is still holding back, not a render process
  /// the phone can't have, so it doesn't end the arrangement at once.
  static bool _lateRestart = false;

  /// Restarts given up on in a row.
  static int _late = 0;

  /// The last encode cancelled there while still running (see
  /// [settleCancelled]).
  static RemoteRun? _cancelled;

  /// How long a cancelled encode gets to stop before the next one is
  /// sent: FFmpeg stops x264 within a frame, but a device encoder can
  /// wedge past any cancel.
  @visibleForTesting
  static Duration cancelGrace = const Duration(seconds: 5);

  /// The render process's pid, once an encode has started there: its
  /// memory goes into a lost save's note ([pid] fetches it).
  static int? get knownPid => _pid;

  static bool get enabled => !_off;

  @visibleForTesting
  static void debugReset({bool enabled = false}) {
    _off = !enabled;
    _deaths = 0;
    _pid = null;
    _restarting = false;
    _deadPid = null;
    _lateRestart = false;
    _late = 0;
    _cancelled = null;
    _waitedFirst = false;
    cancelGrace = const Duration(seconds: 5);
    restartSettle = const Duration(seconds: 2);
    firstPatience = const Duration(seconds: 12);
  }

  /// Starts [cmd] there; null when it can't take it, and the caller runs
  /// the encode in the app. [stillWanted] ends a wait for the process
  /// early once the encode is no longer wanted.
  static Future<RemoteRun?> start(
    String cmd, {
    required bool hardware,
    bool Function()? stillWanted,
  }) async {
    if (_off) return null;
    try {
      final args = {'args': FFmpegKitConfig.parseArguments(cmd)};
      var id = await _channel.invokeMethod<int>('run', args);
      // The first binding of the run took longer than RenderClient's
      // 4 s: a new process on a slow phone short of memory, where the
      // save needs it most. The binding is still on its way, so the
      // process is waited for once, and asked again, before the encode
      // goes into the app for the rest of the run. Not after a death:
      // [awaitRestart] has already waited for that one.
      if (id == null && !_lateRestart && !_waitedFirst) {
        _waitedFirst = true;
        if (await _awaitFirst(stillWanted)) {
          id = await _channel.invokeMethod<int>('run', args);
        } else if (!(stillWanted?.call() ?? true)) {
          return null;
        }
      }
      if (id != null) {
        _lateRestart = false;
        _late = 0;
        // Read at every encode: the process can be let go when idle and
        // reclaimed, and the next encode starts a new one with no death
        // seen in between. The old pid then named a dead process, whose
        // exit record [lastExit] would have read as this one's.
        final p = await pid();
        _pid = p == _deadPid ? null : p;
        return RemoteRun._(id, hardware: hardware);
      }
      // Android still holding the restart back after a death: this
      // encode runs in the app, and the next one waits for the process
      // again. Twice in a row, and the process is taken for gone.
      if (_lateRestart) {
        _lateRestart = false;
        _late++;
        if (_late < 2) {
          _restarting = true;
          rlog('render: the render process is not back yet — '
              'this encode runs in the app');
          return null;
        }
      }
      rlog('render: no render process to be had — encoding in the app');
    } on MissingPluginException {
      // A build without it.
    } catch (e) {
      rlog('render: the render process refused the encode: $e');
    }
    _off = true;
    return null;
  }

  /// Whether the first binding's wait ([start]) has been spent this run.
  static bool _waitedFirst = false;

  /// How long [start] waits for a render process that didn't answer the
  /// first binding in time.
  @visibleForTesting
  static Duration firstPatience = const Duration(seconds: 12);

  /// Waits up to [firstPatience] for a render process to be listed, and
  /// a moment more for it to answer: whether one came.
  static Future<bool> _awaitFirst(bool Function()? stillWanted) async {
    final clock = Stopwatch()..start();
    while (stillWanted?.call() ?? true) {
      final p = await pid();
      if (p != null && p != _deadPid) {
        rlog('render: the render process came up '
            '${clock.elapsed.inMilliseconds} ms after its first binding '
            'was given up on');
        await Future<void>.delayed(restartSettle);
        return stillWanted?.call() ?? true;
      }
      if (clock.elapsed >= firstPatience) return false;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// An encode died there and the app lived.
  static void noteDeath() {
    _died();
    if (++_deaths >= deathLimit && !_off) {
      _off = true;
      rlogError('render', 'the render process died $_deaths times — '
          'encoding in the app from now on');
    }
  }

  /// An encode died there with the app out of sight: Android reclaiming
  /// a background app's processes, which says nothing against this
  /// one, so it doesn't count toward [deathLimit].
  static void noteAwayDeath() => _died();

  static void _died() {
    // A process [kill] ended is already the dead one.
    if (_pid != null) _deadPid = _pid;
    _pid = null;
    _restarting = true;
  }

  /// After a death there, waits up to [limit] for the render process
  /// to start again, and returns at once otherwise. Android restarts a
  /// service that died on its own clock: a second at first, then 4, 16
  /// and 64 s for one that keeps dying, longer when memory is short,
  /// and a binding made meanwhile waits with it. Builds from 1.0.10
  /// bind it afresh ('restart'), which starts it at once. Builds up to
  /// 1.0.9 can't, and wait 20 s at most: past that it is the long
  /// backoff, and the app encodes sooner. After a restart given up on,
  /// 5 s: the progress bar has stood still long enough. An encode sent
  /// before then waits 4 s for the binding, then runs in the app.
  /// The dead process can still be listed for a moment, so only
  /// another pid counts. Stops early once [stillWanted] says the
  /// encode is no longer wanted.
  static Future<void> awaitRestart({
    bool Function()? stillWanted,
    Duration limit = const Duration(seconds: 60),
  }) async {
    if (_off || !_restarting) return;
    var rebinds = true;
    try {
      await _channel.invokeMethod<void>('restart');
    } on MissingPluginException {
      rebinds = false;
    } catch (_) {}
    final cap = _late > 0
        ? const Duration(seconds: 5)
        : rebinds
            ? limit
            : const Duration(seconds: 20);
    final wait = cap < limit ? cap : limit;
    final clock = Stopwatch()..start();
    var waited = false;
    while (stillWanted?.call() ?? true) {
      final p = await pid();
      if (p != null && p != _deadPid) {
        _restarting = false;
        _pid = p;
        _late = 0;
        if (waited) await Future<void>.delayed(restartSettle);
        return;
      }
      if (clock.elapsed >= wait) {
        _restarting = false;
        _lateRestart = true;
        rlogError('render', 'no new render process in '
            '${wait.inSeconds}s after a death');
        return;
      }
      waited = true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Before an encode goes there, lets the last cancelled one end:
  /// the process runs one at a time, so a cancelled encode still
  /// running holds the next behind it, a progress bar that never
  /// moves. One that doesn't stop within [cancelGrace] is wedged past
  /// its cancel, and its process is ended (not counted as a death:
  /// nobody wanted that encode any more).
  static Future<void> settleCancelled() async {
    final run = _cancelled;
    _cancelled = null;
    if (run == null || _off) return;
    final clock = Stopwatch()..start();
    while (await run.returnCode() == null) {
      if (clock.elapsed >= cancelGrace) {
        rlogError('render', '${run.name} still running '
            '${cancelGrace.inSeconds}s after its cancel — '
            'ending its process');
        if (await kill()) {
          _restarting = true;
          // Until the binding hears of the death: a rebind before then
          // ([awaitRestart]) reaches the dying process, or does nothing.
          final heard = Stopwatch()..start();
          while (await run.returnCode() == null &&
              heard.elapsed < const Duration(seconds: 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Keeps the screen on while a save the user waits on runs. A slow
  /// save outlasts the screen's timeout, and with the screen off the
  /// app is in the background, where Android reclaims the render
  /// process first (2026-10-14), and where iOS suspends an app mid-
  /// encode and then ends it for the memory FFmpeg holds. Store builds
  /// up to 1.0.9 don't know the call, and the screen goes off as it
  /// always did.
  static Future<void> keepScreenOn(bool on) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  /// FFmpeg couldn't be started there at all.
  static void noteUnavailable(String why) {
    _off = true;
    rlogError('render', 'the render process could not run FFmpeg: $why');
  }

  /// Ends the render process: for an encode wedged inside the device
  /// encoder, which a cancel never reaches and which holds its whole
  /// graph until the process ends. In the app that memory was lost for
  /// the rest of the run.
  static Future<bool> kill() async {
    try {
      final killed = await _channel.invokeMethod<bool>('kill') ?? false;
      if (killed) {
        // The pid stays listed a moment after the kill: [awaitRestart]
        // must not take it for the new process.
        if (_pid != null) _deadPid = _pid;
        _pid = null;
      }
      return killed;
    } catch (_) {
      return false;
    }
  }

  /// The render process's pid now, or null when none is running. Only
  /// read: [knownPid] is the process the encodes went to, which this
  /// may be the dead one of for a moment after a death.
  static Future<int?> pid() async {
    try {
      return await _channel.invokeMethod<int>('pid');
    } catch (_) {
      return null;
    }
  }

  /// What Android recorded about the death of the render process the
  /// last encode ran in: why it ended, and how much the system thought
  /// of it then. Null where it can't say (before Android 11, store
  /// builds up to 1.0.9, or not recorded yet). Asked before the death
  /// is noted, while [knownPid] is still the dead process. Only a
  /// record not written yet is asked for again: before Android 11 the
  /// answer is at once, or every death waited a second for nothing.
  static Future<RenderExit?> lastExit() async {
    final pid = _pid ?? _deadPid;
    if (pid == null) return null;
    // Android writes the record a moment after the binding hears of
    // the death.
    for (var i = 0; i < 4; i++) {
      try {
        final r = await _channel
            .invokeMethod<Map<Object?, Object?>>('exitInfo', {'pid': pid});
        if (r != null) {
          return r['unsupported'] == true ? null : RenderExit.from(r);
        }
      } on MissingPluginException {
        return null;
      } catch (_) {
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  /// What Android recorded about the death of this app's own process
  /// [pid], asked at the next launch about a save that process died in.
  /// [since] (ms since the epoch) is when that save began; an older
  /// record is another process's that had the same pid. Null where
  /// Android has no record of it (and on store builds up to 1.0.9,
  /// whose native side knows only the last two minutes). Throws
  /// [UnsupportedError] where there is never one (not Android, or
  /// before Android 11), and whatever the channel throws; the caller
  /// (`PhoneBudget`) sets the wait.
  static Future<RenderExit?> appExit(int pid, int since) async {
    if (!Platform.isAndroid || pid <= 0) {
      throw UnsupportedError('no exit records here');
    }
    final r = await _channel.invokeMethod<Map<Object?, Object?>>(
        'exitInfo', {'pid': pid, 'since': since});
    if (r == null) return null;
    if (r['unsupported'] == true) {
      throw UnsupportedError('no exit records before Android 11');
    }
    return RenderExit.from(r);
  }
}

/// Android's own account of a death in this app: the render process
/// (`RenderProcess.lastExit`) or, at the next launch, the app's own
/// process during a save (`RenderProcess.appExit`).
/// (`ApplicationExitInfo`, Android 11 and up.)
class RenderExit {
  const RenderExit({
    required this.reason,
    required this.importance,
    this.description = '',
  });

  factory RenderExit.from(Map<Object?, Object?> m) => RenderExit(
        reason: (m['reason'] as int?) ?? 0,
        importance: (m['importance'] as int?) ?? 0,
        description: (m['description'] as String?) ?? '',
      );

  /// `ApplicationExitInfo.REASON_*`.
  final int reason;

  /// `RunningAppProcessInfo.IMPORTANCE_*` as it died.
  final int importance;

  final String description;

  static const _exitSelf = 1;
  static const _signaled = 2;
  static const _userRequested = 10;
  static const _userStopped = 11;
  static const _other = 13;
  static const _packageUpdated = 16;
  static const _crash = 4;
  static const _crashNative = 5;
  static const _anr = 6;
  static const _lowMemory = 3;

  /// `IMPORTANCE_SERVICE`: below the app's own visible and perceptible
  /// ranks, a process of an app out of sight.
  static const _outOfSight = 300;

  /// The encode's own doing: a crash in it (the device encoder's vendor
  /// code), or the process stuck.
  bool get crashed =>
      reason == _crash || reason == _crashNative || reason == _anr;

  /// Ended by Android with the app out of sight: reclaimed, which says
  /// nothing about what the encode cost.
  bool get reclaimed => !crashed && importance >= _outOfSight;

  /// Ended by the person holding the phone: swiped out of the recent
  /// apps (Android says "remove task") or stopped from Settings. Says
  /// nothing about what a save costs.
  bool get userEnded => reason == _userRequested || reason == _userStopped;

  /// Ended with the app in front: the encode died for what it asked
  /// (the low-memory killer) or what it ran.
  bool get inFront => importance > 0 && importance < _outOfSight;

  @override
  String toString() {
    final why = switch (reason) {
      _lowMemory => 'low memory',
      _crash => 'crash',
      _crashNative => 'native crash',
      _anr => 'not responding',
      _exitSelf => 'exited',
      _signaled => 'signaled',
      _userRequested => 'closed by the user',
      _userStopped => 'stopped by the user',
      _other => 'ended by the system',
      _packageUpdated => 'app updated',
      _ => 'reason $reason',
    };
    return '$why, importance $importance'
        '${description.isEmpty ? '' : ' ($description)'}';
  }
}
