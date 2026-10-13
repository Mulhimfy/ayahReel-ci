import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/reel_effects.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_font.dart';
import 'package:ayah_reels/data/verse_ink.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/style_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';

import '../arena_screens_test.dart' show plainTheme;

/// Draws the style step's Type panel — the two rows of face cards, the
/// size, the looks — and its Colour and Effects panels, with the verse
/// in a luminous ink, so they can be looked at without a phone. Skipped
/// unless pointed somewhere:
///
///   STYLE_PREVIEW_OUT=/tmp/style flutter test test/tools/style_preview_test.dart
///
/// In English and in Arabic, and with an Urdu translation, whose
/// Nastaliq is the tallest face any card has to hold.
void main() {
  final out = Platform.environment['STYLE_PREVIEW_OUT'];

  testWidgets('style preview', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Every family the app declares, from pubspec.yaml: a face that is
    // not loaded draws tofu, which looks like a broken card.
    final families = <String, List<String>>{};
    String? family;
    for (final line in File('pubspec.yaml').readAsLinesSync()) {
      final fam = RegExp(r'^\s{4}- family:\s*(\S+)').firstMatch(line);
      if (fam != null) {
        family = fam.group(1)!;
        families[family] = [];
        continue;
      }
      final asset =
          RegExp(r'^\s+- asset:\s*(assets/fonts/\S+\.ttf)').firstMatch(line);
      if (asset != null && family != null) families[family]!.add(asset.group(1)!);
    }
    for (final e in families.entries) {
      final loader = FontLoader(e.key);
      for (final p in e.value) {
        loader.addFont(rootBundle.load(p));
      }
      await loader.load();
    }
    await t.runAsync(SceneCatalog.load);

    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    const still = ReelBackground.still(
      id: 'sky_pexels_01',
      name: 'Sky 1',
      imageAsset: 'assets/backgrounds/sky_pexels_01.jpg',
      gradientArgb: [0xFF10203A, 0xFF6E8CB0],
    );
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1)
      ..selectRange(1, 4)
      ..selectBackground(still)
      ..setLayout(ReelLayout.fullFrame)
      ..setVerseFace(VerseFace.uthmani)
      ..setTextScale(1.0)
      ..setEffects(ReelEffects.off);

    final key = GlobalKey();
    Future<void> shoot(String name, AppLang lang,
        {String Function(L10n l)? tab, double scroll = 0}) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(RepaintBoundary(
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
          home: const StyleScreen(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(
          find.text((tab ?? (l) => l.styleTabType)(L10n(lang))).first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      if (scroll != 0) {
        // The panel's own list, which is the last vertical one built.
        await t.drag(find.byType(ListView).last, Offset(0, -scroll));
        await t.pump(const Duration(milliseconds: 400));
      }
      await t.runAsync(() async {
        final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await b.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('$out/$name.png').writeAsBytes(data!.buffer.asUint8List());
        // ignore: avoid_print
        print('wrote $out/$name.png');
      });
      for (var e = t.takeException(); e != null; e = t.takeException()) {
        // ignore: avoid_print
        print('note: $e');
      }
    }

    SettingsService.state.value = AppSettings.defaults;
    await shoot('type_en', AppLang.en);
    SettingsService.state.value = AppSettings.defaults.copyWith(lang: AppLang.ar);
    await shoot('type_ar', AppLang.ar);
    SettingsService.state.value = AppSettings.defaults
        .copyWith(lang: AppLang.ur, translation: VerseTranslation.urdu);
    await shoot('type_ur', AppLang.ur);
    SettingsService.state.value = AppSettings.defaults;

    creationState.setVerseInk(VerseInk.ember);
    await shoot('colour_ember_en', AppLang.en, tab: (l) => l.styleTabColour);
    creationState
      ..setVerseInk(VerseInk.iris)
      ..setAccentInk(VerseInk.gilded);
    await shoot('colour_iris_en', AppLang.en, tab: (l) => l.styleTabColour);
    await shoot('colour_solid_en', AppLang.en,
        tab: (l) => l.styleTabColour, scroll: 400);
    SettingsService.state.value = AppSettings.defaults.copyWith(lang: AppLang.ar);
    creationState.setVerseInk(VerseInk.aurora);
    await shoot('colour_aurora_ar', AppLang.ar, tab: (l) => l.styleTabColour);
    SettingsService.state.value = AppSettings.defaults;
    await shoot('effects_en', AppLang.en, tab: (l) => l.styleTabEffects);
    creationState
      ..setTextColor(inkOnDark)
      ..setAccentColor(accentOnDark);
  }, skip: out == null);
}
