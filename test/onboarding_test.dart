import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/onboarding_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/shimmer_text.dart';

/// Onboarding is the only screen every single user sees, and it carries
/// eight pages of text through a PageView — the most overflow-prone
/// shape in the app. These pump it at the smallest phone we support and
/// walk every page; any RenderFlex overflow fails the test on its own.
void main() {
  // The language page writes straight through to settings, and the
  // store is a process-wide notifier: hand the next test a clean one.
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  /// Wrapped the way main.dart wraps it — the locale is what carries a
  /// language change down to every page, so a host without it could
  /// not see page 1 do its job.
  Widget host({VoidCallback? onDone}) =>
      ValueListenableBuilder<AppSettings>(
        valueListenable: SettingsService.state,
        builder: (context, s, _) => MaterialApp(
          theme: AppTheme.dark(lang: s.lang),
          locale: s.arabic ? const Locale('ar') : const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: OnboardingScreen(onDone: onDone ?? () {}),
        ),
      );

  // The word-glow and the ripple emblem loop forever by design, so the
  // tree never goes quiet: pumpAndSettle would hang. Everything here
  // advances by fixed durations instead. Layout still runs on every
  // pump, so an overflow would still blow the test up.

  /// Swipes forward exactly one page. Forward is leftward in English
  /// and rightward once page 1 has turned the app Arabic.
  Future<void> advance(WidgetTester t) async {
    final width = t.getSize(find.byType(PageView)).width;
    final sign = SettingsService.state.value.arabic ? 1.0 : -1.0;
    // Past the half-page snap threshold, short of two pages.
    await t.drag(find.byType(PageView), Offset(sign * width * 0.7, 0));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
  }

  void sizePhone(WidgetTester t, Size logical) {
    t.view.physicalSize = Size(logical.width * 3, logical.height * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('walks all eight pages on a small phone without overflowing',
      (t) async {
    sizePhone(t, const Size(360, 640));
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 400));

    // 1 · the language
    expect(find.text('English'), findsOneWidget);
    await advance(t);
    // 2 · the dream
    expect(find.textContaining('travel'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      await advance(t);
    }
    // 8 · the reminder, now the last page — Skip is gone from it. Skip
    // fades rather than unmounts, so assert on what the user sees.
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(
      t
          .widget<AnimatedOpacity>(find.ancestor(
            of: find.text('Skip'),
            matching: find.byType(AnimatedOpacity),
          ))
          .opacity,
      0,
    );
  });

  testWidgets('holds up on a large phone too', (t) async {
    sizePhone(t, const Size(430, 932));
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 7; i++) {
      await advance(t);
    }
    expect(find.text('Allow notifications'), findsOneWidget);
  });

  testWidgets('it opens on the language question, and Skip cannot answer it',
      (t) async {
    sizePhone(t, const Size(390, 844));
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 400));

    expect(find.text('FIRST, YOUR LANGUAGE'), findsOneWidget);
    // Both cards name themselves in their own script, so each one is
    // legible to the reader it is for.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    // Only Arabic and English until More is asked for.
    expect(find.text('اردو'), findsNothing);
    await t.ensureVisible(find.text('More languages'));
    await t.tap(find.text('More languages'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('اردو'), findsOneWidget);
    expect(find.text('More languages'), findsNothing);
    // English until they say otherwise — nothing is decided for them
    // and nothing is left undecided either.
    expect(SettingsService.state.value.arabic, isFalse);

    // The corner Skip is withheld here: beside a question, it reads as
    // an answer to it, and this is the page that has to be answered.
    expect(
      t
          .widget<AnimatedOpacity>(find.ancestor(
            of: find.text('Skip'),
            matching: find.byType(AnimatedOpacity),
          ))
          .opacity,
      0,
    );
  });

  testWidgets('choosing Arabic turns the whole flow on the spot', (t) async {
    sizePhone(t, const Size(390, 844));
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 400));

    await t.tap(find.text('العربية'));
    await t.pump(const Duration(milliseconds: 400));

    expect(SettingsService.state.value.arabic, isTrue);
    // The page the finger is still on is already Arabic — that is the
    // whole confirmation, since there is nothing else here to press.
    expect(find.text('أولًا، لغتك'), findsOneWidget);
    expect(Directionality.of(t.element(find.byType(PageView))),
        TextDirection.rtl);

    // Changing their mind puts it straight back, on the same page.
    await t.tap(find.text('English'));
    await t.pump(const Duration(milliseconds: 400));
    expect(SettingsService.state.value.arabic, isFalse);
    expect(find.text('FIRST, YOUR LANGUAGE'), findsOneWidget);

    // And the argument behind it turns with it.
    await t.tap(find.text('العربية'));
    await t.pump(const Duration(milliseconds: 400));
    await advance(t);
    expect(find.text('الغاية من هذا'), findsOneWidget);
  });

  testWidgets('the argument runs dream → problem → answer → reward',
      (t) async {
    sizePhone(t, const Size(390, 844));
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 400));

    await advance(t);
    expect(find.text('WHAT THIS IS FOR'), findsOneWidget);
    await advance(t);
    expect(find.text('WHAT IS IN THE WAY'), findsOneWidget);
    await advance(t);
    expect(find.text('SO HERE IS THE TURN'), findsOneWidget);
    await advance(t);
    expect(find.text('AND WHAT IT IS WORTH'), findsOneWidget);
  });

  testWidgets('both slogans are carried by the word-glow', (t) async {
    sizePhone(t, const Size(390, 844));
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 400));
    await advance(t);
    await advance(t);
    await advance(t);

    // PageView keeps the neighbouring page mounted, so more than one
    // ShimmerText can be alive at once: match on the text, not on being
    // the only one.
    bool glowing(WidgetTester t, String fragment) => t
        .widgetList<ShimmerText>(find.byType(ShimmerText))
        .any((s) => s.text.contains(fragment));

    expect(glowing(t, "Be the reason there's Quran"), isTrue);
    await advance(t);
    expect(glowing(t, 'sadaqah jariyah'), isTrue);
  });

  testWidgets('the time page names the permission dialog before it opens',
      (t) async {
    sizePhone(t, const Size(390, 844));
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 7; i++) {
      await advance(t);
    }

    expect(find.text('Pick your daily moment'), findsOneWidget);
    // The default the user is nudged toward.
    expect(find.text('8:00 PM'), findsOneWidget);
    // The CTA names the system dialog it is about to open, and the fine
    // print says what will be sent. An unannounced permission prompt
    // gets refused on reflex.
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.textContaining('Your phone will ask next'), findsOneWidget);

    // Declining flips the CTA and withdraws the warning — no dialog is
    // coming any more, so promising one would be a lie. The decline sits
    // under the CTA at the foot of the screen, and goes once used.
    await t.tap(find.text('No reminder, thanks'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Begin'), findsOneWidget);
    expect(find.text('No reminder, thanks'), findsNothing);
    expect(find.textContaining('Your phone will ask next'), findsNothing);
  });
}
