/// Where each of the thirty juz begins.
///
/// The juz is the mushaf's division of the Quran into thirty
/// roughly equal parts — the unit a month of Ramadan is read in, and
/// the scope most people mean when they say what they are learning.
/// Each entry is the surah and ayah a juz opens on; it runs to the
/// ayah before the next one. Generated from the quran.com API by
/// tool/surah_facts.py; static forever, like the surah index.
library;

/// (surah, ayah) a juz begins on, index 0 being juz 1.
const List<(int, int)> juzStarts = [
  (1, 1), // juz 1
  (2, 142), // juz 2
  (2, 253), // juz 3
  (3, 93), // juz 4
  (4, 24), // juz 5
  (4, 148), // juz 6
  (5, 82), // juz 7
  (6, 111), // juz 8
  (7, 88), // juz 9
  (8, 41), // juz 10
  (9, 93), // juz 11
  (11, 6), // juz 12
  (12, 53), // juz 13
  (15, 1), // juz 14
  (17, 1), // juz 15
  (18, 75), // juz 16
  (21, 1), // juz 17
  (23, 1), // juz 18
  (25, 21), // juz 19
  (27, 56), // juz 20
  (29, 46), // juz 21
  (33, 31), // juz 22
  (36, 28), // juz 23
  (39, 32), // juz 24
  (41, 47), // juz 25
  (46, 1), // juz 26
  (51, 31), // juz 27
  (58, 1), // juz 28
  (67, 1), // juz 29
  (78, 1), // juz 30
];

/// The juz a verse falls in, 1..30.
int juzOf(int surah, int ayah) {
  var juz = 1;
  for (var i = 1; i < juzStarts.length; i++) {
    final (s, a) = juzStarts[i];
    if (surah > s || (surah == s && ayah >= a)) {
      juz = i + 1;
    } else {
      break;
    }
  }
  return juz;
}

/// The first verse of [juz], as (surah, ayah).
(int, int) juzStart(int juz) => juzStarts[juz - 1];

/// The juz a surah opens in.
int juzOfSurah(int surah) => juzOf(surah, 1);
