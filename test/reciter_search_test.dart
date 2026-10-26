import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/reciter_search.dart';

Reciter _r(String id, String name, String ar, [String style = 'Murattal']) =>
    Reciter(
      id: id,
      name: name,
      arabicName: ar,
      style: style,
      source: AyahFiles.everyAyah(id),
    );

void main() {
  final list = [
    _r('dussary', 'Yasser Ad-Dussary', 'ياسر الدوسري'),
    _r('ibrahim_dosari', 'Ibrahim Al-Dosari', 'إبراهيم الدوسري'),
    _r('shuraym', 'Saud Ash-Shuraym', 'سعود الشريم'),
    _r('thubaiti', 'Abdulbari Al-Thubaiti', 'عبد الباري الثبيتي'),
    _r('hudhaify', 'Ali Al-Hudhaify', 'علي الحذيفي'),
    _r('husary', 'Mahmoud Al-Husary', 'محمود الحصري',
        'Murattal · measured, classical'),
    _r('husary_mujawwad', 'Al-Husary · Mujawwad', 'محمود الحصري',
        'Mujawwad · ornate, masterly'),
    _r('bukhatir', 'Salah Bukhatir', 'صلاح بوخاطر'),
    _r('salamah', 'Yaser Salamah', 'ياسر سلامة'),
    _r('luhaidan', 'Mohammed Al-Luhaidan', 'محمد اللحيدان'),
    _r('sobhi', 'Islam Sobhi', 'إسلام صبحي'),
  ];
  List<String> find(String q, {String Function(Reciter)? styleOf}) =>
      ReciterSearch.filter(list, q, styleOf: styleOf).map((r) => r.id).toList();

  test('an empty query is the whole list, in its order', () {
    expect(find(''), list.map((r) => r.id));
    expect(find('   '), list.map((r) => r.id));
  });

  test('a name is found however it is transliterated', () {
    expect(find('dosari'), ['dussary', 'ibrahim_dosari']);
    expect(find('Aldossary'), ['dussary', 'ibrahim_dosari']);
    expect(find('shuraim'), ['shuraym']);
    expect(find('Toubayti'), ['thubaiti']);
    expect(find('huthaifi'), ['hudhaify']);
    expect(find('Hussary'), ['husary', 'husary_mujawwad']);
  });

  test('Al-Luhaidan, as he is written and searched for', () {
    for (final q in [
      'luhaidan', 'lohaidan', 'al luhaidan', 'Al-Lohaidan', 'Allohaidan',
      'Luhaydan', 'muhammad luhaidan', 'اللحيدان', 'لحيدان',
    ]) {
      expect(find(q), ['luhaidan'], reason: q);
    }
  });

  test('Islam Sobhi, however his name is written', () {
    for (final q in [
      'sobhi', 'subhi', 'sobhy', 'subhy', 'Islam Sobhi', 'islam subhi',
      'صبحي', 'صبحى', 'إسلام صبحي', 'اسلام صبحي',
    ]) {
      expect(find(q), ['sobhi'], reason: q);
    }
  });

  test('the article beside a name is not held against it', () {
    expect(find('al dosari'), ['dussary', 'ibrahim_dosari']);
    expect(find('Al-Dosari'), ['dussary', 'ibrahim_dosari']);
    expect(find('el shuraym'), ['shuraym']);
    expect(find('ash-shuraim'), ['shuraym']);
  });

  test('every word has to match, name or style', () {
    expect(find('husary mujawwad'), ['husary_mujawwad']);
    expect(find('ibrahim dosari'), ['ibrahim_dosari']);
    expect(find('yasser dosari'), ['dussary']);
  });

  test('Arabic is matched on its letters, spaces, hamza and ta marbuta aside',
      () {
    expect(find('الدوسري'), ['dussary', 'ibrahim_dosari']);
    expect(find('دوسري'), ['dussary', 'ibrahim_dosari']);
    expect(find('ابراهيم'), ['ibrahim_dosari']);
    expect(find('عبدالباري'), ['thubaiti']);
    expect(find('سلامه'), ['salamah']);
    expect(find('الحصري'), ['husary', 'husary_mujawwad']);
  });

  test('the style line as shown on screen is searched too', () {
    String german(Reciter r) =>
        r.style.startsWith('Mujawwad') ? 'Mujawwad · verziert' : 'Murattal';
    expect(find('verziert', styleOf: german), ['husary_mujawwad']);
  });

  test('a short fragment matches as typed, not by its consonants', () {
    // "sd" as a skeleton would be in half the list.
    expect(find('sud'), isEmpty);
    expect(find('zzqx'), isEmpty);
  });

  test('every voice in the app is found by its own names', () {
    for (final r in reciters) {
      final byName = ReciterSearch.filter(reciters, r.name);
      expect(byName, contains(r), reason: r.name);
      final byArabic = ReciterSearch.filter(reciters, r.arabicName);
      expect(byArabic, contains(r), reason: r.arabicName);
      final surname = r.name.split(RegExp(r'[\s·]+')).where((w) => w.length > 3);
      expect(ReciterSearch.filter(reciters, surname.last), contains(r),
          reason: '${r.id} by "${surname.last}"');
    }
  });
}
