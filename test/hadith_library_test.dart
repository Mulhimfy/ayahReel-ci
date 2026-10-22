import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/hadith_library.dart';
import 'package:ayah_reels/data/quran_search.dart';
import 'package:ayah_reels/data/verse_translation.dart';

/// The hadith library, as the card composer uses it.
///
/// The asset itself is checked by `tool/verify_hadith.py` — row
/// alignment, grading, glyph coverage — which needs fontTools and the
/// whole corpus. What is checked here is the half that is Dart: that
/// the files load, that a search finds what a person would type, and
/// that the piece of a hadith the finder offers first is the saying
/// rather than the chain in front of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Read off disk rather than through the bundle: the loader is the
    // same either way, and this keeps the test honest about what it
    // is exercising rather than about how an asset is served.
    final meta = File('assets/hadith/meta.json').readAsStringSync();
    final ar = File('assets/hadith/ar.json.gz').readAsBytesSync();
    final en = File('assets/hadith/en.json.gz').readAsBytesSync();
    await HadithLibrary.loadFrom(meta: meta, arabic: ar, translation: en);
  });

  test('the library loads whole, with every collection named', () {
    expect(HadithLibrary.isLoaded, isTrue);
    expect(HadithLibrary.count, greaterThan(4000));
    expect(HadithLibrary.collections, isNotEmpty);
    for (final c in HadithLibrary.collections) {
      expect(c.id, isNotEmpty);
      expect(c.en, isNotEmpty);
      expect(c.ar, isNotEmpty);
    }
    expect(HadithLibrary.topics, contains('mercy'));
    expect(HadithLibrary.credit, isNotEmpty);
  });

  test('every hadith carries its Arabic, its reference and a real '
      'collection', () {
    final ids = {for (final c in HadithLibrary.collections) c.id};
    for (var i = 0; i < HadithLibrary.count; i += 37) {
      final h = HadithLibrary.at(i)!;
      expect(h.arabic, isNotEmpty, reason: 'row $i has no Arabic');
      expect(h.translation, isNotEmpty, reason: 'row $i has no translation');
      expect(h.number, greaterThan(0));
      expect(ids, contains(h.collection));
    }
    expect(HadithLibrary.at(-1), isNull);
    expect(HadithLibrary.at(HadithLibrary.count), isNull);
  });

  test('an English search finds the words somebody would type', () {
    final hits = HadithLibrary.search('loves for his brother');
    expect(hits, isNotEmpty);
    expect(hits.first.translation.toLowerCase(),
        contains('loves for his brother'));
    // The two Sahihs and the two forties come first — the collections
    // that answer for themselves.
    expect(
      const {'bukhari', 'muslim', 'nawawi', 'qudsi'},
      contains(hits.first.collection),
    );
  });

  test('punctuation and case are not part of the question', () {
    final plain = HadithLibrary.search('prophet said');
    final loud = HadithLibrary.search('PROPHET, said!');
    expect(plain, isNotEmpty);
    expect(loud.map((h) => h.index), plain.map((h) => h.index));
  });

  test('an Arabic search reads the way the Quran search does', () {
    // Typed plainly, with no harakat and the easy spelling — which is
    // how everybody types Arabic and not at all how these editions
    // spell it.
    final hits = HadithLibrary.search('انما الاعمال بالنيات');
    expect(hits, isNotEmpty);
    expect(QuranSearch.normalize(hits.first.arabic),
        contains(QuranSearch.normalize('انما الاعمال بالنيات')));
  });

  test('one letter is not a search', () {
    expect(HadithLibrary.search('a'), isEmpty);
    expect(HadithLibrary.search(''), isEmpty);
  });

  test('a topic gathers hadith and an unknown one gathers none', () {
    final mercy = HadithLibrary.byTopic('mercy', limit: 12);
    expect(mercy, isNotEmpty);
    expect(mercy.length, lessThanOrEqualTo(12));
    expect(HadithLibrary.byTopic('nonsense'), isEmpty);
  });

  test('the quotable part is the saying, not the chain', () {
    const withChain = 'عَنْ أَبِي هُرَيْرَةَ قَالَ قَالَ رَسُولُ اللَّهِ '
        '" مَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الآخِرِ فَلْيَقُلْ '
        'خَيْرًا أَوْ لِيَصْمُتْ "';
    final quote = HadithLibrary.quotable(withChain);
    expect(quote, startsWith('مَنْ كَانَ'));
    expect(quote, isNot(contains('عَنْ أَبِي هُرَيْرَةَ')));
    // Nothing marked off: the whole thing is what there is.
    const plain = 'الدِّينُ النَّصِيحَةُ';
    expect(HadithLibrary.quotable(plain), plain);
    // A pair of quotes around nothing is not a quotation.
    expect(HadithLibrary.quotable('قال " نعم "'), 'قال " نعم "');
  });

  test('the German reader is shown the English edition, and is told so',
      () {
    // The corpus has no German; the finder says which edition it is
    // showing rather than pretending.
    expect(HadithLibrary.langFor(VerseTranslation.german), 'en');
    expect(HadithLibrary.langFor(VerseTranslation.urdu), 'ur');
    expect(HadithLibrary.langFor(VerseTranslation.indonesian), 'id');
    expect(HadithLibrary.langFor(VerseTranslation.english), 'en');
  });

  test('the shipped files are the same length as the index', () {
    final meta = jsonDecode(File('assets/hadith/meta.json').readAsStringSync())
        as Map<String, dynamic>;
    final rows = (meta['rows'] as List).length;
    for (final lang in ['ar', 'en', 'ur', 'id']) {
      final raw = gzip.decode(File('assets/hadith/$lang.json.gz')
          .readAsBytesSync());
      final list = jsonDecode(utf8.decode(raw)) as List;
      expect(list.length, rows, reason: '$lang is out of step with the rows');
    }
  });
}
