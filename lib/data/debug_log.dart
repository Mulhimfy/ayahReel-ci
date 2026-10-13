import 'package:flutter/foundation.dart';

/// Timestamped diagnostic log for the preview/render pipeline.
/// Grep `flutter run` output (or `adb logcat`) for "[reel]".
/// Compiled away in release builds.
void rlog(String message) {
  if (!kReleaseMode) {
    final t = DateTime.now();
    final ts = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    debugPrint('[reel] $ts $message');
  }
}

/// Failures that must survive into release builds, unlike [rlog], which
/// is compiled away.
///
/// The share bugs this exists for only ever appeared on a real device,
/// off the debugger, where a silently swallowed exception looks exactly
/// like a dead button. This reaches `flutter run`, `adb logcat` and the
/// iOS device console alike, and hands the error to the Flutter error
/// reporter so any crash tooling added later picks it up for free.
void rlogError(String what, Object error, [StackTrace? stack]) {
  debugPrint('[reel] ERROR $what: $error');
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: stack,
    library: 'ayah_reels',
    context: ErrorDescription(what),
    silent: true, // already printed above; don't double up the console
  ));
}
