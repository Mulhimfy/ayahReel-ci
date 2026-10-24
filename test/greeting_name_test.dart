import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// The name is the one piece of the user in the app, and it lands in
/// the greeting they see first every time they open it. The part worth
/// pinning is the empty case: a user who never gives a name must never
/// be greeted with a dangling comma.
void main() {
  const en = L10n(AppLang.en);
  const ar = L10n(AppLang.ar);

  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  test('the greeting carries the name, in both languages', () {
    expect(en.greeting(19, name: 'Yusuf'), 'Good evening, Yusuf');
    expect(en.greeting(9, name: 'Yusuf'), 'Good morning, Yusuf');
    expect(ar.greeting(19, name: 'يوسف'), 'مساء الخير، يوسف');
  });

  test('no name means the greeting it always was', () {
    expect(en.greeting(19), 'Good evening');
    expect(en.greeting(19, name: ''), 'Good evening');
    // Whitespace is not a name either.
    expect(en.greeting(19, name: '   '), 'Good evening');
    expect(ar.greeting(19, name: ' '), 'مساء الخير');
    expect(en.greeting(2), 'Peaceful night');
  });

  test('a name is trimmed rather than pasted in as typed', () {
    expect(en.greeting(9, name: '  Yusuf '), 'Good morning, Yusuf');
  });

  Widget host() => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SettingsScreen(permissionCheck: () async => true),
        ),
      );

  testWidgets('Settings invites a name, then reports the one given',
      (t) async {
    await t.pumpWidget(host());
    await t.pump();

    expect(find.text('Your name'), findsOneWidget);
    // No name yet: the end of the row is empty.
    expect(find.text('Yusuf'), findsNothing);

    await t.tap(find.text('Your name'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Yusuf');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(SettingsService.state.value.name, 'Yusuf');
    // The name given sits at the end of the row.
    expect(find.text('Yusuf'), findsOneWidget);
  });

  testWidgets('the same row takes the name back off', (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(name: 'Yusuf');
    await t.pumpWidget(host());
    await t.pump();

    await t.tap(find.text('Your name'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();

    expect(SettingsService.state.value.name, '');
    expect(find.text('Yusuf'), findsNothing);
  });

  testWidgets('dismissing the prompt changes nothing', (t) async {
    SettingsService.state.value =
        AppSettings.defaults.copyWith(name: 'Yusuf');
    await t.pumpWidget(host());
    await t.pump();

    await t.tap(find.text('Your name'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Someone else');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(SettingsService.state.value.name, 'Yusuf');
  });
}
