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

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_light.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/render/verses_story.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/screens/my_reels_screen.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/screens/style_screen.dart';
import 'package:ayah_reels/screens/verses_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/widgets/app_toast.dart';
import 'package:ayah_reels/widgets/arena_guide.dart';
import 'package:ayah_reels/widgets/colour_picker.dart';
import 'package:ayah_reels/widgets/direct_share_button.dart';
import 'package:ayah_reels/widgets/how_to_sheet.dart';
import 'package:ayah_reels/widgets/instagram_choice.dart';
import 'package:ayah_reels/widgets/verses_milestone.dart';

import '../arena_screens_test.dart' show plainTheme;

/// Draws this batch's new surfaces on a desk, so they can be looked at
/// without a phone: the "Your verses" card and its page, the toasts,
/// Instagram's story-or-reel panel, the colour mixer, the Tanafus guide
/// and the Settings dots. Not a test of anything: skipped unless it is
/// pointed somewhere.
///
///   BATCH_PREVIEW_OUT=/tmp/batch flutter test test/tools/batch_preview_test.dart
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
  final out = Platform.environment['BATCH_PREVIEW_OUT'];
  TestWidgetsFlutterBinding.ensureInitialized();

  SavedReel reel(String surah, int from, int to, int day) => SavedReel(
        id: 'r$day',
        fileName: 'reel_r$day.mp4',
        reciterName: 'Mishary Alafasy',
        surahName: surah,
        startAyah: from,
        endAyah: to,
        gradientArgb: const [0xFF1B2433, 0xFF0B0F17],
        createdAt: DateTime(2026, 6, day),
      );

  final reels = [
    reel('Al-Fatiha', 1, 7, 1),
    reel('Al-Baqarah', 255, 257, 2),
    reel('Al-Kahf', 1, 10, 3),
    reel('Ya-Sin', 1, 12, 4),
    reel('Ar-Rahman', 1, 13, 5),
    reel('Al-Mulk', 1, 5, 6),
    reel('Al-Ikhlas', 1, 4, 7),
    reel('Al-Baqarah', 285, 286, 8),
    reel('Ash-Sharh', 1, 8, 9),
    reel('Maryam', 1, 15, 10),
  ];

  testWidgets('batch preview', (t) async {
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
    for (final v in ['regular', '500', '600', '700', '800']) {
      await load('Inter_$v', 'assets/fonts/Inter.ttf');
    }
    SettingsService.state.value = AppSettings.defaults.copyWith(name: 'Yusuf');

    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final key = GlobalKey();
    Widget host(Widget child) => RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: plainTheme(),
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
        // ignore: avoid_print
        print('(ignored) ${e.toString().split('\n').first}');
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
      drain();
    }

    Future<void> scene(Widget w) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(host(w));
    }

    // The card itself, as it is shared: with words and without.
    final light = VerseLight.of(reels);
    for (final (name, words) in [('verses_card_plain', false), ('verses_card_words', true)]) {
      await t.runAsync(() async {
        final bytes = await VersesStory.png(
          l: L10n.en,
          light: light,
          name: words ? 'Yusuf' : '',
          numbers: words,
        );
        await File('$out/$name.png').writeAsBytes(bytes, flush: true);
      });
      drain();
    }
    await t.runAsync(() async {
      final bytes = await VersesStory.png(
          l: const L10n(AppLang.ar), light: light, name: 'يوسف', numbers: true);
      await File('$out/verses_card_ar.png').writeAsBytes(bytes, flush: true);
    });
    drain();

    // The Reels tab, on its second page.
    final docs = Directory('$out/reels')..createSync(recursive: true);
    for (final r in reels) {
      File('${docs.path}/${r.fileName}').writeAsBytesSync(const [0]);
    }
    File('${docs.path}/library.json').writeAsStringSync(
        jsonEncode([for (final r in reels.reversed) r.toJson()]));
    await scene(const Scaffold(body: MyReelsScreen()));
    await settle();
    await t.tap(find.text(L10n.en.reelsTabVerses));
    await settle(3000);
    await shoot('reels_verses_page');
    // Its "?", beside the card.
    await t.tap(find.byType(HowToButton));
    await settle(1400);
    await shoot('verses_sun_howto');

    // The tenth reel's offer, over a page.
    await scene(Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () =>
                offerVersesMilestone(context, reels: 10, onSee: () {}),
            child: const Text('milestone'),
          ),
        ),
      ),
    ));
    await settle(200);
    await t.tap(find.text('milestone'));
    await settle(3200);
    await shoot('verses_milestone');

    // The toasts, side by side, landed.
    await scene(Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const AppToast(
                message: 'Saved to your gallery and My Reels',
                tone: ToastTone.done),
            const SizedBox(height: 14),
            const AppToast(message: 'Trimmed to ayah 7', tone: ToastTone.info),
            const SizedBox(height: 14),
            AppToast(
              message: "Couldn't save the reel. Your phone is out of space.",
              tone: ToastTone.problem,
              actionLabel: 'Report',
              onAction: () {},
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    ));
    await settle(1800);
    await shoot('toasts');

    // Instagram's question, over its button.
    await scene(Scaffold(
      body: Align(
        alignment: const Alignment(0, 0.75),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Builder(
            builder: (button) => DirectShareButton(
              label: L10n.en.sendToInstagram,
              icon: Icons.movie_creation_outlined,
              leading: const InstagramGlyph(),
              colors: instagramMesh,
              onPressed: () => showInstagramChoice(button),
            ),
          ),
        ),
      ),
    ));
    await settle(200);
    await t.tap(find.byType(DirectShareButton));
    await settle(800);
    await shoot('instagram_choice');

    // The colour mixer, with many colours kept — none dropped — and
    // then letting some go.
    SettingsService.state.value = SettingsService.state.value.copyWith(
        customColours: [
      for (var i = 0; i < 26; i++)
        HSVColor.fromAHSV(1, (i * 37) % 360.0, 0.55 + (i % 3) * 0.15,
                0.55 + (i % 4) * 0.12)
            .toColor()
            .toARGB32(),
    ]);
    await scene(const Scaffold(
      body: Center(
        child: CustomColourCircle(
            current: 0xFF3366CC, chosen: false, onPick: _noop),
      ),
    ));
    await settle(200);
    await t.tap(find.byType(CustomColourCircle));
    await settle(800);
    await shoot('colour_picker');
    await t.tap(find.text(L10n.en.customColourRemove));
    await settle(300);
    await shoot('colour_picker_remove');

    // The Tanafus guide.
    await scene(Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showArenaGuide(context),
            child: const Text('?'),
          ),
        ),
      ),
    ));
    await settle(200);
    await t.tap(find.text('?'));
    await settle(1400);
    await shoot('tanafus_guide');

    // Settings, with every dot lit.
    SettingsService.state.value = AppSettings.defaults;
    await scene(Scaffold(
      body: SettingsScreen(
        permissionCheck: () async => true,
        widgetCheck: () async => false,
      ),
    ));
    await settle(600);
    await shoot('settings_dots');

    // What follows draws whole screens; a step that cannot be taken on
    // the desk is reported and passed over, not the end of the run.
    Future<void> attempt(String what, Future<void> Function() step) async {
      try {
        await step();
      } catch (e) {
        // ignore: avoid_print
        print('(skipped $what) ${e.toString().split('\n').first}');
      }
      drain();
    }

    // The verse picker: the slim player, a run chosen, its name, and
    // the "?" sheet.
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1);
    await scene(const VersesScreen());
    await settle(600);
    Offset onVerse(int n) =>
        t.getCenter(find.descendant(
            of: find.byType(ListView), matching: find.text('$n'))) +
        const Offset(120, 0);
    await attempt('verses', () async {
      await t.tapAt(onVerse(1));
      await settle(300);
      await t.tapAt(onVerse(3));
      await settle(900);
      await shoot('verses_picker');
      await t.tap(find.byType(HowToButton));
      await settle(1400);
      await shoot('verses_howto');
    });

    // The scenery screen: tall, wide, scrolled into the grid, and its
    // "?" sheet.
    SettingsService.state.value =
        AppSettings.defaults.copyWith(sceneryTourDone: true);
    creationState
      ..selectRange(1, 4)
      ..selectBackground(backgrounds.first);
    await t.runAsync(SceneCatalog.load);
    await scene(const BackgroundScreen());
    await settle(900);
    await shoot('scenery_tall');
    await attempt('scenery wide', () async {
      await t.tap(find.text(L10n.en.frameLetterbox));
      await settle(900);
      await shoot('scenery_wide');
    });
    await attempt('scenery scrolled', () async {
      await t.drag(
          find.byType(CustomScrollView).first, const Offset(0, -420));
      await settle(600);
      await shoot('scenery_scrolled');
    });
    await attempt('scenery how-to', () async {
      await t.tap(find.byType(HowToButton));
      await settle(1400);
      await shoot('scenery_howto');
    });

    // The style step on that wide card: its band among the colours,
    // and its corners among the effects.
    await attempt('style band', () async {
      creationState.setLayout(ReelLayout.letterbox);
      await scene(const StyleScreen());
      await settle(900);
      await t.tap(find.text(L10n.en.styleTabColour).first);
      await settle(400);
      await t.tap(find.text(L10n.en.styleBackdropColour));
      await settle(600);
      await shoot('style_band');
      await t.tap(find.text(L10n.en.styleTabEffects).first);
      await settle(600);
      await shoot('style_effects_corners');
    });
  }, skip: out == null, timeout: const Timeout(Duration(minutes: 8)));
}

void _noop(int _) {}
