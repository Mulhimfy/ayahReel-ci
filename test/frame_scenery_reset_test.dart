import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// Changing the frame changes what a scenery is: the wide card wants
/// 16:9 footage, the full frame upright. A selection made for the frame
/// the user just left cannot ride along into the one they moved to —
/// these pin that it is dropped, that the screen says so, and that the
/// user's own photo is never what gets thrown away.
void main() {
  late Scene upright;
  late Scene wide;

  setUpAll(() async {
    await SceneCatalog.load();
    upright = SceneCatalog.all.firstWhere((s) => !s.wide);
    wide = SceneCatalog.all.firstWhere((s) => s.wide);
  });

  setUp(() {
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1)
      ..selectRange(1, 4)
      ..setMultiScene(false);
    // Coach marks would cover the frame pills.
    SettingsService.state.value =
        AppSettings.defaults.copyWith(sceneryTourDone: true);
  });

  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  Future<void> open(WidgetTester t) async {
    await t.runAsync(SceneCatalog.load);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const BackgroundScreen(),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('the wide card drops a scenery picked for the full frame',
      (t) async {
    creationState
      ..setLayout(ReelLayout.fullFrame)
      ..selectBackground(SceneCatalog.background(upright));
    await open(t);

    await t.tap(find.text('Wide card'));
    await t.pump();

    expect(creationState.scenes, isEmpty);
    expect(creationState.background, isNull);
    expect(find.text('Pick a scenery for the new frame'), findsOneWidget);
  });

  testWidgets('the full frame drops a scenery picked for the wide card',
      (t) async {
    creationState
      ..setLayout(ReelLayout.letterbox)
      ..selectBackground(SceneCatalog.background(wide));
    await open(t);

    await t.tap(find.text('Full frame'));
    await t.pump();

    expect(creationState.scenes, isEmpty);
    expect(find.text('Pick a scenery for the new frame'), findsOneWidget);
  });

  testWidgets('a scenery that fits the new frame is left alone', (t) async {
    // The wide card is being chosen for footage already shot for it —
    // nothing here is out of place, so nothing goes.
    creationState
      ..setLayout(ReelLayout.fullFrame)
      ..selectBackground(SceneCatalog.background(wide));
    await open(t);

    await t.tap(find.text('Wide card'));
    await t.pump();

    expect(creationState.background?.id, wide.id);
    expect(find.text('Pick a scenery for the new frame'), findsNothing);
  });

  testWidgets("the user's own photo survives the frame changing", (t) async {
    creationState
      ..setLayout(ReelLayout.fullFrame)
      ..selectBackground(const ReelBackground.deviceFile(
        id: 'custom_abc123',
        name: 'From gallery',
        filePath: '/tmp/mine.jpg',
        fileIsImage: true,
      ));
    await open(t);

    await t.tap(find.text('Wide card'));
    await t.pump();

    expect(creationState.background?.id, 'custom_abc123');
    expect(find.text('Pick a scenery for the new frame'), findsNothing);
  });

  testWidgets('a run drops only the scenes the new frame cannot take',
      (t) async {
    final upright2 = SceneCatalog.all.firstWhere(
        (s) => !s.wide && s.id != upright.id);
    creationState
      ..setLayout(ReelLayout.letterbox)
      ..setMultiScene(true)
      ..selectBackground(SceneCatalog.background(wide))
      ..toggleScene(SceneCatalog.background(upright), limit: 4)
      ..toggleScene(SceneCatalog.background(upright2), limit: 4);
    expect(creationState.scenes.length, 3);
    await open(t);

    await t.tap(find.text('Full frame'));
    await t.pump();

    expect(creationState.scenes.map((b) => b.id),
        [upright.id, upright2.id]);
    // The run reopens on what is left, in the order it was picked.
    expect(creationState.background?.id, upright.id);
  });

  test('dropScenes keeps the run in order and answers how many went', () {
    creationState
      ..startNewReel()
      ..setMultiScene(true)
      ..selectBackground(SceneCatalog.background(wide))
      ..toggleScene(SceneCatalog.background(upright), limit: 4);

    expect(creationState.dropScenes((b) => b.id != wide.id), 1);
    expect(creationState.scenes.single.id, upright.id);
    // Weights stay as long as the run they belong to.
    expect(creationState.sceneWeights.length, 1);
    // Nothing to drop is not a change, and must not be reported as one.
    expect(creationState.dropScenes((_) => true), 0);
  });
}
