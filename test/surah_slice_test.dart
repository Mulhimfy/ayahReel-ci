import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ayah_reels/data/download.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/surah_slice.dart';
import 'package:ayah_reels/data/trouble.dart';

/// The arithmetic behind a reel cut out of a whole-surah file, off the
/// device: frame headers, tag sizes, the byte a moment is at, the two
/// published table formats, and where the cuts land.
void main() {
  group('Mp3Layout.header', () {
    test('reads an MPEG-1 128 kbps 44.1 kHz frame, with and without pad',
        () {
      final h = Mp3Layout.header(Uint8List.fromList([0xFF, 0xFB, 0x90, 0]), 0)!;
      expect(h.kbps, 128);
      expect(h.rate, 44100);
      expect(h.samplesPerFrame, 1152);
      expect(h.length, 417);
      final p = Mp3Layout.header(Uint8List.fromList([0xFF, 0xFB, 0x92, 0]), 0)!;
      expect(p.length, 418);
    });

    test('reads an MPEG-2 64 kbps 22.05 kHz frame', () {
      final h = Mp3Layout.header(Uint8List.fromList([0xFF, 0xF3, 0x80, 0]), 0)!;
      expect(h.kbps, 64);
      expect(h.rate, 22050);
      expect(h.samplesPerFrame, 576);
      expect(h.length, 72 * 64000 ~/ 22050);
    });

    test('refuses what is not a Layer III frame header', () {
      Uint8List b(List<int> x) => Uint8List.fromList(x);
      expect(Mp3Layout.header(b([0xFF, 0xEB, 0x90, 0]), 0), isNull,
          reason: 'reserved version');
      expect(Mp3Layout.header(b([0xFF, 0xFD, 0x90, 0]), 0), isNull,
          reason: 'layer II');
      expect(Mp3Layout.header(b([0xFF, 0xFB, 0xF0, 0]), 0), isNull,
          reason: 'bad bitrate');
      expect(Mp3Layout.header(b([0xFF, 0xFB, 0x9C, 0]), 0), isNull,
          reason: 'reserved sample rate');
      expect(Mp3Layout.header(b([0x49, 0x44, 0x33, 0]), 0), isNull);
      expect(Mp3Layout.header(b([0xFF, 0xFB]), 0), isNull, reason: 'short');
    });
  });

  test('id3Size counts the header, the tag and a footer', () {
    Uint8List tag(int flags) => Uint8List.fromList(
        [0x49, 0x44, 0x33, 3, 0, flags, 0, 0, 2, 1]); // size 2<<7|1 = 257
    expect(Mp3Layout.id3Size(tag(0)), 10 + 257);
    expect(Mp3Layout.id3Size(tag(0x10)), 10 + 257 + 10);
    expect(Mp3Layout.id3Size(Uint8List.fromList([0xFF, 0xFB, 0x90, 0])), 0);
  });

  group('Mp3Layout.parse', () {
    test('finds the first frame past the tag, and an Info header', () {
      final f = _Mp3(frames: 40, info: true, junk: 3);
      final lay = f.layout();
      expect(lay.dataStart, f.tagSize + 3);
      expect(lay.kbps, 128);
      expect(lay.rate, 44100);
      expect(lay.info, isTrue);
      expect(lay.firstAudioFrame, 1);
      expect(lay.total, f.bytes.length);
    });

    test('refuses a variable-bitrate file', () {
      final f = _Mp3(frames: 10, xing: true);
      expect(f.layout, throwsFormatException);
    });

    test('refuses a file with no audio at the start', () {
      expect(
          () => Mp3Layout.parse(Uint8List(10), Uint8List(3000), 3010),
          throwsFormatException);
    });
  });

  test('durationMs is how long the frames play', () {
    final f = _Mp3(frames: 3000, info: true);
    final lay = f.layout();
    expect(lay.durationMs, closeTo(2999 * lay.frameMs, lay.frameMs));
  });

  test('every frame starts where timeOf says it plays', () {
    final f = _Mp3(frames: 3000, info: true);
    final lay = f.layout();
    for (final k in [1, 2, 10, 999, 2999]) {
      expect(lay.timeOf(f.frameStart[k]), closeTo((k - 1) * lay.frameMs, 1e-6),
          reason: 'frame $k');
    }
  });

  group('SurahSlice.fetch', () {
    test('lands on a whole frame and knows when it plays', () async {
      final f = _Mp3(frames: 6000, info: true);
      final lay = f.layout();
      final dir = Directory.systemTemp.createTempSync('slice');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = File('${dir.path}/s.mp3');
      final origin = await SurahSlice.fetch(
        f.client(),
        Uri.parse('https://x/001.mp3'),
        lay,
        out,
        fromMs: 60000,
        toMs: 90000,
      );
      final got = out.readAsBytesSync();
      // A frame, confirmed by the one after it, in the original file.
      final at = f.indexOfBytes(got.sublist(0, 32));
      expect(f.frameStart, contains(at));
      final k = f.frameStart.indexOf(at);
      expect(origin, closeTo((k - 1) * lay.frameMs, 1e-6));
      // It starts at or a little before the moment asked for, and
      // reaches past the end of it.
      expect(origin, lessThanOrEqualTo(60000));
      expect(origin, greaterThan(60000 - 8 * lay.frameMs));
      final endMs = origin + got.length / lay.frameBytes * lay.frameMs;
      expect(endMs, greaterThanOrEqualTo(90000));
    });

    group('on a network that breaks', () {
      setUp(() => Download.debugTiming(
          stall: const Duration(milliseconds: 300),
          backoffUnit: const Duration(milliseconds: 10)));
      tearDown(Download.debugTiming);

      Future<(double, Uint8List)> fetchVia(_Mp3 f, http.Client client,
          {int attempts = Download.attempts}) async {
        final dir = Directory.systemTemp.createTempSync('slice');
        addTearDown(() => dir.deleteSync(recursive: true));
        final out = File('${dir.path}/s.mp3');
        final origin = await SurahSlice.fetch(
            client, Uri.parse('https://x/001.mp3'), f.layout(), out,
            fromMs: 60000, toMs: 90000, attempts: attempts);
        expect(File('${out.path}.part').existsSync(), isFalse);
        return (origin, out.readAsBytesSync());
      }

      int from(String range) =>
          int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);

      test('carries on from the byte a dropped connection reached',
          () async {
        final f = _Mp3(frames: 6000, info: true);
        final whole = await fetchVia(f, f.client());
        final asked = <String>[];
        final broken = await fetchVia(
            f, f.flaky([(50000, _Break.drop), (20000, _Break.drop)], asked));
        expect(broken.$1, whole.$1);
        expect(broken.$2, whole.$2);
        expect(asked, hasLength(3));
        expect(from(asked[1]), from(asked[0]) + 50000);
        expect(from(asked[2]), from(asked[0]) + 70000);
      });

      test('and from where a body stopped coming', () async {
        final f = _Mp3(frames: 6000, info: true);
        final whole = await fetchVia(f, f.client());
        final asked = <String>[];
        final stalled =
            await fetchVia(f, f.flaky([(80000, _Break.stall)], asked));
        expect(stalled.$2, whole.$2);
        expect(from(asked[1]), from(asked[0]) + 80000);
      });

      test('a break before the first frame is found is picked up too',
          () async {
        final f = _Mp3(frames: 6000, info: true);
        final whole = await fetchVia(f, f.client());
        final broken =
            await fetchVia(f, f.flaky([(300, _Break.drop)], <String>[]));
        expect(broken.$1, whole.$1);
        expect(broken.$2, whole.$2);
      });

      test('keeps going for as long as every try brings something',
          () async {
        final f = _Mp3(frames: 6000, info: true);
        final whole = await fetchVia(f, f.client());
        final asked = <String>[];
        // Each answer cut off after 40 kB: a link that can't hold a
        // long download, which used to fail the slice on the third.
        final broken = await fetchVia(
            f, f.flaky(List.filled(40, (40000, _Break.drop)), asked),
            attempts: 1);
        expect(broken.$2, whole.$2);
        expect(asked.length, greaterThan(3));
      });

      test('gives up after tries in a row that bring nothing', () async {
        var calls = 0;
        final client = MockClient.streaming((_, __) async {
          calls++;
          throw http.ClientException('Network is unreachable');
        });
        await expectLater(
          fetchVia(_Mp3(frames: 6000), client, attempts: 3),
          throwsA(isA<TroubleException>()
              .having((e) => e.trouble, 'trouble', Trouble.offline)),
        );
        expect(calls, 3);
      });

      group('a fetch the network gave up on', () {
        late Directory dir;
        late File out;
        setUp(() {
          dir = Directory.systemTemp.createTempSync('carry');
          out = File('${dir.path}/slice_67_1_5.mp3');
        });
        tearDown(() => dir.deleteSync(recursive: true));

        Future<double> fetchInto(_Mp3 f, http.Client client,
                {Mp3Layout? lay}) =>
            SurahSlice.fetch(client, Uri.parse('https://x/067.mp3'),
                lay ?? f.layout(), out,
                fromMs: 60000, toMs: 90000, attempts: 2);

        /// 60 kB, then the network goes and doesn't come back.
        http.Client goesAway(_Mp3 f) {
          var n = 0;
          final serve = f.flakyHandler([(60000, _Break.drop)], <String>[]);
          return MockClient.streaming((req, body) async {
            if (n++ > 0) throw http.ClientException('Network is unreachable');
            return serve(req, body);
          });
        }

        test('leaves what came for the next fetch, which carries on from it',
            () async {
          final f = _Mp3(frames: 6000, info: true);
          await expectLater(
            fetchInto(f, goesAway(f)),
            throwsA(isA<TroubleException>()
                .having((e) => e.trouble, 'trouble', Trouble.offline)),
          );
          expect(File('${out.path}.part').existsSync(), isTrue);

          final asked = <String>[];
          final origin = await fetchInto(f, f.flaky(const [], asked));
          expect(asked, hasLength(1), reason: 'one request: the rest');
          final whole = File('${dir.path}/whole.mp3');
          final wholeOrigin = await SurahSlice.fetch(f.client(),
              Uri.parse('https://x/067.mp3'), f.layout(), whole,
              fromMs: 60000, toMs: 90000);
          expect(origin, wholeOrigin);
          expect(out.readAsBytesSync(), whole.readAsBytesSync());
          expect(File('${out.path}.part').existsSync(), isFalse);
          expect(File('${out.path}.part.json').existsSync(), isFalse);
        });

        test('but not into another file', () async {
          final f = _Mp3(frames: 6000, info: true);
          await expectLater(fetchInto(f, goesAway(f)), throwsException);
          // The same name, but the host has a different file there now.
          final g = _Mp3(frames: 7000, info: true);
          final asked = <String>[];
          await fetchInto(g, g.flaky(const [], asked));
          // Asked from the start of the range, as a first fetch asks.
          final fresh = <String>[];
          final again = File('${dir.path}/again.mp3');
          await SurahSlice.fetch(g.flaky(const [], fresh),
              Uri.parse('https://x/067.mp3'), g.layout(), again,
              fromMs: 60000, toMs: 90000);
          expect(asked, fresh);
          expect(out.readAsBytesSync(), again.readAsBytesSync());
        });

        test('a refusal leaves nothing behind', () async {
          final f = _Mp3(frames: 6000, info: true);
          await expectLater(fetchInto(f, goesAway(f)), throwsException);
          await expectLater(
            fetchInto(
                f,
                MockClient.streaming((_, __) async =>
                    http.StreamedResponse(const Stream.empty(), 404))),
            throwsA(isA<TroubleException>()
                .having((e) => e.trouble, 'trouble', Trouble.host)),
          );
          expect(dir.listSync(), isEmpty);
        });
      });

      test('a file the server says it does not have is asked for once',
          () async {
        var calls = 0;
        final client = MockClient.streaming((_, __) async {
          calls++;
          return http.StreamedResponse(const Stream.empty(), 404);
        });
        await expectLater(
          fetchVia(_Mp3(frames: 6000), client),
          throwsA(isA<TroubleException>()
              .having((e) => e.trouble, 'trouble', Trouble.host)),
        );
        expect(calls, 1);
      });
    });

    test('says so when the server ignores the range', () async {
      final f = _Mp3(frames: 200);
      final lay = f.layout();
      final dir = Directory.systemTemp.createTempSync('slice');
      addTearDown(() => dir.deleteSync(recursive: true));
      final client = MockClient.streaming((req, _) async =>
          http.StreamedResponse(Stream.value(f.bytes), 200));
      await expectLater(
        SurahSlice.fetch(client, Uri.parse('https://x/001.mp3'), lay,
            File('${dir.path}/s.mp3'),
            fromMs: 1000, toMs: 2000, attempts: 1),
        throwsException,
      );
      expect(File('${dir.path}/s.mp3').existsSync(), isFalse);
    });
  });

  test('Mp3Layout.read reads the tag size and the first frame over HTTP',
      () async {
    final f = _Mp3(frames: 100, info: true);
    final lay = await Mp3Layout.read(f.client(), Uri.parse('https://x/1.mp3'));
    expect(lay.dataStart, f.tagSize);
    expect(lay.total, f.bytes.length);
    expect(lay.info, isTrue);
  });

  group('SurahSlice.parseTable', () {
    test('mp3quran: verse 0 is skipped, the rest become windows', () {
      final t = SurahSlice.parseTable(const Mp3QuranTiming(1), [
        {'ayah': 0, 'start_time': 0, 'end_time': 4000},
        {'ayah': 1, 'start_time': 4000, 'end_time': 9000},
        {'ayah': 2, 'start_time': 9000, 'end_time': 15000},
        {'ayah': 3, 'start_time': 15000, 'end_time': 17500},
      ], 112, 3);
      expect(t.map((w) => (w.ayah, w.startMs, w.endMs)),
          [(1, 4000, 9000), (2, 9000, 15000), (3, 15000, 17500)]);
    });

    test('QUL: segments keyed "surah:ayah" become windows', () {
      final t = SurahSlice.parseTable(const QulTiming(13), {
        'segments': {
          '112:1': {'time_from': 0, 'time_to': 2580, 'segments': []},
          '112:2': {'time_from': 2580, 'time_to': 4000},
          '112:3': {'time_from': 4000, 'time_to': 6200},
        },
        'pagination': {'total_pages': 1},
      }, 112, 3);
      expect(t.map((w) => (w.ayah, w.startMs, w.endMs)),
          [(1, 0, 2580), (2, 2580, 4000), (3, 4000, 6200)]);
    });

    test('a last verse that ends before it starts is kept, to be given '
        'the end of its file', () {
      final t = SurahSlice.parseTable(const Mp3QuranTiming(1), [
        {'ayah': 1, 'start_time': 0, 'end_time': 5000},
        {'ayah': 2, 'start_time': 5000, 'end_time': 962},
      ], 36, 2);
      expect(t.last.durationMs, 0);
      final fixed = SurahSlice.withFileEnd(t, 12345.6);
      expect(fixed.last.endMs, 12345);
      expect(fixed.first, same(t.first));
      // A table that is fine is left as it is.
      expect(SurahSlice.withFileEnd(fixed, 99999), same(fixed));
      // Only the last verse may be empty.
      expect(
          () => SurahSlice.parseTable(const Mp3QuranTiming(1), [
                {'ayah': 1, 'start_time': 0, 'end_time': 0},
                {'ayah': 2, 'start_time': 0, 'end_time': 900},
              ], 36, 2),
          throwsFormatException);
    });

    test('refuses a table that would misplace a verse', () {
      Map<String, dynamic> row(int a, int s, int e) =>
          {'ayah': a, 'start_time': s, 'end_time': e};
      const m = Mp3QuranTiming(1);
      expect(() => SurahSlice.parseTable(m, [row(1, 0, 10)], 1, 2),
          throwsFormatException,
          reason: 'too few verses');
      expect(
          () => SurahSlice.parseTable(
              m, [row(1, 0, 10), row(3, 10, 20)], 1, 2),
          throwsFormatException,
          reason: 'numbering');
      expect(
          () => SurahSlice.parseTable(
              m, [row(1, 0, 10), row(2, 30, 30), row(3, 30, 40)], 1, 3),
          throwsFormatException,
          reason: 'empty window');
      expect(
          () => SurahSlice.parseTable(
              m, [row(1, 50, 60), row(2, 40, 70)], 1, 2),
          throwsFormatException,
          reason: 'going back');
      expect(
          () => SurahSlice.parseTable(m, [
                {'ayah': 1, 'start_time': 'soon', 'end_time': 10},
              ], 1, 1),
          throwsFormatException,
          reason: 'not a number');
      expect(() => SurahSlice.parseTable(m, {'no': 'list'}, 1, 1),
          throwsFormatException);
      expect(
          () => SurahSlice.parseTable(const QulTiming(1), {
                'segments': {
                  '1:1': {'time_from': 0, 'time_to': 10},
                },
              }, 1, 2),
          throwsFormatException,
          reason: 'a verse missing from the page');
    });
  });

  group('SurahSlice.snap', () {
    test('finds the quietest frame in reach, the nearer of two equals', () {
      final env = List<double>.filled(300, 70);
      env[100] = 20; // 1000 ms
      env[140] = 20; // 1400 ms
      expect(SurahSlice.snap(env, 1150, before: 350, after: 350), 1000);
      expect(SurahSlice.snap(env, 1250, before: 350, after: 350), 1400);
      // Out of reach on one side only.
      expect(SurahSlice.snap(env, 1150, before: 100, after: 350), 1400);
    });
  });

  group('SurahSlice.plan', () {
    // Speech everywhere but the breaths, 300 ms each, centred on the true
    // boundaries at 5 s, 12 s and 20 s of the surah; the slice starts at
    // 2 s of it, so those are at 3, 10 and 18 s of the slice.
    List<double> envelope() {
      final env = List<double>.filled(2500, 70); // 25 s
      for (final c in [300, 1000, 1800]) {
        for (var k = c - 15; k < c + 15; k++) {
          env[k] = 25;
        }
      }
      return env;
    }

    test('moves every boundary into the breath the table is near', () {
      // A table a little off everywhere: late, early, late.
      const table = [
        AyahTiming(1, 5200, 11800),
        AyahTiming(2, 11800, 20250),
        AyahTiming(3, 20250, 26000),
      ];
      final plan = SurahSlice.plan(
          table: table, start: 1, last: 2, originMs: 2000, env: envelope());
      // The cut opens in the first breath and closes in the third.
      expect(plan.cutStart, inInclusiveRange(2850, 3140));
      expect(plan.cutEnd, inInclusiveRange(17850, 18140));
      expect(plan.timings.map((w) => w.ayah), [1, 2]);
      expect(plan.timings.first.startMs, 0);
      expect(plan.timings.last.endMs, plan.cutEnd - plan.cutStart);
      final mid = plan.timings[1].startMs + plan.cutStart;
      expect(mid, inInclusiveRange(9850, 10140));
      expect(plan.timings[0].endMs, plan.timings[1].startMs);
    });

    test('looks further outwards for the first cut than inwards', () {
      // The table starts verse 1 700 ms after the breath: past the
      // reach of an inner boundary, inside that of a reel's edge.
      const table = [
        AyahTiming(1, 5850, 12000),
        AyahTiming(2, 12000, 20000),
      ];
      final plan = SurahSlice.plan(
          table: table, start: 1, last: 1, originMs: 2000, env: envelope());
      expect(plan.cutStart, inInclusiveRange(2850, 3140));
    });

    test('a last verse that runs past the file ends where the audio does',
        () {
      const table = [
        AyahTiming(1, 5000, 12000),
        AyahTiming(2, 12000, 29000),
      ];
      final env = envelope();
      final plan = SurahSlice.plan(
          table: table, start: 2, last: 2, originMs: 2000, env: env);
      expect(plan.cutEnd, lessThanOrEqualTo(env.length * 10));
      expect(plan.timings.single.endMs, plan.cutEnd - plan.cutStart);
    });

    test('never lets two snapped boundaries cross', () {
      // Two verse starts 100 ms apart in the table, the same breath in
      // reach of both.
      const table = [
        AyahTiming(1, 9900, 10000),
        AyahTiming(2, 10000, 10100),
        AyahTiming(3, 10100, 16000),
      ];
      final plan = SurahSlice.plan(
          table: table, start: 1, last: 3, originMs: 2000, env: envelope());
      for (final w in plan.timings) {
        expect(w.durationMs, greaterThanOrEqualTo(SurahSlice.minVerseMs));
      }
    });

    test('refuses a range the slice does not hold', () {
      const table = [AyahTiming(1, 90000, 95000)];
      expect(
          () => SurahSlice.plan(
              table: table,
              start: 1,
              last: 1,
              originMs: 2000,
              env: envelope()),
          throwsFormatException);
    });
  });

  group('pauses, joined verses and opening words', () {
    // Speech at 70 dB, and quiet at 25 over [quiet] (ms of the slice).
    List<double> shaped(int ms, List<(int, int)> quiet) {
      final env = List<double>.filled(ms ~/ 10, 70);
      for (final (a, b) in quiet) {
        for (var k = a ~/ 10; k < b ~/ 10; k++) {
          env[k] = 25;
        }
      }
      return env;
    }

    test('quietBelow sits between the floor and speech; pauses are runs '
        'of it long enough to be breaths', () {
      final env = shaped(20000, [(1000, 2000), (5000, 5150), (9000, 9600)]);
      final q = SurahSlice.quietBelow(env);
      expect(q, closeTo(25 + 0.35 * 45, 0.01));
      // 150 ms is a gap between words, not a breath.
      expect(SurahSlice.pauses(env, q), [(1000, 2000), (9000, 9600)]);
      // Digital silence is left out of the floor.
      final opened = [...List<double>.filled(300, 0), ...env];
      expect(SurahSlice.quietBelow(opened), closeTo(q, 0.01));
    });

    test('a boundary with a breath in reach moves into it; one with none '
        'keeps the table\'s time', () {
      final env = shaped(30000, [
        (2800, 3400), (9700, 10300), (17800, 18400), (23800, 24400),
      ]);
      // A 50 ms dip between two consonants, 200 ms after the table's
      // time for verse 3: the quietest thing in reach, and no breath.
      for (var k = 1320; k < 1325; k++) {
        env[k] = 55;
      }
      const table = [
        AyahTiming(1, 3100, 9800),
        AyahTiming(2, 9800, 13000),
        AyahTiming(3, 13000, 18100),
        AyahTiming(4, 18100, 30000),
      ];
      final plan = SurahSlice.plan(
          table: table, start: 1, last: 3, originMs: 0, env: env);
      final starts = [for (final w in plan.timings) w.startMs + plan.cutStart];
      expect(starts[1], inInclusiveRange(9700, 10290));
      expect(starts[2], 13000);
    });

    // A surah file that opens the way Al-Banna's do: a moment of
    // silence, the basmala (3.5 s), a breath, then verse 1 — which the
    // table starts at 0, basmala and all.
    final opening = shaped(20000, [(0, 800), (4300, 5100), (9000, 9700)]);
    const table = [AyahTiming(1, 0, 9300), AyahTiming(2, 9300, 20000)];

    test('a reel from verse 1 starts in the breath after the opening words',
        () {
      final plan = SurahSlice.plan(
          table: table,
          start: 1,
          last: 1,
          originMs: 0,
          env: opening,
          openingMs: 3600);
      expect(plan.cutStart, inInclusiveRange(4300, 5090));
      expect(plan.cutEnd, inInclusiveRange(9000, 9690));
      // Without being told, the reel keeps them.
      final kept = SurahSlice.plan(
          table: table, start: 1, last: 1, originMs: 0, env: opening);
      expect(kept.cutStart, lessThan(800));
    });

    test('with no breath where the opening should end, the reel keeps it',
        () {
      // The breath comes at 1 s, far too soon to follow the basmala.
      final early = shaped(20000, [(0, 300), (1300, 1900), (9000, 9700)]);
      expect(SurahSlice.openingPause(
              SurahSlice.pauses(early, SurahSlice.quietBelow(early)), 0,
              openingMs: 3600),
          isNull);
      final plan = SurahSlice.plan(
          table: table,
          start: 1,
          last: 1,
          originMs: 0,
          env: early,
          openingMs: 3600);
      expect(plan.cutStart, lessThan(800));
    });

    test('the opening is measured from where the speech starts', () {
      // A table that starts verse 1 inside a long silence: the basmala
      // is timed from its first sound, not from the table's zero.
      final late = shaped(20000, [(0, 2500), (6000, 6800), (11000, 11600)]);
      final p = SurahSlice.openingPause(
          SurahSlice.pauses(late, SurahSlice.quietBelow(late)), 0,
          openingMs: 3600);
      expect(p, (6000, 6800));
    });
  });

  test('envelopeOf reads raw samples as 100 ms loudness, 10 ms apart', () {
    final dir = Directory.systemTemp.createTempSync('env');
    addTearDown(() => dir.deleteSync(recursive: true));
    // One second of silence, then one of a loud square wave, at 4 kHz.
    final b = ByteData(SurahSlice.envRate * 2 * 2);
    for (var i = 0; i < SurahSlice.envRate; i++) {
      b.setInt16((SurahSlice.envRate + i) * 2, i.isEven ? 12000 : -12000,
          Endian.little);
    }
    final f = File('${dir.path}/x.pcm')
      ..writeAsBytesSync(b.buffer.asUint8List());
    final env = SurahSlice.envelopeOf(f.path);
    expect(env.length, 200);
    expect(env[20], lessThan(1));
    expect(env[180], greaterThan(70));
    // Each step is the average of the 100 ms around it, so the quiet
    // side hears the edge 50 ms out.
    expect(env[95], greaterThan(env[80]));
    expect(env[94], lessThan(1));
  });
}

