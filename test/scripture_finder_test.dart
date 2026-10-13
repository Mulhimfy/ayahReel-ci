import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/hadith_library.dart';
import 'package:ayah_reels/data/quran_search.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/scripture_finder.dart';
import 'package:ayah_reels/widgets/surah_picker_sheet.dart';

/// The app's own directories, which the verse reader asks for on its
/// way to the surah cache.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getTemporaryPath() async => dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Finding the words, and taking a piece of them.
///
/// The piece picker is the unusual thing in this app and the reason
/// the sheet exists at all: almost nothing anybody quotes on a card is
/// the whole of a hadith with its chain, or the whole of a long verse.
/// Tap the first word, tap the last, and that is what travels.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const l = L10n.en;

  setUpAll(() async {
    for (final e in {
      'HafsUthmani': 'assets/fonts/UthmanicHafs.ttf',
      'NotoNaskhArabic': 'assets/fonts/NotoNaskhArabic.ttf',
      'Inter': 'assets/fonts/Inter.ttf',
    }.entries) {
      final loader = FontLoader(e.key)..addFont(rootBundle.load(e.value));
      await loader.load();
    }
    await HadithLibrary.loadFrom(
      meta: File('assets/hadith/meta.json').readAsStringSync(),
      arabic: File('assets/hadith/ar.json.gz').readAsBytesSync(),
      translation: File('assets/hadith/en.json.gz').readAsBytesSync(),
    );
  });

  List<ScriptureQuote>? picked;

  /// Pumps until the sheet has stopped moving.
  ///
  /// Never [WidgetTester.pumpAndSettle] while this sheet is up: its
  /// search field takes focus on the way in and a focused field blinks
  /// its caret for good, so "settled" never comes.
  Future<void> settle(WidgetTester t) async {
    // A search is a debounce, then a match, then a rebuild — three
    // turns of the loop, not one.
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  tearDown(() => QuranSearch.clientForTest = null);

  setUp(() {
    // The finder now reopens on the verse it was last left on, so a
    // test that does not clear that inherits where the one before it
    // was reading.
    SettingsService.state.value = AppSettings.defaults;
    final tmp = Directory.systemTemp.createTempSync('scripture_finder_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    addTearDown(() {
      try {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* Windows holds the handle; the runner cleans up */}
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
    });
  });

  Future<void> open(WidgetTester t, {bool hadith = false}) async {
    // Loaded inside the test rather than in setUpAll: the index is
    // read once and kept, and a search awaits it — from the test's own
    // zone, which is the only one whose microtasks a pump drains.
    QuranSearch.resetForTest();
    QuranSearch.loadFrom(File('assets/quran_search.json').readAsStringSync());
    picked = null;
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      // A plain theme: [AppTheme.dark] resolves its faces over the
      // network, which the runner does not have.
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
            primary: AppColors.gold, surface: AppColors.surface),
      ),
      localizationsDelegates: const [L10n.delegate],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showScriptureFinder(context, hadith: hadith);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await settle(t);
  }

  testWidgets('the Quran side opens on a surah and its verses, and a tap '
      'puts one on a card', (t) async {
    await open(t);
    // Al-Fatiha is bundled whole — Arabic and every edition — so the
    // finder has something to show before it has a connection.
    expect(find.text(l.localizedSurahName('Al-Fatiha')), findsOneWidget);
    expect(find.text('1:1'), findsOneWidget);
    expect(find.text('1:2'), findsOneWidget);
    // The verse is shown as it reads, with the line under it.
    expect(find.textContaining('All praise is due to Allah'), findsWidgets);

    await t.tap(find.text('1:2'));
    await settle(t);
    await t.tap(find.text(l.findAdd));
    await settle(t);

    expect(picked, hasLength(1));
    expect(picked!.first.quran, isTrue);
    expect(picked!.first.source.surah, 1);
    expect(picked!.first.source.startAyah, 2);
    expect(picked!.first.reference, contains('1:2'));
    // The translation comes with it, because it came with the verse.
    expect(picked!.first.translation, isNotEmpty);
  });

  testWidgets('the surah is changed through the reels\' own picker',
      (t) async {
    await open(t);
    await t.tap(find.text(l.findChooseSurah));
    await settle(t);
    // The picker searches names, numbers and references in either
    // script — it is the one the verse step has always used.
    expect(find.byType(SurahPickerSheet), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'kahf');
    await settle(t);
    await t.tap(find.byType(ListTile).first);
    for (var i = 0; i < 4; i++) {
      await settle(t);
    }

    // No network in the runner, so the translation cannot be fetched —
    // and the Arabic is still there, off the bundled index, with a
    // line saying why the English is not.
    expect(find.text(l.localizedSurahName('Al-Kahf')), findsOneWidget);
    expect(find.text(l.findArabicOnly), findsOneWidget);
    expect(find.text('18:1'), findsOneWidget);
  });

  testWidgets('a piece of a verse is what the card gets, and the '
      'translation stays behind', (t) async {
    final semantics = t.ensureSemantics();
    await open(t);
    await t.tap(find.text('1:2'));
    await settle(t);

    await t.tap(find.text(l.findPart));
    await settle(t);
    // Every word is its own target — a word inside a paragraph is a
    // hit box six pixels tall, and this is a gesture people are meant
    // to get right the first time.
    final words = find.bySemanticsLabel(RegExp('^${l.a11yCardWord}: '));
    expect(words.evaluate().length, greaterThan(3));
    await t.tap(words.first);
    await settle(t);
    await t.tap(words.at(2));
    await settle(t);
    await t.tap(find.text(l.findAdd));
    await settle(t);

    expect(picked, hasLength(1));
    final quote = picked!.first;
    expect(quote.text.split(RegExp(r'\s+')), hasLength(3));
    // A run of three words has no matching run in the English, and
    // cutting one to fit would be inventing it.
    expect(quote.translation, isEmpty);
    expect(quote.reference, contains('1:2'));
    semantics.dispose();
  });

  testWidgets('the reader reopens on the verse it was last left on',
      (t) async {
    // Somebody working through a surah comes back to it. Opening on
    // Al-Fatiha 1 every time makes them find their place by hand.
    SettingsService.state.value =
        AppSettings.defaults.copyWith(lastSurah: 1, lastAyah: 5);
    await open(t);
    await settle(t);
    expect(find.text(l.localizedSurahName('Al-Fatiha')), findsOneWidget);
    // And scrolled to it, not merely opened on the surah: the verse
    // asked for is on screen and the ones above it are not.
    expect(find.text('1:5'), findsOneWidget);
    expect(find.text('1:1'), findsNothing,
        reason: 'the list never left the top');

    // Choosing another verse is what gets remembered next.
    await t.tap(find.text('1:7'));
    await settle(t);
    expect(SettingsService.state.value.lastSurah, 1);
    expect(SettingsService.state.value.lastAyah, 7);
  });

  testWidgets('the Quran side searches the verse in Arabic and the '
      'translation in English', (t) async {
    await open(t);
    // The box is on this half at all, which it was not: the words
    // went into the surah picker behind "Change", and somebody
    // looking for "mercy" in the Cards tab had nothing to type into.
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(find.text(l.findVerseHint), findsOneWidget);

    // Arabic goes to the bundled index, offline, with no network at
    // all — the whole Quran is in the app.
    QuranSearch.clientForTest =
        MockClient((_) async => http.Response('{}', 500));
    await t.enterText(field, 'الرحمن الرحيم');
    await settle(t);
    expect(find.textContaining('1:3'), findsWidgets,
        reason: 'the Arabic index did not answer');

    // English goes to the translation, which is a request.
    QuranSearch.clientForTest = MockClient((req) async {
      expect(req.url.queryParameters['q'], 'mercy');
      return http.Response(
          jsonEncode({
            'search': {
              'results': [
                {
                  'verse_key': '1:3',
                  'translations': [
                    {'text': 'The Entirely <em>Merciful</em>, the '
                        'Especially <em>Merciful</em>,'},
                  ],
                },
              ],
            },
          }),
          200);
    });
    await t.enterText(field, 'mercy');
    await settle(t);
    await settle(t);
    expect(find.textContaining('The Entirely Merciful'), findsWidgets,
        reason: 'the translation search did not answer');

    // And a hit is a card: tapping it opens the verse with its real
    // translation, not the snippet that matched.
    await t.tap(find.textContaining('The Entirely Merciful').first);
    await settle(t);
    await t.tap(find.text(l.findAdd));
    await settle(t);
    expect(picked, hasLength(1));
    expect(picked!.first.source.surah, 1);
    expect(picked!.first.source.startAyah, 3);
    expect(picked!.first.translation, isNotEmpty);
  });

  testWidgets('the hadith side opens on its topics and finds a saying',
      (t) async {
    await open(t, hadith: true);
    expect(find.text(l.hadithTopicName('mercy')), findsOneWidget);
    // The edition is named: a translation nobody is named for is one
    // nobody can weigh.
    expect(find.textContaining(HadithLibrary.credit), findsOneWidget);

    await t.enterText(find.byType(TextField), 'loves for his brother');
    await settle(t);
    await t.tap(find.textContaining("An-Nawawi's Forty").first);
    await settle(t);
    // A hadith opens on the saying rather than on the chain in front
    // of it, and the whole is one tap away.
    expect(find.text(l.findWhole), findsWidgets);
    await t.tap(find.text(l.findAdd));
    await settle(t);

    expect(picked, hasLength(1));
    expect(picked!.first.source.isHadith, isTrue);
    expect(picked!.first.reference, contains('13'));
    expect(picked!.first.quran, isFalse,
        reason: 'a hadith must never be set in a face cut for the Quran');
    // This one is set down without quotation marks around the saying,
    // so what is offered is the whole narration — and the whole
    // narration is what a card of an-Nawawi's thirteenth should carry.
    // Where an edition does mark the saying off, the finder opens on
    // it; see the hadith library's own tests.
    expect(picked!.first.text, contains('يُؤْمِنُ'));
  });

  testWidgets('a hadith search that finds nothing says so', (t) async {
    await open(t, hadith: true);
    await t.enterText(find.byType(TextField), 'z');
    await settle(t);
    expect(find.text(l.findTypeMore), findsOneWidget);

    await t.enterText(find.byType(TextField), 'qqqqqqqq');
    await settle(t);
    expect(find.text(l.findNothing), findsOneWidget);
  });
}
