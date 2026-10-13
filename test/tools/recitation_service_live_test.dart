import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/recitation_service.dart';

/// [RecitationService.load] end to end, the way the preview calls it:
/// real downloads from every kind of source, the app's own FFmpeg
/// command lines, its isolate hop, its cut plan and its duration check.
/// Only FFmpegKit, which has no desktop build, is stood in for by the
/// machine's ffmpeg, given the same arguments.
///
/// The progress callback holds something no isolate can be sent, as
/// the preview's does (it leads back to the screen). A closure that
/// carries it across an isolate boundary failed every surah-file voice
/// on the phone as "check your connection"; this is what would catch
/// that again.
///
/// Off by default — it downloads a few megabytes and needs ffmpeg:
///
///   LIVE_RECITERS=1 flutter test test/tools/recitation_service_live_test.dart
void main() {
  final live = Platform.environment['LIVE_RECITERS'] == '1';
  late Directory root;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('recitations');
    RecitationService.debugRoot = root;
    RecitationService.debugFfmpeg = (command) async {
      final args = FFmpegKitConfig.parseArguments(command);
      final r = await Process.run('ffmpeg', ['-v', 'error', ...args]);
      if (r.exitCode != 0) {
        // ignore: avoid_print
        print('ffmpeg ${args.join(' ')}\n${r.stderr}');
      }
      return r.exitCode == 0;
    };
    RecitationService.debugProbeMs = (path) async {
      final r = await Process.run('ffprobe', [
        '-v', 'error', '-show_entries', 'format=duration', //
        '-of', 'json', path,
      ]);
      final d = jsonDecode(r.stdout as String)['format']['duration'];
      return (double.parse(d as String) * 1000).round();
    };
  });

  tearDownAll(() {
    RecitationService.debugRoot = null;
    RecitationService.debugFfmpeg = null;
    RecitationService.debugProbeMs = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  setUp(RecitationService.debugReset);

  Reciter voice(String id) => reciters.firstWhere((r) => r.id == id);

  Future<int> probe(String path) => RecitationService.debugProbeMs!(path);

  /// One reel's worth, loaded as the preview loads it, and checked the
  /// way the preview relies on it: a file that runs as long as its
  /// verses, one window per verse, back to back from zero.
  Future<Recitation> reel(String id, int surah, int start, int end) async {
    final screen = _Screen();
    final rec = await RecitationService.load(voice(id), surah,
        startAyah: start, endAyah: end, onProgress: screen.progress);
    expect(rec.firstAyah, start);
    expect(rec.lastAyah, end);
    expect(rec.timings.first.startMs, 0);
    for (var i = 1; i < rec.timings.length; i++) {
      expect(rec.timings[i].startMs, rec.timings[i - 1].endMs);
    }
    final ms = await probe(rec.audioPath);
    expect(ms, closeTo(rec.timings.last.endMs, 200),
        reason: '$id $surah:$start-$end runs ${ms}ms');
    expect(screen.last, 1.0, reason: 'progress reaches the end');
    return rec;
  }

  final skip = live ? false : 'set LIVE_RECITERS=1 to run against the servers';
  const t = Timeout(Duration(minutes: 4));

  group('surah-file voices', () {
    for (final id in ['kanakri', 'ghamdi', 'jaleel', 'khayyat', 'burhaji']) {
      test('$id: Al-Mulk 1-5, and one verse', () async {
        await reel(id, 67, 1, 5);
        await reel(id, 2, 255, 255);
      }, skip: skip, timeout: t);
    }

    test('albanna: a reel from verse 1 starts after the basmala', () async {
      final r = voice('albanna');
      expect((r.source as SurahFiles).openingMs, isNotNull);
      final rec = await reel('albanna', 112, 1, 4);
      // Verse 1 of Al-Ikhlas takes him a few seconds; the basmala
      // before it, which his table counts in, three and a half more.
      expect(rec.timings.first.durationMs, lessThan(6000));
    }, skip: skip, timeout: t);

    test('akhdar: the end of Ya-Sin, whose table has no end for it',
        () async {
      final rec = await reel('akhdar', 36, 80, 83);
      expect(rec.timings.last.durationMs, greaterThan(2000));
    }, skip: skip, timeout: t);

    test('a second load of the same range comes off the disk', () async {
      await reel('kanakri', 112, 1, 4);
      RecitationService.debugReset();
      final watch = Stopwatch()..start();
      await reel('kanakri', 112, 1, 4);
      expect(watch.elapsedMilliseconds, lessThan(3000));
    }, skip: skip, timeout: t);

    test('the reciter screen sample: one verse, ready to play', () async {
      final f = await RecitationService.sampleAyah(voice('khayyat'), 1, 2);
      expect(await probe(f.path), greaterThan(1000));
    }, skip: skip, timeout: t);
  });

  group('every voice not on EveryAyah', () {
    // Al-Ikhlas whole, as a reel, and the reciter screen's sample:
    // one of each for every voice that came from somewhere new.
    for (final r in reciters.where((r) => r.everyAyahFolder == null)) {
      test('${r.id}: a reel and a sample', () async {
        await reel(r.id, 112, 1, 4);
        final f = await RecitationService.sampleAyah(r, 1, 2);
        expect(await probe(f.path), greaterThan(1000));
      }, skip: skip, timeout: t);
    }
  });

  group('every EveryAyah voice', () {
    // A short surah and Al-Mulk 1-5 for each: Al-Fatiha, or Al-Ikhlas
    // for the three whose Al-Fatiha ships in the app (an asset, which
    // this harness can't load without the test binding, which would
    // take the network away). Some of these sets tag their files with
    // cover art, which failed every join of Fares Abbad's until the
    // encode was made audio-only.
    for (final r in reciters.where((r) => r.everyAyahFolder != null)) {
      test('${r.id}: a short surah and Al-Mulk 1-5', () async {
        if (r.hasBundledFatiha) {
          await reel(r.id, 112, 1, 4);
        } else {
          await reel(r.id, 1, 1, 7);
        }
        await reel(r.id, 67, 1, 5);
      }, skip: skip, timeout: t);
    }
  });

  group('per-ayah voices', () {
    for (final id in ['nufais', 'mustafa_ismail', 'alafasy']) {
      test('$id: Al-Ikhlas', () async {
        await reel(id, 112, 1, 4);
        final f = await RecitationService.sampleAyah(voice(id), 1, 2);
        expect(await probe(f.path), greaterThan(1000));
      }, skip: skip, timeout: t);
    }
  });
}

/// Stands in for the preview screen behind a progress callback: it
/// holds a native object, which no isolate message may carry.
class _Screen {
  final recorder = ui.PictureRecorder();
  double last = 0;
  void progress(double v) => last = v;
}
