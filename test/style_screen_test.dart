import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:ayah_reels/data/band_glow.dart';
import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/reel_effects.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_ink.dart';
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/style_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/ayah_overlay.dart';

/// The style step: the screen between the scenery and the reel.
///
/// Three things are pinned here, and they are the three the feature
/// would be worthless without:
///
///  1. **Nothing plays.** The frame is a still. A running video is the
///     worst possible ground for judging a typeface, and a decoder
///     held open here is one the preview screen may then not get.
///  2. It fits. Four panels' worth of controls on a phone with a
///     short screen is exactly where a row of swatches quietly slides
///     off the bottom.
///  3. Every control writes to the one object that holds the reel, so
///     the frame, the preview screen and the exporter cannot disagree
///     about what was chosen.
void main() {
  const still = ReelBackground.still(
    id: 'sky_pexels_01',
    name: 'Sky 1',
    imageAsset: 'assets/backgrounds/sky_pexels_01.jpg',
    gradientArgb: [0xFF10203A, 0xFF6E8CB0],
  );

  setUp(() {
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1)
      ..selectRange(1, 4)
      ..selectBackground(still)
      ..setLayout(ReelLayout.fullFrame)
      ..setVerseFace(VerseFace.uthmani)
      ..setTranslationFace(TranslationFace.inter)
      ..setTranslationFace(TranslationFace.plex)
      ..setTextColor(inkOnDark)
      ..setAccentColor(accentOnDark)
      ..setTextScale(1.0)
      ..setEffects(ReelEffects.off);
    SettingsService.state.value = AppSettings.defaults;
  });

  tearDown(() {
    creationState.setEffects(ReelEffects.off);
    SettingsService.state.value = AppSettings.defaults;
  });

  /// The glowing button at the bottom of this screen pulses forever,
  /// so `pumpAndSettle` on it never returns. Everything here pumps a
  /// fixed beat instead, which is long enough for the panel's own
  /// 180ms animations to land.
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  /// The switch on the effect named [label].
  Finder switchOf(String label) => find
      .descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byType(Switch),
      )
      .first;

  /// The panel's own vertical scroll view: a net for screens smaller
  /// than the app is laid out for, which must have nothing to scroll.
  ScrollPosition panelScroll(WidgetTester t) => t
      .state<ScrollableState>(find
          .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first)
      .position;

  Future<void> openTab(WidgetTester t, String tab) async {
    await t.tap(find.text(tab).first);
    await settle(t);
  }

  Future<void> open(WidgetTester t,
      {Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.runAsync(SceneCatalog.load);
    final lang = SettingsService.state.value.lang;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(lang: lang),
      locale: Locale(lang.code),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [for (final l in AppLang.values) Locale(l.code)],
      home: const StyleScreen(),
    ));
    await settle(t);
  }

  const l = L10n.en;

  testWidgets('the frame is a still: no decoder, no playing video',
      (t) async {
    await open(t);
    // A scenery from the app's own library draws its bundled poster.
    // Nothing on this screen may hold a video decoder open — the
    // preview screen is where those are counted, and it has none to
    // spare.
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.byType(AyahOverlay), findsWidgets);
  });

  testWidgets('every panel fits whole, with nothing to scroll, on a small '
      'phone and a large one — full frame and wide card', (t) async {
    for (final wide in [false, true]) {
      creationState.setLayout(wide ? ReelLayout.letterbox : ReelLayout.fullFrame);
      for (final size in [
        const Size(360, 640),
        const Size(390, 844),
        const Size(430, 932),
      ]) {
        for (final tab in [
          l.styleTabType,
          l.styleTabColour,
          l.styleTabEffects,
          l.styleTabMotion,
          l.styleTabName,
        ]) {
          // Where an overflow comes from, should one: the widget that
          // made it, out of the error's own report.
          final reports = <String>[];
          final prior = FlutterError.onError;
          FlutterError.onError = (d) {
            reports.add([
              d.exceptionAsString(),
              ...?d.informationCollector?.call().map((n) => '$n'),
            ].join('\n'));
            prior?.call(d);
          };
          try {
            await open(t, size: size);
            await openTab(t, tab);
          } finally {
            FlutterError.onError = prior;
          }
          final e = t.takeException();
          expect(e, isNull,
              reason: '$tab overflowed at $size'
                  '${wide ? ', wide card' : ''}: ${reports.join('\n')}');
          expect(panelScroll(t).maxScrollExtent, 0,
              reason: '$tab scrolls at $size${wide ? ', wide card' : ''}');
          if (wide && tab == l.styleTabColour) {
            // And the band's colours, behind their half of the switch.
            await t.tap(find.text(l.styleBackdropColour));
            await settle(t);
            expect(panelScroll(t).maxScrollExtent, 0,
                reason: 'the band\'s colours scroll at $size');
          }
        }
      }
    }
    creationState.setLayout(ReelLayout.fullFrame);
  });

  testWidgets('the type panel sets the verse face and the size', (t) async {
    await open(t);
    expect(creationState.verseFace, VerseFace.uthmani);
    // The cards spell the face's name under a specimen set in it.
    await t.tap(find.text(VerseFace.scheherazade.label).first);
    await settle(t);
    expect(creationState.verseFace, VerseFace.scheherazade);

    // And the frame is now set in it.
    final card = t.widget<AyahOverlay>(find.byType(AyahOverlay).first);
    expect(card.verseFace, VerseFace.scheherazade);

    await t.drag(find.byType(Slider).first, const Offset(-60, 0));
    await settle(t);
    expect(creationState.textScale, lessThan(1.0));
  });

  testWidgets('the translation row follows the edition’s script',
      (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(translation: VerseTranslation.urdu);
    await open(t);
    // Urdu is set in Arabic script, so the row is the Arabic-script
    // list and Nastaliq is on it. Inter is not.
    expect(find.text(TranslationFace.nastaliq.label), findsOneWidget);
    expect(find.text(TranslationFace.inter.label), findsNothing);
    await t.tap(find.text(TranslationFace.nastaliq.label));
    await settle(t);
    expect(creationState.arabicScriptFace, TranslationFace.nastaliq);
    // The Latin choice is untouched: it belongs to the other script.
    expect(creationState.latinFace, TranslationFace.inter);
    expect(creationState.typography.translation, TranslationFace.nastaliq);
  });

  testWidgets('the colour panel sets the verse; the motion panel sets the '
      'accent, which is the motion\'s colour', (t) async {
    final h = t.ensureSemantics();
    await open(t);
    await openTab(t, l.styleTabColour);

    // The label names the target as well as the colour. Every colour is
    // in view: nothing to scroll to.
    const mint = 0xFF9FE8C9;
    await t.tap(find.bySemanticsLabel(
        '${l.styleVerseColour}${l.comma} ${l.a11yColourSwatch(mint)}'));
    await settle(t);
    expect(creationState.textArgb, mint);
    expect(creationState.accentArgb, accentOnDark, reason: 'accent untouched');
    // The accent is no longer a colour target of its own here: one
    // control for one colour.
    expect(find.text(l.styleAccentColour), findsNothing);

    await openTab(t, l.styleTabMotion);
    // The motion's colours are light, never flat: the house gold and
    // the luminous inks, and no flat swatch or mixer among them.
    for (final c in versePalette) {
      expect(
          find.bySemanticsLabel(
              '${l.motionColour}${l.comma} ${l.a11yColourSwatch(c)}'),
          findsNothing,
          reason: '0x${c.toRadixString(16)}');
    }
    await t.tap(find.bySemanticsLabel(
        '${l.motionColour}${l.comma} ${l.a11yInkSwatch(VerseInk.aurora)}'));
    await settle(t);
    expect(creationState.accentInk, VerseInk.aurora);
    expect(creationState.accentArgb, VerseInk.aurora.base);
    expect(creationState.textArgb, mint, reason: 'verse untouched');

    final card = t.widget<AyahOverlay>(find.byType(AyahOverlay).first);
    expect(card.textColor.toARGB32(), mint);
    expect(card.accent!.toARGB32(), VerseInk.aurora.base);

    // Another ink; then the house gold puts it back.
    await t.tap(find.bySemanticsLabel(
        '${l.motionColour}${l.comma} ${l.a11yInkSwatch(VerseInk.ember)}'));
    await settle(t);
    expect(creationState.accentInk, VerseInk.ember);
    await t.tap(find.bySemanticsLabel(
        '${l.motionColour}${l.comma} ${l.colourName(accentOnDark)}'));
    await settle(t);
    expect(creationState.accentInk, VerseInk.none);
    expect(creationState.accentArgb, accentOnDark);
    h.dispose();
  });

  testWidgets('the motion panel offers the five looks, all in view, and '
      'one switch: the recited word lighting up', (t) async {
    await open(t);
    await openTab(t, l.styleTabMotion);
    for (final p in MotionPreset.values) {
      expect(find.text(l.motionPresetName(p.name)), findsOneWidget,
          reason: p.name);
    }
    expect(find.text('Breathe'), findsNothing);
    expect(find.text('Rise'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
    final was = creationState.wordHighlight;
    await t.tap(find.text(l.wordLightShort));
    await settle(t);
    expect(creationState.wordHighlight, !was);
    await t.tap(find.byType(Switch));
    await settle(t);
    expect(creationState.wordHighlight, was);
    await t.tap(find.text(l.motionPresetName(MotionPreset.thread.name)));
    await settle(t);
    expect(creationState.motion, MotionPreset.thread.motion);
  });

  testWidgets('the verse moves up and down from beside the frame, and '
      'stops at the ends', (t) async {
    creationState.setOverlayAlign(0.5);
    addTearDown(() => creationState.setOverlayAlign(0.5));
    await open(t);
    await t.tap(find.byIcon(Icons.expand_more_rounded));
    await settle(t);
    expect(creationState.overlayAlign, closeTo(0.55, 1e-9));
    await t.tap(find.byIcon(Icons.expand_less_rounded));
    await settle(t);
    await t.tap(find.byIcon(Icons.expand_less_rounded));
    await settle(t);
    expect(creationState.overlayAlign, closeTo(0.45, 1e-9));
    creationState.setOverlayAlign(0);
    await settle(t);
    await t.tap(find.byIcon(Icons.expand_less_rounded));
    await settle(t);
    expect(creationState.overlayAlign, 0);
  });

  testWidgets('a luminous ink draws the verse, and a flat colour takes it off',
      (t) async {
    final h = t.ensureSemantics();
    await open(t);
    await openTab(t, l.styleTabColour);
    // The inks are one line of small squares that scrolls sideways.
    final rows = {
      for (final ink in VerseInk.ordered(onLight: false).take(5))
        t
            .getRect(find.bySemanticsLabel(
                '${l.styleVerseColour}${l.comma} ${l.a11yInkSwatch(ink)}'))
            .center
            .dy
            .round(),
    };
    expect(rows.length, 1);

    await t.tap(find.bySemanticsLabel(
        '${l.styleVerseColour}${l.comma} ${l.a11yInkSwatch(VerseInk.iris)}'));
    await settle(t);
    expect(creationState.verseInk, VerseInk.iris);
    // The flat colour stands in for it everywhere that knows only one.
    expect(creationState.textArgb, VerseInk.iris.base);
    var card = t.widget<AyahOverlay>(find.byType(AyahOverlay).first);
    expect(card.ink, VerseInk.iris);
    expect(card.textColor.toARGB32(), VerseInk.iris.base);
    // And the heading names it.
    expect(find.textContaining(l.inkName(VerseInk.iris)), findsWidgets);

    const mint = 0xFF9FE8C9;
    await t.tap(find.bySemanticsLabel(
        '${l.styleVerseColour}${l.comma} ${l.a11yColourSwatch(mint)}'));
    await settle(t);
    expect(creationState.verseInk, VerseInk.none);
    expect(creationState.textArgb, mint);
    card = t.widget<AyahOverlay>(find.byType(AyahOverlay).first);
    expect(card.ink, VerseInk.none);
    h.dispose();
  });

  test('every ink has a name in every language', () {
    for (final lang in AppLang.values) {
      final ll = L10n(lang);
      final names = <String>{};
      for (final ink in VerseInk.values) {
        if (ink.isNone) continue;
        expect(ll.inkName(ink), isNotEmpty);
        names.add(ll.inkName(ink));
      }
      expect(names.length, VerseInk.values.length - 1,
          reason: 'two inks share a name in ${lang.code}');
    }
  });

  test('every swatch in the palette has a name to read', () {
    for (final argb in versePalette) {
      expect(l.colourName(argb), isNot('colour'),
          reason: '${argb.toRadixString(16)} is unnamed');
    }
  });

  testWidgets('the effects panel grades, and one tap turns each on',
      (t) async {
    await open(t);
    await openTab(t, l.styleTabEffects);
    expect(creationState.effects.isNeutral, isTrue);

    await t.tap(find.text(l.lookName(ReelLook.golden.name)));
    await settle(t);
    expect(creationState.effects.look, ReelLook.golden);
    expect(creationState.effects.gradesPicture, isTrue);

    // Each row is a switch that lands on a strength somebody would
    // have chosen, not on zero.
    bool warmthOn() => t.widget<Switch>(switchOf(l.effectWarmth)).value;
    expect(warmthOn(), isFalse);
    await t.tap(switchOf(l.effectWarmth));
    await settle(t);
    expect(creationState.effects.warmth, greaterThan(0));
    // And the row says so. This is the assertion that catches a panel
    // Flutter has decided it need not rebuild — the switches went on
    // showing "off" while the reel warmed up underneath them.
    expect(warmthOn(), isTrue);

    // And off again puts it back to nothing.
    await t.tap(switchOf(l.effectWarmth));
    await settle(t);
    expect(creationState.effects.warmth, 0);
    expect(warmthOn(), isFalse);
  });

  testWidgets('a wide card adds its band to the colours — blurred, '
      'luminous or flat — and its corners to the effects', (t) async {
    final h = t.ensureSemantics();
    creationState
      ..setLayout(ReelLayout.letterbox)
      ..setRoundedCorners(false)
      ..setBackdrop(LetterboxBackdrop.blur);
    await open(t);
    await openTab(t, l.styleTabColour);
    await t.tap(find.text(l.styleBackdropColour));
    await settle(t);
    // The blur leads the luminous grounds, in their grid, on their row.
    final blurAt = t.getRect(find.bySemanticsLabel(
        '${l.styleBackdropColour}${l.comma} ${l.backdropBlur}'));
    final firstGlowAt = t.getRect(find.bySemanticsLabel(
        '${l.styleBackdropColour}${l.comma} '
        '${l.bandGlowName(BandGlow.values.first)}'));
    expect(blurAt.center.dy, closeTo(firstGlowAt.center.dy, 1));
    expect(blurAt.center.dx, lessThan(firstGlowAt.center.dx));
    await t.tap(find.bySemanticsLabel(
        '${l.styleBackdropColour}${l.comma} ${l.bandGlowName(BandGlow.aurora)}'));
    await settle(t);
    expect(creationState.backdrop, LetterboxBackdrop.glow);
    expect(creationState.bandGlow, BandGlow.aurora);
    expect(creationState.backdropArgb, BandGlow.aurora.base);
    const ivory = 0xFFF3EADA;
    await t.tap(find.bySemanticsLabel(
        '${l.styleBackdropColour}${l.comma} ${l.a11yColourSwatch(ivory)}'));
    await settle(t);
    expect(creationState.backdrop, LetterboxBackdrop.colour);
    expect(creationState.backdropArgb, ivory);
    await t.tap(find.bySemanticsLabel(
        '${l.styleBackdropColour}${l.comma} ${l.backdropBlur}'));
    await settle(t);
    expect(creationState.backdrop, LetterboxBackdrop.blur);

    await openTab(t, l.styleTabEffects);
    await t.tap(switchOf(l.roundedCorners));
    await settle(t);
    expect(creationState.roundedCorners, isTrue);
    creationState.setLayout(ReelLayout.fullFrame);
    h.dispose();
  });

  test('every luminous ground has a name in every language, and the pale '
      'ones are the ones that take dark ink', () {
    for (final lang in AppLang.values) {
      final ll = L10n(lang);
      final names = {for (final g in BandGlow.values) ll.bandGlowName(g)};
      expect(names.length, BandGlow.values.length,
          reason: 'two grounds share a name in ${lang.code}');
    }
    for (final g in BandGlow.values) {
      expect(g.light, isLightSurface(g.base), reason: g.name);
      expect(
          isLightGround(
              layout: ReelLayout.letterbox,
              backdrop: LetterboxBackdrop.glow,
              backdropArgb: g.base),
          g.light,
          reason: g.name);
    }
    expect({for (final g in BandGlow.values) if (g.light) g},
        {BandGlow.pearl, BandGlow.dawn});
  });

  testWidgets('a full frame has no band to colour and no corners', (t) async {
    await open(t);
    await openTab(t, l.styleTabColour);
    expect(find.text(l.styleBackdropColour), findsNothing);
    await openTab(t, l.styleTabEffects);
    expect(find.text(l.roundedCorners), findsNothing);
  });

  testWidgets('fade is the first of the switches', (t) async {
    await open(t);
    await openTab(t, l.styleTabEffects);
    // At the head of the list, where a short panel still shows it
    // without a scroll.
    expect(t.widget<Switch>(find.byType(Switch).first),
        t.widget<Switch>(switchOf(l.effectFadeShort)));
    await t.tap(switchOf(l.effectFadeShort));
    await settle(t);
    expect(creationState.effects.fade, isTrue);
  });

  testWidgets('a slider dragged through the middle keeps its row open',
      (t) async {
    await open(t);
    await openTab(t, l.styleTabEffects);
    await t.tap(switchOf(l.effectWarmth)); // warmth on, at +50%
    await settle(t);
    expect(find.byType(Slider), findsWidgets);

    // Warmth runs cool-to-warm through zero, and zero is the middle of
    // the track. Landing on it must not tear the slider out from under
    // the finger: the switch opened the row, and only the switch
    // closes it.
    final slider = find.byType(Slider).first;
    await t.drag(slider, Offset(-t.getSize(slider).width / 2, 0));
    await settle(t);
    expect(creationState.effects.warmth, lessThanOrEqualTo(0));
    expect(find.byType(Slider), findsWidgets,
        reason: 'the row closed itself mid-drag');
    expect(t.widget<Switch>(switchOf(l.effectWarmth)).value, isTrue);
  });

  testWidgets('reset clears only the panel that is open', (t) async {
    final h = t.ensureSemantics();
    await open(t);
    creationState
      ..setVerseFace(VerseFace.lateef)
      ..setEffects(const ReelEffects(look: ReelLook.noir, vignette: 0.5));
    await settle(t);

    // Type is open: the faces go back, the grade stays. A reset that
    // quietly took the grade off with the typeface would be a button
    // nobody dares press.
    await t.tap(find.bySemanticsLabel(l.styleReset));
    await settle(t);
    expect(creationState.verseFace, VerseFace.uthmani);
    expect(creationState.effects.look, ReelLook.noir);

    await openTab(t, l.styleTabEffects);
    await t.tap(find.bySemanticsLabel(l.styleReset));
    await settle(t);
    expect(creationState.effects, ReelEffects.off);
    h.dispose();
  });

  testWidgets('it holds up in Arabic and Urdu, mirrored', (t) async {
    for (final lang in [AppLang.ar, AppLang.ur]) {
      SettingsService.state.value = AppSettings.defaults.copyWith(
        lang: lang,
        // Urdu reads its own edition; Arabic reads the verse itself
        // and leaves the translation in English, which is the pair
        // this screen has to lay out either way.
        translation: lang == AppLang.ur
            ? VerseTranslation.urdu
            : VerseTranslation.english,
      );
      final ll = L10n(lang);
      for (final tab in [
        ll.styleTabType,
        ll.styleTabColour,
        ll.styleTabEffects
      ]) {
        await open(t, size: const Size(360, 640));
        expect(Directionality.of(t.element(find.byType(StyleScreen))),
            TextDirection.rtl);
        await openTab(t, tab);
        expect(t.takeException(), isNull,
            reason: '$tab overflowed in ${lang.code}');
      }
    }
  });

  testWidgets('it is the fourth of five steps', (t) async {
    final h = t.ensureSemantics();
    await open(t);
    expect(WizardSteps.style, 4);
    expect(WizardSteps.total, 5);
    expect(find.bySemanticsLabel(l.a11yStep(4, 5)), findsOneWidget);
    h.dispose();
  });
}
