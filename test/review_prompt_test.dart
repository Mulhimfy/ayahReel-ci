import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/review_prompt.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/store_links.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/screens/settings_screen.dart';
import 'package:ayah_reels/theme/app_theme.dart';

/// The rating ask is spent from a budget neither store will report on:
/// iOS shows its sheet three times a year and returns nothing either
/// way. So the only thing that can be pinned down is our half — when
/// the ladder decides an export has earned an ask, and the fact that
/// Settings always carries a route the quota cannot close.
void main() {
  ReviewAsk ask({
    required int exports,
    int asks = 0,
    bool wentToListing = false,
    bool android = false,
  }) =>
      ReviewPrompt.decide(
        exports: exports,
        asks: asks,
        wentToListing: wentToListing,
        android: android,
      );

  group('the ladder, on iOS', () {
    test('says nothing before the first milestone', () {
      for (var n = 0; n < ReviewPrompt.milestones.first; n++) {
        expect(ask(exports: n), ReviewAsk.none,
            reason: '$n exports asked too early');
      }
    });

    test('the very first kept reel is the first ask', () {
      // Apple sets no minimum-usage floor, so the earliest clean
      // moment is the one taken. If this ever has to move, it is a
      // product decision and not a compliance one.
      expect(ReviewPrompt.milestones.first, 1);
      expect(ask(exports: 1), ReviewAsk.native);
    });

    test('every milestone fires on the export that reaches it', () {
      for (var i = 0; i < ReviewPrompt.milestones.length; i++) {
        final at = ReviewPrompt.milestones[i];
        expect(ask(exports: at - 1, asks: i), ReviewAsk.none,
            reason: 'ask ${i + 1} fired one export early');
        expect(ask(exports: at, asks: i), ReviewAsk.native,
            reason: 'ask ${i + 1} missed its own milestone');
      }
    });

    test('counts alone decide it — no elapsed time anywhere', () {
      // Deliberate: reaching every milestone in one afternoon spends
      // every ask that afternoon. iOS shows what its own 3-per-365
      // allowance permits and swallows the rest in silence.
      for (var i = 0; i < ReviewPrompt.milestones.length; i++) {
        expect(ask(exports: ReviewPrompt.milestones.last, asks: i),
            ReviewAsk.native);
      }
    });

    test('spends exactly the three asks iOS allows, then stops', () {
      var asks = 0;
      for (var day = 0; day < 365; day++) {
        if (ask(exports: day + 1, asks: asks) == ReviewAsk.native) asks++;
      }
      expect(asks, 3);
      expect(asks, ReviewPrompt.milestones.length);
    });

    test('our own sheet never appears by itself on iOS', () {
      // Guideline 5.6.1 disallows custom review prompts. Nothing but the
      // Settings row may open ours here — at any count, ever.
      for (var n = 1; n <= 200; n++) {
        for (var spent = 0; spent <= ReviewPrompt.milestones.length; spent++) {
          expect(ask(exports: n, asks: spent), isNot(ReviewAsk.banner));
        }
      }
    });
  });

  group('the ladder, on Android', () {
    test('the OS sheet gets one go and only one', () {
      expect(ask(exports: 1, android: true), ReviewAsk.native);
      // Play throttles repeat flows inside a month and never says
      // whether anything appeared, so a second call is a near-certain
      // no-op. Ours takes over instead.
      for (var n = 2; n <= 200; n++) {
        expect(ask(exports: n, asks: 1, android: true),
            isNot(ReviewAsk.native));
      }
    });

    test('our sheet follows the OS one, and repeats', () {
      final shown = <int>[];
      for (var n = 1; n <= 30; n++) {
        if (ask(exports: n, asks: 1, android: true) == ReviewAsk.banner) {
          shown.add(n);
        }
      }
      expect(shown, [5, 10, 15, 20, 25, 30]);
    });

    test('our sheet never precedes the OS one', () {
      for (var n = 1; n <= 200; n++) {
        expect(ask(exports: n, asks: 0, android: true),
            isNot(ReviewAsk.banner),
            reason: 'ours jumped the queue at $n exports');
      }
    });
  });

  group('both platforms', () {
    test('nothing asks again once the listing has been opened', () {
      for (final android in [true, false]) {
        expect(
          ask(exports: 10000, asks: 1, wentToListing: true, android: android),
          ReviewAsk.none,
          reason: 'they have been handed the store once; that is enough',
        );
      }
    });
  });

  group('the manual route', () {
    tearDown(() => SettingsService.state.value = AppSettings.defaults);

    testWidgets('Settings carries a row that opens the sheet', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SettingsScreen(permissionCheck: () async => true),
        ),
      ));
      await t.pump();

      expect(find.text(L10n.en.rateAppTitle), findsOneWidget);

      await t.tap(find.text(L10n.en.rateAppTitle));
      // GlowButton's glow loops forever, so settle by the clock.
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.text(L10n.en.rateSheetTitle), findsOneWidget);
      expect(find.text(L10n.en.rateSheetBody), findsOneWidget);
      // Five stars, filled, and none of them tappable: a sheet that
      // collects the rating itself and forks on the answer is the
      // pattern App Store guideline 5.6.1 exists to refuse. These are
      // decoration in front of a link to the listing.
      // Scoped to the sheet: the Settings row behind it wears the
      // same star.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.star_rounded),
        ),
        findsNWidgets(5),
      );
      // The button says which store it is about to leave for. The
      // test host is neither phone, so it takes the Play branch.
      expect(find.text(L10n.en.openPlayStore), findsOneWidget);
    });

    test('the Apple link lands on the review composer, not screenshots', () {
      expect(appStoreReviewUrl, startsWith(appStoreUrl));
      expect(appStoreReviewUrl, endsWith('?action=write-review'));
    });
  });

  test('both languages carry every rating string', () {
    const ar = L10n(AppLang.ar);
    for (final pair in <List<String>>[
      [L10n.en.sectionRate, ar.sectionRate],
      [L10n.en.rateAppTitle, ar.rateAppTitle],
      [L10n.en.rateAppSubtitle, ar.rateAppSubtitle],
      [L10n.en.rateSheetTitle, ar.rateSheetTitle],
      [L10n.en.rateSheetBody, ar.rateSheetBody],
      [L10n.en.openAppStore, ar.openAppStore],
      [L10n.en.openPlayStore, ar.openPlayStore],
      [L10n.en.storeOpenFailed, ar.storeOpenFailed],
    ]) {
      expect(pair[0], isNotEmpty);
      expect(pair[1], isNotEmpty);
      expect(pair[1], isNot(pair[0]),
          reason: '"${pair[0]}" was never translated');
    }
  });
}
