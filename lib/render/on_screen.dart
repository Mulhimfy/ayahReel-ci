import 'dart:async';
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../data/debug_log.dart';

/// Whether the app is on screen, for drawing pictures off-screen
/// (`toImage`).
///
/// A picture drawn off-screen still borrows the window's GPU surface.
/// With the app out of sight there is no surface, so Flutter makes a
/// throwaway one for every picture. On Android's OpenGL path, which
/// phones without a usable Vulkan driver take, that crashes the app.
/// Play, 28 days to 2026-10-11: 16 users of 1.0.8 on Honor, realme and
/// Infinix phones, all a SIGSEGV in `BlitCopyBufferToTextureCommandGLES`
/// under `AndroidSurfaceGLImpeller::CreateSnapshotSurface`, all with the
/// app in the background. A save left running while its owner switched
/// apps drew its verse cards exactly there.
///
/// "Resumed" can come before the surface too: Android sends it with the
/// window's focus, which outlives a screen switched off and on, and a
/// picture drawn the moment the app came back (reminders re-armed on
/// the way back from the system's settings, a save picking up) could
/// still find none. So once the app has been away, it counts as on
/// screen again only after the raster thread has drawn a frame: a
/// frame's timings are reported only for one drawn on a surface.
/// Flutter's own issue: flutter/flutter#192365.
abstract final class OnScreen {
  /// Resumed, or not yet told otherwise (tests, and the first moments
  /// of a launch).
  static bool get now {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  /// Whether a frame has been drawn on a surface since the launch, or
  /// since the app last came back. True where nothing [watch]es (tests).
  static bool _drawn = true;

  /// The engine's timestamp (microseconds) of the first frame asked for
  /// since the app came back; null until one has begun. Frame timings
  /// arrive in batches up to a second late in release builds, so a
  /// batch heard after the return can still be frames drawn before the
  /// app left: only a frame that began no earlier than this one counts.
  static int? _since;

  /// Room for that frame's own start, which comes one frame interval
  /// before the timestamp it is handed (its vsync target).
  static const _sinceSlackUs = 100000;

  static AppLifecycleListener? _away;

  /// How many times the app has gone out of sight since the launch:
  /// another app in front, or the screen off. Android reclaims the
  /// processes of an app that is away, so a process that died across
  /// one of these may have died for that alone.
  static int get departures => _departures;
  static int _departures = 0;

  /// Out of sight now: hidden or paused. Not while merely inactive (the
  /// notification shade, a system dialog), with the app still showing.
  static bool get away => !_visible;
  static bool _visible = true;

  /// How long the app has been in front since it last came back; zero
  /// while it is away.
  static Duration get backFor => _visible ? _back.elapsed : Duration.zero;
  static final _back = Stopwatch();

  /// Starts telling an app that is back from one that has drawn again.
  /// Called once, at launch, before the first frame.
  static void watch() {
    if (_away != null) return;
    _drawn = false;
    _back.start();
    _away = AppLifecycleListener(onStateChange: (s) {
      if (s != AppLifecycleState.resumed) {
        _drawn = false;
        _since = null;
      }
      final visible =
          s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
      if (_visible && !visible) _departures++;
      if (!_visible && visible) _back.reset();
      _visible = visible;
    });
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (!now) return;
      final since = _since;
      if (since == null) {
        // No frame asked for since the return yet: only the launch's.
        if (_departures == 0 && timings.isNotEmpty) _drawn = true;
        return;
      }
      if (timings.any((t) =>
          t.timestampInMicroseconds(FramePhase.vsyncStart) >=
          since - _sinceSlackUs)) {
        _drawn = true;
      }
    });
  }

  /// Returns at once when the app is on screen and has drawn; otherwise
  /// once it is back and has drawn a frame.
  ///
  /// A save left in the background waits here rather than crashing, and
  /// goes on by itself when its owner comes back.
  static Future<void> settle(String why) async {
    if (now && _drawn) return;
    rlog('$why: the app is out of sight; drawing waits for it');
    do {
      while (!now || !_drawn) {
        await back();
        await _drawFrame();
      }
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // Gone again in that wait, and the picture would be drawn with
      // no surface after all (Play, 1.0.9, 2026-10-24: one Oppo Reno4 F,
      // the same crash in the background): wait for it again.
    } while (!now || !_drawn);
    rlog('$why: back on screen');
  }

  /// Returns once the app is in front again, at once if it is: for work
  /// that needs the app foremost but not its surface.
  static Future<void> back() async {
    if (now) return;
    final returned = Completer<void>();
    final listener = AppLifecycleListener(onStateChange: (_) {
      if (now && !returned.isCompleted) returned.complete();
    });
    try {
      await returned.future;
    } finally {
      listener.dispose();
    }
  }

  /// Asks for frames until one is drawn, the app leaves again, or three
  /// seconds pass. A release build reports a frame's timings within a
  /// second of drawing it; a phone that never reports them must not
  /// hold a save forever.
  static Future<void> _drawFrame() async {
    // A clock that can't be set: the wall clock is corrected the moment
    // a phone wakes, which is when the app comes back.
    final clock = Stopwatch()..start();
    if (_since == null) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        _since ??=
            SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
      });
    }
    while (now && !_drawn) {
      if (clock.elapsed > const Duration(seconds: 3)) {
        rlog('on screen: no frame reported since the app came back');
        _drawn = true;
        return;
      }
      SchedulerBinding.instance.scheduleForcedFrame();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
