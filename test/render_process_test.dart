import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/render_process.dart';

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
