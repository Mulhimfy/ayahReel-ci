import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/breath_pace.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_lines.dart';

/// A loudness envelope in 10 ms steps: voice (60 dB) inside the [voiced]
/// windows, in ms, and silence (20 dB) everywhere else.
List<double> envelope(int totalMs, List<(int, int)> voiced) => [
      for (var k = 0; k < totalMs ~/ 10; k++)
        voiced.any((v) => k * 10 >= v.$1 && k * 10 < v.$2) ? 60.0 : 20.0,
    ];

/// Where the light is told the words of a verse with no word timing
/// are: inside the voice the recording has, waiting through its pauses.
void main() {
  // What SurahSlice.quietBelow makes of the envelopes here.
  const quiet = 34.0;
  // Four words of three letters.
  const words = ['كتب', 'كتب', 'كتب', 'كتب'];

  test('the words fill the voice the recording has, not a guess at it', () {
    final w = BreathPace.stretch(
        words, envelope(5000, [(400, 4400)]), quiet, 0, 5000)!;
    expect(w, [(400, 1400), (1400, 2400), (2400, 3400), (3400, 4400)]);
  });

  test('the light waits through a breath', () {
    final w = BreathPace.stretch(words,
        envelope(5400, [(400, 2400), (3000, 5000)]), quiet, 0, 5400)!;
    // 4 s of voice, a second a word; nothing moves from 2.4 s to 3 s.
    expect(w, [(400, 1400), (1400, 2400), (3000, 4000), (4000, 5000)]);
  });

  test('a gap shorter than a breath is ridden over, as before', () {
    final w = BreathPace.stretch(words,
        envelope(5000, [(400, 2400), (2600, 4600)]), quiet, 0, 5000)!;
    expect(w[1].$1, 1450);
    expect(w[2].$1, 2500);
  });

  test('a pause sign takes no time, and a madd a little more', () {
    expect(BreathPace.weightOf('ۚ'), 0);
    expect(BreathPace.weightOf('كتب'), 3);
    // Jim, alif with the madd sign, hamza: three letters and a madd.
    expect(BreathPace.weightOf('جَآءَ'), 3 + BreathPace.maddWeight);
    final w = BreathPace.stretch(
        ['كتب', 'ۚ', 'كتب'], envelope(3000, [(0, 3000)]), quiet, 0, 3000)!;
    expect(w, [(0, 1500), (1500, 1500), (1500, 3000)]);
  });

  test('a stretch the loudness cannot read keeps the even pace', () {
    // Silence throughout.
    expect(BreathPace.stretch(words, envelope(5000, []), quiet, 0, 5000),
        isNull);
    // A second of voice in five: noise, a mark set wide, a wrong file.
    expect(
        BreathPace.stretch(
            words, envelope(5000, [(0, 1000)]), quiet, 0, 5000),
        isNull);
  });

  test('a cut verse is read line by line, each in its own window', () {
    VersePart part(int i, int k0, int k1, int from, int to) => VersePart(
          ayah: 1,
          index: i,
          count: 2,
          tokenStart: k0,
          tokenEnd: k1,
          startMs: from,
          endMs: to,
          arabic: words.sublist(k0, k1).join(' '),
          translation: '',
          fit: 1,
        );
    final times = BreathPace.verseTimes(
      tokens: words,
      env: envelope(5400, [(400, 2400), (3000, 5000)]),
      quiet: quiet,
      verseStartMs: 0,
      verseEndMs: 5400,
      parts: [part(0, 0, 2, 0, 2700), part(1, 2, 4, 2700, 5400)],
    );
    expect(times, [(400, 1400), (1400, 2400), (3000, 4000), (4000, 5000)]);
  });

  test('a reel paces only the verses it is asked for, from their starts',
      () {
    const verse = 'كتب كتب كتب كتب';
    final times = BreathPace.reelTimes(
      env: envelope(10000, [(400, 4400), (5400, 9400)]),
      recitation: const Recitation(
        reciterId: 'upload',
        surah: 1,
        audioPath: '',
        timings: [AyahTiming(1, 0, 5000), AyahTiming(2, 5000, 10000)],
      ),
      ayahs: const [
        Ayah(number: 1, arabic: verse, translation: ''),
        Ayah(number: 2, arabic: verse, translation: ''),
      ],
      startAyah: 1,
      endAyah: 2,
      wants: (a) => a == 2,
    );
    expect(times.keys, [2]);
    expect(times[2], [(400, 1400), (1400, 2400), (2400, 3400), (3400, 4400)]);
  });
}
