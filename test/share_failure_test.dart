import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/invite_sheet.dart';

/// A share that the OS refuses must say so.
///
/// The invite path had no catch at all, so when iOS started rejecting
/// every share for a missing position rect, the button simply did
/// nothing — no banner, no log, nothing to report. The rect is fixed
/// (see share_origin_test.dart); this pins the other half, so the next
/// platform-side refusal is visible instead of silent.
void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');

  /// Makes the platform reject every share, the way iOS did.
  void refuseShares(WidgetTester t) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'error',
        message: 'sharePositionOrigin: argument must be set',
      ),
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
  }

  testWidgets('a refused share tells the user instead of doing nothing',
      (t) async {
    refuseShares(t);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        floatingActionButton: InviteFab(),
        body: SizedBox.expand(),
      ),
    ));

    await t.tap(find.byType(InviteFab));
    // GlowButton's glow loops forever, so settle by the clock.
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Share AyahReel'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Could not share'), findsOneWidget);
    // And it reached the error reporter, so crash tooling sees it too.
    expect(t.takeException(), isA<PlatformException>());
  });
}
