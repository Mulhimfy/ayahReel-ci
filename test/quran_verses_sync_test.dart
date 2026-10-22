import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/quran_verses.dart';
import 'package:ayah_reels/data/surah_index.dart';

/// The Android and iOS widgets carry their own copy of the verse list,
/// because neither is drawn by Flutter and neither can read a Dart
/// constant. Three copies of the same ninety verses are three chances
/// to drift, and a widget showing a different verse from the card — or
/// a different spelling of the same one — would be the kind of bug
/// nobody reports and everybody notices. So: the copies are generated
/// from one source (tool/quran_verses.py), and this test refuses a
/// build where any of them has wandered.
void main() {
  // `flutter test` runs from the project root.
  const copies = [
    'android/app/src/main/assets/quran_verses.json',
    'ios/AyahWidget/quran_verses.json',
  ];

  Map<String, dynamic> load(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue,
        reason: '$path is missing; run `python3 tool/quran_verses.py gen`');
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  }

  void same(Map<String, dynamic> j, QuranVerse v, String where) {
    final surah = surahIndex[v.surah - 1];
    expect(j['surah'], v.surah, reason: where);
    expect(j['start'], v.startAyah, reason: where);
    expect(j['end'], v.endAyah, reason: where);
    expect(j['surahName'], v.surahName, reason: where);
    expect(j['surahNameAr'], surah.nameArabic, reason: where);
    expect(j['arabic'], v.arabic, reason: where);
    expect(j['shown'], v.shown, reason: where);
    expect(j['translation'], v.translation, reason: where);
  }

  for (final path in copies) {
    test('$path matches the Dart list, verse for verse', () {
      final doc = load(path);
      same(doc['jumuah'] as Map<String, dynamic>, jumuahVerse, "$path jumu'ah");
      final list = (doc['verses'] as List).cast<Map<String, dynamic>>();
      expect(list, hasLength(quranVerses.length), reason: path);
      for (var i = 0; i < list.length; i++) {
        same(list[i], quranVerses[i], '$path #$i');
      }
    });
  }

  test('the two native copies are byte-identical', () {
    final a = File(copies[0]).readAsStringSync();
    final b = File(copies[1]).readAsStringSync();
    expect(a, b);
  });
}
