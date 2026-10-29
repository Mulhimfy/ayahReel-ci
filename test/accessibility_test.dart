import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/reel_effects.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/render/reel_poster.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/screens/home_shell.dart';
import 'package:ayah_reels/screens/onboarding_screen.dart';
import 'package:ayah_reels/screens/reel_player_screen.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/screens/verses_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/coach_marks.dart';
import 'package:ayah_reels/widgets/day_verse_card.dart';
import 'package:ayah_reels/widgets/hashtags_sheet.dart';
import 'package:ayah_reels/widgets/widget_sheet.dart';

/// What a screen reader is told about the app.
///
/// Most of the app's controls are drawn rather than borrowed — a
/// painted tablet, a pill, a tile, a drag — and none of those says
/// anything to VoiceOver or TalkBack on its own. These pin that every
/// one of them now has a name, a role and a state, that the pages
/// read in the order they are laid out, and that the drags a reader
/// cannot perform have an adjustable value standing in for them.
///
/// Semantics are asserted on the live tree rather than on widget
/// properties, because what matters is what the two readers are
/// handed, after every merge and exclusion the framework applies.
void main() {
  const l = L10n.en;

  Widget host(Widget child, {bool scaffold = true}) => MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: scaffold ? Scaffold(body: child) : child,
      );

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  /// Every node in the tree, flattened in reading order.
  List<SemanticsData> nodes(WidgetTester t) {
    final out = <SemanticsData>[];
    void walk(SemanticsNode n) {
      out.add(n.getSemanticsData());
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    // The root owner has no semantics of its own; the view's does.
    walk(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
    return out;
  }

  /// The first node whose label starts with [prefix].
  SemanticsData node(WidgetTester t, String prefix) => nodes(t).firstWhere(
        (d) => d.label.startsWith(prefix),
        orElse: () => throw StateError('no node labelled "$prefix…"'),
      );

  /// The node whose label is exactly [label].
  SemanticsData exact(WidgetTester t, String label) => nodes(t).firstWhere(
        (d) => d.label == label,
        orElse: () => throw StateError('no node labelled "$label"'),
      );

  /// The first node whose label has [part] somewhere in it — for text
  /// the framework wraps in direction marks, such as Arabic.
  SemanticsData containing(WidgetTester t, String part) =>
      nodes(t).firstWhere(
        (d) => d.label.contains(part),
        orElse: () => throw StateError('no node containing "$part"'),
      );

  bool isButton(SemanticsData d) => d.flagsCollection.isButton;
  bool isHeader(SemanticsData d) => d.flagsCollection.isHeader;
  bool isSelected(SemanticsData d) =>
      d.flagsCollection.isSelected == Tristate.isTrue;
  bool isToggled(SemanticsData d) =>
      d.flagsCollection.isToggled == Tristate.isTrue;
  bool hasSelectedState(SemanticsData d) =>
      d.flagsCollection.isSelected != Tristate.none;
  bool hasToggledState(SemanticsData d) =>
      d.flagsCollection.isToggled != Tristate.none;
  bool isEnabled(SemanticsData d) =>
      d.flagsCollection.isEnabled == Tristate.isTrue;
  bool isLive(SemanticsData d) => d.flagsCollection.isLiveRegion;
  bool taps(SemanticsData d) => d.hasAction(SemanticsAction.tap);

  /// Where [prefix] falls in reading order.
  int order(WidgetTester t, String prefix) =>
      nodes(t).indexWhere((d) => d.label.startsWith(prefix));

  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  group('settings', () {
    testWidgets('every row is one control with a role and a state',
        (t) async {
      final h = t.ensureSemantics();
      SettingsService.state.value = AppSettings.defaults
          .copyWith(personalReminderOn: true, name: 'Yusuf');
      await t.pumpWidget(host(SettingsScreen(
        permissionCheck: () async => true,
        widgetCheck: () async => true,
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(isHeader(node(t, l.settingsTitle)), isTrue);

      // The two language rows are buttons that open a picker, each
      // read once, each saying what a double tap will do.
      final appLang = node(t, '${l.appLanguageTitle}\n');
      expect(isButton(appLang), isTrue);
      expect(taps(appLang), isTrue);
      expect(appLang.hint, l.a11ySetsLanguage);
      final verseTr = node(t, '${l.verseTranslationTitle}\n');
      expect(isButton(verseTr), isTrue);
      expect(verseTr.hint, l.a11ySetsTranslation);

      // A row that opens the time picker is a button carrying the
      // time, and its switch stays a control of its own, named.
      final reminder = node(t, '${l.myReminderTitle}\n');
      expect(isButton(reminder), isTrue);
      expect(reminder.label, contains('8:00 PM'));
      expect(reminder.hint, l.a11yChangesReminderTime);
      final reminderSwitch = nodes(t).firstWhere(
          (d) => d.label == l.myReminderTitle && hasToggledState(d));
      expect(isToggled(reminderSwitch), isTrue);

      // A row that opens something is a button, with its value after
      // its name, and "new" while its dot is lit.
      expect(node(t, l.yourNameTitle).label, '${l.yourNameTitle}\nYusuf');
      expect(isButton(node(t, l.yourNameTitle)), isTrue);
      expect(node(t, l.rateAppTitle).label, '${l.rateAppTitle}\n${l.a11yNew}');
      expect(node(t, l.widgetRowTitle).label,
          '${l.widgetRowTitle}\n${l.a11yWidgetPlaced}');
      h.dispose();
    });
  });

  group('home', () {
    testWidgets('the verse card is one button carrying the whole verse',
        (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(host(DayVerseCard(
        date: DateTime(2026, 3, 13, 9), // a Friday
        isInstalled: () async => false,
      )));
      await t.pump(const Duration(milliseconds: 600));
      final card = node(t, l.jumuahToday);
      expect(isButton(card), isTrue);
      expect(taps(card), isTrue);
      expect(card.label, contains('${l.jumuahCardBody}, Al-Ahzab · 56'));
      expect(card.label, contains('confers blessing upon the Prophet'));
      expect(card.hint, l.a11yMakesVerseReel);
      // The inner "Make the reel" door does the same as the card, so
      // it is folded in rather than read as a second button.
      expect(nodes(t).where(isButton), hasLength(1));
      h.dispose();
    });

    testWidgets('the home tab reads top to bottom, and the bar says which '
        'tab is open', (t) async {
      final h = t.ensureSemantics();
      phone(t);
      await t.pumpWidget(host(const HomeShell(), scaffold: false));
      await t.pump(const Duration(milliseconds: 900));
      // The test font is wider than Inter, so the nudge's button row
      // overflows a 390px phone here and nowhere else.
      t.takeException();

      final greeting = order(t, 'السَّلَامُ عَلَيْكُمْ');
      final headline = order(t, l.beTheReason);
      final create = order(t, l.createButton);
      // Whichever verse card is showing. On a Friday the home screen
      // carries the Jumu'ah card instead of the ordinary one — the
      // test above this pins that card in its own right — and looking
      // only for the ordinary heading made this read as a broken
      // reading order one day in seven.
      final ordinary = order(t, l.verseFromTheQuran);
      final verse = ordinary >= 0
          ? ordinary
          : nodes(t).indexWhere((d) => d.label.contains(l.jumuahCardBody));
      expect(verse, isNonNegative, reason: 'no verse card on the home tab');
      expect(greeting, lessThan(headline));
      expect(headline, lessThan(create));
      expect(create, lessThan(verse));
      expect(isHeader(node(t, l.beTheReason)), isTrue);

      // The bar: four buttons, the open one selected, the dot said
      // after the name.
      final home = node(t, l.navHome);
      expect(isButton(home), isTrue);
      expect(isSelected(home), isTrue);
      final cards = node(t, l.navCards);
      expect(isButton(cards), isTrue);
      expect(isSelected(cards), isFalse);
      expect(taps(cards), isTrue);
      final settings = node(t, l.navSettings);
      expect(isSelected(settings), isFalse);
      expect(settings.label, '${l.navSettings}, ${l.a11yNew}');
      expect(taps(settings), isTrue);
      h.dispose();
    });
  });

  group('onboarding', () {
    testWidgets('pages carry a heading, a page count, and labelled '
        'language cards', (t) async {
      final h = t.ensureSemantics();
      phone(t);
      await t.pumpWidget(
          host(OnboardingScreen(onDone: () {}), scaffold: false));
      await t.pump(const Duration(milliseconds: 600));

      expect(isHeader(node(t, 'Which language')), isTrue);
      // Set in capitals for the eye, read in sentence case.
      expect(node(t, 'First, your language').label, 'First, your language');
      final english = node(t, 'English');
      expect(isButton(english), isTrue);
      expect(isSelected(english), isTrue);
      expect(isSelected(containing(t, 'العربية')), isFalse);
      final dots = node(t, l.a11yPageOf(1, 8));
      expect(isLive(dots), isTrue);
      h.dispose();
    });
  });

  group('the wizard', () {
    testWidgets('verses are buttons that say the ayah and how to reach it',
        (t) async {
      final h = t.ensureSemantics();
      phone(t);
      creationState
        ..startNewReel()
        ..selectReciter(reciters.first)
        ..selectSurah(1);
      await t.pumpWidget(host(const VersesScreen(), scaffold: false));
      await t.pump(const Duration(milliseconds: 300));

      expect(isHeader(node(t, l.chooseTheVerses)), isTrue);
      // Read off WizardSteps rather than written out: the flow grew a
      // style step between the scenery and the reel, and a literal
      // here is exactly the thing that gets left behind when it grows
      // another.
      expect(node(t, l.a11yStep(WizardSteps.verses, WizardSteps.total)).label,
          l.a11yStep(2, 5));
      final picker = node(t, 'Al-Fatiha');
      expect(isButton(picker), isTrue);
      expect(picker.hint, l.a11yOpensSurahPicker);

      final first = node(t, l.ayahRange(1, 1));
      expect(isButton(first), isTrue);
      expect(hasSelectedState(first), isTrue);
      expect(isSelected(first), isFalse);
      expect(first.label, contains('In the name of Allah'));
      expect(first.hint, l.a11yVerseTileHint);
      expect(first.hasAction(SemanticsAction.longPress), isTrue);

      // On the verse, clear of its number: the number plays it.
      await t.tapAt(t.getCenter(find.descendant(
              of: find.byType(ListView), matching: find.text('1'))) +
          const Offset(120, 0));
      await t.pump(const Duration(milliseconds: 300));
      expect(isSelected(node(t, l.ayahRange(1, 1))), isTrue);
      h.dispose();
    });

    testWidgets('scenery tiles are named, numbered and say what they need',
        (t) async {
      final h = t.ensureSemantics();
      phone(t);
      creationState
        ..startNewReel()
        ..selectReciter(reciters.first)
        ..selectSurah(1)
        ..selectRange(1, 4)
        ..selectBackground(backgrounds.first);
      SettingsService.state.value =
          AppSettings.defaults.copyWith(sceneryTourDone: true);
      await t.runAsync(SceneCatalog.load);
      await t.pumpWidget(host(const BackgroundScreen(), scaffold: false));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      // The test font overflows the shape row on a 390px phone.
      t.takeException();

      final tiles =
          nodes(t).where((d) => RegExp(r', \d+ of \d+').hasMatch(d.label));
      expect(tiles, isNotEmpty);
      expect(tiles.every(isButton), isTrue);
      expect(tiles.every(hasSelectedState), isTrue);
      expect(tiles.where(isSelected), hasLength(1));
      expect(
          nodes(t).any((d) => d.label.endsWith(l.a11yNeedsDownload)), isTrue);

      // Tabs and frame pills carry their selected state; the multi
      // scene pill is a switch with a hint.
      expect(isSelected(node(t, l.sceneTab('sky'))), isFalse);
      expect(isSelected(node(t, l.frameFull)), isTrue);
      final multi = node(t, l.multipleScenes);
      expect(hasToggledState(multi), isTrue);
      expect(multi.hint, l.a11yMultiSceneHint);
      expect(node(t, l.matchScenesToVerses).hint, l.a11yMatchesScenes);
      expect(node(t, l.useYourOwn).hint, l.a11yOpensGallery);
      expect(isHeader(node(t, l.frameFormat)), isTrue);
      h.dispose();
    });

    testWidgets('the tour seals the screen under it for a reader too',
        (t) async {
      final h = t.ensureSemantics();
      final key = GlobalKey();
      await t.pumpWidget(host(Stack(children: [
        Positioned.fill(
          child: Column(children: [
            const SizedBox(height: 100),
            SizedBox(
              key: key,
              height: 40,
              child: TextButton(onPressed: () {}, child: const Text('under')),
            ),
          ]),
        ),
        Positioned.fill(
          child: CoachMarks(
            steps: [CoachStep(target: key, title: 'Pick a mood', body: 'tabs')],
            onFinished: () {},
          ),
        ),
      ])));
      await t.pump();
      expect(nodes(t).any((d) => d.label == 'under'), isFalse,
          reason: 'the dimmed screen is out of reach');
      expect(isHeader(node(t, 'Pick a mood')), isTrue);
      expect(isButton(node(t, l.tourDone)), isTrue);
      h.dispose();
    });
  });

  group('the player', () {
    testWidgets('the card, the scrubber and the buttons are all named',
        (t) async {
      final h = t.ensureSemantics();
      phone(t);
      ReelPoster.testResolver = (_) async => null;
      addTearDown(() => ReelPoster.testResolver = null);
      final reel = SavedReel(
        id: 'r1',
        fileName: 'reel_r1.mp4',
        reciterName: 'Alafasy',
        surahName: 'Al-Fatihah',
        startAyah: 1,
        endAyah: 7,
        gradientArgb: const [0xFF101418, 0xFF202830],
        createdAt: DateTime(2026, 1, 1),
      );
      await t.pumpWidget(host(ReelPlayerScreen(reel: reel), scaffold: false));
      await t.pump(const Duration(milliseconds: 300));

      // No documents directory under the test binding, so the file
      // never opens: the card says it is loading and everything that
      // needs the file is dimmed but still named.
      expect(isButton(node(t, l.a11yLoadingReel)), isTrue);
      final scrubber = node(t, l.a11yPlaybackPosition);
      expect(scrubber.flagsCollection.isSlider, isTrue);
      expect(scrubber.value, '0:00 / 0:00');
      for (final name in [l.replay, l.play, l.share]) {
        final b = exact(t, name);
        expect(isButton(b), isTrue, reason: name);
        expect(isEnabled(b), isFalse, reason: name);
      }
      expect(node(t, l.hashtags).hint, l.a11yOpensHashtags);
      h.dispose();
    });
  });

  group('sheets', () {
    testWidgets('the widget sheet: numbered steps read as one line each, '
        'and the picture is described', (t) async {
      final h = t.ensureSemantics();
      phone(t);
      await t.pumpWidget(host(WidgetSheet(
        android: true,
        canRequestPin: () async => true,
        isInstalled: () async => false,
      )));
      await t.pump(const Duration(milliseconds: 300));
      expect(isHeader(node(t, l.widgetSheetTitle)), isTrue);
      expect(node(t, l.a11yWidgetPreview).flagsCollection.isImage, isTrue);
      expect(node(t, '1\n').label, '1\n${l.widgetStepsAndroid[0]}');
      h.dispose();
    });

    testWidgets('hashtags: tabs with a state, and a Copy that announces',
        (t) async {
      final h = t.ensureSemantics();
      phone(t);
      await t.pumpWidget(
          host(const Center(child: HashtagsButton(surahName: 'Al-Kahf'))));
      await t.tap(find.byType(HashtagsButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(isSelected(node(t, l.platformInstagram)), isTrue);
      expect(isSelected(node(t, l.platformTikTok)), isFalse);
      final copy = node(t, l.copy);
      expect(isButton(copy), isTrue);
      expect(isLive(copy), isTrue);
      expect(copy.hint, l.a11yCopiesTags);
      h.dispose();
    });
  });

  test('every language carries every spoken string', () {
    const ar = L10n(AppLang.ar);
    for (final s in AppLang.values.map(L10n.new)) {
      expect(s.a11yNew, isNotEmpty);
      expect(s.a11yStep(1, 4), contains('1'));
      expect(s.a11yPageOf(2, 8), contains('2'));
      expect(s.a11yBusy('x'), contains('x'));
      expect(s.a11yRewards(3, 40, 2), contains('40'));
      expect(s.a11yRewards(0, 5, 0), isNot(contains('0')));
      expect(s.a11yReel('Al-Kahf', 'Alafasy', '1 Jan'), contains('1 Jan'));
      expect(s.a11yVerseCard('r', 'a', 't'), contains('r'));
      expect(s.a11yNthOf('Sky', 3, 40), contains('3'));
      expect(s.a11ySceneSegment(2, 3, true), contains('3'));
      expect(s.colourName(0xFFEEC96B), isNot('colour'));
      expect(s.a11yColourSwatch(0xFF000000), isNotEmpty);
      expect(s.sceneName('sky_pexels_03', 'Sky'), isNotEmpty);
      // The style step. Every swatch it offers has to have a name in
      // every language: a reader told "colour" twenty-four times has
      // been handed a grid it cannot use.
      for (final argb in versePalette) {
        expect(s.colourName(argb), isNot('colour'),
            reason: '${argb.toRadixString(16)} is unnamed in ${s.lang.code}');
        expect(s.a11yColourSwatch(argb), isNotEmpty);
      }
      for (final look in ReelLook.values) {
        expect(s.lookName(look.name), isNotEmpty);
      }
      expect(s.lookName('golden'), isNot(s.lookName('noir')));
      expect(s.a11yStyleStage, isNotEmpty);
      expect(s.a11ySetsFace, isNotEmpty);
      expect(s.a11yAppliesLook, isNotEmpty);
      expect(s.styleReset, isNotEmpty);
      // The card composer. Everything a reader is told while making
      // one: what the card is, what a tap on a block does, what a word
      // in the finder is, and how many cards are in hand.
      expect(s.a11yCardPreview, isNotEmpty);
      expect(s.a11ySelectsBlock, isNotEmpty);
      expect(s.a11yOpensCard, isNotEmpty);
      expect(s.a11yAddsToCard, isNotEmpty);
      expect(s.a11yCardWord, isNotEmpty);
      expect(s.a11yCardBlock('x'), contains('x'));
      expect(s.a11yCardsInDeck(3), contains('3'));
      expect(s.cardNumberOf(2, 5), contains('5'));
      expect(s.cardCount(1), isNotEmpty);
      expect(s.cardCount(3), contains('3'));
      expect(s.cardSavedToGallery(4), contains('4'));
      expect(s.findCredit('x'), contains('x'));
      expect(s.findGrading('Sahih'), contains('Sahih'));
      expect(s.hadithReference('bukhari', 13), contains('13'));
      expect(s.cardVerseReference('Al-Kahf', 18, 10, 10), contains('18:10'));
      expect(s.cardVerseReference('Al-Kahf', 18, 10, 12), contains('10–12'));
    }
    expect(ar.sceneName('sky_pexels_03', 'Sky 3'), 'سماء 3');
    expect(const L10n(AppLang.ur).sceneName('sky_pexels_03', 'Sky 3'),
        'آسمان 3');
    expect(const L10n(AppLang.de).sceneName('sky_pexels_03', 'Sky 3'),
        'Himmel 3');
  });
}
