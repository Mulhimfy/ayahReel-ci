import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// The scenery screen carries four controls a first-time user has no
/// way to guess at — the tab rail, the multi-scene pill, the frame, and
/// what the wide card opens up. The walkthrough is what tells them, and
/// it has exactly one chance: it is shown on the first visit and never
/// again. These pin that it comes up, walks in order, cannot be
/// dropped part-way, and marks itself seen at the end.
void main() {
  setUp(() {
    // A four-verse reel: enough room for several sceneries, so the
    // multi-scene pill — and its step — is on screen.
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1)
      ..selectRange(1, 4)
      ..selectBackground(backgrounds.first);
    SettingsService.state.value =
        AppSettings.defaults.copyWith(sceneryTourDone: false);
  });

  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  Widget host() => MaterialApp(
        theme: AppTheme.dark(),
        home: const BackgroundScreen(),
      );

  /// Opens the screen with the catalog already in hand.
  ///
  /// The walkthrough waits for the catalog — an empty rail has nothing
  /// to point at — and reading the asset is real I/O, which a pumped
  /// test's fake clock would never let finish. [WidgetTester.runAsync]
  /// is where that read is allowed to happen; the screen's own load
  /// then returns from the cache on the first frame.
  Future<void> open(WidgetTester t) async {
    await t.runAsync(SceneCatalog.load);
    await t.pumpWidget(host());
    await t.pump();
    await t.pump();
  }

  testWidgets('first visit is walked through, in order', (t) async {
    await open(t);

    expect(find.text('Pick a mood'), findsOneWidget);
    expect(find.text('1 of 4'), findsOneWidget);

    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('More than one scene'), findsOneWidget);

    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('The frame'), findsOneWidget);

    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('Corners and edges'), findsOneWidget);
    expect(find.textContaining('next screen'), findsOneWidget);

    await t.tap(find.text('Got it'));
    await t.pump();

    expect(find.text('Corners and edges'), findsNothing);
    expect(SettingsService.state.value.sceneryTourDone, isTrue);
  });

  testWidgets('it cannot be dropped part-way', (t) async {
    await open(t);

    // One chance at four controls, and only OK spends it: there is no
    // Skip, and a tap on the dimmed screen neither ends the tour nor
    // skips the card it is holding.
    expect(find.text('Skip'), findsNothing);
    await t.tapAt(const Offset(12, 12));
    await t.pump();

    expect(find.text('Pick a mood'), findsOneWidget);
    expect(SettingsService.state.value.sceneryTourDone, isFalse);

    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('More than one scene'), findsOneWidget);
  });

  testWidgets('a second visit is left alone', (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(sceneryTourDone: true);
    await open(t);

    expect(find.text('Pick a mood'), findsNothing);
    // The screen itself is untouched by the walkthrough's absence.
    expect(find.text('Choose the scenery'), findsOneWidget);
  });
}
