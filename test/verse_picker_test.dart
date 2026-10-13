import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/quran_text_service.dart';
import 'package:ayah_reels/data/reel_duration.dart';
import 'package:ayah_reels/data/reel_limits.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/verses_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/glow_button.dart';

/// The verse picker builds its run one tap at a time. Two rules carry
/// the meaning: the run can never have a hole in it — a reel that skips
/// an ayah recites the Quran wrong — and a third tap must go on
/// building rather than wipe what the first two picked.
///
/// Al-Fatiha is bundled, so the list renders with no network.
void main() {
  const l = L10n.en;

  setUp(() {
    creationState.selectReciter(reciters.first);
    creationState.selectSurah(1);
  });

  Widget host() => MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const VersesScreen(),
      );

  /// The ayah's number badge. The surah card carries a number too, so
  /// the finder has to stay inside the list.
  Finder ayah(int n) =>
      find.descendant(of: find.byType(ListView), matching: find.text('$n'));

  /// A tall test surface: the verse tiles carry Arabic plus a
  /// translation, so at the default 800x600 the list would only build
  /// its first few and taps further down would miss.
  void sizeTallPhone(WidgetTester t) {
    t.view.physicalSize = const Size(400 * 3, 1600 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> tapAyah(WidgetTester t, int n) async {
    await t.tap(ayah(n));
    // Fixed pumps throughout: the CTA's glow repeats forever, so
    // pumpAndSettle would never return.
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> holdAyah(WidgetTester t, int n) async {
    await t.longPress(ayah(n));
    await t.pump(const Duration(milliseconds: 300));
  }

  GlowButton cta(WidgetTester t) => t.widget<GlowButton>(find.byType(GlowButton));

  /// What the button should read for a run, before any of the audio
  /// has been fetched: the picker's own estimate of how long it runs.
  /// Computed rather than written out, so the assertion says "the
  /// length of this run" and not "eighteen seconds".
  String lengthOf(int start, int end) => l.continueWith(l.reelLengthAbout(
        ReelDuration.estimateMs(
          fatiha,
          startAyah: start,
          endAyah: end,
          pace: reciters.first.pace,
        ),
      ));

  testWidgets('every tap extends the run, and the third keeps it',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 2);
    expect(creationState.startAyah, 2);
    expect(creationState.endAyah, 2);
    expect(cta(t).label, lengthOf(2, 2));

    await tapAyah(t, 3);
    await tapAyah(t, 4);
    expect(creationState.startAyah, 2);
    expect(creationState.endAyah, 4);
    expect(cta(t).label, lengthOf(2, 4));

    // The ayah before the run extends it just as well.
    await tapAyah(t, 1);
    expect(creationState.startAyah, 1);
    expect(creationState.endAyah, 4);
  });

  testWidgets('a tap that would leave a gap is refused, with a warning',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 1);
    await tapAyah(t, 4);

    expect(find.text(l.ayahsMustFollowOn), findsOneWidget);
    expect(creationState.startAyah, 1);
    expect(creationState.endAyah, 1);
    expect(cta(t).label, lengthOf(1, 1));
  });

  testWidgets('tapping inside the run drops that ayah and the rest',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    for (final n in [2, 3, 4, 5]) {
      await tapAyah(t, n);
    }
    expect(creationState.endAyah, 5);

    await tapAyah(t, 4);
    expect(creationState.startAyah, 2);
    expect(creationState.endAyah, 3);
  });

  testWidgets("tapping the run's first ayah clears the selection",
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 3);
    await tapAyah(t, 4);
    expect(cta(t).onPressed, isNotNull);

    await tapAyah(t, 3);
    expect(cta(t).label, l.continueLabel);
    expect(cta(t).onPressed, isNull);
  });

  testWidgets('holding an ayah reaches it in one gesture, span and all',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 2);
    await holdAyah(t, 5);
    expect(creationState.startAyah, 2);
    expect(creationState.endAyah, 5);
    expect(cta(t).label, lengthOf(2, 5));

    // Reaching back before the run carries the span with it too.
    await holdAyah(t, 1);
    expect(creationState.startAyah, 1);
    expect(creationState.endAyah, 5);

    // Held inside, the run ends where the finger landed.
    await holdAyah(t, 3);
    expect(creationState.startAyah, 1);
    expect(creationState.endAyah, 3);
  });

  group('the hour cap is held here, not in the preview', () {
    /// A surah of very long verses read by one of the slow mujawwad
    /// voices, so the cap is crossed in a handful of taps instead of
    /// ninety: about thirteen minutes a verse by the picker's own
    /// estimate, four of which fit inside the hour and five of which
    /// do not.
    final slow = reciters.firstWhere((r) => r.id == 'husary_mujawwad');

    List<Ayah> hugeSurah(int count) => [
          for (var n = 1; n <= count; n++)
            Ayah(
              number: n,
              arabic: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ ' * 100,
              translation: 'Long verse $n.',
            ),
        ];

    setUp(() {
      QuranTextService.seed(2, hugeSurah(5));
      creationState.selectSurah(2);
      creationState.selectReciter(slow);
    });
    tearDown(() => QuranTextService.seed(2, null));

    /// Everything on screen at once: these verses are enormous, and
    /// scrolling to reach the tap target is not what is under test.
    void sizeVeryTall(WidgetTester t) {
      t.view.physicalSize = const Size(400 * 3, 60000 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }

    testWidgets('a tap past the hour is refused where it is made',
        (t) async {
      sizeVeryTall(t);
      await t.pumpWidget(host());
      await t.pump();

      // Four of these fit inside the hour; the fifth does not, and the
      // picker says so rather than letting the preview trim it three
      // screens later.
      for (final n in [1, 2, 3, 4]) {
        await tapAyah(t, n);
      }
      expect(creationState.endAyah, 4);
      expect(
        ReelDuration.estimateMs(hugeSurah(5),
            startAyah: 1, endAyah: 4, pace: slow.pace),
        lessThanOrEqualTo(ReelLimits.maxReelMs),
      );
      expect(
        ReelDuration.estimateMs(hugeSurah(5),
            startAyah: 1, endAyah: 5, pace: slow.pace),
        greaterThan(ReelLimits.maxReelMs),
      );

      await tapAyah(t, 5);
      expect(find.text(l.reelCapReached), findsOneWidget);
      expect(creationState.endAyah, 4, reason: 'the run must not grow');
      // And the way out is still open: the button goes on working for
      // the run that does fit.
      expect(cta(t).onPressed, isNotNull);
    });

    testWidgets('holding past the hour stops at the last verse that fits',
        (t) async {
      sizeVeryTall(t);
      await t.pumpWidget(host());
      await t.pump();

      await tapAyah(t, 1);
      await holdAyah(t, 5);
      expect(creationState.endAyah, 4);
      expect(find.text(l.reelCapReached), findsOneWidget);
    });
  });

  testWidgets('holding with nothing picked opens the run on that ayah',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await holdAyah(t, 4);
    expect(creationState.startAyah, 4);
    expect(creationState.endAyah, 4);
    expect(find.text(l.ayahsMustFollowOn), findsNothing);
  });
}
