import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/review_prompt.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/feedback_sheet.dart';
import 'package:ayah_reels/widgets/rate_sheet.dart';

/// The rating sheet asks for stars, sends five to the store, and asks
/// the rest what would make it five — with the store's button still in
/// front of them, because a sheet that sent only the happy to the store
/// would be review gating, which both stores forbid.
void main() {
  const l = L10n.en;

  setUp(() => ReviewPrompt.resetForTest());

  Widget host() => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(
                onPressed: () => showRateSheet(c),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(host());
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opens on five stars to tap and nothing else asked',
      (t) async {
    await open(t);
    expect(find.text(l.rateHowMany), findsOneWidget);
    for (var n = 1; n <= 5; n++) {
      expect(find.byKey(ValueKey('rate-star-$n')), findsOneWidget);
    }
    expect(find.byType(FeedbackField), findsNothing);
  });

  testWidgets('fewer than five ask what would help, and still offer the '
      'store', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('rate-star-3')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(l.rateWhatWouldHelp), findsOneWidget);
    expect(find.byType(FeedbackField), findsOneWidget);
    // The store is never kept from anyone.
    expect(find.text(l.openPlayStore), findsOneWidget);
  });
}
