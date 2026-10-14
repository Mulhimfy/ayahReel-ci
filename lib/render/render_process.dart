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

  /// The render process's pid, once an encode has started there: its
  /// memory goes into a lost save's note ([pid] fetches it).
  static int? get knownPid => _pid;

  static bool get enabled => !_off;

  @visibleForTesting
  static void debugReset({bool enabled = false}) {
    _off = !enabled;
    _deaths = 0;
    _pid = null;
  }

  /// Starts [cmd] there; null when it can't take it, and the caller runs
  /// the encode in the app.
  static Future<RemoteRun?> start(String cmd, {required bool hardware}) async {
    if (_off) return null;
    try {
      final id = await _channel.invokeMethod<int>(
          'run', {'args': FFmpegKitConfig.parseArguments(cmd)});
      if (id != null) {
        if (_pid == null) await pid();
        return RemoteRun._(id, hardware: hardware);
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

  /// An encode died there and the app lived.
  static void noteDeath() {
    _pid = null;
    if (++_deaths >= deathLimit && !_off) {
      _off = true;
      rlogError('render', 'the render process died $_deaths times — '
          'encoding in the app from now on');
    }
  }

  /// An encode died there with the app out of sight: Android reclaiming
  /// a background app's processes, which says nothing against this
  /// one, so it doesn't count toward [deathLimit].
  static void noteAwayDeath() => _pid = null;

  /// Waits, up to [limit], for Android to start the render process
  /// again after a death. It does that by itself, a second or more
  /// later and longer when memory is short, and an encode sent before
  /// then finds no process and runs in the app for the rest of the run.
  static Future<void> awaitRestart(
      {Duration limit = const Duration(seconds: 20)}) async {
    if (_off) return;
    final until = DateTime.now().add(limit);
    while (await pid() == null && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
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
      if (killed) _pid = null;
      return killed;
    } catch (_) {
      return false;
    }
  }

  static Future<int?> pid() async {
    try {
      return _pid = await _channel.invokeMethod<int>('pid');
    } catch (_) {
      return null;
    }
  }
}
