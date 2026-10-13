import 'dart:async';

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
abstract final class OnScreen {
  /// Resumed, or not yet told otherwise (tests, and the first moments
  /// of a launch).
  static bool get now {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  /// Returns at once when the app is on screen; otherwise once it is
  /// back and has drawn a frame. The surface is made after Android says
  /// the app is back, so "resumed" alone can still be too early.
  ///
  /// A save left in the background waits here rather than crashing, and
  /// goes on by itself when its owner comes back.
  static Future<void> settle(String why) async {
    if (now) return;
    rlog('$why: the app is out of sight; drawing waits for it');
    while (!now) {
      final back = Completer<void>();
      final listener = AppLifecycleListener(onStateChange: (_) {
        if (now && !back.isCompleted) back.complete();
      });
      try {
        await back.future;
      } finally {
        listener.dispose();
      }
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    rlog('$why: back on screen');
  }
}