/// A constant-bitrate MPEG-1 Layer III file, 128 kbps at 44.1 kHz, made
/// the way an encoder makes one: a frame is padded by a byte whenever
/// the running total falls a byte behind the rate. Each frame's first
/// bytes after the header carry its index, so a slice can be traced
/// back to where it came from.
class _Mp3 {
  final Uint8List bytes;
  final int tagSize;

  /// Offset of every frame in [bytes].
  final List<int> frameStart;

  _Mp3._(this.bytes, this.tagSize, this.frameStart);

  factory _Mp3(
      {required int frames, bool info = false, bool xing = false, int junk = 0}) {
    const tagBody = 300;
    final out = BytesBuilder();
    out.add([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, tagBody >> 7, tagBody & 127]);
    out.add(Uint8List(tagBody));
    out.add(Uint8List(junk));
    final starts = <int>[];
    const exact = 144 * 128000 / 44100;
    var owed = 0.0;
    for (var k = 0; k < frames; k++) {
      owed += exact - 417;
      final pad = owed >= 1;
      if (pad) owed -= 1;
      final f = Uint8List(417 + (pad ? 1 : 0));
      f.setAll(0, [0xFF, 0xFB, pad ? 0x92 : 0x90, 0x44]);
      if (k == 0 && (info || xing)) {
        f.setAll(36, (xing ? 'Xing' : 'Info').codeUnits);
      } else {
        // Distinct content per frame, never a false sync word.
        final id = ByteData(4)..setUint32(0, k);
        for (var i = 4; i + 4 <= f.length; i += 4) {
          f.setAll(i, id.buffer.asUint8List());
          f[i] &= 0x7F;
        }
      }
      starts.add(out.length);
      out.add(f);
    }
    return _Mp3._(out.toBytes(), 10 + tagBody, starts);
  }

