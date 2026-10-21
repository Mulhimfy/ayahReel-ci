import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/live_recitation.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/recitation_service.dart' show LiveClip;

/// The recitation at the head of the verse picker keeps a timeline of
/// the whole surah, and every move on it — ten seconds either way, a
/// pull, a tap on a verse — lands on an ayah and a place inside it.
/// Nothing sounds under test (no plugin answers), so this is the
/// arithmetic alone: the place moves exactly as it would on a phone.
void main() {
  final voice = reciters.firstWhere((r) => r.hasBundledFatiha);
  final windows = voice.timings!;

  test('the bundled Al-Fatiha is timed exactly, from the first beat',
      () async {
    final live = LiveRecitation();
    addTearDown(live.dispose);
    await live.open(voice, 1, fatiha);
    expect(LiveRecitation.enabled, isFalse);
    expect(live.status, LiveStatus.paused);
    expect(live.ayah, 1);
    expect(live.ayahCount, fatiha.length);
    expect(live.timelineExact, isTrue);
    expect(live.totalMs, windows.fold<int>(0, (s, w) => s + w.durationMs));
    expect(live.ayahStarts.first, 0);
    expect(live.ayahStarts[1], windows.first.durationMs);
  });

  test('a move lands on the ayah it reaches, and inside it', () async {
    final live = LiveRecitation();
    addTearDown(live.dispose);
    await live.open(voice, 1, fatiha);

    await live.seekTo(live.ayahStarts[3] + 10);
    expect(live.ayah, 4);
    expect(live.positionMs, live.ayahStarts[3] + 10);

    // Ten seconds on from there, wherever that falls.
    final before = live.positionMs;
    await live.skip(10000);
    final want = (before + 10000).clamp(0, live.totalMs - 1);
    expect(live.positionMs, want);
    expect(live.ayah, live.ayahAt(want));

    // Past either end: held at the end that was passed.
    await live.skip(-1000000);
    expect(live.ayah, 1);
    expect(live.positionMs, 0);
    await live.skip(1000000);
    expect(live.ayah, fatiha.length);

    await live.seekAyah(3);
    expect(live.ayah, 3);
    expect(live.positionMs, live.ayahStarts[2]);
    expect(live.ayahProgress, 0);
  });

  test('every point of the timeline belongs to exactly one ayah', () async {
    final live = LiveRecitation();
    addTearDown(live.dispose);
    await live.open(voice, 1, fatiha);
    for (var a = 1; a <= fatiha.length; a++) {
      final start = live.ayahStarts[a - 1];
      expect(live.ayahAt(start), a);
      if (start > 0) expect(live.ayahAt(start - 1), a - 1);
    }
    expect(live.ayahAt(live.totalMs - 1), fatiha.length);
  });

  test('an open at a later ayah starts there, and clear empties the line',
      () async {
    final live = LiveRecitation();
    addTearDown(live.dispose);
    await live.open(voice, 1, fatiha, from: 5);
    expect(live.ayah, 5);
    expect(live.positionMs, live.ayahStarts[4]);
    live.clear();
    expect(live.status, LiveStatus.idle);
    expect(live.totalMs, 0);
    expect(live.ayahCount, 0);
  });

  test("a per-ayah file's words move past the silence its listen skips", () {
    const spans = [WordSpan(0, 1, 400, 900), WordSpan(1, 2, 900, 1500)];
    // The file's own window starts at its first sample; the listen
    // starts 340 ms in, where the voice does.
    const trimmed = LiveClip(1, 'f.mp3', 340, 2000, windowMs: 0);
    expect([for (final s in LiveRecitation.inClip(spans, trimmed)) s.startMs],
        [60, 560]);
    // A window cut out of a longer file starts where its clip does.
    const cut = LiveClip(1, 'surah.mp3', 5000, 9000);
    expect(identical(LiveRecitation.inClip(spans, cut), spans), isTrue);
  });
}
