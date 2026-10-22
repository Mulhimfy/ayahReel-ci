import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/arena_challenge.dart';
import 'package:ayah_reels/data/arena_engine.dart';
import 'package:ayah_reels/data/arena_service.dart';
import 'package:ayah_reels/data/quran_search.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/series_library.dart';
import 'package:ayah_reels/data/series_planner.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/render/arena_story.dart';
import 'package:ayah_reels/screens/arena_play_screen.dart';
import 'package:ayah_reels/screens/arena_result_screen.dart';
import 'package:ayah_reels/screens/arena_screen.dart';
import 'package:ayah_reels/screens/cards_screen.dart';
import 'package:ayah_reels/screens/home_shell.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/arena_constellation.dart';

/// Draws the arena on a desk, so it can be looked at without a phone.
/// Not a test of anything: it is skipped unless it is pointed
/// somewhere.
///
///   ARENA_PREVIEW_OUT=/tmp/arena flutter test test/tools/arena_preview_test.dart
///
/// The shell with its doors, the Cards tab's two rooms, the lobby with
/// and without its first-time note and with a code, every kind of
/// question before and after it is answered, the result with its review
/// open and a question looked at again, a result against a code, the
/// shelf of rounds, and the story in both scripts.
class _Tmp extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Tmp(this.dir);
  final String dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  final out = Platform.environment['ARENA_PREVIEW_OUT'];
  TestWidgetsFlutterBinding.ensureInitialized();

  const allGames = {
    ArenaGame.completeVerse,
    ArenaGame.missingWord,
    ArenaGame.whichSurah,
    ArenaGame.nextVerse,
    ArenaGame.orderWords,
    ArenaGame.surahFacts,
  };

  testWidgets('arena preview', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    PathProviderPlatform.instance = _Tmp(out!);
    Future<void> load(String family, String asset) async {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
    }

    await load('HafsUthmani', 'assets/fonts/UthmanicHafs.ttf');
    await load('Inter', 'assets/fonts/Inter.ttf');
    await load('IBMPlexSansArabic', 'assets/fonts/IBMPlexSansArabic.ttf');
    await load('CormorantGaramond', 'assets/fonts/CormorantGaramond.ttf');
    await load('ElMessiri', 'assets/fonts/ElMessiri.ttf');
    // The story picture sets its own faces through google_fonts, under
    // these names; the same bundled files stand in for them.
    for (final v in ['regular', '500', '600', '700', '800']) {
      await load('Inter_$v', 'assets/fonts/Inter.ttf');
      await load('IBMPlexSansArabic_$v', 'assets/fonts/IBMPlexSansArabic.ttf');
    }
    // A string asset this size is decoded on another isolate, and the
    // arena's file is real I/O: both need the real clock.
    late final ArenaCorpus corpus;
    await t.runAsync(() async {
      QuranSearch.loadFrom(await rootBundle.loadString(QuranSearch.asset));
      corpus = await ArenaCorpus.load();
    });
    ArenaService.reset();
    ArenaService.fileOverride = File('$out/arena_state.json');
    if (ArenaService.fileOverride!.existsSync()) {
      ArenaService.fileOverride!.deleteSync();
    }
    SettingsService.state.value = AppSettings.defaults.copyWith(name: 'Yusuf');

    // Logical pixels, one to one: every frame here is rasterized in
    // software, and a blur over a 3x phone is most of a second each.
    // The picture is taken at 2x instead.
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final key = GlobalKey();
    Widget host(Widget child, {AppLang lang = AppLang.en}) => RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: plainTheme(lang: lang),
            locale: Locale(lang.code),
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [for (final l in AppLang.values) Locale(l.code)],
            home: child,
          ),
        );

    void drain() {
      for (var e = t.takeException(); e != null; e = t.takeException()) {
        final text = e.toString();
        // Fonts and overflows are the desk's own; so is a plugin with
        // no phone under it (the reel shelf asks FFmpeg for posters).
        if (!text.contains('font') &&
            !text.contains('overflowed') &&
            !text.contains('MissingPluginException')) {
          throw e;
        }
      }
    }

    Future<void> shoot(String name) async {
      await t.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final f = File('$out/$name.png');
        await f.writeAsBytes(data!.buffer.asUint8List(), flush: true);
        // ignore: avoid_print
        print('wrote ${f.path}');
      });
      drain();
    }

    Future<void> settle([int ms = 1400]) async {
      for (var i = 0; i < 12; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump();
        drain();
      }
      for (var i = 0; i < ms ~/ 200; i++) {
        await t.pump(const Duration(milliseconds: 200));
        drain();
      }
      await t.pump(Duration(milliseconds: ms % 200));
      drain();
    }

    Future<void> scene(Widget w, {AppLang lang = AppLang.en}) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(host(w, lang: lang));
    }

    Future<void> scrollTo(Finder f) async {
      await t.scrollUntilVisible(f, 200,
          scrollable: find.byType(Scrollable).first);
      await settle(400);
    }

    // A few rounds already on the shelf, so the history has something
    // to show wherever it appears.
    const setup = ArenaSetup(scope: ArenaScope.juz(30), games: allGames);
    ArenaResult played(ArenaSetup s, int seed, int right) {
      final round = ArenaRound.generate(corpus, s, seed);
      return ArenaResult(
        setup: s,
        seed: seed,
        answers: [
          for (var i = 0; i < round.questions.length; i++)
            ArenaAnswer(
                chosen: i < right
                    ? round.questions[i].answer
                    : (round.questions[i].answer + 1) % 4,
                correct: i < right,
                timeLeft: 0.4 + 0.05 * i,
                points: i < right ? 120 + 8 * i : 0),
        ],
      );
    }

    await t.runAsync(() async {
      ArenaService.now = () => DateTime(2026, 9, 18, 21);
      await ArenaService.record(played(setup, 21, 6), mode: ArenaMode.solo);
      ArenaService.now = () => DateTime(2026, 9, 20, 9);
      await ArenaService.record(
          played(const ArenaSetup(scope: ArenaScope.surah(67), games: allGames),
              22, 9),
          mode: ArenaMode.challenge,
          rival: 'Amina',
          rivalScore: 900,
          rivalCorrect: 7,
          code: 'ABCD-EFGH-JKMN');
      ArenaService.now = () => DateTime(2026, 9, 22, 19);
      await ArenaService.record(
          played(const ArenaSetup(scope: ArenaScope.quran(), games: allGames),
              23, 3),
          mode: ArenaMode.solo);
      ArenaService.now = DateTime.now;
      await ArenaService.remember({'intro': '1'});
    });

    // A couple of reels in the library and a series under way, so the
    // home page has its shelf switch and its day lamps to show.
    final docs = Directory('$out/reels')..createSync(recursive: true);
    final kept = [
      for (final (i, surah) in [(1, 'Al-Mulk'), (2, 'Ya-Sin')])
        SavedReel(
          id: 'r$i',
          fileName: 'reel_r$i.mp4',
          reciterName: 'Mishary Alafasy',
          surahName: surah,
          startAyah: 1,
          endAyah: 5,
          gradientArgb: const [0xFF1B2433, 0xFF0B0F17],
          createdAt: DateTime(2026, 9, i),
        ),
    ];
    for (final r in kept) {
      File('${docs.path}/${r.fileName}').writeAsBytesSync(const [0]);
    }
    File('${docs.path}/library.json')
        .writeAsStringSync(jsonEncode([for (final r in kept) r.toJson()]));
    await t.runAsync(() async {
      final s = ReelSeries.plan(
        surah: 36,
        reciterId: 'alafasy',
        perDay: 1,
        days: 7,
        cuts: [
          for (var i = 0; i < 9; i++)
            SeriesCut(startAyah: i * 9 + 1, endAyah: i * 9 + 9, estimateMs: 40000),
        ],
        now: DateTime.now().subtract(const Duration(days: 2)),
      );
      await SeriesLibrary.add(s);
      await SeriesLibrary.markReelDone(s.id, 0, savedReelId: 'r1');
      await SeriesLibrary.markReelDone(s.id, 2, savedReelId: 'r2');
    });

    // 1 · The shell, with both doors.
    await scene(const HomeShell());
    await settle(1600);
    await shoot('01_shell_home');
    // Lower down: the series' lamps and the shelf, with its switch. A
    // step that can't be taken here is passed over, not the end of the
    // run.
    try {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await settle(800);
      await shoot('01b_shell_home_lower');
      await t.tap(find.text(L10n.en.shelfRounds).first);
      await settle(800);
      await shoot('01c_shell_home_rounds');
    } catch (e) {
      // ignore: avoid_print
      print('(skipped the home shelf) ${e.toString().split('\n').first}');
    }
    drain();

    // 2 · The Cards tab: its two rooms.
    await scene(
        const Scaffold(backgroundColor: AppColors.bg, body: CardsScreen()));
    await settle(1400);
    await shoot('02_cards_tab_cards');
    await t.tap(find.text(L10n.en.arenaTitle).first);
    await settle(1200);
    await shoot('03_cards_tab_arena');

    // 3 · The lobby: the first-time note, then quiet, then a code.
    await t.runAsync(() => ArenaService.remember({'intro': '0'}));
    await scene(const ArenaScreen());
    await settle(1400);
    await shoot('04_lobby_intro');
    await t.tap(find.text(L10n.en.arenaIntroGo));
    await settle(800);
    await shoot('05_lobby_solo');
    await scrollTo(find.text(L10n.en.arenaSecondsTitle));
    await shoot('06_lobby_solo_lower');
    await scrollTo(find.text(L10n.en.arenaRecent));
    await settle(900);
    await shoot('07_lobby_rounds');
    await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await settle(400);
    await t.tap(find.text(L10n.en.arenaChallenge));
    await settle(500);
    const c = ArenaChallenge(
      setup:
          ArenaSetup(scope: ArenaScope.surah(67), games: allGames, seconds: 15),
      seed: 4242,
      score: 1320,
      correct: 8,
    );
    await t.enterText(find.byType(TextField).last, c.code);
    await settle(800);
    await shoot('08_lobby_challenge');

    // 4 · Every kind of question: asked, then answered.
    final round = ArenaRound.generate(corpus, setup, 12345);
    await scene(const ArenaPlayScreen(
      setup: setup,
      seed: 12345,
      mode: ArenaMode.solo,
      me: 'Yusuf',
    ));
    await settle(400);
    final seen = <ArenaGame>{};
    for (var i = 0; i < round.questions.length; i++) {
      final q = round.questions[i];
      await settle(1300);
      final fresh = seen.add(q.game);
      if (fresh) await shoot('10_play_${q.game.name}_asked');
      final ok = q.game != ArenaGame.missingWord || !fresh;
      if (q.game == ArenaGame.orderWords) {
        final order = ok ? q.order : q.order.reversed.toList();
        for (var k = 0; k < order.length; k++) {
          if (k == order.length ~/ 2 && fresh) {
            await settle(300);
            await shoot('10_play_orderWords_half');
          }
          await t.tap(find.byKey(ValueKey('word${order[k]}')),
              warnIfMissed: false);
          await settle(120);
        }
      } else {
        final pick = ok ? q.answer : (q.answer + 1) % q.options.length;
        await t.tap(find.byKey(ValueKey('opt$i-$pick')), warnIfMissed: false);
      }
      await settle(500);
      if (fresh) await shoot('11_play_${q.game.name}_answered');
      await settle(2400);
    }
    await settle(2600);
    await shoot('20_result_solo');
    await scrollTo(find.text(L10n.en.arenaShowReview));
    await t.tap(find.text(L10n.en.arenaShowReview));
    await settle(900);
    await scrollTo(find.text(L10n.en.arenaReview));
    await shoot('21_result_solo_review');
    final wrong = find.textContaining(L10n.en.arenaYourAnswer).first;
    await scrollTo(wrong);
    await t.tap(wrong, warnIfMissed: false);
    await settle(900);
    await shoot('22_result_replay');

    // 5 · A result against a code, standing behind it.
    const vsSetup = ArenaSetup(scope: ArenaScope.surah(36), games: allGames);
    final vs = played(vsSetup, 777, 8);
    await scene(ArenaResultScreen(
      round: ArenaRound.generate(corpus, vsSetup, 777),
      result: vs,
      mode: ArenaMode.challenge,
      me: 'Yusuf',
      challenge: ArenaChallenge(
          setup: vsSetup, seed: 777, score: vs.score + 150, correct: 9),
      rival: 'Amina',
      file: false,
    ));
    await settle(2600);
    await shoot('23_result_challenge_behind');

    // 6 · The lobby in Arabic.
    await scene(const ArenaScreen(), lang: AppLang.ar);
    await settle(1400);
    await shoot('30_lobby_arabic');

    // 7 · The story picture, both scripts, alone and against a code.
    // Its faces are asked of google_fonts, whose failed loads under the
    // runner are reported as unhandled errors; a zone of its own keeps
    // them out of the test's.
    final nodes = ConstellationNode.ofRound(
        round.questions, played(setup, 12345, 8).answers);
    await t.runAsync(() async => runZonedGuarded(() async {
          for (final l in [L10n.en, const L10n(AppLang.ar)]) {
            final bytes = await ArenaStory.png(
              l: l,
              nodes: nodes,
              seed: 12345,
              name: 'Yusuf',
              score: 1480,
              correct: 8,
              asked: 10,
              scope: arenaScopeLabel(l, const ArenaScope.juz(30)),
              tier: 3,
            );
            final f = File('$out/40_story_${l.lang.code}.png');
            await f.writeAsBytes(bytes, flush: true);
            // ignore: avoid_print
            print('wrote ${f.path}');
          }
          final bytes = await ArenaStory.png(
            l: L10n.en,
            nodes: nodes,
            seed: 12345,
            name: 'Yusuf',
            score: 1480,
            correct: 8,
            asked: 10,
            scope: arenaScopeLabel(L10n.en, const ArenaScope.juz(30)),
            tier: 3,
            rival: 'Amina',
            rivalScore: 1210,
          );
          final f = File('$out/41_story_versus.png');
          await f.writeAsBytes(bytes, flush: true);
          // ignore: avoid_print
          print('wrote ${f.path}');
        }, (e, s) {
          if (!e.toString().contains('font')) throw e;
        }));
    drain();
  }, skip: out == null, timeout: const Timeout(Duration(minutes: 8)));
}

/// The app's theme without its faces — see the note on the same helper
/// in test/arena_screens_test.dart.
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
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
      bodyMedium:
          ui(fontSize: 14.5, height: 1.45, color: AppColors.textSecondary),
      labelLarge: ui(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: arabic ? 0 : 0.2),
    ),
    appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
  );
}
