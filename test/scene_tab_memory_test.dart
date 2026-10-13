import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// Which tab the scenery picker opens on.
///
/// Sky until the user says otherwise, then whatever they last browsed —
/// and never the tab of the stand-in background the screen falls back
/// to when nothing has been chosen, which used to land everybody on
/// Abstract.
void main() {
  setUp(() {
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1)
      ..selectRange(1, 4);
    // A reel keeps the scenery the last one ended on, so the singleton
    // arrives here carrying whatever the previous test picked. Empty it
    // back to the fresh-install state each test starts from.
    final carried = creationState.background;
    if (carried != null) creationState.toggleScene(carried, limit: 4);
    // The walkthrough would cover the rail with coach marks.
    SettingsService.state.value =
        AppSettings.defaults.copyWith(sceneryTourDone: true);
  });

  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  Widget host() => MaterialApp(
        theme: AppTheme.dark(),
        home: const BackgroundScreen(),
      );

  /// Opens the screen with the catalog already read — see the tour
  /// test: the asset read is real I/O and needs [runAsync].
  Future<void> open(WidgetTester t) async {
    await t.runAsync(SceneCatalog.load);
    await t.pumpWidget(host());
    await t.pump();
    await t.pump();
  }

  /// The rail's open tab is the one drawn in the selected weight. The
  /// rail is a lazy horizontal list, so only the tabs near the start
  /// are built — every tab asserted on here is one of those.
  bool railHas(WidgetTester t, String label) {
    final f = find.text(label);
    expect(f, findsOneWidget, reason: '$label is not on the rail');
    return t.widget<Text>(f).style?.fontWeight == FontWeight.w600;
  }

  testWidgets('opens on Sky when nothing has been chosen', (t) async {
    await open(t);

    expect(railHas(t, 'Sky'), isTrue);
    expect(railHas(t, 'Mountains'), isFalse);
  });

  testWidgets('the tab last browsed outranks a carried-over scenery',
      (t) async {
    // A reel keeps the scenery the last one ended on, so after the
    // first reel there is always one — and it must not overrule the
    // one statement the user actually made about where to start.
    await t.runAsync(SceneCatalog.load);
    creationState.selectBackground(SceneCatalog.background(
        SceneCatalog.all.firstWhere((s) => s.tab == 'water' && !s.wide)));
    SettingsService.state.value =
        SettingsService.state.value.copyWith(sceneTab: 'desert');

    await open(t);

    expect(railHas(t, 'Desert'), isTrue);
    expect(railHas(t, 'Sky'), isFalse);
  });

  testWidgets('a saved tab the library no longer has falls back to Sky',
      (t) async {
    SettingsService.state.value =
        SettingsService.state.value.copyWith(sceneTab: 'volcanoes');

    await open(t);

    expect(railHas(t, 'Sky'), isTrue);
  });

  testWidgets('tapping a tab is what gets remembered', (t) async {
    await open(t);

    await t.tap(find.text('Desert'));
    await t.pump();

    expect(railHas(t, 'Desert'), isTrue);
    expect(SettingsService.state.value.sceneTab, 'desert');
  });

  testWidgets('a second visit still opens on Sky when nothing was picked',
      (t) async {
    // The regression this file's header describes, and the one the
    // first fix left standing. The screen seeds a stand-in background
    // on the way in so the renderer always has a picture, and
    // startNewReel keeps a background across reels — so from the second
    // visit onward there is always a non-null one. Read as a choice,
    // that stand-in is `backgrounds.first`, which is an Abstract scene:
    // every user who opened the picker once and picked nothing landed
    // on Abstract for good.
    await open(t);
    expect(railHas(t, 'Sky'), isTrue);

    // Leave without touching a thing, and come back.
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(creationState.background, isNotNull,
        reason: 'the stand-in should still be seated — that is the trap');
    expect(creationState.backgroundChosen, isFalse,
        reason: 'but seating it is not choosing it');

    await open(t);

    // Abstract sits too far along the rail to be built, so it is
    // named here rather than asserted on: only one tab is ever drawn
    // selected, and Sky holding it is Abstract not holding it.
    expect(creationState.background!.id, startsWith('abstract_'),
        reason: 'the stand-in is still an Abstract scene — that is the trap');
    expect(railHas(t, 'Sky'), isTrue);
    expect(railHas(t, 'Mountains'), isFalse);
  });

  testWidgets('a scenery already chosen still opens on its own tab',
      (t) async {
    // Coming back from the preview, or in from a featured template: the
    // ring belongs on screen, not four tabs away.
    await t.runAsync(SceneCatalog.load);
    final water =
        SceneCatalog.all.firstWhere((s) => s.tab == 'water' && !s.wide);
    creationState.selectBackground(SceneCatalog.background(water));

    await open(t);

    expect(railHas(t, 'Water'), isTrue);
    expect(railHas(t, 'Sky'), isFalse);
  });
}
