import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/rewards_service.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/nudge_dot.dart';

/// A new install is pointed at two rows — Rate and the verse widget —
/// by a dot on each, and by a dot on the Settings tab that leads to
/// them. Each row's dot goes out for good the first time the row is
/// opened, and the tab's only once both have; a widget that is already
/// on the home screen needs no pointing at.
void main() {
  Widget host({bool widgetInstalled = false}) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SettingsScreen(
            permissionCheck: () async => true,
            widgetCheck: () async => widgetInstalled,
          ),
        ),
      );

  setUp(RewardsService.resetForTest);
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  /// Whether the dot on the row titled [title] is lit.
  bool dotOn(WidgetTester t, String title) {
    final row = find
        .ancestor(of: find.text(title), matching: find.byType(InkWell))
        .first;
    return t
        .widget<NudgeDot>(
            find.descendant(of: row, matching: find.byType(NudgeDot)))
        .on;
  }

  testWidgets('a fresh install has both rows lit, and so the tab',
      (t) async {
    await t.pumpWidget(host());
    await t.pump();

    expect(dotOn(t, 'Rate AyahReel'), isTrue);
    expect(dotOn(t, 'Verse widget'), isTrue);
    expect(SettingsService.state.value.nudgesPending, isTrue);
  });

  testWidgets('opening a row puts its dot out; the tab waits for both',
      (t) async {
    await t.pumpWidget(host());
    await t.pump();

    await t.tap(find.text('Rate AyahReel'));
    await t.pump();
    expect(SettingsService.state.value.rateNudgeSeen, isTrue);
    expect(SettingsService.state.value.widgetNudgeSeen, isFalse);
    expect(SettingsService.state.value.nudgesPending, isTrue,
        reason: 'one row opened is not both');

    // Close the rate sheet the tap opened.
    await t.tapAt(const Offset(10, 10));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    await t.tap(find.text('Verse widget'));
    await t.pump();
    expect(SettingsService.state.value.widgetNudgeSeen, isTrue);
    expect(SettingsService.state.value.nudgesPending, isFalse);
  });

  testWidgets('a dot, once out, stays out', (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(rateNudgeSeen: true);
    await t.pumpWidget(host());
    await t.pump();

    expect(dotOn(t, 'Rate AyahReel'), isFalse);
    expect(dotOn(t, 'Verse widget'), isTrue);
  });

  testWidgets('a widget already on the home screen retires its own dot',
      (t) async {
    await t.pumpWidget(host(widgetInstalled: true));
    await t.pump();
    await t.pump();

    expect(SettingsService.state.value.widgetNudgeSeen, isTrue);
    expect(dotOn(t, 'Verse widget'), isFalse);
    expect(dotOn(t, 'Rate AyahReel'), isTrue);
  });

  test('the flags survive a round trip through the settings file', () {
    final saved = AppSettings.defaults
        .copyWith(rateNudgeSeen: true, widgetNudgeSeen: false)
        .toJson();
    final back = AppSettings.fromJson(saved);
    expect(back.rateNudgeSeen, isTrue);
    expect(back.widgetNudgeSeen, isFalse);
    expect(back.nudgesPending, isTrue);

    // An install from before the dots existed is pointed at both rows.
    final old = AppSettings.fromJson(const {'onboardingDone': true});
    expect(old.nudgesPending, isTrue);
  });
}
