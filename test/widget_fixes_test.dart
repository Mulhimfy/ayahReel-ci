import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/widgets/night_sky.dart';
import 'package:ayah_reels/widgets/surah_picker_sheet.dart';

void main() {
  test('an ayah number too long for an int is a name search, not a throw',
      () {
    final q = SurahPickerSheet.parse('baqarah 123456789012345678901234');
    expect(q.surah, 'baqarah');
    expect(q.ayah, isNull);
    final r = SurahPickerSheet.parse('baqarah 255-99999999999999999999999');
    expect(r.ayah, 255);
    expect(r.endAyah, isNull);
  });

  test('Arabic counts take the dual and the eleven-and-up singular', () {
    const ar = L10n(AppLang.ar);
    expect(ar.sceneLimit(2), contains('لمشهدين'));
    expect(ar.sceneLimit(5), contains('5 مشاهد'));
    expect(ar.sceneLimit(12), contains('12 مشهدًا'));
    expect(ar.scenesTooShort(2), contains('لقطتان'));
    expect(ar.scenesTooShort(11), contains('11 لقطةً'));
    expect(ar.cardSavedToGallery(2), contains('بطاقتان'));
    expect(ar.cardSavedToGallery(4), contains('4'));
  });

  test('German dates take the ordinal dot; Urdu says one card in words',
      () {
    final d = DateTime(2026, 10, 4);
    expect(const L10n(AppLang.de).formatDate(d), '4. Okt. 2026');
    expect(const L10n(AppLang.en).formatDate(d), '4 Oct 2026');
    expect(const L10n(AppLang.ur).cardCount(1), isNot(contains('۱')));
  });

  test('the three alignment buttons have three names in every language', () {
    for (final lang in AppLang.values) {
      final l = L10n(lang);
      expect({l.cardAlignLeft, l.cardAlignCentre, l.cardAlignRight},
          hasLength(3),
          reason: lang.name);
    }
  });

  testWidgets('the Bismillah ornament lays out right to left',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: SizedBox(width: 320, child: BismillahOrnament()),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(OrnamentRule), findsNWidgets(2));
  });
}
