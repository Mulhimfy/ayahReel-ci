import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/invite_sheet.dart';

/// The invitation is the app's only growth loop, so it has to be
/// reachable from anywhere and it has to explain itself before it asks.
void main() {
  Widget host() => MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          floatingActionButton: InviteFab(),
          body: SizedBox.expand(),
        ),
      );

  testWidgets('the button opens the reason before the share sheet',
      (t) async {
    await t.pumpWidget(host());
    await t.tap(find.byType(InviteFab));
    // GlowButton's glow loops forever, so settle by the clock.
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    // The reward, in the user's terms, before anything is asked of them.
    expect(find.textContaining('counts for you too'), findsOneWidget);
    expect(find.textContaining('Whoever guides to good'), findsOneWidget);
    expect(find.text('Sahih Muslim'), findsOneWidget);
    expect(find.text('Share AyahReel'), findsOneWidget);
  });

  testWidgets('backing out asks one question, and either answer ends it',
      (t) async {
    await t.pumpWidget(host());
    await t.tap(find.byType(InviteFab));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    await t.tap(find.text('Not now'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    // The one gentle second thought — a single question, never a chain.
    expect(find.text('Are you sure you want to lose the rewards?'),
        findsOneWidget);

    await t.tap(find.text('Leave'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Share AyahReel'), findsNothing);
  });

  testWidgets('choosing Stay keeps the sheet open', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.byType(InviteFab));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    await t.tap(find.text('Not now'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Stay'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Share AyahReel'), findsOneWidget);
  });

  testWidgets('the button stays quiet — no gold fill to fight the CTA',
      (t) async {
    await t.pumpWidget(host());
    final material = t.widget<Material>(
      find.descendant(
        of: find.byType(InviteFab),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, isNot(AppColors.gold));
    expect(material.color, isNot(AppColors.goldBright));
  });
}
