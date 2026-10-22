import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/reel_duration.dart';
import 'package:ayah_reels/data/user_audio_service.dart';

/// An uploaded recitation is one unbroken file, so where its verses
/// fall has to be worked out rather than counted. These tests pin the
/// working-out: the parsing of what FFmpeg heard, and the placement
/// that turns it into a timing table.
///
/// All of it is pure — no plugins, no device — which is the whole
/// reason [UserAudioService.plan] takes its silences as an argument
/// instead of going and finding them.
void main() {
  /// The boundaries the letter-count model alone would propose across
  /// [from]..[to] — what [UserAudioService.plan] starts from before any
  /// silence is allowed to correct it.
  List<int> predicted(int startAyah, int endAyah, int from, int to) {
    final span = to - from;
    final weights = [
      for (var a = startAyah; a <= endAyah; a++)
        ReelDuration.estimateMs(fatiha, startAyah: a, endAyah: a),
    ];
    final total = weights.fold<int>(0, (s, w) => s + w);
    final out = <int>[from];
    var acc = 0;
    for (var i = 0; i < weights.length - 1; i++) {
      acc += weights[i];
      out.add(from + (span * acc / total).round());
    }
    return out..add(to);
  }

  group('silencedetect parsing', () {
    test('pairs every start with its end, in time order', () {
      const log = '''
[silencedetect @ 0x1] silence_start: 0
[silencedetect @ 0x1] silence_end: 0.512 | silence_duration: 0.512
frame= 12 fps=0 q=-0.0 size=N/A time=00:00:06.00
[silencedetect @ 0x1] silence_start: 6.031
[silencedetect @ 0x1] silence_end: 6.531 | silence_duration: 0.5
''';
      final gaps = UserAudioService.parseSilence(log);
      expect(gaps.length, 2);
      expect(gaps.first.startMs, 0);
      expect(gaps.first.endMs, 512);
      expect(gaps.last.startMs, 6031);
      expect(gaps.last.endMs, 6531);
      expect(gaps.last.midMs, 6281);
    });

    test('a start with no end is not a gap', () {
      // What a run cut short leaves behind: the file ends quiet and
      // FFmpeg never reports the close.
      const log = 'silence_start: 3.0\n';
      expect(UserAudioService.parseSilence(log), isEmpty);
    });

    test('nothing in the log is no gaps, not an error', () {
      expect(UserAudioService.parseSilence('ffmpeg version 6.0\n'), isEmpty);
    });
  });

  group('placing verses in an upload', () {
    test('lead-in and run-out silence belong to no verse', () {
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 1,
        endAyah: 3,
        durationMs: 20000,
        silences: const [
          SilenceGap(0, 500), // lead-in
          SilenceGap(16000, 20000), // run-out
        ],
      );
      // A little of each is handed back: the breath before the first
      // word belongs with it.
      expect(t.first.startMs, 380);
      expect(t.last.endMs, 16120);
    });

    test('a boundary snaps to the breath nearest it', () {
      const from = 380;
      const to = 16120;
      final p = predicted(1, 3, from, to);
      // Gaps sitting exactly where the text says the joints are: the
      // snap is certain, so the result is exactly their middles.
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 1,
        endAyah: 3,
        durationMs: 20000,
        silences: [
          const SilenceGap(0, 500),
          SilenceGap(p[1] - 200, p[1] + 200),
          SilenceGap(p[2] - 200, p[2] + 200),
          const SilenceGap(16000, 20000),
        ],
      );
      expect(t.map((w) => w.ayah), [1, 2, 3]);
      expect(t[0].endMs, p[1]);
      expect(t[1].endMs, p[2]);
    });

    test('a breath too far off is left alone', () {
      const from = 380;
      const to = 16120;
      final p = predicted(1, 3, from, to);
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 1,
        endAyah: 3,
        durationMs: 20000,
        silences: [
          const SilenceGap(0, 500),
          // Deep inside the last verse, nowhere near a joint: a pause
          // the reciter took mid-ayah, which is exactly the kind of gap
          // that must not move a boundary.
          const SilenceGap(to - 900, to - 500),
          const SilenceGap(16000, 20000),
        ],
      );
      expect(t[0].endMs, p[1]);
      expect(t[1].endMs, p[2]);
    });

    test('no silences at all still places every verse', () {
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 1,
        endAyah: 7,
        durationMs: 46000,
        silences: const [],
      );
      expect(t.length, 7);
      expect(t.first.ayah, 1);
      expect(t.last.ayah, 7);
      expect(t.first.startMs, 0);
      expect(t.last.endMs, 46000);
      for (var i = 1; i < t.length; i++) {
        expect(t[i].startMs, t[i - 1].endMs, reason: 'no holes');
        expect(t[i].durationMs, greaterThan(0));
      }
    });

    test('one verse takes the whole audible span', () {
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 4,
        endAyah: 4,
        durationMs: 9000,
        silences: const [SilenceGap(0, 1000), SilenceGap(8000, 9000)],
      );
      expect(t.length, 1);
      expect(t.single.ayah, 4);
      expect(t.single.startMs, 880);
      expect(t.single.endMs, 8120);
    });

    test('a noisy detection cannot put two verses on one breath', () {
      // Forty gaps for six joints: whatever gets claimed, the table
      // still has to come out ascending and one verse per slice.
      final noise = [
        for (var ms = 500; ms < 45000; ms += 1100)
          SilenceGap(ms, ms + 300),
      ];
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 1,
        endAyah: 7,
        durationMs: 46000,
        silences: noise,
      );
      expect(t.length, 7);
      for (var i = 1; i < t.length; i++) {
        expect(t[i].startMs, t[i - 1].endMs);
        expect(t[i].durationMs,
            greaterThanOrEqualTo(UserAudioService.minAyahMs));
      }
    });

    test('the run is contiguous and starts at the ayah asked for', () {
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 3,
        endAyah: 6,
        durationMs: 30000,
        silences: const [],
      );
      expect(t.map((w) => w.ayah), [3, 4, 5, 6]);
    });
  });

  group('marks and timings are inverses', () {
    test('a table survives the round trip', () {
      final t = UserAudioService.plan(
        ayahs: fatiha,
        startAyah: 1,
        endAyah: 5,
        durationMs: 28000,
        silences: const [],
      );
      final again = UserAudioService.timingsFrom(
          UserAudioService.marksOf(t), t.first.ayah);
      expect(again.length, t.length);
      for (var i = 0; i < t.length; i++) {
        expect(again[i].ayah, t[i].ayah);
        expect(again[i].startMs, t[i].startMs);
        expect(again[i].endMs, t[i].endMs);
      }
    });

    test('marks pushed together are pushed back apart', () {
      // What a hand edit can ask for: three boundaries on one instant.
      final t = UserAudioService.timingsFrom([1000, 1000, 1000, 5000], 10);
      expect(t.map((w) => w.ayah), [10, 11, 12]);
      for (var i = 0; i < t.length; i++) {
        expect(t[i].durationMs,
            greaterThanOrEqualTo(UserAudioService.minAyahMs));
      }
      for (var i = 1; i < t.length; i++) {
        expect(t[i].startMs, t[i - 1].endMs);
      }
    });

    test('out-of-order marks come back in order', () {
      final t = UserAudioService.timingsFrom([4000, 1000, 9000], 1);
      expect(t.first.startMs, lessThan(t.first.endMs));
      expect(t.last.startMs, lessThan(t.last.endMs));
      expect(t[1].startMs, t[0].endMs);
    });
  });
}
