import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/ambient_pace.dart';

/// A loop on one ticker: paced (`vsync: ambient`) or a plain one
/// (`vsync: this`), as the app's ambient widgets have them.
class _Loop extends StatefulWidget {
  final bool paced;
  final List<Duration> ticks;
  const _Loop({required this.paced, required this.ticks});

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with AmbientTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    final vsync = widget.paced ? ambient : this;
    _ticker = vsync.createTicker(widget.ticks.add)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  bool asked() => SchedulerBinding.instance.hasScheduledFrame;

  testWidgets('a plain ticker asks for the very next frame', (t) async {
    final ticks = <Duration>[];
    await t.pumpWidget(_Loop(paced: false, ticks: ticks));
    expect(asked(), isTrue);
    await t.pump(const Duration(milliseconds: 16));
    expect(ticks, isNotEmpty);
    expect(asked(), isTrue);
  });

  testWidgets('an ambient ticker asks for a frame only at the beat, and '
      'rides on every frame drawn before it', (t) async {
    final ticks = <Duration>[];
    await t.pumpWidget(_Loop(paced: true, ticks: ticks));
    // Started, and waiting: no frame asked for yet.
    expect(asked(), isFalse);
    // At the beat it asks for one.
    await t.binding.delayed(AmbientPace.beat + const Duration(milliseconds: 1));
    expect(asked(), isTrue);
    await t.pump();
    expect(ticks, hasLength(1));
    expect(asked(), isFalse);
    // A frame something else draws before the next beat carries a tick
    // too, at that frame's own time.
    SchedulerBinding.instance.scheduleFrame();
    await t.pump(const Duration(milliseconds: 5));
    expect(ticks, hasLength(2));
    expect(ticks[1] - ticks[0], const Duration(milliseconds: 5));
    expect(asked(), isFalse);
  });

  testWidgets('an ambient ticker under a disabled TickerMode asks for '
      'nothing', (t) async {
    final ticks = <Duration>[];
    await t.pumpWidget(TickerMode(
      enabled: false,
      child: _Loop(paced: true, ticks: ticks),
    ));
    await t.binding.delayed(const Duration(milliseconds: 200));
    expect(asked(), isFalse);
    await t.pump();
    expect(ticks, isEmpty);
    // Enabled again, it keeps the beat.
    await t.pumpWidget(TickerMode(
      enabled: true,
      child: _Loop(paced: true, ticks: ticks),
    ));
    await t.binding.delayed(AmbientPace.beat + const Duration(milliseconds: 1));
    expect(asked(), isTrue);
    await t.pump();
    expect(ticks, hasLength(1));
  });

  test('every beat lands on one shared grid', () {
    for (var i = 0; i < 20; i++) {
      final d = AmbientPace.untilNextBeat();
      expect(d, greaterThan(Duration.zero));
      expect(d, lessThanOrEqualTo(AmbientPace.beat));
    }
  });
}
