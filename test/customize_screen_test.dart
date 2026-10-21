import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/verse_motion.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/customize_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/glow_button.dart';
import 'package:ayah_reels/widgets/surah_title.dart';
import 'package:ayah_reels/widgets/verse_stage.dart';

/// Settings → Customize, as a page: a reel plays its choices at the
/// head, and every choice below changes that reel at once and is kept.
void main() {
  tearDown(() {
    SettingsService.state.value = AppSettings.defaults;
    creationState
      ..setMotion(VerseMotion.standard)
      ..setWordHighlight(true);
  });

  Widget host({Locale locale = const Locale('en')}) => MaterialApp(
        theme: AppTheme.dark(),
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // The page's reel plays on a loop; held still, the page settles.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const CustomizeScreen(),
      );

  Future<void> open(WidgetTester t, {Locale locale = const Locale('en')}) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(host(locale: locale));
    await t.pumpAndSettle();
  }

  Finder page() => find
      .descendant(
          of: find.byType(CustomizeScreen), matching: find.byType(Scrollable))
      .first;

  Future<void> reach(WidgetTester t, Finder f) async {
    await t.scrollUntilVisible(f, 200, scrollable: page());
    await t.pumpAndSettle();
  }

  VerseStage stage(WidgetTester t) => t.widget<VerseStage>(find.byType(VerseStage));

  /// Back up to the reel at the head of the page, which the list lets go
  /// of while it is scrolled out of sight.
  Future<void> top(WidgetTester t) async {
    await t.scrollUntilVisible(find.byType(VerseStage), -300,
        scrollable: page());
    await t.pumpAndSettle();
  }

  Color? colourOf(WidgetTester t, String text) =>
      t.widget<Text>(find.text(text)).style?.color;

  testWidgets('a new install: one line at a time, the light, no surah name',
      (t) async {
    await open(t);
    expect(find.byType(VerseStage), findsOneWidget);
    expect(find.byType(SurahTitleLine), findsNothing);
    expect(colourOf(t, 'Line by line'), AppColors.goldBright);
    expect(colourOf(t, '1'), AppColors.goldBright);
    expect(colourOf(t, '2'), isNot(AppColors.goldBright));
    expect(stage(t).motion, VerseMotion.standard);
    // Ayat al-Kursi a line at a time is several lines.
    expect(stage(t).units.length, greaterThan(3));
    // Nothing to put back yet.
    await reach(t, find.byType(QuietButton));
    expect(t.widget<QuietButton>(find.byType(QuietButton)).onPressed, isNull);
  });

  testWidgets('the lines at a time play on the reel at once', (t) async {
    await open(t);
    final one = stage(t).units.length;
    await t.tap(find.text('2'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.verseLines, 2);
    expect(stage(t).units.length, lessThan(one));

    await t.tap(find.text('Whole verse'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.verseLines, VerseLines.whole);
    expect(stage(t).units, hasLength(1));
    // Nothing to count, and no scenery to follow lines, with no lines.
    expect(find.text('Lines at a time'), findsNothing);
    expect(find.text('Every line'), findsNothing);

    // Back to lines: where it was left.
    await t.tap(find.text('Line by line'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.verseLines, VerseLines.preferred);
  });

  testWidgets('the scenery follows the lines, or each verse', (t) async {
    await open(t);
    await reach(t, find.text('Every verse'));
    await t.tap(find.text('Every verse'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.scenesFollowLines, isFalse);
    await t.tap(find.text('Every line'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.scenesFollowLines, isTrue);
  });

  testWidgets('a motion picked here is the one the reel plays and keeps',
      (t) async {
    await open(t);
    await reach(t, find.text('Golden thread'));
    await t.tap(find.text('Golden thread'));
    await t.pumpAndSettle();
    expect(creationState.motion, MotionPreset.thread.motion);

    await reach(t, find.text('Highlight recited word'));
    await t.tap(find.text('Highlight recited word'));
    await t.pumpAndSettle();
    expect(creationState.wordHighlight, isFalse);

    await top(t);
    expect(stage(t).motion, MotionPreset.thread.motion);
    expect(stage(t).highlight, isFalse);
  });

  testWidgets('the surah name, on, heads the reel', (t) async {
    await open(t);
    await reach(t, find.text('Surah name'));
    await t.tap(find.text('Surah name'));
    await t.pumpAndSettle();
    expect(SettingsService.state.value.surahTitle, isTrue);
    await top(t);
    expect(find.byType(SurahTitleLine), findsOneWidget);
  });

  testWidgets('back to the defaults puts this page back, and only it',
      (t) async {
    SettingsService.state.value = AppSettings.defaults.copyWith(
      verseLines: 3,
      scenesFollowLines: false,
      surahTitle: true,
      highQualityVideo: true,
      name: 'Yusuf',
    );
    creationState
      ..setMotion(MotionPreset.gilded.motion)
      ..setWordHighlight(false);
    await open(t);
    await reach(t, find.byType(QuietButton));
    await t.tap(find.byType(QuietButton));
    await t.pumpAndSettle();
    final s = SettingsService.state.value;
    expect(s.verseLines, VerseLines.preferred);
    expect(s.scenesFollowLines, isTrue);
    expect(s.surahTitle, isFalse);
    expect(s.highQualityVideo, isFalse);
    // Not this page's.
    expect(s.name, 'Yusuf');
    expect(creationState.motion, VerseMotion.standard);
    expect(creationState.wordHighlight, isTrue);
    expect(t.widget<QuietButton>(find.byType(QuietButton)).onPressed, isNull);
  });

  testWidgets('reads right to left in Arabic', (t) async {
    await open(t, locale: const Locale('ar'));
    expect(t.takeException(), isNull);
    expect(find.text('سطرًا سطرًا'), findsOneWidget);
    expect(Directionality.of(t.element(find.text('سطرًا سطرًا'))),
        TextDirection.rtl);
    expect(find.byType(VerseStage), findsOneWidget);
  });
}
