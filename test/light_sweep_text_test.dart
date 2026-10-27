import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/light_sweep_text.dart';

/// The Telegram row's title: a band of light passes through it, then
/// rests with nothing moving, and stays still for reduced motion.
void main() {
  Widget app({bool still = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: still),
          child: const Scaffold(
            body: Center(
              child: LightSweepText(
                text: 'Join us on Telegram',
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      );

  testWidgets('a pass, then a rest that asks for no frames', (t) async {
    await t.pumpWidget(app());
    expect(find.text('Join us on Telegram'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    // The first pass starts a moment after the screen is in.
    await t.pump(const Duration(milliseconds: 700));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShaderMask), findsOneWidget);
    // Over: the text is its own again, and nothing is scheduled.
    await t.pump(const Duration(milliseconds: 1000));
    expect(find.byType(ShaderMask), findsNothing);
    expect(t.binding.hasScheduledFrame, isFalse);
    // And it comes round again.
    await t.pump(const Duration(milliseconds: 3300));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('reduced motion: never a pass', (t) async {
    await t.pumpWidget(app(still: true));
    await t.pump(const Duration(seconds: 6));
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('Join us on Telegram'), findsOneWidget);
  });
}
