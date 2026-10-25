import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/quran_repository.dart';
import 'package:ayah_reels/data/quran_text_service.dart';
import 'package:ayah_reels/data/reel_duration.dart';
import 'package:ayah_reels/data/reel_limits.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/verses_screen.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/glow_button.dart';
import 'package:ayah_reels/widgets/recitation_deck.dart';

/// The verse picker builds its run from taps: the first verse, then the
/// last, and everything between. Three rules carry the meaning: the run
/// can never have a hole in it — a reel that skips an ayah recites the
/// Quran wrong — a far verse is reached without walking back to undo the
/// old run, and choosing a verse never moves the voice: its number does.
///
/// Al-Fatiha is bundled, so the list renders with no network.
void main() {
  const l = L10n.en;

  setUp(() {
    creationState.selectReciter(reciters.first);
    creationState.selectSurah(1);
    // Each test opens the picker on nothing chosen; the run the last
    // test left is what a later reel would reopen on (see the test of
    // that below).
    creationState.debugForgetRange();
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

  /// A point on the verse itself, clear of its number — the number is
  /// a button of its own, which plays the verse.
  Offset onVerse(WidgetTester t, int n) =>
      t.getCenter(ayah(n)) + const Offset(120, 0);

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
    await t.tapAt(onVerse(t, n));
    // Fixed pumps throughout: the CTA's glow repeats forever, so
    // pumpAndSettle would never return.
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> holdAyah(WidgetTester t, int n) async {
    await t.longPressAt(onVerse(t, n));
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

  testWidgets('the surah search is open from the start, over the surah',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();
    // No tap to find it: the field is there, and the surah under it.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(l.searchSurahHint), findsOneWidget);
    expect(find.text(l.surahTitle(QuranRepository.surahInfo(1))),
        findsOneWidget);
    // Typing lists what it names, in place of the verses.
    await t.enterText(find.byType(TextField), '18');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(l.surahTitle(QuranRepository.surahInfo(18))),
        findsOneWidget);
    expect(find.text(l.surahTitle(QuranRepository.surahInfo(1))),
        findsNothing);
  });

  testWidgets('choosing never moves the voice; the number does', (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();
    final deck = t.widget<RecitationDeck>(find.byType(RecitationDeck));
    final live = deck.live;
    expect(live.ayah, 1);

    await tapAyah(t, 3);
    expect(creationState.startAyah, 3);
    expect(live.ayah, 1, reason: 'choosing leaves the voice where it is');

    await t.tap(find.byKey(const ValueKey('listen-5')));
    await t.pump(const Duration(milliseconds: 300));
    expect(live.ayah, 5);
    expect(creationState.startAyah, 3,
        reason: 'listening leaves the choice where it is');
    expect(creationState.endAyah, 3);
  });

  testWidgets('ten seconds back and on, at the two ends of the line',
      (t) async {
    final h = t.ensureSemantics();
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();
    final live = t.widget<RecitationDeck>(find.byType(RecitationDeck)).live;
    expect(live.totalMs, greaterThan(10000));
    expect(live.positionMs, 0);
    final chosen = (creationState.startAyah, creationState.endAyah);

    await t.tap(find.bySemanticsLabel(l.liveForward10));
    await t.pump(const Duration(milliseconds: 300));
    expect(live.positionMs, 10000);
    expect(live.ayah, live.ayahAt(10000));
    expect((creationState.startAyah, creationState.endAyah), chosen,
        reason: 'moving the voice chooses nothing');

    await t.tap(find.bySemanticsLabel(l.liveBack10));
    await t.pump(const Duration(milliseconds: 300));
    expect(live.positionMs, 0);
    // Back from the start stays at the start.
    await t.tap(find.bySemanticsLabel(l.liveBack10));
    await t.pump(const Duration(milliseconds: 300));
    expect(live.positionMs, 0);
    h.dispose();
  });

  testWidgets('a reel begun again opens on the verses of the last',
      (t) async {
    sizeTallPhone(t);
    // The run the last reel was made of: this session's, or the last
    // launch's, put back by LastChoices.
    creationState.selectRange(3, 5);
    await t.pumpWidget(host());
    await t.pump(const Duration(milliseconds: 300));
    expect(cta(t).label, lengthOf(3, 5));
    expect(find.text(l.ayahRange(3, 5)), findsOneWidget);

    // A far verse starts again from it, as from any run. The list was
    // scrolled to the run, so the first verse is brought back first.
    await t.ensureVisible(ayah(1));
    await t.pump(const Duration(milliseconds: 300));
    await tapAyah(t, 1);
    expect((creationState.startAyah, creationState.endAyah), (1, 1));
  });

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

  testWidgets('the first verse, then the last: everything between is chosen',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 2);
    await tapAyah(t, 6);
    expect(creationState.startAyah, 2);
    expect(creationState.endAyah, 6);
    expect(cta(t).label, lengthOf(2, 6));
    // The run is named under the list, where a far one can be seen.
    expect(find.text(l.ayahRange(2, 6)), findsOneWidget);
  });

  testWidgets('the last verse can come first', (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 6);
    await tapAyah(t, 3);
    expect(creationState.startAyah, 3);
    expect(creationState.endAyah, 6);
  });

  testWidgets('inside the run a tap ends it there; its ends drop off',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 2);
    await tapAyah(t, 6);

    await tapAyah(t, 4);
    expect(creationState.startAyah, 2);
    expect(creationState.endAyah, 4);

    await tapAyah(t, 4);
    expect(creationState.startAyah, 2);
    expect(creationState.endAyah, 3);

    await tapAyah(t, 2);
    expect(creationState.startAyah, 3);
    expect(creationState.endAyah, 3);
  });

  testWidgets('a far verse starts the run again, and Undo brings it back',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 1);
    await tapAyah(t, 2);
    await tapAyah(t, 6);
    expect(creationState.startAyah, 6);
    expect(creationState.endAyah, 6);
    expect(find.text(l.versesStartedAgain(6)), findsOneWidget);

    // Let the toast land before reaching for its button.
    await t.pump(const Duration(milliseconds: 700));
    await t.tap(find.text(l.undo));
    await t.pump(const Duration(milliseconds: 300));
    expect(creationState.startAyah, 1);
    expect(creationState.endAyah, 2);
  });

  testWidgets('a run of one lets go on a second tap; the cross lets any go',
      (t) async {
    sizeTallPhone(t);
    await t.pumpWidget(host());
    await t.pump();

    await tapAyah(t, 3);
    expect(cta(t).onPressed, isNotNull);
    await tapAyah(t, 3);
    expect(cta(t).label, l.continueLabel);
    expect(cta(t).onPressed, isNull);

    await tapAyah(t, 2);
    await tapAyah(t, 5);
    expect(cta(t).onPressed, isNotNull);
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump(const Duration(milliseconds: 300));
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

  group('the basmala, asked above a surah\'s first verse', () {
    setUp(() {
      QuranTextService.seed(2, [
        for (var n = 1; n <= 5; n++)
          Ayah(
            number: n,
            arabic: 'ذَٰلِكَ ٱلْكِتَـٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ',
            translation: 'Verse $n.',
          ),
      ]);
      creationState
        ..selectSurah(2)
        ..debugForgetRange();
      SettingsService.state.value = AppSettings.defaults;
    });
    tearDown(() {
      QuranTextService.seed(2, null);
      SettingsService.state.value = AppSettings.defaults;
    });

    testWidgets('once verse 1 is chosen, and it is Customize\'s switch',
        (t) async {
      sizeTallPhone(t);
      await t.pumpWidget(host());
      await t.pump();
      expect(find.text(l.includeBasmala), findsNothing);

      await tapAyah(t, 1);
      expect(find.text(l.includeBasmala), findsOneWidget);
      expect(SettingsService.state.value.basmala, isTrue);

      await t.tap(find.text(l.includeBasmala));
      await t.pump(const Duration(milliseconds: 300));
      expect(SettingsService.state.value.basmala, isFalse);
      await t.tap(find.text(l.includeBasmala));
      await t.pump(const Duration(milliseconds: 300));
      expect(SettingsService.state.value.basmala, isTrue);

      // Still a run from verse 1 when it grows.
      await tapAyah(t, 3);
      expect(creationState.endAyah, 3);
      expect(find.text(l.includeBasmala), findsOneWidget);
    });

    testWidgets('not for a run that starts later', (t) async {
      sizeTallPhone(t);
      await t.pumpWidget(host());
      await t.pump();
      await tapAyah(t, 2);
      expect(creationState.startAyah, 2);
      expect(find.text(l.includeBasmala), findsNothing);
    });

    testWidgets('not in Al-Fatiha, whose first verse is the basmala',
        (t) async {
      creationState
        ..selectSurah(1)
        ..debugForgetRange();
      sizeTallPhone(t);
      await t.pumpWidget(host());
      await t.pump();
      await tapAyah(t, 1);
      expect(creationState.startAyah, 1);
      expect(find.text(l.includeBasmala), findsNothing);
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
  });
}
