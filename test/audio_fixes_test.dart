import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/user_audio_service.dart';

/// Pins the review fixes of 2026-10-05 that are pure logic: reading
/// silence marks out of `ametadata`'s file, escaping that file's path
/// for the filter graph, and keeping hand-edited marks inside the
/// recording.
void main() {
  group('silence marks', () {
    test("ametadata's print-out is read like the log", () {
      // What `ametadata=mode=print:file=…` writes after silencedetect,
      // whatever FFmpeg's log level: the same marks, as `key=value`.
      const marks = '''
frame:0    pts:0       pts_time:0
lavfi.silence_start=0
frame:22   pts:22528   pts_time:0.510839
lavfi.silence_end=0.512
lavfi.silence_duration=0.512
frame:55   pts:56320   pts_time:1.277098
lavfi.silence_start=0.999955
frame:86   pts:88064   pts_time:1.996916
lavfi.silence_end=2.000068
lavfi.silence_duration=1.000113
''';
      final gaps = UserAudioService.parseSilence(marks);
      expect(gaps.length, 2);
      expect(gaps.first.startMs, 0);
      expect(gaps.first.endMs, 512);
      expect(gaps.last.startMs, 1000);
      expect(gaps.last.endMs, 2000);
    });

    test('a start with no end is still not a gap', () {
      expect(UserAudioService.parseSilence('lavfi.silence_start=3.5\n'),
          isEmpty);
    });
  });

  group('filter path', () {
    test('an ordinary app path is left alone', () {
      const p = '/data/user/0/app/cache/ua_silence_1.txt';
      expect(UserAudioService.filterPath(p), p);
    });

    test('escaped for both the option and the graph', () {
      // Checked against desktop FFmpeg 8: this spelling opens
      // `/x/a:b/it's,x[1];.txt`.
      expect(UserAudioService.filterPath("/x/a:b/it's,x[1];.txt"),
          r"/x/a\\:b/it\\\'s\,x\[1\]\;.txt");
    });
  });

  group('timings stay inside the recording', () {
    const gap = UserAudioService.minAyahMs;

    test('a last mark past the end is held at the end', () {
      final t =
          UserAudioService.timingsFrom([0, 1000, 2000, 9500], 1, endMs: 9000);
      expect(t.last.endMs, 9000);
      expect(t.first.startMs, 0);
      expect(t[1].startMs, 1000);
    });

    test('marks pushed apart near the end are pulled back, not out', () {
      // Three boundaries dragged onto one instant just before the end:
      // pushing them apart used to carry the last one past the file.
      final t = UserAudioService.timingsFrom([0, 8900, 8900, 8900], 1,
          endMs: 9000);
      expect(t.last.endMs, 9000);
      for (final w in t) {
        expect(w.durationMs, greaterThanOrEqualTo(gap));
      }
      for (var i = 1; i < t.length; i++) {
        expect(t[i].startMs, t[i - 1].endMs);
      }
    });

    test('a file too short for every verse still ascends', () {
      final t = UserAudioService.timingsFrom([0, 0, 0], 1, endMs: 500);
      expect(t.first.startMs, 0);
      for (final w in t) {
        expect(w.durationMs, greaterThanOrEqualTo(gap));
      }
    });

    test('marks inside the end are untouched', () {
      final t = UserAudioService.timingsFrom([100, 4000, 8000], 1,
          endMs: 9000);
      expect([t[0].startMs, t[0].endMs, t[1].endMs], [100, 4000, 8000]);
    });
  });
}
