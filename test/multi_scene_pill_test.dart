import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/background_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// The multi-scene pill animates, and an animated control has one way
/// of failing that a still one does not: disappearing for part of its
/// own cycle. These walk the whole cycle and pin that the pill is on
/// screen, readable, and still takes a tap at every frame of it.
void main() {
  setUp(() {
    creationState
      ..startNewReel()
      ..selectReciter(reciters.first)
      ..selectSurah(1)
      ..selectRange(1, 4)
      ..setMultiScene(false);
    // Coach marks would cover the pill.
    SettingsService.state.value =
        AppSettings.defaults.copyWith(sceneryTourDone: true);
  });

  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  Future<void> open(WidgetTester t, {bool stillMotion = false}) async {
    await t.runAsync(SceneCatalog.load);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: stillMotion
          ? const MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: BackgroundScreen(),
            )
          : const BackgroundScreen(),
    ));
    await t.pump();
    await t.pump();
  }

  /// The pill's own cycle is 4200ms; walk a little past it.
  Future<void> walkTheCycle(
    WidgetTester t,
    void Function(int atMs) check,
  ) async {
    for (var ms = 0; ms <= 4600; ms += 100) {
      await t.pump(const Duration(milliseconds: 100));
      check(ms);
    }
  }

  testWidgets('stays on screen for every frame of the sweep', (t) async {
    await open(t);

    await walkTheCycle(t, (ms) {
      expect(find.text('Multiple scenes'), findsOneWidget,
          reason: 'the pill went missing $ms ms into the cycle');
      expect(t.takeException(), isNull, reason: 'it threw at $ms ms');
    });
  });

  testWidgets('takes a tap mid-sweep, with the light over it', (t) async {
    await open(t);
    // Into the sweep, where the band is across the middle of the pill:
    // whatever paints it must not be in front of the gesture.
    await t.pump(const Duration(milliseconds: 700));

    await t.tap(find.text('Multiple scenes'));
    await t.pump();

    expect(creationState.multiScene, isTrue);
    // The label stops being a label and becomes a count out of what
    // the reel can hold — how many that is, is the scene planner's
    // business, not this test's.
    expect(find.textContaining(' of '), findsWidgets);
  });

  testWidgets('once on, it counts and keeps breathing', (t) async {
    creationState.setMultiScene(true);
    await open(t);

    await walkTheCycle(t, (ms) {
      expect(find.textContaining(' of '), findsWidgets,
          reason: 'the count went missing $ms ms into the cycle');
    });
  });

  testWidgets('reduced motion leaves it plainly on screen', (t) async {
    await open(t, stillMotion: true);

    await walkTheCycle(t, (ms) {
      expect(find.text('Multiple scenes'), findsOneWidget,
          reason: 'the pill went missing $ms ms into the cycle');
    });
  });
}
