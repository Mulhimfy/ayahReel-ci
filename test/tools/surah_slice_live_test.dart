import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/surah_index.dart';
import 'package:ayah_reels/data/surah_slice.dart';

/// The app's own slicing, run against the real servers: one voice of
/// every kind of file the surah-file voices come in, Ayat al-Kursi out
/// of the middle of Al-Baqarah, decoded by the machine's ffmpeg the
/// way the device decodes it, and cut where the plan says.
///
/// Off by default — it downloads a few megabytes per voice and needs
/// ffmpeg on the PATH:
///
///   LIVE_RECITERS=1 flutter test test/tools/surah_slice_live_test.dart
///
/// tool/verify_reciters.py checks every voice's tables against its
/// audio with the same arithmetic in Python; this is what keeps the
/// Dart side honest to it.
void main() {
  final live = Platform.environment['LIVE_RECITERS'] == '1';

  // Chosen for their files, not their voices: MPEG-1 at 44.1, 32 and
  // 48 kHz, MPEG-2 at 22.05 kHz, and 128 to 320 kbps.
  const ids = ['kanakri', 'yamani', 'burhaji', 'masrawi', 'salimi'];

  test('albanna: Al-Ikhlas from verse 1 starts after the basmala', () async {
    final r = reciters.firstWhere((r) => r.id == 'albanna');
    final source = r.source as SurahFiles;
    final client = http.Client();
    final dir = Directory.systemTemp.createTempSync('live_albanna');
    addTearDown(() {
      client.close();
      dir.deleteSync(recursive: true);
    });
    const surah = 112;
    final count = surahIndex[surah - 1].ayahCount;
    final res = await client.get(source.timing.url(surah, count));
    final table = SurahSlice.parseTable(
        source.timing, jsonDecode(res.body), surah, count);
    expect(table.first.startMs, 0, reason: 'the table counts the basmala');
    final url = source.url(surah);
    final lay = await Mp3Layout.read(client, url);
    final slice = File('${dir.path}/s.mp3');
    final origin = await SurahSlice.fetch(client, url, lay, slice,
        fromMs: 0, toMs: table.first.endMs + SurahSlice.edgeMs + 1000);
    final pcm = File('${dir.path}/s.pcm');
    final ff = await Process.run('ffmpeg', [
      '-v', 'error', '-i', slice.path, '-ac', '1', //
      '-ar', '${SurahSlice.envRate}', '-f', 's16le', '-y', pcm.path,
    ]);
    expect(ff.exitCode, 0, reason: '${ff.stderr}');
    final env = SurahSlice.envelopeOf(pcm.path);
    final plan = SurahSlice.plan(
        table: table,
        start: 1,
        last: 1,
        originMs: origin,
        env: env,
        openingMs: source.openingMs);
    // The basmala takes him about three and a half seconds.
    expect(plan.cutStart, greaterThan(3500));
    expect(plan.cutEnd - plan.cutStart, greaterThan(2000));
  },
      skip: live ? false : 'set LIVE_RECITERS=1 to run against the servers',
      timeout: const Timeout(Duration(minutes: 3)));

  for (final id in ids) {
    test('$id: Ayat al-Kursi is cut in its breaths', () async {
      final r = reciters.firstWhere((r) => r.id == id);
      final source = r.source as SurahFiles;
      final client = http.Client();
      final dir = Directory.systemTemp.createTempSync('live_$id');
      addTearDown(() {
        client.close();
        dir.deleteSync(recursive: true);
      });
      const surah = 2, ayah = 255;
      final count = surahIndex[surah - 1].ayahCount;
      final res = await client.get(source.timing.url(surah, count));
      final table = SurahSlice.parseTable(
          source.timing, jsonDecode(res.body), surah, count);
      final url = source.url(surah);
      final lay = await Mp3Layout.read(client, url);
      final from = table[ayah - 1].startMs, to = table[ayah - 1].endMs;
      final slice = File('${dir.path}/s.mp3');
      final origin = await SurahSlice.fetch(client, url, lay, slice,
          fromMs: from - SurahSlice.edgeMs - 1000,
          toMs: to + SurahSlice.edgeMs + 1000);
      // Only the verse's bytes, give or take the room at both ends.
      expect(slice.lengthSync(), lessThan(lay.total / 10));

      final pcm = File('${dir.path}/s.pcm');
      final ff = await Process.run('ffmpeg', [
        '-v', 'error', '-i', slice.path, '-ac', '1', //
        '-ar', '${SurahSlice.envRate}', '-f', 's16le', '-y', pcm.path,
      ]);
      expect(ff.exitCode, 0, reason: '${ff.stderr}');
      final env = SurahSlice.envelopeOf(pcm.path);
      final plan = SurahSlice.plan(
          table: table,
          start: ayah,
          last: ayah,
          originMs: origin,
          env: env);

      // The cut is the verse, to within the reach of its two edges.
      final want = to - from;
      final got = plan.cutEnd - plan.cutStart;
      expect(got, inInclusiveRange(want - 2 * SurahSlice.snapMs,
          want + 2 * SurahSlice.edgeMs));
      // And both cuts are in the quiet: near the slice's floor, far
      // below its speech.
      final sorted = [...env]..sort();
      final floor = sorted[(sorted.length * 0.05).floor()];
      final speech = sorted[(sorted.length * 0.9).floor()];
      for (final at in [plan.cutStart, plan.cutEnd - 10]) {
        final e = env[min(env.length - 1, at ~/ 10)];
        expect(e, lessThan(floor + 0.35 * (speech - floor)),
            reason: '$id: cut at ${at}ms is at ${e.toStringAsFixed(1)} dB '
                '(floor ${floor.toStringAsFixed(1)}, '
                'speech ${speech.toStringAsFixed(1)})');
      }
    }, skip: live ? false : 'set LIVE_RECITERS=1 to run against the servers',
        timeout: const Timeout(Duration(minutes: 3)));
  }
}
