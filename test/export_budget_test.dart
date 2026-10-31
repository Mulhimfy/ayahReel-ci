import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/export_budget.dart';
import 'package:ayah_reels/data/feedback_service.dart';
import 'package:ayah_reels/render/render_plan.dart';
import 'package:ayah_reels/render/render_process.dart' show RenderExit;
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

    test('an iPhone of 3 GB or less plans tightest; 4 GB and up keep '
        'roomy', () {
      ExportBudget ios(double? gbs) => PhoneBudget.hardwareBudget(
          memKb: gbs == null ? null : (gbs * gb).round(), ios: true);
      // What iOS reports: an XR or SE (2020) 2.8 GB, an 8 just under 2,
      // an 11 or 13 about 3.8, a 15 Pro about 7.5.
      expect(ios(2.8), ExportBudget.tightest);
      expect(ios(1.9), ExportBudget.tightest);
      expect(ios(3.8), ExportBudget.roomy);
      expect(ios(7.5), ExportBudget.roomy);
      // An older build's native side can't say: as it always was.
      expect(ios(null), ExportBudget.roomy);
    });

    test('an iPhone keeps roomy in passes of 16 cards, or 24 from 6 GB',
        () {
      int? cards(double? gbs, {bool ios = true}) => PhoneBudget.passCardsFor(
          memKb: gbs == null ? null : (gbs * gb).round(), ios: ios);
      // 2026-10-31: iPhones reporting 3683 and 5667 MB lost their first
      // save in one pass of 54 and 84 cards.
      expect(cards(3.6), RenderPlan.clipsPerPassLowMemory);
      expect(cards(3.8), 16);
      expect(cards(5.5), 24);
      expect(cards(7.5), 24);
      expect(cards(null), isNull, reason: 'memory unknown: as before');
      expect(cards(3.6, ios: false), isNull,
          reason: 'a 4 GB Android phone is planned tight instead');
      expect(cards(7.5, ios: false), isNull,
          reason: 'Android encodes in a process of its own');
      expect(PhoneBudget.smallIphoneCards, RenderPlan.clipsPerPassLowMemory);
      expect(PhoneBudget.iphoneCards,
          lessThan(RenderPlan.clipsPerPass), reason: 'held below 48');
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

    test('only a loss on a lean budget takes the phone to the smallest',
        () {
      ExportBudget after(ExportBudget hw, int n, int lean) =>
          PhoneBudget.budgetFor(hardware: hw, losses: n, leanLosses: lean);
      expect(after(ExportBudget.tightest, 3, 0), ExportBudget.tightest,
          reason: 'old losses, hardware ones, the cards: not the encode');
      expect(after(ExportBudget.tightest, 1, 1), ExportBudget.smallest);
      expect(after(ExportBudget.tight, 2, 1), ExportBudget.smallest);
      expect(after(ExportBudget.roomy, 1, 1), ExportBudget.tight,
          reason: 'a phone not yet planned tightest tries tightest first');
    });

    test('an encode stage is a pass, the one pass, or the join', () {
      expect(PhoneBudget.inEncode('5 cards in one pass'), isTrue);
      expect(PhoneBudget.inEncode('pass 3/7, 8 cards, in the app'), isTrue);
      expect(PhoneBudget.inEncode('join'), isTrue);
      expect(PhoneBudget.inEncode('cards'), isFalse);
      expect(PhoneBudget.inEncode('hardware probe'), isFalse);
      expect(PhoneBudget.inEncode('planning'), isFalse);
      expect(PhoneBudget.inEncode('starting'), isFalse);
      expect(PhoneBudget.inEncode(null), isFalse);
    });

    test('an x264 encode that died on the tightest budget plans the phone '
        'smallest; a hardware one does not', () async {
      PhoneBudget.debugMemKb = (2.8 * gb).round();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tightest);
      await PhoneBudget.exportStarted();
      PhoneBudget.exportPlanned(ExportBudget.tightest);
      await PhoneBudget.renderDied(hardware: true);
      expect(PhoneBudget.lasting, ExportBudget.tightest,
          reason: "the device encoder's death says nothing about x264");
      await PhoneBudget.renderDied(hardware: false);
      await PhoneBudget.exportEnded();
      expect(PhoneBudget.lasting, ExportBudget.smallest);
      expect(PhoneBudget.summary, startsWith('smallest, 2867 MB'));
      expect(jsonDecode(history().readAsStringSync())['leanLost'], 1);
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.smallest, reason: 'for good');
    });

    test('a render death on the tightest budget outside a save costs nothing',
        () async {
      PhoneBudget.debugMemKb = (2.8 * gb).round();
      await PhoneBudget.load();
      PhoneBudget.exportPlanned(ExportBudget.tightest);
      await PhoneBudget.renderDied(hardware: false);
      expect(PhoneBudget.lasting, ExportBudget.tightest);
    });

    test('a save the app died in, inside a tightest encode, plans the phone '
        'smallest and says what it ran at', () async {
      PhoneBudget.debugMemKb = (1.8 * gb).round();
      await PhoneBudget.exportStarted();
      PhoneBudget.exportPlanned(ExportBudget.tightest);
      PhoneBudget.exportStage('5 cards in one pass');
      await PhoneBudget.debugFlush();
      expect(jsonDecode(history().readAsStringSync())['budget'], 'tightest');
      PhoneBudget.reset(); // the app dies here
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.smallest);
      expect(PhoneBudget.lostDetail, ' (5 cards in one pass, tightest, 0 s in)');
    });

    test('a save the app died in while drawing the cards is no lean loss',
        () async {
      PhoneBudget.debugMemKb = (1.8 * gb).round();
      await PhoneBudget.exportStarted();
      PhoneBudget.exportPlanned(ExportBudget.tightest);
      PhoneBudget.exportStage('cards');
      await PhoneBudget.debugFlush();
      PhoneBudget.reset();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tightest);
    });

    test('a record written before the budget was is read at the phone\'s '
        'own budget', () async {
      // As 2026-10-14 code leaves a save the app died in.
      history().writeAsStringSync(jsonEncode({
        'lost': 2,
        'running': true,
        'stage': '5 cards in one pass',
        'rssMb': 91,
      }));
      PhoneBudget.debugMemKb = (1.8 * gb).round();
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.smallest);

      // The same on a phone that was planned roomy is no lean loss.
      PhoneBudget.reset();
      history().writeAsStringSync(jsonEncode({
        'lost': 0,
        'running': true,
        'stage': '5 cards in one pass',
      }));
      PhoneBudget.debugMemKb = 8 * gb;
      await PhoneBudget.load();
      expect(PhoneBudget.now, ExportBudget.tight);
    });

    test('a save the user closed the app on is not a lost save', () async {
      // A 3.7 GB phone, 1.3 GB free, the app at 166 MB in pass 5 of 17
      // (2026-10-21 note): no phone out of memory. Android's record says
      // why the app ended (the 1.0.10 store build up).
      PhoneBudget.debugMemKb = (3.7 * gb).round();
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('pass 5/17, 6 cards');
      await PhoneBudget.debugFlush();
      final mark = jsonDecode(history().readAsStringSync()) as Map;
      expect(mark['pid'], pid);
      expect(mark['since'], isA<int>());

      PhoneBudget.reset(); // swiped out of the recent apps
      PhoneBudget.debugMemKb = (3.7 * gb).round();
      int? askedPid;
      int? askedSince;
      PhoneBudget.debugAppExit = (p, since) async {
        askedPid = p;
        askedSince = since;
        return const RenderExit(
            reason: 10, importance: 100, description: 'remove task');
      };
      await PhoneBudget.load();
      expect(askedPid, pid);
      expect(askedSince, mark['since']);
      expect(PhoneBudget.takeLostExport(), isFalse);
      expect(PhoneBudget.now, ExportBudget.tight, reason: 'not one smaller');
      expect(PhoneBudget.summary, 'tight, 3788 MB, 1 closed');

      // Killed by Android in front: counted, and the note says so.
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('pass 2/9, 8 cards');
      await PhoneBudget.debugFlush();
      PhoneBudget.reset();
      PhoneBudget.debugMemKb = (3.7 * gb).round();
      PhoneBudget.debugAppExit =
          (p, since) async => const RenderExit(reason: 6, importance: 100);
      await PhoneBudget.load();
      expect(PhoneBudget.takeLostExport(), isTrue);
      expect(PhoneBudget.now, ExportBudget.tightest);
      // (No app or phone memory here: /proc is read on Android only.)
      expect(PhoneBudget.lostDetail,
          ' (pass 2/9, 8 cards, 0 s in; '
          'Android: not responding, importance 100)');

      // No record (before Android 11, or 1.0.9's native side): as before.
      await PhoneBudget.exportStarted();
      PhoneBudget.reset();
      PhoneBudget.debugMemKb = (3.7 * gb).round();
      PhoneBudget.debugAppExit = (p, since) async => null;
      await PhoneBudget.load();
      expect(PhoneBudget.takeLostExport(), isTrue);
      expect(PhoneBudget.summary, startsWith('tightest, 3788 MB, 2 lost'));
    });

    test('a lost save says what Android answered, or that it did not',
        () async {
      // 2026-10-31: an Android 13 Go phone's note had no Android reason
      // at all. Asked at a slow cold start, the 3-second wait ran out.
      PhoneBudget.debugMemKb = (3.8 * gb).round();
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('2 cards in one pass');
      await PhoneBudget.debugFlush();
      PhoneBudget.reset();
      PhoneBudget.debugMemKb = (3.8 * gb).round();
      PhoneBudget.appExitWait = const Duration(milliseconds: 50);
      addTearDown(() => PhoneBudget.appExitWait = const Duration(seconds: 20));
      PhoneBudget.debugAppExit =
          (p, since) => Completer<RenderExit?>().future; // never answers
      await PhoneBudget.load();
      expect(PhoneBudget.takeLostExport(), isTrue);
      expect(PhoneBudget.lostDetail,
          ' (2 cards in one pass, 0 s in; Android: no answer)');

      // Asked, and nothing from after the save began.
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('pass 1/3, 8 cards');
      await PhoneBudget.debugFlush();
      PhoneBudget.reset();
      PhoneBudget.debugMemKb = (3.8 * gb).round();
      PhoneBudget.debugAppExit = (p, since) async => null;
      await PhoneBudget.load();
      expect(PhoneBudget.lostDetail,
          ' (pass 1/3, 8 cards, 0 s in; Android: no record)');

      // Not Android, or before Android 11: never a record, nothing said.
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('join');
      await PhoneBudget.debugFlush();
      PhoneBudget.reset();
      PhoneBudget.debugMemKb = (3.8 * gb).round();
      PhoneBudget.debugAppExit =
          (p, since) async => throw UnsupportedError('Android 10');
      await PhoneBudget.load();
      expect(PhoneBudget.lostDetail, ' (join, 0 s in)');
    });

    test('a lost save says how long it had run', () {
      expect(
          PhoneBudget.describeLoss(const {
            'stage': 'pass 4/9, 8 cards',
            'budget': 'tight',
            'since': 1000,
            'at': 95400,
            'rssMb': 215,
          }),
          ' (pass 4/9, 8 cards, tight, 94 s in; app 215 MB)');
      // A clock set back between the two: no figure rather than a wrong one.
      expect(
          PhoneBudget.describeLoss(
              const {'stage': 'join', 'since': 5000, 'at': 1000}),
          ' (join)');
    });

    test('a save whose screen went while the app lived is not lost',
        () async {
      // The mark names this very process: only the engine was made
      // again, so nothing died for want of memory.
      PhoneBudget.debugMemKb = (3.8 * gb).round();
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('2 cards in one pass');
      await PhoneBudget.debugFlush();
      PhoneBudget.reset();
      PhoneBudget.debugMemKb = (3.8 * gb).round();
      PhoneBudget.debugLivePid = pid;
      var asked = false;
      PhoneBudget.debugAppExit = (p, since) async {
        asked = true;
        return null;
      };
      await PhoneBudget.load();
      expect(asked, isFalse, reason: 'a live process has no exit record');
      expect(PhoneBudget.takeLostExport(), isFalse);
      expect(PhoneBudget.now, ExportBudget.tight);
      expect(PhoneBudget.summary, 'tight, 3891 MB, 1 closed');
      expect(jsonDecode(history().readAsStringSync())['running'], isFalse);
    });

    test('an encode in the app says so in the stage, once', () async {
      await PhoneBudget.exportStarted();
      PhoneBudget.exportStage('pass 1/2, 4 cards');
      PhoneBudget.encodeInApp();
      PhoneBudget.encodeInApp();
      await PhoneBudget.debugFlush();
      expect(jsonDecode(history().readAsStringSync())['stage'],
          'pass 1/2, 4 cards, in the app');
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
      expect(PhoneBudget.lostDetail, ' (pass 3/7, 8 cards, 0 s in)');
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

  test('the smallest budget: below tightest, lean, small, never ahead', () {
    expect(ExportBudget.tightest.tighter, ExportBudget.smallest);
    expect(ExportBudget.smallest.tighter, ExportBudget.smallest);
    expect(ExportBudget.tight.lean, isFalse);
    expect(ExportBudget.tightest.lean, isTrue);
    expect(ExportBudget.smallest.lean, isTrue);
    expect(ExportBudget.tightest.small, isFalse);
    expect(ExportBudget.smallest.small, isTrue);
    expect(ExportBudget.smallest.rendersAhead, isFalse);
    expect(RenderPlan.clipsPerPassSmallest,
        lessThan(RenderPlan.clipsPerPassLeast));
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

    test('only the smallest budget hands the encoder 720x1280', () {
      final small = VideoRenderer.stillReelCommand(
          background: 'bg.png', cards: cards, small: true);
      expect(small,
          contains('scale=720:1280:flags=area:out_color_matrix=bt709'));
      expect(small, isNot(contains('scale=1080:1920:out_color_matrix')));
      final full = VideoRenderer.stillReelCommand(
          background: 'bg.png', cards: cards);
      expect(full, contains('scale=1080:1920:out_color_matrix=bt709'));
      expect(full, isNot(contains('720:1280')));
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
      // Then how long ago, since the failure outlives the run now.
      expect(line, endsWith('the end, just now'));
      expect(line.length, lessThan(340));
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
    // And the budget it ran at, where it was written (since 2026-10-17).
    expect(
        PhoneBudget.describeLoss(const {
          'stage': '5 cards in one pass, in the app',
          'budget': 'tightest',
          'rssMb': 91,
          'freeMb': 352,
        }),
        ' (5 cards in one pass, in the app, tightest; app 91 MB; '
        'phone 352 MB free)');
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
