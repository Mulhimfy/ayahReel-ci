import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/offline_pack.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/offline_sheet.dart';

/// The offline sheet: every part with its size, the voice's three
/// scopes, the moving sceneries left out until ticked, and the total
/// following the choices.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SceneCatalog.load();
  });

  tearDown(OfflinePack.debugReset);

  Future<void> open(WidgetTester t) async {
    SceneCatalog.configureForTest(
        baseUrl: '', cacheDir: Directory.systemTemp.createTempSync('sc'));
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: OfflineSheet()),
    ));
    await t.pump();
  }

  String total(WidgetTester t) => t
      .widget<Text>(find.textContaining('best on Wi-Fi'))
      .data!;

  testWidgets('each part says its size, and the total follows the ticks',
      (t) async {
    await open(t);
    expect(find.text('Verses and translation'), findsOneWidget);
    expect(find.text('Still sceneries'), findsOneWidget);
    expect(find.text('Moving sceneries'), findsOneWidget);
    expect(find.text('Whole Quran'), findsOneWidget);
    expect(find.text("Juz' 30"), findsOneWidget);
    // The moving sceneries say their size though they are not ticked.
    final clips = OfflinePack.sceneBytes(clips: true);
    expect(clips, greaterThan(100 * 1000 * 1000));
    expect(find.textContaining(OfflineSheet.sizeLabel(clips)), findsOneWidget);

    final before = total(t);
    await t.tap(find.text('Moving sceneries'));
    await t.pump();
    expect(total(t), isNot(before), reason: 'ticking them adds their size');

    final withClips = total(t);
    await t.tap(find.text("Juz' 30"));
    await t.pump();
    expect(total(t), isNot(withClips), reason: "Juz' 30 is less than all");
  });

  testWidgets('Download starts the run, which the sheet then shows',
      (t) async {
    await open(t);
    await t.tap(find.text('None'));
    await t.tap(find.text('Still sceneries'));
    await t.pump();
    expect(OfflinePack.state.value.stage, OfflineStage.idle);
    await t.tap(find.text('Download'));
    await t.pump();
    expect(OfflinePack.state.value.stage, isNot(OfflineStage.idle));
    OfflinePack.stop();
    await t.pumpWidget(const SizedBox());
  });
}
