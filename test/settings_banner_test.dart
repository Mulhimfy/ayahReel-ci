import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// A switch that reads "on" while the OS silently drops everything is
/// the worst state this screen can be in. The banner exists only for
/// that case, and must not appear in any other.
void main() {
  Widget host({required bool osAllows}) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SettingsScreen(permissionCheck: () async => osAllows),
        ),
      );

  const bannerText = 'Your reminders can’t reach you';

  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  testWidgets('appears when a reminder is on but the OS is blocking',
      (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(streakReminderOn: true);

    await t.pumpWidget(host(osAllows: false));
    await t.pump(); // let the permission check land

    expect(find.text(bannerText), findsOneWidget);
    expect(find.text('Open phone settings'), findsOneWidget);
  });

  testWidgets('stays away once the OS allows notifications', (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(streakReminderOn: true);

    await t.pumpWidget(host(osAllows: true));
    await t.pump();

    expect(find.text(bannerText), findsNothing);
  });

  testWidgets('stays away when the user wants no reminders at all',
      (t) async {
    SettingsService.state.value = AppSettings.defaults.copyWith(
      streakReminderOn: false,
      personalReminderOn: false,
    );

    await t.pumpWidget(host(osAllows: false));
    await t.pump();

    // Nothing is being promised, so nothing is being broken.
    expect(find.text(bannerText), findsNothing);
  });

  testWidgets('the personal reminder alone is enough to raise it',
      (t) async {
    SettingsService.state.value = AppSettings.defaults.copyWith(
      streakReminderOn: false,
      personalReminderOn: true,
    );

    await t.pumpWidget(host(osAllows: false));
    await t.pump();

    expect(find.text(bannerText), findsOneWidget);
  });

  testWidgets('never accuses the OS before the answer is back', (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(streakReminderOn: true);

    await t.pumpWidget(host(osAllows: false));
    // First frame only: the check is still in flight.
    expect(find.text(bannerText), findsNothing);

    await t.pump();
    expect(find.text(bannerText), findsOneWidget);
  });
}
