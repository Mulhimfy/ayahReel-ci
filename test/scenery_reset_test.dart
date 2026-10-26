import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/glow_button.dart';

/// The scenery screen's reset lets go of every scenery chosen for the
/// reel, and its notices rise over the button at its foot instead of
/// sitting on it.
void main() {
  late List<Scene> bundled;

  setUpAll(() async {
    await SceneCatalog.load();
    bundled = SceneCatalog.all.where((s) => s.bundled && !s.wide).toList();
  });

  setUp(() {
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1)
      ..selectRange(1, 7)
      ..setLayout(ReelLayout.fullFrame)
      ..setMultiScene(false);
    SettingsService.state.value =
        AppSettings.defaults.copyWith(sceneryTourDone: true);
  });

  tearDown(() {
    SettingsService.state.value = AppSettings.defaults;
    creationState.setMultiScene(false);
  });

  Finder reset() => find.byTooltip('Reset');

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(SceneCatalog.load);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const BackgroundScreen(),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('no reset until something is chosen', (t) async {
    await open(t);
    expect(reset(), findsNothing);
  });

  testWidgets('reset lets go of every scenery chosen for the reel',
      (t) async {
    creationState
      ..setMultiScene(true)
      ..toggleScene(SceneCatalog.background(bundled[0]), limit: 7)
      ..toggleScene(SceneCatalog.background(bundled[1]), limit: 7)
      ..toggleScene(SceneCatalog.background(bundled[2]), limit: 7);
    await open(t);
    expect(creationState.scenes.length, greaterThan(1));
    expect(reset(), findsOneWidget);

    await t.tap(reset());
    await t.pump();
    expect(creationState.scenes, isEmpty);
    expect(creationState.backgroundChosen, isFalse);
    // Several sceneries stays on, so picking again counts from one.
    expect(creationState.multiScene, isTrue);
    expect(reset(), findsNothing);
    // Nothing to style yet: the button waits for a pick.
    final style = t.widget<GlowButton>(find.byType(GlowButton));
    expect(style.onPressed, isNull);

    // The notice it leaves sits above that button, not on it.
    await t.pump(const Duration(milliseconds: 750));
    final notice = t.getRect(find.text('Cleared. Pick your sceneries again.'));
    final button = t.getRect(find.byType(GlowButton));
    expect(notice.bottom, lessThan(button.top));
  });

  testWidgets('one scenery: reset takes it off too', (t) async {
    creationState.selectBackground(SceneCatalog.background(bundled[0]));
    await open(t);
    await t.tap(reset());
    await t.pump();
    expect(creationState.scenes, isEmpty);
    expect(creationState.background, isNull);
  });
}
