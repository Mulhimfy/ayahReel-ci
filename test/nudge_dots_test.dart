import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/rewards_service.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/nudge_dot.dart';

/// A new install is pointed at four rows — Rate, the verse widget,
/// Telegram and the name — by a dot on each, and by a dot on the
/// Settings tab that leads to them. Each row's dot goes out for good
/// the first time the row is opened, and the tab's only once all have;
/// a widget that is already on the home screen, or a name already
/// given, needs no pointing at.
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

  testWidgets('a fresh install has every row lit, and so the tab',
      (t) async {
    await t.pumpWidget(host());
    await t.pump();

    expect(dotOn(t, 'Rate AyahReel'), isTrue);
    expect(dotOn(t, 'Verse widget'), isTrue);
    expect(dotOn(t, 'Join Telegram'), isTrue);
    expect(dotOn(t, 'Your name'), isTrue);
    expect(SettingsService.state.value.nudgesPending, isTrue);
  });

  testWidgets('opening a row puts its dot out; the tab waits for both',
      (t) async {
    // The two rows added later are out of the way here; they have a
    // test of their own below.
    SettingsService.state.value = AppSettings.defaults
        .copyWith(telegramNudgeSeen: true, nameNudgeSeen: true);
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

  testWidgets('the Telegram and name rows go out when opened', (t) async {
    await t.pumpWidget(host());
    await t.pump();

    await t.tap(find.text('Join Telegram'));
    await t.pump();
    expect(SettingsService.state.value.telegramNudgeSeen, isTrue);
    expect(dotOn(t, 'Join Telegram'), isFalse);
    // No browser under test: the row says the link did not open.
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.text('Your name'));
    await t.pump();
    expect(SettingsService.state.value.nameNudgeSeen, isTrue);
    // (The row's own dot is behind the name dialog now; the flag is
    // what lights it.)
    expect(SettingsService.state.value.nameNudgePending, isFalse);
    expect(SettingsService.state.value.nudgesPending, isTrue,
        reason: 'Rate and the widget are still waiting');
  });

  test('a name already given needs no dot', () {
    final named = AppSettings.defaults.copyWith(
      name: 'Yusuf',
      rateNudgeSeen: true,
      widgetNudgeSeen: true,
      telegramNudgeSeen: true,
    );
    expect(named.nameNudgePending, isFalse);
    expect(named.nudgesPending, isFalse);
    expect(named.copyWith(name: '').nudgesPending, isTrue);
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
        .copyWith(
            rateNudgeSeen: true,
            widgetNudgeSeen: false,
            telegramNudgeSeen: true,
            nameNudgeSeen: true)
        .toJson();
    final back = AppSettings.fromJson(saved);
    expect(back.rateNudgeSeen, isTrue);
    expect(back.widgetNudgeSeen, isFalse);
    expect(back.telegramNudgeSeen, isTrue);
    expect(back.nameNudgeSeen, isTrue);
    expect(back.nudgesPending, isTrue);

    // An install from before the dots existed is pointed at both rows.
    final old = AppSettings.fromJson(const {'onboardingDone': true});
    expect(old.nudgesPending, isTrue);
  });
}
