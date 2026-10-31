import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/recitation_service.dart';

/// The verse picker's listen of a surah-file voice comes in runs, and
/// the player changes files only between runs: inside one, a reciter
/// who carries a verse into the next (wasl) is heard doing it, with no
/// stop between the verses.
void main() {
  int end(List<int> ms, int ayah, int stop, {bool carriesOn = false}) =>
      RecitationService.liveRunEnd(ms, ayah, stop, carriesOn: carriesOn);
  List<int> even(int n, int ms) => List.filled(n, ms);

  test('a short surah comes whole: no seam anywhere in Al-Fatiha', () {
    const fatiha = [6200, 5100, 4300, 4800, 5600, 5200, 11800];
    expect(end(fatiha, 1, 7), 7);
    expect(end(fatiha, 4, 7), 7);
  });

  test('a long surah starts on a short run, then long ones', () {
    final ms = even(100, 10000);
    expect(end(ms, 1, 100), 2);
    expect(end(ms, 3, 100, carriesOn: true), 11);
  });

  test('no short run is left at the end of a surah', () {
    // 3 to 11 would leave ayah 12, ten seconds, a file of its own.
    expect(end(even(12, 10000), 3, 12, carriesOn: true), 12);
  });

  test('a run stops short of the next one', () {
    final ms = even(100, 10000);
    expect(end(ms, 3, 6, carriesOn: true), 6);
    expect(end(ms, 6, 6), 6);
  });

  test('one long ayah is a run by itself', () {
    expect(end(const [120000, 120000, 120000], 1, 3), 1);
  });
}
