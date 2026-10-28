import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The beat the app's ambient motion keeps: the sky, the glows, the
/// shimmers, the turning seals.
///
/// A ticker asks for a frame at every vsync, and every frame is drawn
/// whole: Impeller keeps no cache of what didn't change, so one glow
/// pulsing on Home had the phone re-draw the sky, every blur and every
/// card 60 to 120 times a second while nobody touched anything. Play's
/// vitals (28 days to 2026-10-28) and the owner's own Redmi 13 both
/// said the app felt slow; a GPU that never rests is a hot phone, and
/// a hot phone slows everything down.
///
/// So ambient motion draws 30 frames a second on its own, which a
/// drift or a breath can't be told from, and rides along on every
/// frame something else is drawing anyway: a scroll, a press, a page
/// sliding in. Under a finger it is as smooth as before.
abstract final class AmbientPace {
  /// 30 frames a second.
  static const beat = Duration(microseconds: 33334);

  static final Stopwatch _clock = Stopwatch()..start();

  /// Until the next beat. One grid for every paced ticker, so tickers
  /// started at different moments still land in the same frame rather
  /// than each paying for one of its own.
  static Duration untilNextBeat() {
    final b = beat.inMicroseconds;
    return Duration(microseconds: b - _clock.elapsedMicroseconds % b);
  }
}

/// A [Ticker] that keeps [AmbientPace]: it ticks on any frame drawn
/// before the next beat, and asks for one itself only at the beat.
///
/// The elapsed time it hands on is the frame's own, as a plain ticker's
/// is, so an animation driven by it is at the right place on every
/// frame it is drawn on; there are just fewer frames when nothing else
/// is moving.
class PacedTicker extends Ticker {
  PacedTicker(this._onPacedTick, {super.debugLabel}) : super(_unused);

  static void _unused(Duration _) {}

  final TickerCallback _onPacedTick;

  /// The frame callback waiting for the next frame, whoever asks for it.
  int? _frame;

  /// Asks for that frame at the beat, if nothing has by then.
  Timer? _timer;

  Duration? _start;

  @override
  TickerFuture start() {
    _start = null;
    final future = super.start();
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase.index > SchedulerPhase.idle.index &&
        phase.index < SchedulerPhase.postFrameCallbacks.index) {
      _start = SchedulerBinding.instance.currentFrameTimeStamp;
    }
    return future;
  }

  @override
  bool get scheduled => _frame != null;

  @override
  void scheduleTick({bool rescheduling = false}) {
    if (_frame != null) return;
    final binding = SchedulerBinding.instance;
    _frame = binding.scheduleFrameCallback(
      _tick,
      rescheduling: rescheduling,
      scheduleNewFrame: false,
    );
    _timer = Timer(AmbientPace.untilNextBeat(), () {
      _timer = null;
      if (_frame == null) return;
      if (forceFrames) {
        binding.scheduleForcedFrame();
      } else {
        binding.scheduleFrame();
      }
    });
  }

  @override
  void unscheduleTick() {
    _timer?.cancel();
    _timer = null;
    final id = _frame;
    if (id != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _frame = null;
    }
  }

  void _tick(Duration timeStamp) {
    _frame = null;
    _timer?.cancel();
    _timer = null;
    _start ??= timeStamp;
    _onPacedTick(timeStamp - _start!);
    // The callback may have stopped the ticker, or stopped and started
    // it again, which schedules a tick of its own.
    if (shouldScheduleTick) scheduleTick(rescheduling: true);
  }
}

/// [TickerProviderStateMixin] with a second provider, [ambient], whose
/// tickers keep [AmbientPace].
///
/// `vsync: this` is for motion someone is watching happen: a press, an
/// entrance, a sheet sliding up. `vsync: ambient` is for motion that
/// only has to be there: a loop that runs as long as the widget does.
/// Both kinds are muted with the [TickerMode] around the widget, as
/// Flutter's own mixins mute theirs.
@optionalTypeArgs
mixin AmbientTickerProviderStateMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  Set<Ticker>? _tickers;
  ValueListenable<TickerModeData>? _mode;

  /// Vends [PacedTicker]s; see the mixin.
  late final TickerProvider ambient = _AmbientVsync(this);

  @override
  Ticker createTicker(TickerCallback onTick) =>
      _track(_FullTicker(onTick, this));

  Ticker _track(Ticker ticker) {
    if (_mode == null) _watchMode();
    final values = _mode!.value;
    ticker
      ..muted = !values.enabled
      ..forceFrames = values.forceFrames;
    (_tickers ??= <Ticker>{}).add(ticker);
    return ticker;
  }

  void _untrack(Ticker ticker) => _tickers?.remove(ticker);

  @override
  void activate() {
    super.activate();
    // A new place in the tree may have a new TickerMode above it.
    _watchMode();
    _apply();
  }

  void _apply() {
    final tickers = _tickers;
    if (tickers == null) return;
    final values = _mode!.value;
    for (final t in tickers) {
      t
        ..muted = !values.enabled
        ..forceFrames = values.forceFrames;
    }
  }

  void _watchMode() {
    final mode = TickerMode.getValuesNotifier(context);
    if (mode == _mode) return;
    _mode?.removeListener(_apply);
    mode.addListener(_apply);
    _mode = mode;
  }

  @override
  void dispose() {
    assert(() {
      for (final t in _tickers ?? const <Ticker>{}) {
        if (t.isActive) {
          throw FlutterError(
              '$this was disposed with an active Ticker. Dispose every '
              'AnimationController before calling super.dispose().');
        }
      }
      return true;
    }());
    _mode?.removeListener(_apply);
    _mode = null;
    super.dispose();
  }
}

class _AmbientVsync implements TickerProvider {
  final AmbientTickerProviderStateMixin _owner;
  _AmbientVsync(this._owner);

  @override
  Ticker createTicker(TickerCallback onTick) =>
      _owner._track(_PacedWidgetTicker(onTick, _owner));
}

class _FullTicker extends Ticker {
  _FullTicker(super.onTick, this._owner);
  final AmbientTickerProviderStateMixin _owner;

  @override
  void dispose() {
    _owner._untrack(this);
    super.dispose();
  }
}

class _PacedWidgetTicker extends PacedTicker {
  _PacedWidgetTicker(super.onTick, this._owner);
  final AmbientTickerProviderStateMixin _owner;

  @override
  void dispose() {
    _owner._untrack(this);
    super.dispose();
  }
}
