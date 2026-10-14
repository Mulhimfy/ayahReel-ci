import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/on_screen.dart';

/// Pictures drawn off-screen (`toImage`) borrow the window's surface,
/// and on Android's OpenGL path one drawn without it crashes the app.
/// Once the app has been away, "resumed" isn't enough: the surface is
/// there when a frame has been drawn on it, which is when Flutter
/// reports that frame's timings.
void main() {
  FrameTiming drawn() => FrameTiming(
        vsyncStart: 0,
        buildStart: 1,
        buildFinish: 2,
        rasterStart: 3,
        rasterFinish: 4,
        rasterFinishWallTime: 4,
      );

  testWidgets('after the app was away, a picture waits for a frame drawn '
      'since it came back', (t) async {
    final b = t.binding;
    void go(List<AppLifecycleState> states) {
      for (final s in states) {
        b.handleAppLifecycleStateChanged(s);
      }
    }

    OnScreen.watch();
    go([AppLifecycleState.resumed]);
    // The launch's first frame.
    b.platformDispatcher.onReportTimings!([drawn()]);
    var done = false;
    await OnScreen.settle('test').then((_) => done = true);
    expect(done, isTrue, reason: 'on screen and drawn: at once');

    // The notification shade leaves the app showing.
    final before = OnScreen.departures;
    go([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(OnScreen.departures, before);
    expect(OnScreen.away, isFalse);

    go([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(OnScreen.departures, before + 1, reason: 'one departure');
    expect(OnScreen.away, isTrue);
    done = false;
    final waiting = OnScreen.settle('test').then((_) => done = true);
    await t.pump(const Duration(seconds: 1));
    expect(done, isFalse, reason: 'away');

    go([
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await t.pump(const Duration(milliseconds: 500));
    expect(done, isFalse, reason: 'back, but nothing drawn yet');
    expect(OnScreen.away, isFalse);
    expect(OnScreen.departures, before + 1);

    b.platformDispatcher.onReportTimings!([drawn()]);
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 400));
    await waiting;
    expect(done, isTrue, reason: 'back and drawn');
  });
}
