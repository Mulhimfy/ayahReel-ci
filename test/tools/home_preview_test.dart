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

import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/home_shell.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// Draws Home on a desk, so its opening frame, the Create button and
/// the choice it opens can be looked at without a phone: the top of the
/// page in English and in Arabic, the page scrolled to its verse card
/// and shelf, and the choice of a reel, a quiz or a card as it rises out
/// of the button, frame by frame. Skipped unless pointed somewhere:
///
///   STYLE_PREVIEW_OUT=/tmp/home flutter test test/tools/home_preview_test.dart
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

  testWidgets('home preview', (t) async {
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

    void drain() {
      for (var e = t.takeException(); e != null; e = t.takeException()) {
        // ignore: avoid_print
        print('note: ${e.toString().split('\n').first}');
      }
    }

    Future<ui.Image> grab({double ratio = 2}) async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = (await t.runAsync(() => b.toImage(pixelRatio: ratio)))!;
      drain();
      return image;
    }

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

    Widget app() => RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [for (final l in AppLang.values) Locale(l.code)],
            home: const HomeShell(),
          ),
        );

    /// Real time for the pictures to decode, then frames for them.
    Future<void> settle([int rounds = 12]) async {
      for (var i = 0; i < rounds; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 60));
      }
      drain();
    }

    for (final lang in [AppLang.en, AppLang.ar]) {
      SettingsService.state.value =
          AppSettings.defaults.copyWith(lang: lang, name: 'Amina');
      await t.pumpWidget(app());
      await settle(20);
      await t.pump(const Duration(seconds: 2));
      await settle();
      await sheet('home_${lang.code}', [await grab()], columns: 1);

      if (lang == AppLang.en) {
        // The page under the picture: the verse card over the join, and
        // the shelf.
        await t.drag(find.byType(ListView).first, const Offset(0, -420));
        await settle();
        await sheet('home_scrolled', [await grab()], columns: 1);
        await t.drag(find.byType(ListView).first, const Offset(0, 420));
        await settle();

        // The choice, rising out of the button.
        await t.tap(find.text(L10n.en.createButton));
        final frames = <ui.Image>[];
        var at = 0;
        for (final ms in [60, 140, 220, 320, 440, 600, 800, 1400]) {
          await t.pump(Duration(milliseconds: ms - at));
          at = ms;
          frames.add(await grab(ratio: 1));
        }
        await sheet('chooser', frames, columns: 4);
        await sheet('chooser_open', [await grab()], columns: 1);
        // Closing — a tap on the frosted page — runs it back into the
        // button.
        await t.tapAt(const Offset(24, 120));
        final closing = <ui.Image>[];
        at = 0;
        for (final ms in [80, 200, 320, 460]) {
          await t.pump(Duration(milliseconds: ms - at));
          at = ms;
          closing.add(await grab(ratio: 1));
        }
        await sheet('chooser_closing', closing, columns: 4);
        await settle(30);
      }
      await t.pumpWidget(const SizedBox());
      await settle(4);
    }
    SettingsService.state.value = AppSettings.defaults;
  }, skip: out == null, timeout: const Timeout(Duration(minutes: 8)));
}
