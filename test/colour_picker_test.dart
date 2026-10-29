import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/widgets/colour_picker.dart';

/// The custom colour circle at the end of every row of swatches: it
/// mixes a colour, and Save keeps it for every other row in the app.
void main() {
  const l = L10n.en;
  tearDown(() => SettingsService.state.value = AppSettings.defaults);

  test('kept colours are newest first, never twice, and none fall off',
      () async {
    for (var i = 0; i < 40; i++) {
      await CustomColours.save(0xFF000000 + i);
    }
    await CustomColours.save(0xFF000005);
    final kept = CustomColours.saved;
    expect(kept, hasLength(40), reason: 'the first one kept is still there');
    expect(kept, contains(0xFF000000));
    expect(kept.first, 0xFF000005);
    expect(kept.where((c) => c == 0xFF000005), hasLength(1));
    await CustomColours.remove(0xFF000005);
    expect(CustomColours.saved, isNot(contains(0xFF000005)));
  });

  testWidgets('"Remove" lets kept colours go with a tap, and "Done" puts '
      'the taps back', (t) async {
    final h = t.ensureSemantics();
    int? picked;
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    SettingsService.state.value = AppSettings.defaults
        .copyWith(customColours: const [0xFF112233, 0xFF445566, 0xFF778899]);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: CustomColourCircle(
            current: 0xFF3366CC,
            chosen: false,
            onPick: (c) => picked = c,
          ),
        ),
      ),
    ));
    await t.tap(find.byType(CustomColourCircle));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text(l.customColourRemove), findsOneWidget);

    await t.tap(find.text(l.customColourRemove));
    await t.pump();
    expect(find.text(l.customColourRemoveDone), findsOneWidget);
    await t.tap(find.bySemanticsLabel(l.customColourIs('#445566')));
    await t.pump();
    expect(SettingsService.state.value.customColours,
        [0xFF112233, 0xFF778899]);
    expect(picked, isNull, reason: 'removing picks nothing');

    await t.tap(find.text(l.customColourRemoveDone));
    await t.pump();
    await t.tap(find.bySemanticsLabel(l.customColourIs('#778899')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(picked, 0xFF778899);
    h.dispose();
  });

  test('a code reads as one', () {
    expect(hexOf(0xFFA1B2C3), '#A1B2C3');
    expect(hexOf(0xFF00000A), '#00000A');
  });

  testWidgets('the circle opens the mixer, and Save answers and keeps the '
      'colour', (t) async {
    int? picked;
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: CustomColourCircle(
            current: 0xFF3366CC,
            chosen: false,
            onPick: (c) => picked = c,
          ),
        ),
      ),
    ));
    await t.tap(find.byType(CustomColourCircle));
    // The Save button's glow never settles; the sheet is up by the clock.
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text(l.customColourTitle), findsOneWidget);
    expect(find.text('#3366CC'), findsOneWidget);
    expect(find.text(l.customColourKeptEmpty), findsOneWidget);
    await t.tap(find.text(l.customColourSave));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(picked, isNotNull);
    expect(picked! & 0xFFFFFF, 0x3366CC);
    expect(SettingsService.state.value.customColours.first & 0xFFFFFF,
        0x3366CC);
  });
}
