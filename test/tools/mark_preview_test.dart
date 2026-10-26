import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/arena_fx.dart';
import 'package:ayah_reels/widgets/tanafus_button.dart';

/// Draws the Tanafus mark on a desk, at every size it is worn at, so
/// it can be judged as a mark and not as a line of code. Skipped unless
/// it is pointed somewhere:
///
///   ARENA_PREVIEW_OUT=/tmp/mark flutter test test/tools/mark_preview_test.dart
void main() {
  final out = Platform.environment['ARENA_PREVIEW_OUT'];
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mark preview', (t) async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
    t.view.physicalSize = const Size(1500, 560);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();

    Future<void> shoot(String name, {double ratio = 2}) async {
      await t.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final f = File('$out/$name.png');
        await f.writeAsBytes(data!.buffer.asUint8List(), flush: true);
        // ignore: avoid_print
        print('wrote ${f.path}');
      });
      t.takeException();
    }

    Widget host(Widget child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
          home: RepaintBoundary(
            key: key,
            child: Material(
              color: AppColors.bg,
              child: Center(child: child),
            ),
          ),
        );

    Widget cell(String label, Widget w) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 230, width: 230, child: Center(child: w)),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        );

    // 1 · The mark alone at the sizes it is worn at, still and alive.
    await t.pumpWidget(host(Wrap(
      spacing: 0,
      runSpacing: 0,
      alignment: WrapAlignment.center,
      children: [
        cell('22', const TanafusMark(size: 22, glow: false)),
        cell('36 · glow off', const TanafusMark(size: 36, glow: false)),
        cell('64', const TanafusMark(size: 64)),
        cell('96 · story', const TanafusMark(size: 96)),
        cell('200', const TanafusMark(size: 200)),
        cell('200 · phase .3', const TanafusMark(size: 200, phase: 0.3)),
        cell('200 · phase .7', const TanafusMark(size: 200, phase: 0.7)),
        cell('120 · white', const TanafusMark(size: 120, color: Colors.white)),
      ],
    )));
    await t.pump(const Duration(milliseconds: 100));
    await shoot('mark_sizes');

    // 2 · The doors: the roundel and the FAB, on the dark and on a
    // light photograph-like wall, caught at a few moments of the turn.
    await t.pumpWidget(host(Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0E1420), Color(0xFF3B2F4A)]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++) ...[
                TanafusButton(onTap: () {}),
                const SizedBox(width: 40),
              ],
            ],
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                TanafusFab(onTap: () {}),
                const SizedBox(width: 40),
              ],
            ],
          ),
        ],
      ),
    )));
    await t.pump(const Duration(milliseconds: 100));
    await shoot('doors_a', ratio: 3);
    await t.pump(const Duration(milliseconds: 1900));
    await shoot('doors_b', ratio: 3);
    await t.pump(const Duration(milliseconds: 2100));
    await shoot('doors_c', ratio: 3);
  }, skip: out == null);
}
