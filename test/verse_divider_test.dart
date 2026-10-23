import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_numbering.dart';
import 'package:ayah_reels/state/creation_state.dart' show TextPreset;
import 'package:ayah_reels/theme/app_theme.dart';
import 'package:ayah_reels/widgets/ayah_overlay.dart';

/// The gold rule is what tells the eye where the Arabic ends and the
/// translation begins. It used to be a classic-only flourish, which
/// left glow and minimal reels running the two blocks together. Every
/// preset draws it now, and this pins that — the overlay is rasterized
/// as-is into the exported video, so a preset losing the rule again
/// would ship straight into people's reels.
void main() {
  const ayah = Ayah(
    number: 1,
    arabic: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
    translation: 'In the name of Allah, the Most Gracious, the Most Merciful.',
  );

  Widget host(TextPreset preset, {bool onLight = false}) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: AyahOverlay(
              ayah: ayah,
              width: 360,
              preset: preset,
              onLight: onLight,
              numbering: VerseNumbering.off,
            ),
          ),
        ),
      );

  for (final preset in TextPreset.values) {
    testWidgets('${preset.name} draws the rule between verse and translation',
        (t) async {
      await t.pumpWidget(host(preset));
      await t.pump();

      final rule = find.byKey(AyahOverlay.dividerKey);
      expect(rule, findsOneWidget);

      // Between the two, not above or below both.
      final ruleY = t.getCenter(rule).dy;
      expect(ruleY, greaterThan(t.getCenter(find.text(ayah.arabic)).dy));
      expect(ruleY, lessThan(t.getCenter(find.text(ayah.translation)).dy));
    });
  }

  testWidgets('the rule takes the deeper gold on a pale band', (t) async {
    Future<Color> ruleColorAt({required bool onLight}) async {
      await t.pumpWidget(host(TextPreset.glow, onLight: onLight));
      await t.pump();
      final box = t.widget<Container>(find.byKey(AyahOverlay.dividerKey));
      final gradient =
          (box.decoration as BoxDecoration).gradient as LinearGradient;
      return gradient.colors[1]; // transparent, gold, transparent
    }

    final onDark = await ruleColorAt(onLight: false);
    final onPale = await ruleColorAt(onLight: true);
    expect(onDark.toARGB32() & 0x00FFFFFF, AppColors.goldBright.toARGB32() & 0x00FFFFFF);
    expect(onPale.toARGB32() & 0x00FFFFFF, AppColors.gold.toARGB32() & 0x00FFFFFF);
  });
}
