import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/reel_duration.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/render/scene_plan.dart';
import 'package:ayah_reels/state/creation_state.dart' show ScenePacing;

/// A reel that opens a surah on its first verse opens on the basmala,
/// as the voice recites it: a window numbered 0 at the head of the
/// recording (see `RecitationService.withBasmala`), which the reel then
/// starts at, shows as a unit of its own, and gives to verse 1's scene.
void main() {
  // The basmala, then three verses after it.
  const opened = Recitation(
    reciterId: 'v',
    surah: 36,
    audioPath: '/x.m4a',
    timings: [
      AyahTiming(0, 0, 5200),
      AyahTiming(1, 5200, 8000),
      AyahTiming(2, 8000, 12000),
      AyahTiming(3, 12000, 15000),
    ],
  );
  // The same verses with none.
  const plain = Recitation(
    reciterId: 'v',
    surah: 36,
    audioPath: '/y.m4a',
    timings: [
      AyahTiming(1, 0, 2800),
      AyahTiming(2, 2800, 6800),
      AyahTiming(3, 6800, 9800),
    ],
  );

  test('a reel from verse 1 starts at the basmala, from any other verse '
      'at the verse', () {
    expect(opened.opensWithBasmala, isTrue);
    expect(plain.opensWithBasmala, isFalse);
    expect(opened.startOf(1), 0);
    expect(opened.startOf(2), 8000);
    expect(plain.startOf(1), 0);
    // Verse windows are found by number whatever the recording opens on.
    expect(opened.timing(2).startMs, 8000);
    expect(opened.covers(1, 3), isTrue);
  });

  test('the basmala is a unit of its own before verse 1, and only for a '
      'reel from verse 1', () {
    final units = VerseUnit.of(opened, 1, 3, null);
    expect(units.map((u) => (u.ayah, u.startMs, u.endMs)).toList(), [
      (0, 0, 5200),
      (1, 5200, 8000),
      (2, 8000, 12000),
      (3, 12000, 15000),
    ]);
    expect(VerseUnit.indexAt(units, 100), 0);
    expect(VerseUnit.of(opened, 2, 3, null).map((u) => u.ayah), [2, 3]);
    expect(VerseUnit.of(plain, 1, 3, null).first.ayah, 1);
  });

  test("verse 1's scene holds the basmala, a verse at a time or a line", () {
    final byVerse = ScenePlan.slotsFor(
      recitation: opened,
      startAyah: 1,
      endAyah: 3,
      pacing: ScenePacing.perAyah,
    );
    expect(byVerse.first.startMs, 0);
    expect(byVerse.first.ayah, 1);
    final byLine = ScenePlan.slotsFor(
      recitation: opened,
      startAyah: 1,
      endAyah: 3,
      pacing: ScenePacing.perLine,
      units: VerseUnit.of(opened, 1, 3, null),
    );
    expect(byLine.first.startMs, 0);
    expect(byLine, hasLength(4));
  });

  test('on by default, kept off once turned off', () {
    expect(AppSettings.defaults.basmala, isTrue);
    expect(AppSettings.fromJson(const {}).basmala, isTrue);
    expect(
        AppSettings.fromJson(
                AppSettings.defaults.copyWith(basmala: false).toJson())
            .basmala,
        isFalse);
  });

  test("the basmala's length at a voice's pace, which a take that opens "
      'with the isti\'adha runs well past', () {
    expect(ReelDuration.basmalaMs, 5570);
  });
}
