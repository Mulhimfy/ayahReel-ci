import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ayah_reels/data/audio_mirror.dart';
import 'package:ayah_reels/data/download.dart';
import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/feedback_service.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/quran_text_service.dart';
import 'package:ayah_reels/data/recitation_service.dart';
import 'package:ayah_reels/data/surah_index.dart';
import 'package:ayah_reels/data/surah_slice.dart';
import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/data/words_host.dart';

/// A voice whose host is down still makes a reel: every file and table
/// the app asks a host for is looked up in our mirror
/// (Mulhimfy/ayahreel-audio) and, when the host fails, read from its
/// pack there — the same bytes, answered as the host answers them.
void main() {
  const ayahUrl = 'https://everyayah.com/data/Alafasy_128kbps/002255.mp3';
  const base = AudioMirror.base;
  // A pack: distinct bytes, so any read from the wrong place shows.
  final pack = Uint8List.fromList(List.generate(4000, (i) => i * 7 % 251));
  // 002255 is the 1000 bytes at 1200 in it.
  final verse = pack.sublist(1200, 2200);
  final index = {
    'v': 1,
    'packs': [
      {'name': 'p1-abc.bin'},
    ],
    'files': {
      '002255': [0, 1200, 1000],
      '002256': [0, 2200, 900],
    },
  };
  final ghamdiTiming = {
    '001': [
      for (var a = 1; a <= 7; a++)
        {'ayah': a, 'start_time': (a - 1) * 1000, 'end_time': a * 1000},
    ],
  };

  final kawtharArabic = {
    '108': {
      'verses': [
        for (var a = 1; a <= 3; a++)
          {'id': 6204 + a, 'verse_key': '108:$a', 'text_uthmani': 'آية $a'},
      ],
    },
  };

  late Directory dir;
  late List<String> asked;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mirror');
    asked = [];
    AudioMirrorClient.debugReset();
    Download.debugTiming(
        stall: const Duration(seconds: 2),
        backoffUnit: const Duration(milliseconds: 5));
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
    Download.debugTiming();
  });

  /// The mirror as GitHub serves it, and a host that does what [host]
  /// says (an answer, or a throw).
  AudioMirrorClient client(FutureOr<http.Response> Function(http.Request) host,
      {Duration patience = const Duration(seconds: 1), int indexStatus = 200}) {
    final net = MockClient((req) async {
      final u = req.url.toString();
      final r = req.headers['Range'];
      asked.add(r == null ? u : '$u $r');
      if (!u.startsWith(base)) return host(req);
      if (u.endsWith('/index.json')) {
        return http.Response(jsonEncode(index), indexStatus);
      }
      if (u.endsWith('/voice-ghamdi/timing.json')) {
        return http.Response(jsonEncode(ghamdiTiming), 200);
      }
      if (u == '$base/text/uthmani.json') {
        // As GitHub serves it: bytes, and no charset.
        return http.Response.bytes(utf8.encode(jsonEncode(kawtharArabic)), 200,
            headers: {'content-type': 'application/octet-stream'});
      }
      if (u == '$base/voice-alafasy/p1-abc.bin') {
        final m = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(r ?? '')!;
        final a = int.parse(m.group(1)!);
        final b = int.parse(m.group(2)!);
        return http.Response.bytes(pack.sublist(a, b + 1), 206,
            headers: {'content-range': 'bytes $a-$b/${pack.length}'});
      }
      return http.Response('', 404);
    });
    final store = MirrorStore(base: base, client: net, dir: () async => dir);
    return AudioMirrorClient(net,
        map: AudioMirror.map, store: store, patience: patience);
  }

  Future<http.Response> get(http.Client c, String url, {String? range}) async =>
      http.Response.fromStream(await c.send(http.Request('GET', Uri.parse(url))
        ..headers.addAll({if (range != null) 'Range': range})));

  group('every address the app asks for is in the map', () {
    test('a verse file, a surah file, an unpadded one, one from elsewhere', () {
      final m = AudioMirror.map;
      expect(m.fileOf(Uri.parse(ayahUrl)), (voice: 'alafasy', key: '002255'));
      expect(m.fileOf(Uri.parse('https://server7.mp3quran.net/s_gmd/002.mp3')),
          (voice: 'ghamdi', key: '002'));
      expect(
          m.fileOf(Uri.parse(
              'https://download.quranicaudio.com/qdc/hadi_toure/mp3/2.mp3')),
          (voice: 'toure', key: '002'));
      expect(
          m.fileOf(Uri.parse(
              'https://media.way2quran.com/islam-sobhi/hafs-an-asim/072.mp3')),
          (voice: 'sobhi', key: '072'));
      expect(
          m.fileOf(Uri.parse('https://everyayah.com/data/Nobody/002255.mp3')),
          isNull);
      expect(
          m.fileOf(
              Uri.parse('https://everyayah.com/data/Alafasy_128kbps/x.mp3')),
          isNull);
      expect(
          m.fileOf(Uri.parse(
              'https://ayahreel-words.mulhimfy.workers.dev/v1/index.json')),
          isNull);
    });

    test('so is every voice, every surah and every published table', () {
      final m = AudioMirror.map;
      var files = 0;
      var tables = 0;
      for (final r in reciters) {
        switch (r.source) {
          case final AyahFiles s:
            for (final info in surahIndex) {
              final key = '${info.number.toString().padLeft(3, '0')}'
                  '${info.ayahCount.toString().padLeft(3, '0')}';
              expect(m.fileOf(s.url(info.number, info.ayahCount)),
                  (voice: r.id, key: key));
              files++;
            }
          case final SurahFiles s:
            for (final info in surahIndex) {
              final n = info.number;
              if (s.missing.contains(n)) continue;
              final key = n.toString().padLeft(3, '0');
              expect(m.fileOf(s.url(n)), (voice: r.id, key: key),
                  reason: '${r.id} $n');
              files++;
              if (s.timing is OwnTiming) continue;
              expect(m.docOf(s.timing.url(n, info.ayahCount)),
                  (release: 'voice-${r.id}', asset: 'timing.json', key: key));
              tables++;
            }
          case OwnAudio():
            break;
        }
      }
      expect(files, greaterThan(10000));
      expect(tables, greaterThan(8000));
    });

    test('and the text of every surah, in Arabic and every edition', () {
      final m = AudioMirror.map;
      for (final info in surahIndex) {
        final key = info.number.toString().padLeft(3, '0');
        expect(m.docOf(QuranTextService.arabicUrl(info.number)),
            (release: 'text', asset: 'uthmani.json', key: key));
        for (final t in VerseTranslation.values) {
          expect(
              m.docOf(
                  QuranTextService.translationUrl(info.number, t.resourceId)),
              (release: 'text', asset: 'tr-${t.resourceId}.json', key: key));
        }
      }
    });

    test('our own timing is never looked for there', () {
      final sobhi = reciters.firstWhere((r) => r.id == 'sobhi');
      expect((sobhi.source as SurahFiles).timing, isA<OwnTiming>());
      final m = AudioMirror.map;
      expect(
          m.docOf(Uri.parse('https://ayahreel-words.mulhimfy.workers.dev'
              '/v1/vt_sobhi/2.json')),
          isNull);
    });
  });

  test('a host that answers is all that is asked', () async {
    final c = client((_) => http.Response.bytes(verse, 200));
    final res = await get(c, ayahUrl);
    expect(res.bodyBytes, verse);
    expect(asked, [ayahUrl]);
    expect(AudioMirrorClient.served, 0);
  });

  test('a host that is down: the same file, from its pack', () async {
    final c = client((_) => throw const SocketException('down'));
    final res = await get(c, ayahUrl);
    expect(res.statusCode, 200);
    expect(res.bodyBytes, verse);
    expect(res.contentLength, 1000);
    expect(asked, [
      ayahUrl,
      '$base/voice-alafasy/index.json',
      '$base/voice-alafasy/p1-abc.bin bytes=1200-2199',
    ]);
    expect(AudioMirrorClient.served, 1);
    expect(AudioMirrorClient.hostsDown, ['everyayah.com']);
    expect(FeedbackService.mirrorLine(),
        '1 from the mirror · failing: everyayah.com');

    // Passed over now, and the index read from the phone.
    asked.clear();
    final next =
        await get(c, 'https://everyayah.com/data/Alafasy_128kbps/002256.mp3');
    expect(next.bodyBytes, pack.sublist(2200, 3100));
    expect(asked, ['$base/voice-alafasy/p1-abc.bin bytes=2200-3099']);
    expect(File('${dir.path}/voice-alafasy.index.json').existsSync(), isTrue);
  });

  test('a resumed download gets the rest, in the file\'s own bytes', () async {
    final c = client((_) => http.Response('', 503));
    final res = await get(c, ayahUrl, range: 'bytes=400-');
    expect(res.statusCode, 206);
    expect(res.headers['content-range'], 'bytes 400-999/1000');
    expect(res.bodyBytes, verse.sublist(400));
    expect(asked.last, '$base/voice-alafasy/p1-abc.bin bytes=1600-2199');

    final part = await get(c, ayahUrl, range: 'bytes=10-19');
    expect(part.bodyBytes, verse.sublist(10, 20));
    expect(part.headers['content-range'], 'bytes 10-19/1000');
    final past = await get(c, ayahUrl, range: 'bytes=1000-');
    expect(past.statusCode, 416);
  });

  test(
      'a file the host has lost is had from the mirror; the host is '
      'still asked first next time', () async {
    final c = client((_) => http.Response('', 404));
    expect((await get(c, ayahUrl)).bodyBytes, verse);
    expect(AudioMirrorClient.hostsDown, isEmpty);
    asked.clear();
    await get(c, ayahUrl);
    expect(asked.first, ayahUrl);
  });

  test('neither has it: the host\'s own answer', () async {
    final c = client((_) => http.Response('', 404));
    final res =
        await get(c, 'https://everyayah.com/data/Alafasy_128kbps/002257.mp3');
    expect(res.statusCode, 404);
  });

  test('both down: the host\'s failure, as before there was a mirror',
      () async {
    final c =
        client((_) => throw const SocketException('down'), indexStatus: 500);
    await expectLater(get(c, ayahUrl), throwsA(isA<SocketException>()));
    // The mirror is passed over too now, and the host asked alone.
    asked.clear();
    await expectLater(get(c, ayahUrl), throwsA(isA<SocketException>()));
    expect(asked, [ayahUrl]);
  });

  test(
      'a host that doesn\'t answer: the mirror is asked beside it, and '
      'the first answer wins', () async {
    final c = client((_) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      return http.Response.bytes(verse, 200);
    }, patience: const Duration(milliseconds: 50));
    final watch = Stopwatch()..start();
    final res = await get(c, ayahUrl);
    expect(res.bodyBytes, verse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(AudioMirrorClient.served, 1);
    expect(AudioMirrorClient.hostsDown, ['everyayah.com']);
  });

  test('a published verse table, as its host publishes it', () async {
    final c = client((_) => http.Response('', 502));
    const ghamdi = Mp3QuranTiming(30);
    final res = await c.get(ghamdi.url(1, 7));
    expect(res.statusCode, 200);
    final t = SurahSlice.parseTable(ghamdi, jsonDecode(res.body), 1, 7);
    expect(t.length, 7);
    expect(t.last.endMs, 7000);
  });

  test('the verse text, when quran.com is down', () async {
    final c = client((_) => throw const SocketException('down'));
    final res = await c.get(QuranTextService.arabicUrl(108));
    expect(res.statusCode, 200);
    expect(jsonDecode(res.body), kawtharArabic['108'],
        reason: 'the Arabic read as UTF-8, as quran.com sends it');
    expect(AudioMirrorClient.hostsDown, ['api.quran.com']);
  });

  test(
      'our Worker, blocked at workers.dev: the same request at its '
      'second address, key and all', () async {
    final seen = <String, String?>{};
    final net = MockClient((req) async {
      seen[req.url.toString()] = req.headers['x-ayahreel-key'];
      if (req.url.host.endsWith('workers.dev')) {
        throw const SocketException('blocked');
      }
      return http.Response('{"table":"x"}', 200);
    });
    final c = AudioMirrorClient(net,
        map: AudioMirror.map,
        store: MirrorStore(base: base, client: net, dir: () async => dir));
    const path = '/tables/sobhi-0123456789ab.json';
    final res = await c.get(Uri.parse('${WordsHost.base}$path'),
        headers: {'x-ayahreel-key': 'k'});
    expect(res.statusCode, 200);
    expect(res.body, '{"table":"x"}');
    expect(seen, {
      '${WordsHost.base}$path': 'k',
      '${WordsHost.fallbackBase}$path': 'k',
    });
    expect(WordsHost.fallbackBase, startsWith('https://'));
    expect(WordsHost.fallbackBase, isNot(contains('workers.dev')));
  });

  test(
      'a host that breaks off mid-file: the resume comes from the mirror, '
      'and the file is whole', () async {
    var tries = 0;
    final net = MockClient.streaming((req, _) async {
      final u = req.url.toString();
      final r = req.headers['Range'];
      asked.add(r == null ? u : '$u $r');
      if (u.endsWith('/index.json')) {
        return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(index))), 200);
      }
      if (u.startsWith(base)) {
        final m = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(r!)!;
        final a = int.parse(m.group(1)!);
        final b = int.parse(m.group(2)!);
        return http.StreamedResponse(Stream.value(pack.sublist(a, b + 1)), 206,
            headers: {'content-range': 'bytes $a-$b/${pack.length}'});
      }
      tries++;
      final half = StreamController<List<int>>();
      half.add(verse.sublist(0, 300));
      half.addError(const SocketException('reset'));
      half.close();
      return http.StreamedResponse(half.stream, 200, contentLength: 1000);
    });
    final c = AudioMirrorClient(net,
        map: AudioMirror.map,
        store: MirrorStore(base: base, client: net, dir: () async => dir));
    final f = File('${dir.path}/002255.mp3');
    await RecitationService.debugDownload(c, Uri.parse(ayahUrl), f);
    expect(f.readAsBytesSync(), verse);
    expect(tries, 1);
    expect(asked.last, '$base/voice-alafasy/p1-abc.bin bytes=1500-2199');
  });

  test('a pack that is gone: the index is asked for afresh', () async {
    final store = MirrorStore(
        base: base,
        client: MockClient((_) async => http.Response(jsonEncode(index), 200)),
        dir: () async => dir);
    await store.index('alafasy');
    expect(File('${dir.path}/voice-alafasy.index.json').existsSync(), isTrue);
    await store.forget('alafasy');
    expect(File('${dir.path}/voice-alafasy.index.json').existsSync(), isFalse);
  });

  test('off under tests unless asked: the fake hosts stay the hosts', () {
    expect(AudioMirror.enabled, isFalse);
    final inner = http.Client();
    expect(AudioMirror.client(inner), same(inner));
    inner.close();
  });
}
