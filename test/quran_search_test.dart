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

    test('يا ايها: the mushaf joins what is typed apart', () async {
      expect(QuranSearch.loose(QuranSearch.normalize('يَٰٓأَيُّهَا')),
          QuranSearch.loose(QuranSearch.normalize('يا ايها')));
      final hits = await QuranSearch.search('يا ايها');
      expect('${hits.first.surah}:${hits.first.ayah}', '2:21');
      // يَٰبَنِىٓ before إِلَىٰ بَنِىٓ: a match at a word's start first.
      final sons = await QuranSearch.search('يا بني');
      expect('${sons.first.surah}:${sons.first.ayah}', '2:40');
      expect((await QuranSearch.search('يا قوم')).map(_ref), contains('2:54'));
    });

    test('a verse found stays found as the words are typed', () {
      const phrase = 'يا ايها الذين امنوا';
      for (var i = 'يا ايه'.length; i <= phrase.length; i++) {
        final hits = QuranSearch.searchNow(phrase.substring(0, i));
        expect(hits!.map(_ref), contains('2:104'),
            reason: phrase.substring(0, i));
      }
    });

    test('ة typed as ه, شئ for شيء, hamza seated anywhere', () async {
      for (final (q, verse) in [
        ('اقيموا الصلاه', '2:43'),
        ('الملائكه', '2:31'),
        ('علي كل شئ قدير', '2:20'),
        ('هاؤلاء', '2:31'),
      ]) {
        expect((await QuranSearch.search(q)).map(_ref), contains(verse),
            reason: q);
      }
    });

    test('a letter or two wrong, and sound-alikes, still find the verse',
        () async {
      for (final (q, verse) in [
        ('الرهمن الرهيم', '1:1'), // ح typed ه
        ('زلك الكتاب لا ريب فيه', '2:2'), // ذ typed ز
        ('السراط المستقيم', '1:6'), // ص typed س
        ('انا اعطيناك الكوتر', '108:1'), // ث typed ت
        ('ولا الظالين', '1:7'), // ض typed ظ
      ]) {
        final hits = await QuranSearch.search(q);
        expect(hits, isNotEmpty, reason: q);
        expect(_ref(hits.first), verse, reason: q);
      }
    });

    test('a phrase typed on into the next verse', () async {
      final hits = await QuranSearch.search('والعصر ان الانسان لفي خسر');
      expect(hits.map(_ref), ['103:1']);
    });

    test('answers on the spot once the index is read', () {
      expect(QuranSearch.isLoaded, isTrue);
      expect(QuranSearch.searchNow('فاذكروني اذكركم')!.map(_ref), ['2:152']);
    });

    test('counts letters after normalizing', () {
      expect(QuranSearch.letterCount('فِى'), 2);
      expect(QuranSearch.letterCount('2:255'), 0);
    });
  });
}

String _ref(VerseHit h) => '${h.surah}:${h.ayah}';
