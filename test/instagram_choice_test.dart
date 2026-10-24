import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/instagram_choice.dart';

/// "To Instagram" asks one question — story or reel — in a small panel
/// that rises out of the button, and nothing is made until it is
/// answered.
void main() {
  Future<Future<InstagramTarget?> Function()> host(WidgetTester t) async {
    InstagramTarget? picked;
    var done = false;
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Align(
          alignment: const Alignment(0, 0.8),
          child: Builder(
            builder: (button) => TextButton(
              onPressed: () async {
                picked = await showInstagramChoice(button);
                done = true;
              },
              child: const Text('To Instagram'),
            ),
          ),
        ),
      ),
    ));
    return () async => done ? picked : null;
  }

  testWidgets('both doors are offered, and the one tapped is the answer',
      (t) async {
    final result = await host(t);
    await t.pump();
    await t.tap(find.text('To Instagram'));
    await t.pumpAndSettle();

    expect(find.text('Story'), findsOneWidget);
    expect(find.text('Reel'), findsOneWidget);
    // The panel stands above the button that asked.
    expect(t.getCenter(find.text('Story')).dy,
        lessThan(t.getCenter(find.text('To Instagram')).dy));

    await t.tap(find.text('Story'));
    await t.pumpAndSettle();
    expect(find.text('Reel'), findsNothing);
    expect(await result(), InstagramTarget.story);
  });

  testWidgets('a tap anywhere else asks nothing and makes nothing',
      (t) async {
    final result = await host(t);
    await t.pump();
    await t.tap(find.text('To Instagram'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(20, 40));
    await t.pumpAndSettle();
    expect(find.text('Story'), findsNothing);
    expect(await result(), isNull);
  });
}
