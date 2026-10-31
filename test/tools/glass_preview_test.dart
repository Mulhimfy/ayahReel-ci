import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/screens/my_reels_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/app_toast.dart';
import 'package:ayah_reels/widgets/card_scene_sheet.dart';
import 'package:ayah_reels/widgets/gilded_writing.dart';
import 'package:ayah_reels/widgets/glass_tile.dart';
import 'package:ayah_reels/widgets/illumination.dart';

import '../arena_screens_test.dart' show plainTheme;

/// Draws the glass and the light on a desk, frame by frame, so they can
/// be looked at without a phone, as contact sheets: the scenery tiles at
/// rest and as the slow light drifts, a touch from its first frame to
/// its last, a held finger sliding across the grid, the run of light
/// round a tile as it is chosen, the same touch with less motion asked
/// for, the real scenery screen, the app's name being written in, a
/// toast landing, and My Reels and the card's scenery sheet under a
/// finger. Skipped unless pointed somewhere:
///
///   STYLE_PREVIEW_OUT=/tmp/glass flutter test test/tools/glass_preview_test.dart
///
/// (The desk-previews workflow points every tool's variable at the
/// tool's own folder; this one reads the style tool's.)
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
  final out = Platform.environment['STYLE_PREVIEW_OUT'];

  testWidgets('glass preview', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    PathProviderPlatform.instance = _Tmp(out!);
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
      for (final v in ['regular', '500', '600', '700', '800']) {
        final loader = FontLoader('Inter_$v')
          ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
        await loader.load();
      }
    });
    await t.runAsync(SceneCatalog.load);

    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final key = GlobalKey();
    final labKey = GlobalKey();
    final markKey = GlobalKey();

    void drain() {
      for (var e = t.takeException(); e != null; e = t.takeException()) {
        // ignore: avoid_print
        print('note: ${e.toString().split('\n').first}');
      }
    }

    /// One capture of a boundary, or of a part of it given in screen
    /// coordinates.
    Future<ui.Image> grab({GlobalKey? of, double ratio = 2, Rect? crop}) async {
      final b =
          (of ?? key).currentContext!.findRenderObject() as RenderRepaintBoundary;
      final origin = b.localToGlobal(Offset.zero);
      final image = (await t.runAsync(() => b.toImage(pixelRatio: ratio)))!;
      if (crop == null) return image;
      final local = crop.shift(-origin).intersect(Offset.zero & b.size);
      final part = (await t.runAsync(() {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawImageRect(
          image,
          Rect.fromLTWH(local.left * ratio, local.top * ratio,
              local.width * ratio, local.height * ratio),
          Rect.fromLTWH(0, 0, local.width * ratio, local.height * ratio),
          Paint()..filterQuality = FilterQuality.none,
        );
        return recorder.endRecording().toImage(
            (local.width * ratio).round(), (local.height * ratio).round());
      }))!;
      image.dispose();
      drain();
      return part;
    }

    /// Captures side by side, [columns] to a row, as one picture.
    Future<void> sheet(String name, List<ui.Image> frames,
        {int columns = 4}) async {
      if (frames.isEmpty) return;
      await t.runAsync(() async {
        final w = frames.map((f) => f.width).reduce(math.max);
        final h = frames.map((f) => f.height).reduce(math.max);
        final cols = math.min(columns, frames.length);
        final rows = (frames.length / cols).ceil();
        const gap = 6;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, (cols * (w + gap) - gap).toDouble(),
              (rows * (h + gap) - gap).toDouble()),
          Paint()..color = const Color(0xFF3A3F47),
        );
        for (var i = 0; i < frames.length; i++) {
          canvas.drawImage(
            frames[i],
            Offset(((i % cols) * (w + gap)).toDouble(),
                ((i ~/ cols) * (h + gap)).toDouble()),
            Paint(),
          );
        }
        final image = await recorder
            .endRecording()
            .toImage(cols * (w + gap) - gap, rows * (h + gap) - gap);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        for (final f in frames) {
          f.dispose();
        }
        await File('$out/$name.png')
            .writeAsBytes(data!.buffer.asUint8List(), flush: true);
        // ignore: avoid_print
        print('wrote $out/$name.png');
      });
      drain();
    }

    Future<void> shoot(String name,
            {GlobalKey? of, double ratio = 2, Rect? crop}) async =>
        sheet(name, [await grab(of: of, ratio: ratio, crop: crop)]);

    Widget app(Widget home, {bool still = false}) => RepaintBoundary(
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: still),
              child: child!,
            ),
            home: home,
          ),
        );

    /// Lets the posters decode: real time for the codec, a frame after.
    Future<void> decode([int rounds = 10]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump();
        drain();
      }
    }

    /// Frames as a phone draws them, 16 ms apart.
    Future<void> run(int ms) async {
      for (var e = 0; e < ms; e += 16) {
        await t.pump(const Duration(milliseconds: 16));
      }
      drain();
    }

    Future<void> scene(Widget w, {bool still = false}) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(w, still: still));
      await decode();
    }

    Future<void> attempt(String what, Future<void> Function() step) async {
      try {
        await step();
      } catch (e) {
        // ignore: avoid_print
        print('(skipped $what) ${e.toString().split('\n').first}');
      }
      drain();
    }

    // ---- the lab: sky posters under glass, close up ------------------
    final sky = SceneCatalog.inTab('sky').take(9).toList();
    final chosen = ValueNotifier<int>(-1);
    Widget lab() => Scaffold(
          backgroundColor: AppColors.bg,
          body: Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              key: labKey,
              child: SizedBox(
                height: 470,
                child: ColoredBox(
                  color: AppColors.bg,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 9 / 16,
                    ),
                    itemCount: sky.length,
                    itemBuilder: (_, i) => ValueListenableBuilder<int>(
                      valueListenable: chosen,
                      builder: (_, c, __) =>
                          _LabTile(scene: sky[i], selected: c == i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    Rect tile(int i) => t.getRect(find.byType(GlassTile).at(i));
    Rect around(int i) => tile(i).inflate(12);

    // At rest, and as the slow light drifts over it.
    await scene(lab());
    await shoot('lab_rest', of: labKey, ratio: 2);
    final drift = <ui.Image>[];
    for (final ms in const [800, 2400, 2400]) {
      await run(ms);
      drift.add(await grab(of: labKey, ratio: 1.2));
    }
    await sheet('lab_drift_0.8s_3.2s_5.6s', drift, columns: 3);

    // A finger high on the right of the middle tile, held, then let go.
    await scene(lab());
    var r = tile(1);
    var g = await t.startGesture(
        r.topRight + Offset(-r.width * 0.18, r.height * 0.14));
    final touch = <ui.Image>[];
    for (final ms in const [80, 100, 120, 150, 450]) {
      await run(ms);
      touch.add(await grab(of: labKey, ratio: 3, crop: around(1)));
    }
    await g.up();
    for (final ms in const [300, 900]) {
      await run(ms);
      touch.add(await grab(of: labKey, ratio: 3, crop: around(1)));
    }
    await sheet('touch_80_180_300_450_900_up300_up1200', touch);
    await run(2400);

    // Held, then slid down a row and across.
    await scene(lab());
    r = tile(1);
    g = await t.startGesture(r.center);
    await run(200);
    await g.moveBy(const Offset(0, 14));
    await run(48);
    await g.moveTo(tile(4).center + const Offset(-20, -30));
    await run(160);
    final slide = <ui.Image>[await grab(of: labKey, ratio: 1.4)];
    await g.moveTo(tile(5).centerLeft + const Offset(18, 40));
    await run(200);
    slide.add(await grab(of: labKey, ratio: 1.4));
    await g.up();
    await sheet('slide_down_across', slide, columns: 2);
    await run(3200);

    // Chosen: the run of light round the edge.
    await scene(lab());
    await t.tap(find.byType(GlassTile).at(4));
    chosen.value = 4;
    await t.pump();
    final ring = <ui.Image>[];
    for (final ms in const [240, 160, 160, 160, 160, 160]) {
      await run(ms);
      ring.add(await grab(of: labKey, ratio: 3, crop: around(4)));
    }
    await sheet('ring_240_to_1040_by_160', ring, columns: 6);
    await run(3000);
    chosen.value = -1;

    // Less motion asked for: the light, no lean.
    await scene(lab(), still: true);
    r = tile(1);
    g = await t.startGesture(
        r.topRight + Offset(-r.width * 0.18, r.height * 0.14));
    final still = <ui.Image>[];
    for (final ms in const [180, 300]) {
      await run(ms);
      still.add(await grab(of: labKey, ratio: 3, crop: around(1)));
    }
    await g.up();
    await sheet('still_touch_180_480', still, columns: 2);
    await run(3000);

    // ---- the scenery screen itself ----------------------------------
    await attempt('scenery screen', () async {
      SettingsService.state.value = AppSettings.defaults
          .copyWith(sceneryTourDone: true, sceneTab: 'sky');
      creationState
        ..startNewReel()
        ..selectReciter(reciters.first)
        ..selectSurah(1)
        ..selectRange(1, 4)
        ..selectBackground(backgrounds.first);
      await scene(const BackgroundScreen());
      await decode(14);
      await run(1200);
      final screen = <ui.Image>[await grab(ratio: 1.2)];
      final at = t.getRect(find.byType(GlassTile).at(2));
      final finger = await t.startGesture(
          at.topLeft + Offset(at.width * 0.2, at.height * 0.2));
      await run(260);
      screen.add(await grab(ratio: 1.2));
      await finger.up();
      await run(3200);
      await t.drag(find.byType(CustomScrollView).first, const Offset(0, -420));
      await decode(6);
      await run(600);
      screen.add(await grab(ratio: 1.2));
      await sheet('scenery_rest_touch_scrolled', screen, columns: 3);
    });

    // ---- the name, written in ---------------------------------------
    Widget wordmark() => Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(
            child: RepaintBoundary(
              key: markKey,
              child: SizedBox(
                width: 240,
                height: 64,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/backgrounds/aurora_pexels_01.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x660D1117)),
                    ),
                    Center(
                      child: Sheen(
                        period: const Duration(milliseconds: 9000),
                        strength: 0.34,
                        phase: 0.5,
                        child: GildedWriting(
                          'AyahReel',
                          maxLines: 1,
                          style: plainTheme().textTheme.labelSmall!.copyWith(
                                fontSize: 15,
                                height: 1.0,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    await attempt('wordmark', () async {
      // The picture decodes while the clock stands still, so the first
      // frame taken is the name's first frame.
      await scene(wordmark());
      final frames = <ui.Image>[];
      var clock = 0;
      for (final ms in const [
        0, 160, 320, 480, 640, 800, 960, 1120, 1280, 1440, 1600, //
      ]) {
        await run(ms - clock);
        clock = ms;
        frames.add(await grab(of: markKey, ratio: 3));
      }
      // The sheen's first pass, four and a half seconds in.
      await run(4500 + 1600 - clock);
      frames.add(await grab(of: markKey, ratio: 3));
      await sheet('wordmark_0_to_1600_by_160_then_sheen', frames, columns: 2);
    });

    // ---- a toast landing ---------------------------------------------
    await attempt('toast', () async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(app(const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppToast(
                  message: 'Saved to your gallery and My Reels',
                  tone: ToastTone.done),
              SizedBox(height: 40),
            ],
          ),
        ),
      )));
      final frames = <ui.Image>[];
      var clock = 0;
      for (final ms in const [480, 640, 800, 960]) {
        await run(ms - clock);
        clock = ms;
        final card = t.getRect(find.byType(AppToast));
        frames.add(await grab(
            ratio: 4,
            crop: Rect.fromLTWH(card.left, card.top - 8, 150, card.height + 16)));
      }
      await sheet('toast_480_640_800_960', frames);
    });

    // ---- My Reels and the card's scenery under a finger --------------
    final more = <ui.Image>[];
    await attempt('my reels', () async {
      SavedReel reel(String surah, int from, int to, int day) => SavedReel(
            id: 'r$day',
            fileName: 'reel_r$day.mp4',
            reciterName: 'Mishary Alafasy',
            surahName: surah,
            startAyah: from,
            endAyah: to,
            gradientArgb: const [0xFF2A3A55, 0xFF0B0F17],
            createdAt: DateTime(2026, 6, day),
          );
      final reels = [
        reel('Al-Fatiha', 1, 7, 1),
        reel('Al-Mulk', 1, 5, 2),
        reel('Ya-Sin', 1, 12, 3),
        reel('Ar-Rahman', 1, 13, 4),
      ];
      final docs = Directory('$out/reels')..createSync(recursive: true);
      for (final r in reels) {
        File('${docs.path}/${r.fileName}').writeAsBytesSync(const [0]);
      }
      File('${docs.path}/library.json').writeAsStringSync(
          jsonEncode([for (final r in reels.reversed) r.toJson()]));
      await scene(const Scaffold(body: MyReelsScreen()));
      for (var i = 0; i < 12; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump();
      }
      await run(600);
      final at = t.getRect(find.byType(GlassTile).first);
      // Held without letting go: a lift would be a tap, and open the
      // reel.
      final finger = await t.startGesture(
          at.topLeft + Offset(at.width * 0.25, at.height * 0.2));
      await run(300);
      more.add(await grab(ratio: 1.2));
      await finger.cancel();
      await run(3200);
      docs.deleteSync(recursive: true);
    });
    await attempt('card sheet', () async {
      await scene(Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showCardSceneSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await run(500);
      await decode(12);
      await run(300);
      final at = t.getRect(find.byType(GlassTile).at(4));
      final finger = await t.startGesture(
          at.bottomRight - Offset(at.width * 0.2, at.height * 0.2));
      await run(300);
      more.add(await grab(ratio: 1.2));
      await finger.cancel();
      await run(3200);
    });
    await sheet('reels_and_card_sheet_touched', more, columns: 2);

    await t.pumpWidget(const SizedBox());
    await t.pump();
    chosen.dispose();
  }, skip: out == null, timeout: const Timeout(Duration(minutes: 8)));
}

/// A scenery tile as the picker draws it, for the lab.
class _LabTile extends StatelessWidget {
  final Scene scene;
  final bool selected;
  const _LabTile({required this.scene, required this.selected});

  @override
  Widget build(BuildContext context) {
    final g = scene.gradientArgb;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: GlassTile(
        key: ValueKey(scene.id),
        radius: 14,
        selected: selected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.gold : AppColors.stroke,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: GlassDepth(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(g[0]), Color(g[1])],
                      ),
                    ),
                  ),
                  Image.asset(scene.thumbAsset, fit: BoxFit.cover),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
