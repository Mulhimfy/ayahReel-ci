import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FontLoader, StandardMethodCodec, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/arena_challenge.dart';
import 'package:ayah_reels/data/arena_engine.dart';
import 'package:ayah_reels/data/arena_service.dart';
import 'package:ayah_reels/data/quran_search.dart';
import 'package:ayah_reels/data/reminder_service.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/arena_play_screen.dart';
import 'package:ayah_reels/screens/arena_result_screen.dart';
import 'package:ayah_reels/screens/arena_screen.dart';
import 'package:ayah_reels/screens/cards_screen.dart';
import 'package:ayah_reels/screens/home_shell.dart';
import 'package:ayah_reels/screens/reciter_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/a11y.dart';
import 'package:ayah_reels/widgets/arena_constellation.dart';
import 'package:ayah_reels/widgets/arena_history.dart';
import 'package:ayah_reels/widgets/arena_portal.dart';
import 'package:ayah_reels/widgets/illumination.dart';
import 'package:ayah_reels/widgets/invite_sheet.dart';
import 'package:ayah_reels/widgets/tanafus_button.dart';

/// The arena, played through: the doors on the shell, the lobby's
/// choices, a whole round answered, the result with its constellation
/// and its code, the review, and the shelf of rounds kept.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const l = L10n.en;
  late Directory tmp;
  late ArenaCorpus corpus;

  const allGames = {
    ArenaGame.completeVerse,
    ArenaGame.missingWord,
    ArenaGame.whichSurah,
    ArenaGame.nextVerse,
    ArenaGame.orderWords,
    ArenaGame.surahFacts,
  };

  setUpAll(() async {
    for (final e in {
      'HafsUthmani': 'assets/fonts/UthmanicHafs.ttf',
      'Inter': 'assets/fonts/Inter.ttf',
      'IBMPlexSansArabic': 'assets/fonts/IBMPlexSansArabic.ttf',
    }.entries) {
      final loader = FontLoader(e.key)..addFont(rootBundle.load(e.value));
      await loader.load();
    }
    QuranSearch.loadFrom(await rootBundle.loadString(QuranSearch.asset));
    corpus = await ArenaCorpus.load();
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('arena_screens');
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    SettingsService.state.value = AppSettings.defaults;
  });

  tearDown(() {
    ArenaService.fileOverride = null;
    ArenaService.reset();
    SettingsService.state.value = AppSettings.defaults;
    tmp.deleteSync(recursive: true);
  });

  Widget host(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: plainTheme(),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: child,
      );

  /// Lets real I/O finish: the arena's state file is read and written
  /// with dart:io, which fake async never completes on its own.
  ///
  /// Each real-time window lets one I/O call finish; the fake pump
  /// after it runs the continuation, which may start the next call.
  Future<void> io(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await t.pump();
    }
  }

  /// A route pushed by a tap is offstage to the finders until the
  /// overlay has had a frame or two to restage: one long pump moves
  /// the clock, not the frames.
  Future<void> frames(WidgetTester t,
      [Duration first = const Duration(milliseconds: 700)]) async {
    await t.pump(first);
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  /// The one-time note has been read, so the lobby opens quiet.
  Future<void> introSeen() =>
      ArenaService.remember({'intro': '1'});

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  /// Plays every question of [round] on the screen, right or wrong as
  /// [right] says for each, and lands on the result.
  Future<void> play(WidgetTester t, ArenaRound round,
      {bool Function(int i)? right}) async {
    for (var i = 0; i < round.questions.length; i++) {
      final q = round.questions[i];
      await t.pump(const Duration(milliseconds: 700));
      final ok = right?.call(i) ?? true;
      if (q.game == ArenaGame.orderWords) {
        final order = ok ? q.order : q.order.reversed.toList();
        for (final token in order) {
          await t.tap(find.byKey(ValueKey('word$token')), warnIfMissed: false);
          await t.pump(const Duration(milliseconds: 60));
        }
      } else {
        final pick = ok ? q.answer : (q.answer + 1) % q.options.length;
        await t.tap(find.byKey(ValueKey('opt$i-$pick')), warnIfMissed: false);
      }
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text(ok ? l.arenaRight : l.arenaNotThis), findsOneWidget,
          reason: 'question $i (${q.game.name}) did not reveal');
      await t.pump(const Duration(milliseconds: 2500));
    }
    await t.pump(const Duration(milliseconds: 800));
  }

  /// Scrolls [f] into view and lets the list come to rest: a tap that
  /// lands while a scroll is still settling is taken to stop the
  /// scroll and reaches nothing underneath.
  Future<void> scrollTo(WidgetTester t, Finder f) async {
    await t.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
    // A target that is built but below the fold is not dragged to by
    // scrollUntilVisible. Its middle is set into the upper half rather
    // than dragged there: a drag ends in a fling, which carries a long
    // page (the result's, with its card of reasons to send the code)
    // right past it.
    await Scrollable.ensureVisible(t.element(f), alignment: 0.35);
    await t.pump(const Duration(milliseconds: 1200));
  }

  /// Pumps until [f] is gone, a tenth of a second at a time, for up to
  /// [seconds]; says how long it took when it did not.
  Future<void> untilGone(WidgetTester t, Finder f, {int seconds = 4}) async {
    for (var i = 0; i < seconds * 10; i++) {
      if (f.evaluate().isEmpty) return;
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the roundel stands on the shell, dotted until the arena '
      'has been opened; the corner FAB is the invitation', (t) async {
    phone(t);
    await t.runAsync(introSeen);
    await t.pumpWidget(host(const HomeShell()));
    await io(t);
    await t.pump(const Duration(milliseconds: 900));
    t.takeException();
    expect(find.byType(TanafusButton), findsOneWidget);
    expect(find.byType(TanafusFab), findsNothing);
    expect(find.byType(InviteFab), findsOneWidget);
    expect(SettingsService.state.value.arenaSeen, isFalse);
    await t.tap(find.byType(TanafusButton));
    await frames(t);
    await io(t);
    expect(find.byType(ArenaScreen), findsOneWidget);
    expect(find.text(l.arenaPitch), findsOneWidget);
    expect(find.text(l.arenaModeTitle), findsOneWidget);
    expect(SettingsService.state.value.arenaSeen, isTrue);
    await io(t);
  });

  testWidgets('a quiz notification opens the lobby — even the one that '
      'launched the app, before there was a shell to hear it', (t) async {
    phone(t);
    await t.runAsync(introSeen);
    // The tap arrives first; the shell is built after.
    HomeShell.notificationOpens.value = ReminderService.openQuiz;
    await t.pumpWidget(host(const HomeShell()));
    await io(t);
    await frames(t);
    await io(t);
    t.takeException();
    expect(find.byType(ArenaScreen), findsOneWidget);
    expect(find.text(l.arenaModeTitle), findsOneWidget);
    expect(HomeShell.notificationOpens.value, isNull, reason: 'taken once');
    await io(t);
  });

  testWidgets('a reel notification opens the first step of a new reel',
      (t) async {
    // The reciter list's sample player talks to its plugin.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = (channel, handler, message) {
      if (channel.startsWith('xyz.luan/audioplayers')) {
        return Future.value(
            const StandardMethodCodec().encodeSuccessEnvelope(null));
      }
      return handler?.call(message);
    };
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger.allMessagesHandler = null);
    phone(t);
    await t.runAsync(introSeen);
    await t.pumpWidget(host(const HomeShell()));
    await io(t);
    await t.pump(const Duration(milliseconds: 600));
    t.takeException();
    // Tapped while the app is open.
    HomeShell.notificationOpens.value = ReminderService.openReel;
    await frames(t);
    await io(t);
    expect(find.byType(ReciterScreen), findsOneWidget);
    expect(find.byType(ArenaScreen), findsNothing);
    await io(t);
  });

  testWidgets('the Cards tab\'s door opens the lobby, as the roundel does',
      (t) async {
    phone(t);
    await t.runAsync(introSeen);
    await t.pumpWidget(host(const CardsScreen()));
    await io(t);
    await t.pump(const Duration(milliseconds: 600));
    t.takeException();
    // The tab's second room.
    await t.tap(find.text(l.arenaTitle).last);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(ArenaPortal), findsOneWidget);
    expect(find.text(l.arenaEnter), findsOneWidget);
    expect(SettingsService.state.value.arenaSeen, isFalse);
    await t.tap(find.byType(ArenaPortal));
    await frames(t);
    await io(t);
    expect(find.byType(ArenaScreen), findsOneWidget);
    expect(find.byType(ArenaPlayScreen), findsNothing);
    expect(find.text(l.arenaModeTitle), findsOneWidget);
    expect(SettingsService.state.value.arenaSeen, isTrue);
    await io(t);
  });

  testWidgets('the first opening explains itself once', (t) async {
    phone(t);
    await t.pumpWidget(host(const ArenaScreen()));
    await io(t);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text(l.arenaIntroTitle), findsOneWidget);
    expect(find.text(l.arenaIntroDare), findsOneWidget);
    await t.tap(find.text(l.arenaIntroGo));
    await untilGone(t, find.text(l.arenaIntroTitle));
    expect(find.text(l.arenaIntroTitle), findsNothing);
    await io(t);
    expect(ArenaService.state.value.prefs['intro'], '1');
    // A second opening stays quiet.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host(const ArenaScreen()));
    await io(t);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text(l.arenaIntroTitle), findsNothing);
    await io(t);
  });

  testWidgets('the lobby: two ways in, three places, no clock, and a code '
      'that opens the door', (t) async {
    phone(t);
    await t.runAsync(introSeen);
    await t.pumpWidget(host(const ArenaScreen()));
    await io(t);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text(l.arenaSolo), findsWidgets);
    expect(find.text(l.arenaChallenge), findsOneWidget);
    // Whole Quran, a juz, a surah — and the juz pill wears Juz Amma.
    expect(find.text(l.arenaWholeQuran), findsOneWidget);
    expect(find.text(l.arenaJuzAmma), findsOneWidget);
    expect(find.text(l.arenaPickSurah), findsOneWidget);
    await scrollTo(t, find.text(l.arenaBegin));
    expect(find.text(l.arenaBegin), findsOneWidget);
    // Rounds have no clock, so the lobby has none to set.
    expect(find.text('Seconds per question'), findsNothing);
    await scrollTo(t, find.text(l.arenaRecent));
    expect(find.text(l.arenaNoRounds), findsOneWidget);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 1600));
    await t.pump(const Duration(milliseconds: 400));

    await t.tap(find.text(l.arenaChallenge));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(l.arenaHaveCode), findsOneWidget);
    // The page narrows to the code: no scope, no games, no clock.
    expect(find.text(l.arenaScopeTitle), findsNothing);
    await t.enterText(find.byType(TextField).last, 'not a code');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(l.arenaHaveCode), findsOneWidget);
    const c = ArenaChallenge(
      setup: ArenaSetup(scope: ArenaScope.surah(67), games: allGames),
      seed: 4242,
      score: 1320,
      correct: 8,
    );
    await t.enterText(
        find.byType(TextField).last, 'Beat me: ${c.code} in AyahReel');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(l.arenaCodeFromSomeone), findsOneWidget);
    expect(find.textContaining(l.arenaCodeToBeat(1320)), findsOneWidget);
    await scrollTo(t, find.text(l.arenaPlayCode));
    expect(find.text(l.arenaPlayCode), findsOneWidget);
    await io(t);
  });

  testWidgets('the lobby always opens on the gentlest round: Juz\' Amma '
      'and the easiest question, whatever was left (a clock kept from '
      'before included), and a line that says it is a Quran quiz', (t) async {
    phone(t);
    await t.runAsync(() => ArenaService.remember({
          'intro': '1',
          'scope': 's112',
          'seconds': '10',
          'games': 'whichSurah,nextVerse,surahFacts',
        }));
    await t.pumpWidget(host(const ArenaScreen()));
    await io(t);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text(l.arenaWhat), findsOneWidget);
    bool lit(String label) => t
        .widget<A11yTap>(find
            .ancestor(of: find.text(label), matching: find.byType(A11yTap))
            .first)
        .selected!;
    await scrollTo(t, find.text(l.arenaGameName(ArenaSetup.easiestGame)));
    for (final g in ArenaGame.values) {
      expect(lit(l.arenaGameName(g)), g == ArenaSetup.easiestGame,
          reason: '$g');
    }
    expect(ArenaSetup.byEase.toSet(), ArenaGame.values.toSet());
    expect(ArenaSetup.byEase.first, ArenaSetup.easiestGame);
    // Juz' Amma, whatever was left: Al-Ikhlas is not kept.
    expect(find.text(l.arenaJuzAmma), findsWidgets);
    expect(find.text(l.localizedSurahName('Al-Ikhlas')), findsNothing);
    await io(t);
  });

  test('a choice the scope cannot ask falls back to the easiest it can', () {
    expect(askableGames({ArenaGame.whichSurah}, {ArenaGame.missingWord}),
        {ArenaGame.missingWord});
    expect(
        askableGames({ArenaGame.whichSurah, ArenaGame.nextVerse},
            {ArenaGame.nextVerse, ArenaGame.surahFacts}),
        {ArenaGame.whichSurah, ArenaGame.nextVerse});
    expect(askableGames({ArenaGame.whichSurah}, {ArenaGame.surahFacts}),
        {ArenaGame.surahFacts});
  });

  testWidgets('a link the app was opened with is a challenge on the page',
      (t) async {
    phone(t);
    await t.runAsync(introSeen);
    const c = ArenaChallenge(
      setup: ArenaSetup(scope: ArenaScope.juz(30), games: allGames),
      seed: 77,
      score: 900,
      correct: 6,
    );
    ArenaService.takeLink(c.link(by: 'Amina'));
    await t.pumpWidget(host(const ArenaScreen()));
    await io(t);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text(l.arenaCodeFrom('Amina')), findsOneWidget);
    expect(ArenaService.pendingCode.value, isNull);
    await io(t);
  });

  testWidgets('a solo round is played to its result: a constellation, a '
      'code, a folded review, and a question to look at again', (t) async {
    phone(t);
    SettingsService.state.value = AppSettings.defaults.copyWith(name: 'Yusuf');
    const setup = ArenaSetup(scope: ArenaScope.juz(30), games: allGames);
    final round = ArenaRound.generate(corpus, setup, 12345);
    expect(round.questions, hasLength(10));
    await t.pumpWidget(host(const ArenaPlayScreen(
      setup: setup,
      seed: 12345,
      mode: ArenaMode.solo,
      me: 'Yusuf',
    )));
    await io(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(round.questions.map((q) => q.game).toSet(), allGames);
    await play(t, round, right: (i) => i % 3 != 2);
    await io(t);
    expect(find.byType(ArenaResultScreen), findsOneWidget);
    expect(find.text(l.arenaRoundOver), findsOneWidget);
    // Seven of ten is a strong round, in the word the screen uses — on
    // the card, which says it once for the whole screen.
    expect(find.text(l.arenaTierName(2).toUpperCase()), findsOneWidget);
    expect(find.textContaining(l.arenaRightOf(7, 10)), findsWidgets);
    expect(find.byType(ConstellationReveal), findsOneWidget);
    // Filed whole.
    final s = ArenaService.state.value;
    expect(s.played, 1);
    expect(s.history.single.correct, 7);
    expect(s.history.single.answers, hasLength(10));
    expect(s.history.single.seed, 12345);
    expect(s.history.single.me, 'Yusuf');
    // With the verses it asked, for the "Your verses" card.
    expect(s.history.single.verses, ArenaRecord.versesOf(round, 10));
    expect(s.history.single.verses, isNotEmpty);
    expect(s.bestFor(setup), s.history.single.score);
    await t.pump(const Duration(seconds: 2));
    // The card itself is on the screen before it is shared — with no
    // word of the mode's name on it — and one small menu under it says
    // what it carries: the score, the name, the juz. All on; each
    // turns off its own, and only its own, and the card follows.
    expect(find.text(l.arenaTitle), findsNothing);
    expect(find.text(l.arenaCardScore), findsNothing);
    await scrollTo(t, find.text(l.arenaCardMenu));
    await t.tap(find.text(l.arenaCardMenu));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(l.arenaCardScore), findsOneWidget);
    expect(find.text(l.arenaCardName), findsOneWidget);
    expect(find.text(l.arenaCardScope(ArenaScopeKind.juz)), findsOneWidget);
    expect(find.text(l.arenaStoryScored('Yusuf')), findsOneWidget);
    await t.tap(find.text(l.arenaCardScore));
    await t.pump(const Duration(milliseconds: 300));
    expect(SettingsService.state.value.arenaCardScore, isFalse);
    expect(SettingsService.state.value.arenaCardScope, isTrue);
    expect(SettingsService.state.value.arenaCardName, isTrue);
    // With the score off, the name stands where the number stood.
    expect(find.text(l.arenaStoryScored('Yusuf')), findsNothing);
    expect(find.text('Yusuf'), findsWidgets);
    await t.tap(find.text(l.arenaCardName));
    await t.pump(const Duration(milliseconds: 300));
    expect(SettingsService.state.value.arenaCardName, isFalse);
    // Two quick taps, the second before the menu has redrawn.
    await t.tap(find.text(l.arenaCardScore));
    await t.tap(find.text(l.arenaCardName));
    await t.pump(const Duration(milliseconds: 300));
    expect(SettingsService.state.value.arenaCardScore, isTrue);
    expect(SettingsService.state.value.arenaCardName, isTrue);
    // A tap anywhere else puts the menu away (the route leaves the
    // tree on the frame after its reverse animation ends).
    await t.tapAt(const Offset(8, 300));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump();
    expect(find.text(l.arenaCardScore), findsNothing);
    // The card is the whole first screen; under it the scene goes on: a
    // new best, the code that reproduces the round, what to do with
    // it, and the ways to send it.
    await scrollTo(t, find.text(l.arenaNewBest));
    expect(find.text(l.arenaNewBest), findsOneWidget);
    final plate =
        find.textContaining(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$'));
    await scrollTo(t, plate);
    expect(plate, findsOneWidget);
    expect(find.text(l.arenaYourCode), findsOneWidget);
    final code = ArenaChallenge.parse((t.widget(plate) as Text).data)!;
    expect(code.seed, 12345);
    expect(code.correct, 7);
    expect(code.setup.scope, const ArenaScope.juz(30));
    // What to do with it, in three steps.
    await scrollTo(t, find.text(l.arenaStepCompare));
    expect(find.text(l.arenaStepCopy), findsOneWidget);
    expect(find.text(l.arenaStepShare), findsOneWidget);
    expect(find.text(l.arenaStepCompare), findsOneWidget);
    await scrollTo(t, find.text(l.arenaShareCard));
    expect(find.text(l.arenaShareCard), findsOneWidget);
    expect(find.text(l.sendToInstagramStory), findsOneWidget);
    // The review waits folded, then opens on every question.
    expect(find.text(l.arenaReview), findsNothing);
    await scrollTo(t, find.text(l.arenaShowReview));
    await t.tap(find.text(l.arenaShowReview));
    await t.pump(const Duration(milliseconds: 700));
    expect(find.text(l.arenaReview), findsOneWidget);
    expect(find.text(l.arenaHideReview), findsOneWidget);
    // A wrong one says what was answered, and opens the question.
    expect(find.textContaining(l.arenaYourAnswer), findsWidgets);
    final wrong = find.textContaining(l.arenaYourAnswer).first;
    final row = find.ancestor(of: wrong, matching: find.byType(Pressable)).first;
    await scrollTo(t, row);
    await t.tap(row);
    await frames(t);
    expect(find.byType(ArenaReplayScreen), findsOneWidget);
    expect(find.text(l.arenaNotThis), findsOneWidget);
    expect(find.text(l.arenaTapToContinue), findsNothing);
    // The top bar's close comes first in the tree; a wrong option
    // carries the same glyph lower down.
    await t.tap(find.descendant(
        of: find.byType(ArenaReplayScreen),
        matching: find.byIcon(Icons.close_rounded)).first);
    await frames(t);
    await io(t);
  });

  testWidgets('a challenge is answered against its score', (t) async {
    phone(t);
    const setup = ArenaSetup(scope: ArenaScope.surah(112), games: allGames);
    final round = ArenaRound.generate(corpus, setup, 5);
    const c = ArenaChallenge(setup: setup, seed: 5, score: 100, correct: 1);
    await t.pumpWidget(host(const ArenaPlayScreen(
      setup: setup,
      seed: 5,
      mode: ArenaMode.challenge,
      me: 'Me',
      challenge: c,
      rival: 'Amina',
    )));
    await io(t);
    await t.pump(const Duration(milliseconds: 300));
    await play(t, round);
    await io(t);
    expect(find.byType(ArenaResultScreen), findsOneWidget);
    // On the card, and under it the verdict and the way back in.
    expect(find.text('Amina'), findsWidgets);
    await scrollTo(t, find.text(l.arenaYouBeat('Amina')));
    expect(find.text(l.arenaYouBeat('Amina')), findsOneWidget);
    await scrollTo(t, find.text(l.arenaRematch));
    expect(find.text(l.arenaRematch), findsOneWidget);
    expect(ArenaService.state.value.answered, 1);
    final rec = ArenaService.state.value.history.single;
    expect(rec.won, isTrue);
    expect(rec.rival, 'Amina');
    expect(rec.rivalScore, 100);
    expect(rec.code, c.code);
    await t.pump(const Duration(seconds: 2));
    await io(t);
  });

  testWidgets('a question has no clock: it waits for its answer however '
      'long that takes', (t) async {
    phone(t);
    const setup = ArenaSetup(
        scope: ArenaScope.juz(30),
        games: {ArenaGame.whichSurah},
        count: 1);
    await t.pumpWidget(host(const ArenaPlayScreen(
      setup: setup,
      seed: 2,
      mode: ArenaMode.solo,
    )));
    await io(t);
    await t.pump(const Duration(milliseconds: 300));
    // A minute on, still asking: nothing ran out, nothing was settled.
    await t.pump(const Duration(seconds: 60));
    await io(t);
    expect(find.byType(ArenaPlayScreen), findsOneWidget);
    expect(find.byType(ArenaResultScreen), findsNothing);
    expect(find.text(l.arenaNotThis), findsNothing);
    expect(find.text(l.arenaRight), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await io(t);
  });

  testWidgets('a kept round opens again from the shelf, and can be taken '
      'off it', (t) async {
    phone(t);
    await t.runAsync(introSeen);
    const setup = ArenaSetup(scope: ArenaScope.juz(30), games: allGames);
    ArenaResult played(int seed, int right) {
      final round = ArenaRound.generate(corpus, setup, seed);
      return ArenaResult(
        setup: setup,
        seed: seed,
        answers: [
          for (var i = 0; i < round.questions.length; i++)
            ArenaAnswer(
                chosen: round.questions[i].answer,
                correct: i < right,
                points: i < right ? 125 : 0),
        ],
      );
    }

    await t.runAsync(() async {
      ArenaService.now = () => DateTime(2026, 9, 20, 9);
      await ArenaService.record(played(11, 9), mode: ArenaMode.solo);
      ArenaService.now = () => DateTime(2026, 9, 21, 9);
      await ArenaService.record(played(12, 4), mode: ArenaMode.solo);
      ArenaService.now = DateTime.now;
    });
    await t.pumpWidget(host(const ArenaScreen()));
    await io(t);
    await t.pump(const Duration(milliseconds: 900));
    await scrollTo(t, find.text(l.arenaRecent));
    await t.pump(const Duration(milliseconds: 900));
    expect(find.byType(RoundCard), findsNWidgets(2));
    await t.pump(const Duration(milliseconds: 1200));
    expect(find.text('${l.arenaYourBest} · ${9 * 125}'), findsOneWidget);
    // Newest first, and a tap opens it as it was.
    final newest = find.byType(RoundCard).first;
    await t.tap(newest);
    await frames(t);
    await io(t);
    expect(find.byType(ArenaResultScreen), findsOneWidget);
    expect(find.text(l.formatDate(DateTime(2026, 9, 21, 9))), findsOneWidget);
    expect(find.textContaining(l.arenaRightOf(4, 10)), findsWidgets);
    // Opened, not filed again.
    expect(ArenaService.state.value.played, 2);
    await t.pump(const Duration(seconds: 2));
    await t.tap(find.descendant(
        of: find.byType(ArenaResultScreen),
        matching: find.byIcon(Icons.close_rounded)).first);
    await frames(t);
    // A long press takes a round off the shelf.
    await t.longPress(find.byType(RoundCard).last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(l.arenaDeleteRound), findsOneWidget);
    await t.tap(find.text(l.arenaDelete));
    await t.pump(const Duration(milliseconds: 500));
    await io(t);
    await t.pump(const Duration(milliseconds: 500));
    expect(ArenaService.state.value.history, hasLength(1));
    expect(find.byType(RoundCard), findsOneWidget);
    await io(t);
  });
}

/// The app's theme without its faces: [AppTheme.dark] resolves Inter
/// through google_fonts, which the runner cannot fetch and reports as
/// an error the moment real time passes. The bundled Inter, loaded by
/// name, gives the same type without the network.
ThemeData plainTheme({AppLang lang = AppLang.en}) {
  final arabic = lang.arabicScript;
  final family = arabic ? 'IBMPlexSansArabic' : 'Inter';
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: family,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      secondary: AppColors.gold,
      surface: AppColors.surface,
      onPrimary: Color(0xFF14100A),
      onSurface: AppColors.textPrimary,
    ),
  );
  TextStyle ui({
    required double fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: ui(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: arabic ? 0 : -0.5,
          color: AppColors.textPrimary),
      titleMedium: ui(
          fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      bodyMedium: ui(fontSize: 14.5, height: 1.45, color: AppColors.textSecondary),
      labelLarge: ui(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: arabic ? 0 : 0.2),
    ),
    appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
  );
}
