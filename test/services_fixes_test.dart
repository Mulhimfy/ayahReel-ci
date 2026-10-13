import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/quran_search.dart';
import 'package:ayah_reels/data/reciter_search.dart';

/// The 2026-10-05 review's fixes to search, held where they are pure.
void main() {
  group('Urdu and Persian letters', () {
    test('find the name typed with the Arabic ones', () {
      // A name is found by its key containing the typed one's.
      expect(ReciterSearch.arabicKey('السديس'),
          contains(ReciterSearch.arabicKey('سدیس')));
      expect(ReciterSearch.arabicKey('الكناكري'),
          contains(ReciterSearch.arabicKey('کناکری')));
      expect(ReciterSearch.arabicKey('الحذيفي'),
          contains(ReciterSearch.arabicKey('حذیفی')));
      expect(ReciterSearch.arabicKey('سدیس'), isNot(contains('ی')));
    });

    test('reach verse search as typed', () {
      expect(QuranSearch.normalize('کتاب'), QuranSearch.normalize('كتاب'));
      expect(QuranSearch.normalize('رحمۃ'), QuranSearch.normalize('رحمة'));
    });
  });
}
