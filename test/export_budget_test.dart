import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/export_budget.dart';
import 'package:ayah_reels/data/feedback_service.dart';
import 'package:ayah_reels/render/render_plan.dart';
import 'package:ayah_reels/render/video_renderer.dart';

/// Exports sized to the phone: first-time users on 3 and 4 GB Android
/// phones could not save a single reel, because one FFmpeg pass held
/// every verse card of it — 12 to 17 MB each, dozens of them with word
/// highlighting — on top of a ~350 MB encode, and gave every card a
/// decoder thread per core.
void main() {
  const gb = 1024 * 1024; // in kB, as /proc/meminfo counts

  setUp(PhoneBudget.reset);
  tearDown(() {
    PhoneBudget.reset();
    PhoneBudget.debugRoot = null;
    PhoneBudget.debugMemKb = null;
    PhoneBudget.debug32Bit = null;
  });

  group('what the phone allows', () {
    ExportBudget hw(double gbs, {bool is32Bit = false}) =>
        PhoneBudget.hardwareBudget(
            memKb: (gbs * gb).round(), is32Bit: is32Bit);

    test('phones sold as 6 GB and up keep the export they had', () {
      expect(hw(5.4), ExportBudget.roomy);
      expect(hw(7.5), ExportBudget.roomy);
      expect(hw(11.2), ExportBudget.roomy);
    });

    test('4 GB phones plan tight, 3 GB and less tightest', () {
      expect(hw(3.4), ExportBudget.tight);
      expect(hw(3.8), ExportBudget.tight);
      expect(hw(2.8), ExportBudget.tightest);
      expect(hw(1.8), ExportBudget.tightest);
    });

    test('a 32-bit build is tight whatever its memory', () {
      expect(hw(7.5, is32Bit: true), ExportBudget.tight);
      expect(hw(2.8, is32Bit: true), ExportBudget.tightest);
    });

    test('memory that cannot be read changes nothing', () {
      expect(PhoneBudget.hardwareBudget(), ExportBudget.roomy);
      expect(PhoneBudget.hardwareBudget(is32Bit: true), ExportBudget.tight);
    });

    test('a 32-bit build is told by the target in Platform.version', () {
      bool b(String target) => PhoneBudget.is32BitBuild(
          '3.10.0 (stable) (Tue Jul 7 2026) on "$target"');
      expect(b('android_arm'), isTrue);
      expect(b('android_ia32'), isTrue);
      expect(b('android_arm64'), isFalse);
      expect(b('android_x64'), isFalse);
      expect(b('ios_arm64'), isFalse);
      expect(b('linux_x64'), isFalse);
    });

    test('MemTotal is read off /proc/meminfo', () {
      const meminfo = 'MemTotal:        3794352 kB\n'
          'MemFree:          143020 kB\n'
          'MemAvailable:    1210388 kB\n';
      expect(PhoneBudget.memTotalKb(meminfo), 3794352);
      expect(PhoneBudget.memTotalKb('nothing here'), isNull);
    });
  });

  group('what the phone has done', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('budget_');
      PhoneBudget.debugRoot = dir.path;
      PhoneBudget.debugMemKb = 8 * gb;
      PhoneBudget.debug32Bit = false;
    });
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    File history() => File('${dir.path}/${PhoneBudget.fileName}');

    test('every lost export is one step down, to the floor', () {
      ExportBudget after(ExportBudget hw, int n) =>
          PhoneBudget.budgetFor(hardware: hw, losses: n);
      expect(after(ExportBudget.roomy, 0), ExportBudget.roomy);
      expect(after(ExportBudget.roomy, 1), ExportBudget.tight);
      expect(after(ExportBudget.roomy, 2), ExportBudget.tightest);
      expect(after(ExportBudget.tight, 1), ExportBudget.tightest);
      expect(after(ExportBudget.tightest, 5), ExportBudget.tightest);
    });

    test('an export that ended leaves nothing to count', () async {
      await PhoneBudget.exportStarted();
      expect(jsonDecode(history().readAsStringSync())['running'], isTrue);
      await PhoneBudget.exportEnded();
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.roomy);
    });

    test('an export the app died in plans smaller at the next launch',
        () async {
      await PhoneBudget.exportStarted();
      // The app is killed here: no exportEnded. Next launch:
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tight);
      expect(jsonDecode(history().readAsStringSync()),
          {'lost': 1, 'running': false},
          reason: 'counted once, and the mark cleared');

      // Counted once: a launch after that adds nothing.
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tight);

      // A second loss, and the phone is as small as it gets.
      await PhoneBudget.exportStarted();
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tightest);
    });

    test('a lost export says where it died', () async {
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('pass 3/7, 8 cards');
      // The stage is written once the file's path is known, without
      // waiting on the disk.
      await PhoneBudget.debugFlush();
      expect(jsonDecode(history().readAsStringSync())['stage'],
          'pass 3/7, 8 cards');
      // The app is killed here. Next launch:
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.lostDetail, ' (pass 3/7, 8 cards)');
      expect(jsonDecode(history().readAsStringSync()),
          {'lost': 1, 'running': false});
    });

    test('a save that died in the device encoder retires it here', () async {
      expect(PhoneBudget.hardwareTrusted, isTrue);
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('4 cards in one pass, hardware');
      await PhoneBudget.debugFlush();
      // The app is killed here. Next launch:
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.hardwareTrusted, isFalse);
      expect(PhoneBudget.summary, contains('x264 only'));
      expect(jsonDecode(history().readAsStringSync()),
          {'lost': 1, 'hwLost': 1, 'running': false});
      // For good: a launch later it is still retired.
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.hardwareTrusted, isFalse);
    });

    test('one loss elsewhere keeps the device encoder; a second retires it',
        () async {
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('pass 1/2, 8 cards');
      await Future<void>.delayed(Duration.zero);
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.hardwareTrusted, isTrue);
      expect(PhoneBudget.summary, isNot(contains('x264 only')));

      await PhoneBudget.exportStarted();
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.hardwareTrusted, isFalse);
    });

    test('an encode that died in the render process plans smaller, quietly',
        () async {
      await PhoneBudget.exportStarted();
      await PhoneBudget.renderDied(hardware: true);
      await PhoneBudget.exportEnded();
      expect(PhoneBudget.now, ExportBudget.tight);
      expect(PhoneBudget.hardwareTrusted, isFalse);
      expect(PhoneBudget.summary, contains('1 survived'));
      expect(jsonDecode(history().readAsStringSync()),
          {'lost': 1, 'hwLost': 1, 'survived': 1, 'running': false});
      // Remembered, and nothing to tell: the app lived through it.
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tight);
      expect(PhoneBudget.takeLostExport(), isFalse);
    });

    test('a render death in the eager render costs the phone nothing',
        () async {
      await PhoneBudget.load();
      await PhoneBudget.renderDied(hardware: true);
      expect(PhoneBudget.now, ExportBudget.roomy);
      expect(PhoneBudget.hardwareTrusted, isTrue);
      expect(PhoneBudget.summary, contains('1 survived'));
    });

    test('a device encoder that crashed in the eager render is retired',
        () async {
      await PhoneBudget.load();
      await PhoneBudget.renderDied(hardware: true, crashed: true);
      expect(PhoneBudget.now, ExportBudget.roomy, reason: 'not a lost save');
      expect(PhoneBudget.hardwareTrusted, isFalse);
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.hardwareTrusted, isFalse, reason: 'for good');
    });

    test('leaving during a save is on disk at once', () async {
      await PhoneBudget.exportStarted();
      await PhoneBudget.appHidden(true);
      expect(jsonDecode(history().readAsStringSync())['hidden'], isTrue);
      PhoneBudget.exportStage('pass 1/2, 8 cards');
      await PhoneBudget.debugFlush();
      expect(jsonDecode(history().readAsStringSync())['hidden'], isTrue);
    });

    test('readings and marks land in order: an ended export stays ended',
        () async {
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('pass 1/2, 8 cards');
      await PhoneBudget.exportEnded();
      await PhoneBudget.debugFlush();
      expect(jsonDecode(history().readAsStringSync())['running'], isFalse);
    });

    test('a stage outside a foreground export records nothing', () async {
      PhoneBudget.exportStage('pass 1/2, 8 cards');
      await Future<void>.delayed(Duration.zero);
      expect(history().existsSync(), isFalse);
    });

    test('a lost export is told once, and a finished one never', () async {
      await PhoneBudget.exportStarted();
      await PhoneBudget.exportEnded();
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.takeLostExport(), isFalse,
          reason: 'an export that ended has nothing to tell');

      await PhoneBudget.exportStarted();
      PhoneBudget.reset(); // the app dies here
      await PhoneBudget.load();
      expect(PhoneBudget.takeLostExport(), isTrue);
      expect(PhoneBudget.takeLostExport(), isFalse,
          reason: 'once: the notice is not shown on every screen');

      PhoneBudget.reset(); // and the launch after that
      await PhoneBudget.load();
      expect(PhoneBudget.takeLostExport(), isFalse,
          reason: 'counted and told at the launch it was found');
    });

    test('an export that died with the app out of sight is not counted',
        () async {
      // Saved, then the phone locked or another app opened, and Android
      // reclaimed the app in the background — on any phone, whatever
      // the export cost.
      await PhoneBudget.exportStarted();
      await PhoneBudget.appHidden(true);
      expect(jsonDecode(history().readAsStringSync())['hidden'], isTrue);
      PhoneBudget.reset(); // the app dies here
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.roomy);
      expect(PhoneBudget.takeLostExport(), isFalse,
          reason: 'the notice says memory, which this was not');
      expect(jsonDecode(history().readAsStringSync()),
          {'lost': 0, 'running': false});

      // Back in sight before it died: that one counts.
      await PhoneBudget.exportStarted();
      await PhoneBudget.appHidden(true);
      await PhoneBudget.appHidden(false);
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tight);
      expect(PhoneBudget.takeLostExport(), isTrue);
    });

    test('going out of sight with no export under way marks nothing',
        () async {
      await PhoneBudget.exportStarted();
      await PhoneBudget.exportEnded();
      await PhoneBudget.appHidden(true);
      expect(jsonDecode(history().readAsStringSync()),
          {'lost': 0, 'running': false});
    });

    test('a history it cannot read is no history', () async {
      history().writeAsStringSync('{not json');
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.roomy);
      // And it is written over cleanly by the next export.
      await PhoneBudget.exportStarted();
      await PhoneBudget.exportEnded();
      expect(jsonDecode(history().readAsStringSync())['running'], isFalse);
    });

    test('running out of memory narrows the rest of the run, not the next',
        () async {
      await PhoneBudget.load();
      PhoneBudget.outOfMemory(ExportBudget.roomy);
      expect(PhoneBudget.now, ExportBudget.tight);
      PhoneBudget.outOfMemory(ExportBudget.tight);
      expect(PhoneBudget.now, ExportBudget.tightest);
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.roomy);
    });
  });

  test('only a roomy phone renders a reel nobody has asked for yet', () {
    expect(ExportBudget.roomy.rendersAhead, isTrue);
    expect(ExportBudget.tight.rendersAhead, isFalse);
    expect(ExportBudget.tightest.rendersAhead, isFalse);
  });

  test('the smallest plan holds fewer cards a pass than the low-memory one',
      () {
    expect(RenderPlan.clipsPerPassLeast,
        lessThan(RenderPlan.clipsPerPassLowMemory));
    expect(RenderPlan.clipsPerPassLowMemory,
        lessThan(RenderPlan.clipsPerPass));
  });

  group('the FFmpeg inputs', () {
    final cards = [for (var i = 0; i < 40; i++) 'card$i.png'];

    test('every verse card is decoded on one thread', () {
      final cmd = VideoRenderer.stillReelCommand(
          background: 'bg.png', cards: cards);
      for (final c in cards) {
        expect(cmd, contains('-threads 1 -i "$c"'));
      }
      expect(cmd, contains('-threads 1 -i "wm.png"'));
    });

    test('the scenery is left to FFmpeg unless the budget says otherwise',
        () {
      final roomy = VideoRenderer.stillReelCommand(
          background: 'bg.png', cards: cards);
      expect(roomy, startsWith('-loop 1 -framerate 30 -i "bg.png"'));
      expect(roomy, isNot(contains('-threads 2')));
      final tight = VideoRenderer.stillReelCommand(
          background: 'bg.png', cards: cards, sceneThreads: 2);
      expect(tight, contains('-threads 2 -loop 1 -framerate 30 -i "bg.png"'));
      final clip = VideoRenderer.stillReelCommand(
          background: 'bg.mp4', cards: cards, bgIsImage: false,
          sceneThreads: 2);
      expect(clip, contains('-threads 2 -stream_loop -1 -i "bg.mp4"'));
    });

    test('the audio input carries no decoder option', () {
      final cmd = VideoRenderer.stillReelCommand(
          background: 'bg.png', cards: cards, sceneThreads: 2);
      expect(cmd, contains('-t 40.000 -i "a.m4a"'));
      expect(cmd, isNot(contains('-threads 1 -ss')));
    });
  });

  group('what a note says about exports', () {
    test('the budget always, and the last failure once there is one', () {
      PhoneBudget.debugMemKb = (3.7 * gb).round();
      PhoneBudget.debug32Bit = true;
      final before = FeedbackService.payload(message: 'x')['export']!;
      expect(before, startsWith('tight, 3788 MB, 32-bit'));

      FeedbackService.noteExportTrouble(
          'render',
          'RenderFailed(outOfMemory): [png @ 0x7a] Error opening input '
              '/data/user/0/com.ayahreel.app/cache/card7.png: '
              'Cannot allocate memory');
      final after = FeedbackService.payload(message: 'x')['export']!;
      expect(after, contains('render: RenderFailed(outOfMemory)'));
      expect(after, contains('…/card7.png'));
      expect(after, isNot(contains('/data/user')),
          reason: 'folders can name the owner; the file is enough');
    });

    test('a long failure keeps its end, where FFmpeg says what broke', () {
      FeedbackService.noteExportTrouble('render', '${'x' * 500} the end');
      final line = FeedbackService.payload(message: 'x')['export']!;
      expect(line, endsWith('the end'));
      expect(line.length, lessThan(320));
    });
  });

  test('a lost export\'s record reads as one line', () {
    expect(PhoneBudget.describeLoss(const {}), '');
    expect(
        PhoneBudget.describeLoss(const {
          'stage': 'join',
          'rssMb': 640,
          'peakMb': 690,
          'freeMb': 180,
        }),
        ' (join; app 640 MB, 690 MB at most; phone 180 MB free)');
    // A peak started over when the save began is the save's own.
    expect(
        PhoneBudget.describeLoss(const {
          'stage': '4 cards in one pass, hardware',
          'rssMb': 305,
          'peakMb': 1079,
          'peakIsSave': true,
          'freeMb': 443,
        }),
        ' (4 cards in one pass, hardware; app 305 MB, '
        '1079 MB at most in the save; phone 443 MB free)');
  });

  test('/proc lines read in kB', () {
    const status = 'Name:\tayah\n'
        'VmHWM:\t  706560 kB\n'
        'VmRSS:\t  655360 kB\n';
    expect(PhoneBudget.kbField(status, 'VmRSS'), 655360);
    expect(PhoneBudget.kbField(status, 'VmHWM'), 706560);
    expect(PhoneBudget.kbField(status, 'VmSwap'), isNull);
  });
}
