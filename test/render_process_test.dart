import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/render_process.dart';
import 'package:ayah_reels/render/video_renderer.dart';

/// The app's side of the render process: what it sends, how it follows
/// an encode there, and when it gives up on the process and encodes in
/// the app again. The process itself is Kotlin (RenderService.kt); here
/// its channel is played by a handler.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ayahreel/render');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late List<Object?> polls;

  void answer({Object? run = 7}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'run' => run,
        'pid' => 4321,
        'poll' => polls.isEmpty ? null : polls.removeAt(0),
        'kill' => true,
        _ => null,
      };
    });
  }

  setUp(() {
    calls = [];
    polls = [];
    RenderProcess.debugReset(enabled: true);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    RenderProcess.debugReset();
  });

  test('an encode goes over as FFmpeg would split it, quotes and all',
      () async {
    answer();
    final run = await RenderProcess.start(
        '-i "/data/a b/card.png" -y "/data/out.mp4"',
        hardware: false);
    expect(run, isNotNull);
    expect(calls.first.method, 'run');
    expect(calls.first.arguments['args'],
        ['-i', '/data/a b/card.png', '-y', '/data/out.mp4']);
    expect(RenderProcess.knownPid, 4321);
  });

  test('it is followed until it ends, and its log comes back with it',
      () async {
    answer();
    polls = [
      null,
      {'code': 0, 'logs': 'done'}
    ];
    final run = (await RenderProcess.start('-y o.mp4', hardware: true))!;
    expect(run.hardware, isTrue);
    expect(await run.returnCode(), isNull);
    expect((await run.returnCode())!.getValue(), 0);
    expect(await run.logs(), 'done');
    expect(run.died, isFalse);
    // Over is over: no more asking.
    final asked = calls.where((c) => c.method == 'poll').length;
    expect((await run.returnCode())!.getValue(), 0);
    expect(calls.where((c) => c.method == 'poll').length, asked);
  });

  test('a death is a death, and three of them end the arrangement',
      () async {
    answer();
    for (var i = 0; i < RenderProcess.deathLimit; i++) {
      expect(RenderProcess.enabled, isTrue);
      polls = [
        {'code': RenderProcess.died, 'logs': 'the render process died'}
      ];
      final run = (await RenderProcess.start('-y o.mp4', hardware: false))!;
      await run.returnCode();
      expect(run.died, isTrue);
      RenderProcess.noteDeath();
    }
    expect(RenderProcess.enabled, isFalse);
    expect(await RenderProcess.start('-y o.mp4', hardware: false), isNull);
  });

  test('deaths with the app out of sight are not counted against it',
      () async {
    answer();
    for (var i = 0; i < RenderProcess.deathLimit + 2; i++) {
      expect(await RenderProcess.start('-y o.mp4', hardware: false),
          isNotNull);
      RenderProcess.noteAwayDeath();
      expect(RenderProcess.knownPid, isNull, reason: 'a new process');
    }
    expect(RenderProcess.enabled, isTrue);
  });

  test('after a death, the next encode waits for a new process', () async {
    RenderProcess.restartSettle = Duration.zero;
    var pids = <int?>[4321];
    var pidCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'pid') {
        pidCalls++;
        return pids.isEmpty ? null : pids.removeAt(0);
      }
      return call.method == 'run' ? 7 : null;
    });
    // No death, no wait.
    await RenderProcess.awaitRestart();
    expect(pidCalls, 0);

    await RenderProcess.start('-y o.mp4', hardware: false);
    expect(RenderProcess.knownPid, 4321);
    RenderProcess.noteAwayDeath();
    // The dead process is still listed for a moment: not the new one.
    pids = [4321, null, 99];
    pidCalls = 0;
    await RenderProcess.awaitRestart(limit: const Duration(seconds: 5));
    expect(pidCalls, 3);
    expect(RenderProcess.knownPid, 99);
    pidCalls = 0;
    await RenderProcess.awaitRestart();
    expect(pidCalls, 0, reason: 'seen once, waited for once');

    // A render no longer wanted stops waiting.
    RenderProcess.noteDeath();
    await RenderProcess.awaitRestart(stillWanted: () => false);
    expect(pidCalls, 0);

    // And it gives up in time, for the app to encode it.
    pids = List<int?>.filled(100, null, growable: true);
    final clock = Stopwatch()..start();
    await RenderProcess.awaitRestart(limit: const Duration(seconds: 1));
    expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
    pidCalls = 0;
    await RenderProcess.awaitRestart();
    expect(pidCalls, 0, reason: 'given up on, not waited for again');
  });

  test('a death is taken for Android reclaiming the app only when the app '
      'was away for it', () {
    bool reclaimed({
      bool died = true,
      bool givenUp = false,
      bool departed = true,
      bool away = false,
      Duration backFor = const Duration(seconds: 1),
    }) =>
        VideoRenderer.reclaimedAway(
            died: died,
            givenUp: givenUp,
            departed: departed,
            away: away,
            backFor: backFor);

    expect(reclaimed(away: true, departed: false), isTrue,
        reason: 'heard of with the app away');
    expect(reclaimed(), isTrue, reason: 'heard of just after it came back');
    expect(reclaimed(backFor: const Duration(minutes: 2)), isFalse,
        reason: 'a trip away long before says nothing about this death');
    expect(reclaimed(departed: false), isFalse, reason: 'never away');
    expect(reclaimed(away: true, givenUp: true), isFalse,
        reason: 'the watchdog had given up on a wedged encoder');
    expect(reclaimed(away: true, died: false), isFalse,
        reason: 'a failure, not a death');
  });

  test('FFmpeg failing to start there sends the encode back to the app',
      () async {
    answer();
    polls = [
      {'code': RenderProcess.unavailable, 'logs': 'UnsatisfiedLinkError'}
    ];
    final run = (await RenderProcess.start('-y o.mp4', hardware: false))!;
    await run.returnCode();
    expect(run.unavailable, isTrue);
    expect(run.died, isFalse);
    RenderProcess.noteUnavailable(await run.logs());
    expect(RenderProcess.enabled, isFalse);
  });

  test('no process to be had, or no channel at all: the app encodes',
      () async {
    answer(run: null);
    expect(await RenderProcess.start('-y o.mp4', hardware: false), isNull);
    expect(RenderProcess.enabled, isFalse);

    RenderProcess.debugReset(enabled: true);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await RenderProcess.start('-y o.mp4', hardware: false), isNull);
    expect(RenderProcess.enabled, isFalse);
  });

  test('a wedged encode is ended with its process', () async {
    answer();
    final run = (await RenderProcess.start('-y o.mp4', hardware: true))!;
    await run.cancel();
    expect(calls.last.method, 'cancel');
    expect(await RenderProcess.kill(), isTrue);
    expect(calls.last.method, 'kill');
    expect(RenderProcess.knownPid, isNull);
  });
}
