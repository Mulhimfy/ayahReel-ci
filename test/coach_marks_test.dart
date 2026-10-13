import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/coach_marks.dart';

/// The scenery walkthrough is the one thing a first-time user cannot
/// dismiss by accident, and it points at controls that are not always
/// on screen — the multi-scene pill is missing on a one-verse reel, the
/// corners-and-backdrop block only exists once the wide card is on. A
/// step that pointed at nothing would spotlight the top-left corner of
/// the screen, so the walking is pinned here.
///
/// So is the fact that OK is the only tap that does anything. The tour
/// is shown once per install; a stray tap that skipped a card — or the
/// lot — would spend that one chance, and the controls it was about to
/// explain would stay unexplained forever.
void main() {
  final railKey = GlobalKey();
  final pillKey = GlobalKey();
  final extrasKey = GlobalKey();

  /// A stand-in for the scenery screen: two controls always present,
  /// one that comes and goes.
  Widget host({
    required List<CoachStep> steps,
    required VoidCallback onFinished,
    bool showPill = true,
    bool showExtras = true,
  }) =>
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Stack(
            children: [
              // Filled, not loose: a Stack sizes itself to its
              // non-positioned children, and a column of short labels
              // would leave the tour a few pixels wide.
              Positioned.fill(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    SizedBox(
                        key: railKey, height: 40, child: const Text('rail')),
                    if (showPill)
                      SizedBox(
                          key: pillKey, height: 40, child: const Text('pill')),
                    if (showExtras)
                      SizedBox(
                          key: extrasKey,
                          height: 40,
                          child: const Text('extras')),
                  ],
                ),
              ),
              Positioned.fill(
                child: CoachMarks(steps: steps, onFinished: onFinished),
              ),
            ],
          ),
        ),
      );

  List<CoachStep> steps() => [
        CoachStep(target: railKey, title: 'Pick a mood', body: 'tabs'),
        CoachStep(target: pillKey, title: 'More than one', body: 'several'),
        CoachStep(
          target: extrasKey,
          fallback: railKey,
          title: 'Corners and edges',
          body: 'next screen',
        ),
      ];

  testWidgets('walks its steps in order and finishes on the last one',
      (t) async {
    var finished = 0;
    await t.pumpWidget(host(steps: steps(), onFinished: () => finished++));
    await t.pump(); // the post-frame measure

    expect(find.text('Pick a mood'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    // No card offers a way out but forward — not the first one, where
    // a Skip would be easiest to hit and cost the most.
    expect(find.text('Skip'), findsNothing);

    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('More than one'), findsOneWidget);

    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('Corners and edges'), findsOneWidget);

    await t.tap(find.text('Got it'));
    await t.pump();
    expect(finished, 1);
  });

  testWidgets('steps whose control is missing are skipped, not empty',
      (t) async {
    await t.pumpWidget(
        host(steps: steps(), onFinished: () {}, showPill: false));
    await t.pump();

    // Step 2's control is not on this screen, so tapping past step 1
    // lands on step 3 rather than spotlighting nothing.
    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('More than one'), findsNothing);
    expect(find.text('Corners and edges'), findsOneWidget);
  });

  testWidgets('a step falls back when its own control is hidden', (t) async {
    await t.pumpWidget(
        host(steps: steps(), onFinished: () {}, showExtras: false));
    await t.pump();
    await t.tap(find.text('OK'));
    await t.pump();
    await t.tap(find.text('OK'));
    await t.pump();

    // Corners and backdrop live behind the wide card; the step still
    // has something to stand next to.
    expect(find.text('Corners and edges'), findsOneWidget);
  });

  testWidgets('only OK advances, and the screen underneath is sealed',
      (t) async {
    var finished = 0;
    var tappedThrough = false;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  const SizedBox(height: 200),
                  GestureDetector(
                    onTap: () => tappedThrough = true,
                    child: SizedBox(
                        key: railKey, height: 40, child: const Text('rail')),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: CoachMarks(
                steps: [
                  CoachStep(target: railKey, title: 'Pick a mood', body: 'x'),
                  CoachStep(target: railKey, title: 'Second', body: 'y'),
                ],
                onFinished: () => finished++,
              ),
            ),
          ],
        ),
      ),
    ));
    await t.pump();

    // A tap on the dim does nothing: it neither reaches the screen
    // below nor moves the card on. There is no Skip to hit either.
    expect(find.text('Skip'), findsNothing);
    await t.tapAt(const Offset(20, 20));
    await t.pump();
    expect(tappedThrough, isFalse);
    expect(find.text('Pick a mood'), findsOneWidget);

    // A tap on the card itself, but off the button, is just as inert —
    // that is where a finger reaching for OK most often lands short.
    await t.tap(find.text('x'));
    await t.pump();
    expect(find.text('Pick a mood'), findsOneWidget);

    // OK is the one tap that does anything.
    await t.tap(find.text('OK'));
    await t.pump();
    expect(find.text('Second'), findsOneWidget);

    await t.tap(find.text('Got it'));
    await t.pump();
    expect(finished, 1);
  });
}
