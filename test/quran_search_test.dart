import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/quran_search.dart';

/// Searching the Quran by the words of a verse: the mushaf's spelling
/// and the typed spelling meet in the middle, and the index carries
/// every verse.
void main() {
  setUpAll(() {
    QuranSearch.loadFrom(
        File('assets/quran_search.json').readAsStringSync());
  });
  tearDownAll(QuranSearch.resetForTest);

  test('the index is the whole Quran', () async {
    // 6236 verses; the last of the last surah is there.
    final hits = await QuranSearch.search('من الجنة والناس');
    expect(hits.map((h) => '${h.surah}:${h.ayah}'), contains('114:6'));
  });

  group('normalize', () {
    test('drops the harakat and the marks', () {
      expect(QuranSearch.normalize('فَٱذْكُرُونِىٓ أَذْكُرْكُمْ'),
          'فذكروني اذكركم');
    });

    test('spells the mushaf\'s way and the typed way the same', () {
      for (final (mushaf, typed) in [
        ('فِى', 'في'),
        ('ٱلصَّلَوٰةَ', 'الصلاة'),
        ('ٱلزَّكَوٰةَ', 'الزكاة'),
        ('ءَامَنُوا۟', 'آمنوا'),
        ('ٱلرَّحْمَـٰنِ', 'الرحمن'),
        ('ٱلصَّـٰلِحَـٰتِ', 'الصالحات'),
        ('إِبْرَٰهِـۧمَ', 'ابراهيم'),
        ('إِنَّ ٱللَّهَ', 'ان الله'),
        ('عَلَىٰ', 'على'),
      ]) {
        expect(QuranSearch.normalize(mushaf), QuranSearch.normalize(typed),
            reason: '$mushaf vs $typed');
      }
    });

    test('keeps a word\'s first alef and drops the rest', () {
      expect(QuranSearch.normalize('الصالحات'), 'الصلحت');
      expect(QuranSearch.normalize('أذكركم'), 'اذكركم');
      expect(QuranSearch.normalize('الله'), 'الله');
    });
  });

  group('search', () {
    test('finds a verse by its plain words', () async {
      final hits = await QuranSearch.search('فاذكروني اذكركم');
      expect(hits.map((h) => '${h.surah}:${h.ayah}'), ['2:152']);
      expect(hits.single.text, contains('فَٱذْكُرُونِ'));
    });

    test('however the alef and the hamza were typed', () async {
      for (final q in ['آمنوا وعملوا الصالحات', 'امنوا وعملوا الصالحات']) {
        final hits = await QuranSearch.search(q);
        expect(hits, isNotEmpty, reason: q);
      }
    });

    test('finds الصلاة though the mushaf writes الصلوة', () async {
      final hits = await QuranSearch.search('اقيموا الصلاة');
      expect(hits, isNotEmpty);
    });

    test('nothing for one letter, and never more than the limit', () async {
      expect(await QuranSearch.search('ا'), isEmpty);
      expect(await QuranSearch.search('الله', limit: 10), hasLength(10));
    });

    test('counts letters after normalizing', () {
      expect(QuranSearch.letterCount('فِى'), 2);
      expect(QuranSearch.letterCount('2:255'), 0);
    });
  });
}
