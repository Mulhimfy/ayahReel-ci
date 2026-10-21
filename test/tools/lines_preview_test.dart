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
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/render/letterbox_layout.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/screens/style_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/widgets/motion_picker.dart';
import 'package:ayah_reels/widgets/surah_title.dart';

import '../arena_screens_test.dart' show plainTheme;

/// Draws the new surfaces on a desk, so they can be looked at without a
/// phone: Settings' Customize panel open (English and Arabic), the style
/// step's Motion tab mid-loop, the motion sheet, and the surah's name on
/// a full frame and over a pale letterbox band. Skipped unless pointed
/// somewhere:
///
///   LINES_PREVIEW_OUT=/tmp/lines flutter test test/tools/lines_preview_test.dart
void main() {
  final out = Platform.environment['LINES_PREVIEW_OUT'];

  testWidgets('lines preview', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
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
      if (asset != null && family != null) {
        families[family]!.add(asset.group(1)!);
      }
    }
    await t.runAsync(() async {
      for (final e in families.entries) {
        final loader = FontLoader(e.key);
        for (final p in e.value) {
          loader.addFont(rootBundle.load(p));
        }
        await loader.load();
      }
    });
    await t.runAsync(SceneCatalog.load);

    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final key = GlobalKey();
    Future<void> shoot(String name) async {
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

    Widget app(AppLang lang, Widget home) => RepaintBoundary(
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
            home: home,
          ),
        );

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    // ---- Settings: the Customize panel, open ------------------------
    for (final lang in [AppLang.en, AppLang.ar]) {
      SettingsService.state.value =
          AppSettings.defaults.copyWith(lang: lang, verseLines: 2);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(
          lang,
          Scaffold(
            body: SettingsScreen(
              permissionCheck: () async => true,
              widgetCheck: () async => false,
            ),
          )));
      await settle();
      final row = find.text(L10n(lang).customizeTitle);
      await t.scrollUntilVisible(row, 200);
      await t.tap(row);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.drag(find.byType(ListView).first, const Offset(0, -260));
      await t.pump(const Duration(milliseconds: 400));
      await shoot('customize_${lang.code}');
      await t.drag(find.byType(ListView).first, const Offset(0, -420));
      await t.pump(const Duration(milliseconds: 400));
      await shoot('customize_${lang.code}_lower');
    }
    SettingsService.state.value = AppSettings.defaults;

    // ---- the style step's Motion tab, mid-loop -----------------------
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
      ..setEffects(ReelEffects.off)
      ..setSurahTitle(true);
    for (final preset in [
      MotionPreset.thread,
      MotionPreset.light,
      MotionPreset.gilded,
      MotionPreset.unveil,
    ]) {
      creationState.setMotion(preset.motion);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(AppLang.en, const StyleScreen()));
      await settle();
      await t.tap(find.text(const L10n(AppLang.en).styleTabMotion).first);
      await t.pump();
      for (final ms in const [900, 2200, 3600]) {
        await t.pump(Duration(milliseconds: ms == 900 ? 900 : 1300));
        await shoot('motion_${preset.name}_$ms');
      }
    }
    creationState.setMotion(VerseMotion.none);

    // ---- the motion sheet over a reel ---------------------------------
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app(
      AppLang.en,
      Builder(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF0B0F14),
          body: Center(
            child: TextButton(
              onPressed: () => showMotionSheet(context,
                  motion: MotionPreset.thread.motion,
                  hasWords: false,
                  onChanged: (_) {}),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 1200));
    await shoot('motion_sheet_no_words');

    // ---- the surah's name on a frame ----------------------------------
    for (final (name, box, onLight, surah, edition) in [
      ('title_full', null, false, 2, VerseTranslation.english),
      ('title_letterbox_light', LetterboxGeometry.of(16 / 9), true, 36,
          VerseTranslation.english),
      ('title_urdu', null, false, 55, VerseTranslation.urdu),
    ]) {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(
        AppLang.en,
        Center(
          child: SizedBox(
            width: 360,
            height: 640,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: onLight ? const Color(0xFFF3EADA) : null,
                    gradient: onLight
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF16263F), Color(0xFF6E5A3A)],
                          ),
                  ),
                ),
                if (box != null)
                  Positioned(
                    left: box.cardX * 360 / 1080,
                    top: box.cardY * 360 / 1080,
                    width: box.cardW * 360 / 1080,
                    height: box.cardH * 360 / 1080,
                    child: const ColoredBox(color: Color(0xFF345C7A)),
                  ),
                Positioned.fill(
                  child: ReelSurahTitle(
                    width: 360,
                    surah: surah,
                    edition: edition,
                    onLight: onLight,
                    letterbox: box,
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await settle();
      await shoot(name);
    }
  }, skip: out == null);
}
