import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/card_compose.dart';
import 'package:ayah_reels/data/card_deck.dart';
import 'package:ayah_reels/data/card_library.dart';
import 'package:ayah_reels/data/card_style.dart';
import 'package:ayah_reels/data/quran_verses.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/cards_screen.dart';
import 'package:ayah_reels/screens/card_studio_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/card_canvas.dart';

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

/// The tab: four ways in, and the shelf.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  const l = L10n.en;

  setUpAll(() async {
    for (final e in {
      'HafsUthmani': 'assets/fonts/UthmanicHafs.ttf',
      'NotoNaskhArabic': 'assets/fonts/NotoNaskhArabic.ttf',
      'CormorantGaramond': 'assets/fonts/CormorantGaramond.ttf',
      'Inter': 'assets/fonts/Inter.ttf',
    }.entries) {
      final loader = FontLoader(e.key)..addFont(rootBundle.load(e.value));
      await loader.load();
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cards_screen_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SettingsService.state.value = AppSettings.defaults;
  });

  tearDown(() {
    try {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* Windows holds the handle; the runner cleans up */}
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
  });

  Future<void> open(WidgetTester t) async {
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
      home: const CardsScreen(),
    ));
    await t.pump();
    await t.pump();
  }

  /// Lets the shelf finish reading itself off disk.
  ///
  /// Two things have to happen in turn for a file read to land under
  /// the test binding: the real event loop has to deliver the answer
  /// ([WidgetTester.runAsync]), and the fake one has to run the
  /// callback waiting on it (a pump).
  Future<void> shelfLoaded(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
  }

  testWidgets('four ways in, and the shelf says what it holds', (t) async {
    expect(SettingsService.state.value.cardsSeen, isFalse);
    await open(t);
    expect(find.text(l.cardsFromVerse), findsOneWidget);
    expect(find.text(l.cardsFromHadith), findsOneWidget);
    expect(find.text(l.cardsTodaysVerse), findsOneWidget);
    expect(find.text(l.cardsBlank), findsOneWidget);
    expect(find.text(l.cardsEmptyTitle), findsOneWidget);
    // A tab that arrives in an update carries a dot until somebody
    // looks at it; looking is what puts it out.
    expect(SettingsService.state.value.cardsSeen, isTrue);
  });

  testWidgets("today's verse is one tap, and needs nothing from the "
      'network', (t) async {
    await open(t);
    await t.tap(find.text(l.cardsTodaysVerse));
    await t.pumpAndSettle();
    expect(find.byType(CardStudioScreen), findsOneWidget);
    final canvas = t.widget<CardCanvas>(find.byType(CardCanvas).first);
    final verse = QuranVerses.at(DateTime.now());
    expect(canvas.slide.blocks.first.text, verse.arabic);
    expect(canvas.slide.source.isVerse, isTrue);
    expect(canvas.slide.source.surah, verse.surah);
    // The reference travels with it, so a stranger can look it up.
    expect(canvas.slide.blocks.last.text, contains('${verse.surah}:'));
  });

  testWidgets('a blank card opens straight into the words', (t) async {
    await open(t);
    await t.tap(find.text(l.cardsBlank));
    await t.pumpAndSettle();
    expect(find.byType(CardStudioScreen), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the tab asks where the words come from and nothing '
      'else', (t) async {
    await open(t);
    // The look is not a question this tab asks any more. It used to
    // offer the six templates as specimen cards under the four ways
    // in — a row of frames chosen before there were any words to see
    // them under, and every one of them is still reachable in the
    // composer, on the card itself, where the change is visible.
    for (final template in CardTemplate.values) {
      expect(find.text(l.cardTemplateName(template.name)), findsNothing,
          reason: '${template.name} is still offered on the tab');
    }
    // Nor the shape: a card is re-cut in the composer.
    expect(find.text(l.cardFormatName('story')), findsNothing);
  });

  testWidgets('the look is remembered between cards', (t) async {
    // Whatever the composer last left behind is what the next card
    // opens on — which is the whole of what the setting is for now
    // that the tab no longer asks.
    SettingsService.state.value =
        AppSettings.defaults.copyWith(cardTemplate: 'page');
    await open(t);
    await t.tap(find.text(l.cardsTodaysVerse));
    await t.pumpAndSettle();
    final canvas = t.widget<CardCanvas>(find.byType(CardCanvas).first);
    expect(canvas.slide.background.paper, CardTemplate.page.paper);
    expect(canvas.slide.frame, CardTemplate.page.frame);
  });

  testWidgets('a saved deck appears on the shelf, named for what it '
      'quotes', (t) async {
    final deck = CardCompose.deck(
      CardCompose.quote(
        id: 'card',
        text: 'وَقُل رَّبِّ زِدْنِى عِلْمًا',
        reference: 'Ta-Ha · 20:114',
        format: CardFormat.portrait,
        source: const CardSource.verse(20, 114, 114),
        quran: true,
      ),
    );
    await t.runAsync(() => CardLibrary.save(deck));
    await open(t);
    await shelfLoaded(t);
    expect(find.text(l.cardsEmptyTitle), findsNothing);
    expect(find.textContaining('20:114'), findsOneWidget);
  });

  test('a card stands on the same scenery library the reels do', () async {
    // One catalog, one set of files, one download cache: a scenery
    // added to catalog.json appears in both pickers on the same build
    // because neither side keeps a list of its own.
    await SceneCatalog.load();
    expect(SceneCatalog.all, isNotEmpty);
    expect(SceneCatalog.all.where((s) => !s.wide), isNotEmpty);
    // Cards crop rather than letterbox, so the wide sceneries are
    // usable too — and every one of them carries the poster a picker
    // draws before anything has been downloaded.
    expect(SceneCatalog.all.where((s) => s.wide), isNotEmpty);
    for (final scene in SceneCatalog.all) {
      expect(scene.thumbAsset, anyOf(endsWith('.jpg'), endsWith('.webp')));
      // Carried in the app, or served by name and kept once seen —
      // never neither, and never both.
      expect(File(scene.thumbAsset).existsSync(), scene.posterInApp,
          reason: '${scene.id}: poster in the app is ${scene.posterInApp}');
    }
    // The bundled sceneries keep theirs: a phone that has never been
    // online still draws every scenery it can use.
    for (final scene in SceneCatalog.all.where((s) => s.bundled)) {
      expect(scene.posterInApp, isTrue, reason: scene.id);
    }
    // And each tab opens on posters it carries: its first screenful.
    for (final tab in SceneCatalog.tabs) {
      final first = SceneCatalog.leadersFirst(tab, SceneCatalog.inTab(tab))
          .take(12);
      expect(first.every((s) => s.posterInApp), isTrue, reason: tab);
    }
  });

  test('a template that names a scenery family can actually open on one',
      () async {
    // [CardCompose.sceneFor] only ever picks a *bundled* scenery, so a
    // template is not allowed to name a family whose members all live
    // on the server: the card would open on bare paper and the
    // template whose whole idea is a photograph would have none. `sky`
    // was exactly that — sixteen sceneries in the catalog, none of
    // them shipped.
    await SceneCatalog.load();
    for (final template in CardTemplate.values) {
      if (template.sceneFamily.isEmpty) continue;
      final id = CardCompose.sceneFor(template.sceneFamily);
      expect(id, isNotEmpty,
          reason: '${template.name} names "${template.sceneFamily}", which '
              'has no bundled upright scenery');
      final scene = SceneCatalog.byId(id)!;
      expect(scene.bundled, isTrue);
      expect(scene.wide, isFalse);
      expect(scene.isVideo, isFalse);
    }
  });

  test('a new card opens on a scenery drawn for it, never the dark, and '
      'never one it would have to wait for', () async {
    await SceneCatalog.load();
    final seen = <String>{};
    for (var i = 0; i < 60; i++) {
      final ground = groundFor(CardTemplate.classic);
      expect(ground.hasPicture, isTrue);
      final scene = SceneCatalog.byId(ground.sceneId)!;
      // Nothing here has been fetched, so only what ships can be drawn.
      expect(scene.bundled, isTrue);
      expect(scene.isVideo, isFalse);
      expect(scene.wide, isFalse);
      seen.add(scene.id);
    }
    expect(seen.length, greaterThan(4), reason: 'drawn, not fixed');
  });

  test('a card made on a look is matched back to it, so the next one '
      'opens there', () async {
    // What the composer remembers when a card is exported. Nothing had
    // written the setting since the tab's row of specimens came off,
    // which left every new card on the default look whatever the last
    // one was made in.
    for (final template in CardTemplate.values) {
      final slide = CardCompose.quote(
        id: 'card',
        text: 'وَقُل رَّبِّ زِدْنِى عِلْمًا',
        reference: 'Ta-Ha · 20:114',
        format: CardFormat.portrait,
        template: template,
        background: groundFor(template),
        quran: true,
      );
      expect(CardTemplate.matching(slide), template,
          reason: '${template.name} was not matched back to itself');
    }
    // Paper and frame together, so every one of the six is told apart
    // from every other.
    final grounds = {
      for (final t in CardTemplate.values) (t.paper, t.frame)
    };
    expect(grounds, hasLength(CardTemplate.values.length));
  });
}
