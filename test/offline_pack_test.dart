import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/local_range_client.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/offline_pack.dart';
import 'package:ayah_reels/data/quran_text_service.dart';
import 'package:ayah_reels/data/recitation_service.dart';

/// Download for offline: a voice's verses and surahs kept on the phone
/// so a reel needs no network, a surah-file voice read from its copy as
/// it would be from the server, and a run that carries on where it
/// stopped.
void main() {
  late Directory root;
  HttpServer? server;
  var hits = <String>[];

  setUp(() {
    root = Directory.systemTemp.createTempSync('offline_pack');
    RecitationService.debugRoot = root;
    RecitationService.debugFfmpeg = (_) async => true;
    RecitationService.debugProbeMs = (_) async => 1500;
    hits = [];
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    RecitationService.debugRoot = null;
    RecitationService.debugFfmpeg = null;
    RecitationService.debugProbeMs = null;
    RecitationService.debugReset();
    OfflinePack.debugReset();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Constant-bitrate MPEG-1 Layer III frames (128 kbps, 44.1 kHz), no
  /// sound in them: enough for the layout to be read and sliced.
  Uint8List cbr(int frames) {
    const len = 417;
    final b = Uint8List(frames * len);
    for (var f = 0; f < frames; f++) {
      b
        ..[f * len] = 0xFF
        ..[f * len + 1] = 0xFB
        ..[f * len + 2] = 0x90
        ..[f * len + 3] = 0x64;
    }
    return b;
  }

  Future<String> serve(Uint8List Function(String path) body) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((req) async {
      hits.add(req.uri.path);
      final bytes = body(req.uri.path);
      req.response
        ..statusCode = 200
        ..headers.contentLength = bytes.length
        ..add(bytes);
      await req.response.close();
    });
    return 'http://127.0.0.1:${server!.port}';
  }

  test('a per-ayah voice keeps every verse of the surah, measured, and '
      'never fetches one twice', () async {
    final host = await serve((_) => Uint8List.fromList(List.filled(4096, 1)));
    final voice = Reciter(
      id: 'offline_ayah',
      name: 'Test',
      arabicName: 'اختبار',
      style: 'Murattal',
      source: AyahFiles.at(host, 'Test_128kbps'),
    );
    expect(await RecitationService.isOffline(voice, 112), isFalse);
    final seen = <double>[];
    await RecitationService.keepOffline(voice, 112, onProgress: seen.add);
    expect(hits, hasLength(4), reason: "Al-Ikhlas' four verses");
    expect(seen.last, 1.0);
    expect(await RecitationService.isOffline(voice, 112), isTrue);
    final durations = jsonDecode(File(
            '${root.path}/recitations/offline_ayah/durations_112.json')
        .readAsStringSync()) as Map<String, dynamic>;
    expect(durations.keys.toSet(), {'1', '2', '3', '4'});

    await RecitationService.keepOffline(voice, 112);
    expect(hits, hasLength(4), reason: 'everything was already there');
  });

  test('a surah-file voice keeps its whole surah, and is read from it',
      () async {
    final mp3 = cbr(240);
    final host = await serve((_) => mp3);
    final voice = Reciter(
      id: 'offline_surah',
      name: 'Test',
      arabicName: 'اختبار',
      style: 'Murattal',
      source: SurahFiles('$host/s', timing: const Mp3QuranTiming(1)),
    );
    // Its table, as an earlier reel left it on the disk.
    final dir = Directory('${root.path}/recitations/offline_surah')
      ..createSync(recursive: true);
    File('${dir.path}/table_112.json').writeAsStringSync(jsonEncode([
      for (var a = 1; a <= 4; a++) {'a': a, 's': (a - 1) * 1000, 'e': a * 1000},
    ]));
    expect(await RecitationService.isOffline(voice, 112), isFalse);
    await RecitationService.keepOffline(voice, 112);
    expect(hits, ['/s/112.mp3']);
    final whole = File('${dir.path}/whole_112.mp3');
    expect(whole.lengthSync(), mp3.length);
    expect(await RecitationService.isOffline(voice, 112), isTrue);
  });

  test('a copy on the phone answers byte ranges as the server would',
      () async {
    final f = File('${root.path}/whole.mp3')
      ..writeAsBytesSync(List.generate(1000, (i) => i % 256));
    final url = Uri.parse('https://example.invalid/s/001.mp3');
    var passed = 0;
    final inner = _CountingClient(() => passed++);
    final c = LocalRangeClient(inner, url: url, file: f);

    Future<http.StreamedResponse> get(Uri u, [String? range]) {
      final r = http.Request('GET', u);
      if (range != null) r.headers['Range'] = range;
      return c.send(r);
    }

    var res = await get(url, 'bytes=10-19');
    expect(res.statusCode, 206);
    expect(res.headers['content-range'], 'bytes 10-19/1000');
    expect(await res.stream.toBytes(), List.generate(10, (i) => 10 + i));

    res = await get(url, 'bytes=990-');
    expect(res.statusCode, 206);
    expect(res.headers['content-range'], 'bytes 990-999/1000');
    expect((await res.stream.toBytes()).length, 10);

    res = await get(url, 'bytes=2000-2010');
    expect(res.statusCode, 416);

    res = await get(url);
    expect(res.statusCode, 200);
    expect((await res.stream.toBytes()).length, 1000);

    // Anything else goes to the network.
    await get(Uri.parse('https://example.invalid/s/002.mp3'), 'bytes=0-9');
    expect(passed, 1);
  });

  test('the sizes it says before anything is fetched', () {
    final alafasy = reciters.firstWhere((r) => r.id == 'alafasy');
    expect(OfflinePack.kbpsOf(alafasy), 128);
    expect(OfflinePack.surahSeconds, hasLength(114));
    expect(OfflinePack.surahSeconds.fold<int>(0, (a, b) => a + b),
        closeTo(82324, 5));
    final all =
        OfflinePack.voiceBytes(alafasy, [for (var s = 1; s <= 114; s++) s]);
    final short = OfflinePack.surahsFor(OfflineVoice.short);
    expect(all, greaterThan(800 * 1000 * 1000));
    expect(OfflinePack.voiceBytes(alafasy, short), lessThan(all ~/ 10));
    expect(
        OfflinePack.voiceBytes(
            alafasy, OfflinePack.surahsFor(OfflineVoice.none)),
        0);
    expect(short.first, 78);
    expect(short.last, 114);
    expect(OfflinePack.surahsFor(OfflineVoice.surah, surah: 36), [36]);
    // A juz is every surah it reaches into, whole.
    expect(OfflinePack.surahsOfJuz(1), [1, 2]);
    expect(OfflinePack.surahsOfJuz(15), [17, 18]);
    expect(OfflinePack.surahsOfJuz(29), [for (var s = 67; s <= 77; s++) s]);
    expect(OfflinePack.surahsOfJuz(30), short);
    expect(OfflinePack.surahsFor(OfflineVoice.juz, juz: 30), short);
  });

  test('a run with the text already there and nothing else asked ends done',
      () async {
    for (var s = 2; s <= 114; s++) {
      QuranTextService.seed(s, const [Ayah(number: 1, arabic: 'ا', translation: 'a')]);
    }
    addTearDown(() {
      for (var s = 2; s <= 114; s++) {
        QuranTextService.seed(s, null);
      }
    });
    final stages = <OfflineStage>[];
    void listen() => stages.add(OfflinePack.state.value.stage);
    OfflinePack.state.addListener(listen);
    addTearDown(() => OfflinePack.state.removeListener(listen));
    await OfflinePack.run(OfflinePlan(
      voice: reciters.first,
      scope: OfflineVoice.none,
      stills: false,
      clips: false,
    ));
    expect(OfflinePack.state.value.stage, OfflineStage.done);
    expect(OfflinePack.state.value.fraction, 1.0);
    expect(OfflinePack.state.value.missed, 0);
    expect(stages.first, OfflineStage.text);
  });
}

class _CountingClient extends http.BaseClient {
  final void Function() onSend;
  _CountingClient(this.onSend);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onSend();
    return http.StreamedResponse(const Stream.empty(), 404);
  }
}