  Mp3Layout layout() => Mp3Layout.parse(
        Uint8List.sublistView(bytes, 0, 10),
        Uint8List.sublistView(
            bytes, tagSize, (tagSize + 8192).clamp(0, bytes.length)),
        bytes.length,
      );

  int indexOfBytes(List<int> needle) {
    outer:
    for (var i = 0; i + needle.length <= bytes.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// A server that honours byte ranges, in chunks as a network would.
  http.Client client() => MockClient.streaming((req, _) async {
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers['Range']!)!;
        final lo = int.parse(m.group(1)!);
        final hi = int.parse(m.group(2)!).clamp(0, bytes.length - 1);
        final body = Uint8List.sublistView(bytes, lo, hi + 1);
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < body.length; i += 1000) {
            yield body.sublist(i, i + 1000 > body.length ? body.length : i + 1000);
          }
        }

        return http.StreamedResponse(chunks(), 206,
            contentLength: body.length,
            headers: {'content-range': 'bytes $lo-$hi/${bytes.length}'});
      });

  /// The same server on a phone's network: the nth answer breaks off as
  /// [plan]'s nth entry says — after so many bytes, dropped or stalled
  /// for good — and answers past the end of [plan] arrive whole. Every
  /// range asked for goes into [asked].
  http.Client flaky(List<(int, _Break)> plan, List<String> asked) =>
      MockClient.streaming(flakyHandler(plan, asked));

  /// [flaky]'s server, to be called from another handler.
  MockClientStreamHandler flakyHandler(
          List<(int, _Break)> plan, List<String> asked) =>
      (req, _) async {
        final fault = asked.length < plan.length ? plan[asked.length] : null;
        asked.add(req.headers['Range']!);
        final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(asked.last)!;
        final lo = int.parse(m.group(1)!);
        final hi = int.parse(m.group(2)!).clamp(0, bytes.length - 1);
        final body = Uint8List.sublistView(bytes, lo, hi + 1);
        final out = StreamController<List<int>>();
        final upTo = fault == null ? body.length : min(fault.$1, body.length);
        for (var i = 0; i < upTo; i += 1000) {
          out.add(body.sublist(i, min(i + 1000, upTo)));
        }
        switch (fault?.$2) {
          case null:
            out.close();
          case _Break.drop:
            out
              ..addError(http.ClientException(
                  'Connection closed while receiving data'))
              ..close();
          case _Break.stall:
          // Nothing more, ever.
        }
        return http.StreamedResponse(out.stream, 206,
            contentLength: body.length,
            headers: {'content-range': 'bytes $lo-$hi/${bytes.length}'});
      };
}

/// How an answer breaks off: the connection dropped, or the bytes
/// simply stopped coming.
enum _Break { drop, stall }
