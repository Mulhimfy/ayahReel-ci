import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/render/reel_poster.dart';
import 'package:ayah_reels/screens/reel_player_screen.dart';
import 'package:ayah_reels/widgets/reel_thumb.dart';

/// Tapping a reel used to hand it the whole screen: a 9:16 clip
/// stretched until it touched the app bar and both edges, with the app
/// around it gone. The player holds it to a phone-shaped card instead,
/// with room on every side and the transport underneath.
///
/// These pin the sizing, because it is the kind of thing a later
/// "just make it a bit bigger" quietly undoes.
void main() {
  final reel = SavedReel(
    id: 'r1',
    fileName: 'reel_r1.mp4',
    reciterName: 'Alafasy',
    surahName: 'Al-Fatihah',
    startAyah: 1,
    endAyah: 7,
    gradientArgb: const [0xFF101418, 0xFF202830],
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() => ReelPoster.testResolver = (_) async => null);
  tearDown(() => ReelPoster.testResolver = null);

  /// The stage as laid out on a [screen]-sized phone.
  ///
  /// There is no documents directory under the test binding, so the mp4
  /// never opens and the card sits on its poster layer with the spinner
  /// still turning — which is the point of measuring here. The frame is
  /// the frame before a single byte of video has arrived, and it is
  /// already the right size and shape. (Fixed pumps rather than
  /// pumpAndSettle for exactly that reason: the spinner never stops.)
  Future<Size> stageOn(WidgetTester tester, Size screen) async {
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: ReelPlayerScreen(reel: reel)));
    await tester.pump(const Duration(milliseconds: 300));
    return tester.getSize(find.byType(ReelThumb));
  }

  testWidgets('the reel plays in a card, not across the whole screen',
      (tester) async {
    const screen = Size(390, 844);
    final stage = await stageOn(tester, screen);

    expect(stage.width, lessThan(screen.width * 0.8),
        reason: 'the reel must not run edge to edge');
    expect(stage.height, lessThan(screen.height * 0.75),
        reason: 'the reel must not run top to bottom');
    expect(stage.width / stage.height, closeTo(9 / 16, 0.01),
        reason: 'a 1080x1920 reel is never letterboxed or squashed');
  });

  testWidgets('a short screen shrinks the card rather than overflowing',
      (tester) async {
    // Height leads here: 9:16 of the full width would be taller than
    // everything below it leaves room for.
    final stage = await stageOn(tester, const Size(320, 560));

    expect(stage.width / stage.height, closeTo(9 / 16, 0.01));
    expect(tester.takeException(), isNull,
        reason: 'no overflow: the stage gives way to the transport');
  });

  testWidgets('turned sideways it still lays out', (tester) async {
    // Nothing locks the orientation, and landscape leaves less height
    // than the transport alone would like. The card gives all of it up
    // rather than going negative and taking the screen with it.
    final stage = await stageOn(tester, const Size(844, 390));

    expect(stage.width, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the transport sits under the card', (tester) async {
    await stageOn(tester, const Size(390, 844));

    // Play/pause, restart, share — plus the elapsed and total clocks
    // that flank the scrub bar.
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsOneWidget);
    expect(find.text('0:00'), findsNWidgets(2));
  });
}
