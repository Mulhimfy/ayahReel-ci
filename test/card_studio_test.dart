import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart'
    show FontLoader, MethodCall, MethodChannel, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/card_compose.dart';
import 'package:ayah_reels/data/card_deck.dart';
import 'package:ayah_reels/data/card_library.dart';
import 'package:ayah_reels/data/card_style.dart';
import 'package:ayah_reels/data/dedication.dart';
import 'package:ayah_reels/data/instagram_share.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/card_studio_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart' show AppColors;
import 'package:ayah_reels/widgets/card_canvas.dart';
import 'package:ayah_reels/widgets/card_dock.dart';

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

/// The composer, driven the way a thumb drives it.
///
/// Everything in here is a gesture or a tap on a control, and every
/// assertion is about the card that came out — because a composer is
/// the one screen in an app where "it looks fine" and "it works" are
/// the same claim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  const l = L10n.en;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    const files = {
      'HafsUthmani': ['assets/fonts/UthmanicHafs.ttf'],
      'NotoNaskhArabic': ['assets/fonts/NotoNaskhArabic.ttf'],
      'CormorantGaramond': ['assets/fonts/CormorantGaramond.ttf'],
      'Inter': ['assets/fonts/Inter.ttf'],
    };
    for (final entry in files.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('card_studio_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    try {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* Windows holds the handle; the runner cleans up */}
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
  });

  CardDeck deck({CardFormat format = CardFormat.portrait, int cards = 1}) =>
      CardDeck(
        id: 'deck',
        format: format,
        slides: [
          for (var i = 0; i < cards; i++)
            CardCompose.quote(
              id: 'card$i',
              text: 'وَقُل رَّبِّ زِدْنِى عِلْمًا',
              translation: 'And say, "My Lord, increase me in knowledge."',
              reference: 'Ta-Ha · 20:114',
              format: format,
              quran: true,
            ),
        ],
        createdAt: DateTime(2026, 3, 12),
        updatedAt: DateTime(2026, 3, 12),
      );

  Future<void> open(
    WidgetTester t,
    CardDeck d, {
    Size size = const Size(1170, 2532), // a phone
    Locale? locale,
    bool drawn = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
        Locale('ur'),
        Locale('id'),
        Locale('de'),
      ],
      // Not [AppTheme.dark]: that theme resolves its faces through
      // google_fonts, which reaches for the network the moment it is
      // built — there is none here, and the report it files for each
      // face lands between this test and its assertion. Nothing the
      // composer draws takes its colour or its type from the theme
      // (the card's faces are the bundled ones, and the chrome reads
      // AppColors directly), so a plain dark theme exercises exactly
      // the same widgets.
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.gold,
          surface: AppColors.surface,
        ),
      ),
      // The same four the app installs — without the Material ones a
      // locale other than English is only a warning here, but it is a
      // warning that lands as an exception in the middle of a test.
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: CardStudioScreen(deck: d, drawnScenery: drawn),
    ));
    await t.pump();
  }

  /// The card on the stage — the first of the canvases on screen; the
  /// filmstrip's thumbnails come after it.
  CardCanvas stage(WidgetTester t) =>
      t.widget<CardCanvas>(find.byType(CardCanvas).first);

  /// The deck the composer is holding right now. Read off the dock,
  /// which is handed the whole of it — nothing is on disk until the
  /// card has actually been made.
  CardDeck live(WidgetTester t) =>
      t.widget<CardDock>(find.byType(CardDock)).deck;

  /// Taps a control in the dock, dragging its row into view first when
  /// the row is one that scrolls. The pickers hold up to eleven
  /// choices and a phone shows five of them.
  Future<void> tapControl(WidgetTester t, String label) async {
    for (var i = 0; i < 8 && find.text(label).evaluate().isEmpty; i++) {
      // The panel's picker is the first list inside the dock — not the
      // first on screen, which is the filmstrip above it.
      await t.drag(
        find
            .descendant(
                of: find.byType(CardDock), matching: find.byType(ListView))
            .first,
        const Offset(-160, 0),
      );
      await t.pumpAndSettle();
    }
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  /// The library, once whatever is being written to it has landed.
  ///
  /// The composer writes without being asked, so a test has to wait
  /// for a write it never started. Two things have to happen in turn
  /// for one to finish under the test binding: the real event loop has
  /// to deliver the file system's answer ([WidgetTester.runAsync]),
  /// and the fake one has to run the callback waiting on it (a pump).
  /// The library, once anything pending has had every chance to land.
  Future<List<CardDeck>> settled(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    return await t.runAsync(CardLibrary.load) ?? const [];
  }

  Future<List<CardDeck>> savedDecks(WidgetTester t,
      {bool Function(CardDeck)? until}) async {
    var last = const <CardDeck>[];
    for (var i = 0; i < 40; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
      last = await t.runAsync(CardLibrary.load) ?? const <CardDeck>[];
      // The composer saves as it goes, so "there is a deck on disk" is
      // true long before the edit under test has landed: wait for the
      // deck the test is actually looking for.
      if (last.isNotEmpty && (until == null || until(last.first))) {
        return last;
      }
    }
    return last;
  }

  /// Where a block sits on screen right now.
  Rect blockRect(WidgetTester t, CardTextBlock block) {
    final rect = t.getRect(find.byType(CardCanvas).first);
    final w = rect.width;
    final h = rect.height;
    return Rect.fromCenter(
      center: Offset(rect.left + block.x * w, rect.top + block.y * h),
      width: block.width * w,
      height: 24,
    );
  }

  testWidgets('a tap takes a block, a tap on nothing lets it go, and a '
      'tap on what is taken opens its words', (t) async {
    await open(t, deck());
    expect(stage(t).selectedId, isNull);
    final verse = stage(t).slide.blocks.first;
    await t.tapAt(blockRect(t, verse).center);
    await t.pumpAndSettle();
    expect(stage(t).selectedId, verse.id);

    // Again, on the same block: the words open for editing.
    await t.tapAt(blockRect(t, verse).center);
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(verse.text), findsWidgets);
    await t.tap(find.text(l.doneLabel).last);
    await t.pumpAndSettle();

    // The very top of the card is above every block.
    final card = t.getRect(find.byType(CardCanvas).first);
    await t.tapAt(Offset(card.center.dx, card.top + 6));
    await t.pumpAndSettle();
    expect(stage(t).selectedId, isNull);
  });

  testWidgets('dragging moves the block, and the whole drag is one undo '
      'step rather than sixty', (t) async {
    await open(t, deck());
    final before = stage(t).slide.blocks.first;
    await t.dragFrom(blockRect(t, before).center, const Offset(0, 60));
    await t.pumpAndSettle();
    final after = stage(t).slide.block(before.id)!;
    expect(after.y, greaterThan(before.y));
    expect(after.x, closeTo(before.x, 0.002), reason: 'it drifted sideways');
    // One undo, and the card is back where it started.
    final undo = find.descendant(
      of: find.byType(IconButton),
      matching: find.byIcon(Icons.undo_rounded),
    );
    await t.tap(undo);
    await t.pump();
    expect(stage(t).slide.block(before.id)!.y, closeTo(before.y, 1e-9));
  });

  testWidgets('a slider drag is one undo step, whatever it passes '
      'through', (t) async {
    await open(t, deck());
    await t.tap(find.text(l.cardLookTool));
    await t.pumpAndSettle();
    final before = stage(t).slide.effects;
    // Warmth, vibrance, vignette, grain: the first of the four.
    final slider = find.byType(Slider).first;
    await t.drag(slider, const Offset(60, 0));
    await t.pumpAndSettle();
    final after = stage(t).slide.effects;
    expect(after, isNot(before), reason: 'the slider changed nothing');

    await t.tap(find.descendant(
      of: find.byType(IconButton),
      matching: find.byIcon(Icons.undo_rounded),
    ));
    await t.pumpAndSettle();
    expect(stage(t).slide.effects, before,
        reason: 'one drag left more than one thing to undo');
  });

  testWidgets('the shape can be changed at any point and nothing falls '
      'off the card', (t) async {
    await open(t, deck());
    await t.tap(find.text(l.cardShape));
    await t.pumpAndSettle();
    for (final format in [CardFormat.square, CardFormat.story]) {
      await t.tap(find.text(l.cardFormatName(format.name)));
      await t.pumpAndSettle();
      final canvas = stage(t);
      expect(canvas.format, format);
      final cardH = CardFormat.exportWidth / format.aspect;
      for (final b in canvas.slide.blocks) {
        final h = CardCompose.heightOf(b, format);
        expect(b.y * cardH - h / 2, greaterThan(-2),
            reason: '${format.name}: a block ran off the top');
        expect(b.y * cardH + h / 2, lessThan(cardH + 2),
            reason: '${format.name}: a block ran off the bottom');
      }
    }
  });

  testWidgets('a card can be duplicated, and a carousel stops at ten',
      (t) async {
    await open(t, deck());
    await t.tap(find.text(l.cardShape));
    await t.pumpAndSettle();
    // Eleven taps on a control that stops offering itself at ten.
    for (var i = 0; i < 11; i++) {
      final chip = find.text(l.cardDuplicateSlide);
      if (chip.evaluate().isEmpty) break;
      await t.tap(chip, warnIfMissed: false);
      await t.pumpAndSettle();
    }
    final made = live(t);
    expect(made.slides, hasLength(CardDeck.maxSlides));
    // Every card of the deck is its own: editing one must not reach
    // into the one it was copied from.
    final ids = {for (final s in made.slides) s.id};
    expect(ids, hasLength(CardDeck.maxSlides));
    final blockIds = [
      for (final s in made.slides)
        for (final b in s.blocks) b.id
    ];
    expect(blockIds.toSet(), hasLength(blockIds.length));
  });

  testWidgets('a passage becomes a carousel, each card set to its own '
      'piece', (t) async {
    await open(t, deck());
    // Something long enough to be worth breaking up.
    await t.tap(find.text(l.cardText));
    await t.pumpAndSettle();
    await t.tap(find.text(l.cardAddText));
    await t.pumpAndSettle();
    await t.enterText(
      find.byType(TextField),
      List.filled(
        6,
        'Allah does not burden a soul beyond what it can bear. '
            'And He is the Most Merciful of the merciful.',
      ).join(' '),
    );
    await t.tap(find.text(l.doneLabel).last);
    await t.pumpAndSettle();

    await t.tap(find.text(l.cardShape));
    await t.pumpAndSettle();
    await tapControl(t, l.cardSplit);
    await t.pumpAndSettle();

    final slides = live(t).slides;
    expect(slides.length, greaterThan(1));
    // Nothing is lost and nothing is invented.
    final pieces = [
      for (final s in slides)
        s.blocks.map((b) => b.text).firstWhere((t) => t.contains('Allah'),
            orElse: () => ''),
    ]..removeWhere((p) => p.isEmpty);
    expect(pieces.length, slides.length);
    expect(pieces.join(' ').split(RegExp(r'\s+')).length,
        6 * 20);
    // The reference stayed on the first card rather than being
    // repeated across the deck.
    expect(slides.first.blocks.length, greaterThan(1));
    expect(slides.last.blocks, hasLength(1));
  });

  testWidgets('a deck can be made for someone, and every card of it '
      'says so', (t) async {
    await open(t, deck(cards: 2));
    await t.tap(find.text(l.cardShape));
    await t.pumpAndSettle();
    await tapControl(t, l.dedicateRow);

    await t.enterText(find.byType(TextField), 'Maryam');
    await t.pump();
    await t.tap(find.text(l.dedicateSadaqah));
    await t.pump();
    await t.tap(find.text(l.save));
    await t.pumpAndSettle();

    final line = l.dedicationLine(DedicationKind.sadaqah, 'Maryam');
    // The card carries it, and so does every thumbnail of the deck —
    // one dedication for the whole deck, because a carousel is one
    // gift.
    for (final canvas in t.widgetList<CardCanvas>(find.byType(CardCanvas))) {
      expect(canvas.dedication, line);
    }
    // And the control now says what the card says.
    expect(find.text(line), findsWidgets);

    expect(live(t).dedication.name, 'Maryam');
    expect(live(t).dedication.kind, DedicationKind.sadaqah);
  });

  testWidgets('the top bar holds together on a small screen, in every '
      'language', (t) async {
    // Four glyphs and the bar's padding take about 178dp before the
    // story pill or the gold Share is drawn, which leaves 182 on a
    // 360dp screen for a pill that wants 88 and a button whose label
    // is a translated word. "Bagikan" and "Teilen" overrun that on
    // their own, and in release an overflowing Row clips the Share
    // button rather than painting the debug stripes — so nothing on
    // screen says the button has gone.
    // The story pill is a phone-only control and `dart:io` is not
    // something a widget test can move, so without this the bar under
    // test is not the bar that ships.
    InstagramShare.debugSupported = true;
    addTearDown(() => InstagramShare.debugSupported = null);
    for (final code in ['en', 'ar', 'ur', 'id', 'de']) {
      await open(t, deck(),
          size: const Size(1080, 2400), // 360dp across
          locale: Locale(code));
      await t.pump();
      expect(t.takeException(), isNull, reason: '$code overflowed the bar');
      // Both buttons are still buttons, not slivers.
      expect(t.getSize(find.byType(FilledButton)).width, greaterThan(40),
          reason: '$code squeezed the Share button to nothing');
      expect(
          t.getSize(find.text(L10n(AppLang.fromCode(code)).shareToStory)).width,
          greaterThan(10),
          reason: '$code squeezed the story pill to nothing');
    }

    // And 40dp narrower than the narrowest phone, which stands in for
    // the bar at its widest: while a card is exporting a spinner takes
    // 28dp that none of these widths were measured for.
    for (final code in ['id', 'de']) {
      await open(t, deck(),
          size: const Size(960, 2400), // 320dp across
          locale: Locale(code));
      await t.pump();
      expect(t.takeException(), isNull,
          reason: '$code overflowed a 320dp bar');
    }
  });

  testWidgets('the scenery line is a door big enough to hit', (t) async {
    // An 11px glyph and an 11.5px line come to about 16dp of text, and
    // this one takes the tap itself — it is the composer's only sign
    // that the scenery library exists. Below 48dp it is a target a
    // thumb misses.
    await open(t, deck());
    final door = find
        .ancestor(
          of: find.text(l.cardSceneryNote),
          matching: find.byType(GestureDetector),
        )
        .first;
    expect(t.getSize(door).height, greaterThanOrEqualTo(48));
  });

  testWidgets('a card standing on paper is told what would make it '
      'better', (t) async {
    // One gold line, and only while it is true: the scenery library is
    // what a card is most transformed by, and a composer that opens on
    // paper gives no sign it exists.
    await open(t, deck());
    expect(find.text(l.cardSceneryNote), findsOneWidget);

    // It is the door as well as the advice — the same sheet the
    // Scenery chip opens. Not settled: that sheet reads the catalog
    // off the bundle and spins while it does, and a spinner never
    // settles under the fake clock.
    await t.tap(find.text(l.cardSceneryNote));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(l.cardScenery), findsWidgets);
    Navigator.of(t.element(find.text(l.cardScenery).first)).pop();
    await t.pump(const Duration(milliseconds: 400));

  });

  testWidgets('and says nothing once the card is on a scenery', (t) async {
    // A card that has one is not nagged about them.
    final plain = deck();
    await open(
      t,
      plain.copyWith(slides: [
        for (final slide in plain.slides)
          slide.copyWith(
            background: slide.background.copyWith(sceneId: 'sky_pixabay_01'),
          ),
      ]),
    );
    expect(find.text(l.cardSceneryNote), findsNothing);
  });

  testWidgets('a new card on a scenery drawn for it still offers the '
      'library, as an invitation to pick one', (t) async {
    // A new card opens on a photograph drawn at random rather than on
    // the dark; until the user picks a ground of their own, the gold
    // line says so — "Pick your own scenery".
    final plain = deck();
    await open(
      t,
      plain.copyWith(slides: [
        for (final slide in plain.slides)
          slide.copyWith(
            background: slide.background.copyWith(sceneId: 'sky_pixabay_01'),
          ),
      ]),
      drawn: true,
    );
    expect(find.text(l.cardSceneryNote), findsOneWidget);
    expect(l.cardSceneryNote, 'Pick your own scenery');
  });

  testWidgets('one card styled, and the whole deck follows', (t) async {
    await open(t, deck(cards: 3));
    // Give the first card a frame nobody else has.
    await t.tap(find.text(l.cardFrameTool));
    await t.pumpAndSettle();
    await tapControl(t, l.cardFrameName('khatam'));
    expect(stage(t).slide.frame, CardFrame.khatam);

    await t.tap(find.text(l.cardShape));
    await t.pumpAndSettle();
    await t.tap(find.text(l.cardApplyAll));
    await t.pumpAndSettle();
    for (final canvas in t.widgetList<CardCanvas>(find.byType(CardCanvas))) {
      expect(canvas.slide.frame, CardFrame.khatam);
    }
  });

  testWidgets('words can be added, edited and taken off again', (t) async {
    await open(t, deck());
    final before = stage(t).slide.blocks.length;
    await t.tap(find.text(l.cardText));
    await t.pumpAndSettle();
    await t.tap(find.text(l.cardAddText));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'A line of my own');
    await t.tap(find.text(l.doneLabel).last);
    await t.pumpAndSettle();
    expect(stage(t).slide.blocks, hasLength(before + 1));
    final added = stage(t).slide.blocks.last;
    expect(added.text, 'A line of my own');
    expect(added.rtl, isFalse, reason: 'an English line was set right to left');
    expect(stage(t).selectedId, added.id);

    // And off again.
    await t.tap(find.text(l.cardRemoveText));
    await t.pumpAndSettle();
    expect(stage(t).slide.blocks, hasLength(before));
  });

  testWidgets('nothing reaches the library until the card is made',
      (t) async {
    await open(t, deck());
    await t.tap(find.text(l.cardText));
    await t.pumpAndSettle();
    await t.tap(find.text(l.cardAddText));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'A draft nobody asked for');
    await t.tap(find.text(l.doneLabel).last);
    await t.pumpAndSettle();
    // A composer that saved as it went filled the shelf with
    // everything anybody had ever tapped at. The shelf holds what was
    // produced: saved to the gallery, or shared. Nothing else.
    await t.pump(const Duration(seconds: 3));
    await t.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await t.pumpAndSettle();
    expect(await settled(t), isEmpty);
  });

  testWidgets('saving to the gallery is what puts a card on the shelf',
      (t) async {
    // The platform's own gallery call, answered the way a phone that
    // accepted the write would answer it.
    const channel = MethodChannel('gal');
    final puts = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      puts.add(call);
      return call.method == 'hasAccess' || call.method == 'requestAccess'
          ? true
          : null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await open(t, deck());
    await t.tap(find.byIcon(Icons.download_rounded));
    // The export rasterizes, writes a PNG and hands it to the gallery
    // — all of it real work that only turns inside runAsync.
    for (var i = 0; i < 30; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump();
      if (puts.any((c) => c.method == 'putImage')) break;
    }
    expect(puts.map((c) => c.method), contains('putImage'));

    final saved = await savedDecks(t, until: (d) => d.slides.isNotEmpty);
    expect(saved, hasLength(1));
    expect(saved.single.slides.first.blocks.first.text,
        stage(t).slide.blocks.first.text);
  });
}
