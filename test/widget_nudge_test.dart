import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/widget_nudge.dart';

/// The home tab's widget nudge: back every other day until the widget
/// is actually there, and never a flash of it before the app knows.
void main() {
  final now = DateTime(2026, 9, 3, 10);

  Widget host({required bool installed, DateTime? at}) => MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: Scaffold(
          body: WidgetNudge(
            isInstalled: () async => installed,
            now: () => at ?? now,
          ),
        ),
      );

  const title = 'Put a verse on your home screen';

  setUp(() => SettingsService.state.value = AppSettings.defaults);
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  test('is due at first, and again two days after a dismissal', () {
    expect(WidgetNudge.due(AppSettings.defaults, now), isTrue);
    final dismissed = AppSettings.defaults
        .copyWith(widgetNudgeDismissedAt: now.millisecondsSinceEpoch);
    expect(WidgetNudge.due(dismissed, now), isFalse);
    expect(WidgetNudge.due(dismissed, now.add(const Duration(hours: 47))),
        isFalse);
    expect(
        WidgetNudge.due(dismissed, now.add(const Duration(days: 2))), isTrue);
  });

  testWidgets('shows once the widget is known to be missing', (t) async {
    await t.pumpWidget(host(installed: false));
    // Before the answer: nothing.
    expect(find.text(title), findsNothing);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(title), findsOneWidget);
    expect(find.text('Show me how'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('stays away once the widget is on the home screen', (t) async {
    await t.pumpWidget(host(installed: true));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(title), findsNothing);
  });

  testWidgets('Not now puts it away and remembers when', (t) async {
    await t.pumpWidget(host(installed: false));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Not now'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(title), findsNothing);
    expect(SettingsService.state.value.widgetNudgeDismissedAt,
        now.millisecondsSinceEpoch);
  });

  testWidgets('and is back two days later', (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(widgetNudgeDismissedAt: now.millisecondsSinceEpoch);
    await t.pumpWidget(
        host(installed: false, at: now.add(const Duration(days: 1))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(title), findsNothing);

    await t.pumpWidget(
        host(installed: false, at: now.add(const Duration(days: 2))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(title), findsOneWidget);
  });

  testWidgets('Show me how opens the instructions', (t) async {
    await t.pumpWidget(host(installed: false));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Show me how'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('A verse on your home screen'), findsOneWidget);
    expect(find.text('How to add it'), findsOneWidget);
  });
}
