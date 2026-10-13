import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ayah_reels/data/download.dart';
import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/recitation_service.dart';
import 'package:ayah_reels/data/surah_slice.dart';
import 'package:ayah_reels/data/trouble.dart';
import 'package:ayah_reels/l10n/l10n.dart';

/// "Check your connection" is said when it was the connection, and only
/// then. It used to be said for everything, and two faults on the phone
/// — an isolate that couldn't be sent a closure, a join that choked on a
/// reciter's cover art — hid behind it.
void main() {
  group('troubleOf', () {
    test('no answer from the network is offline', () {
      expect(troubleOf(const SocketException('Failed host lookup')),
          Trouble.offline);
      expect(troubleOf(TimeoutException('slow')), Trouble.offline);
      expect(troubleOf(http.ClientException('closed')), Trouble.offline);
      expect(troubleOf(const HttpException('Connection closed')),
          Trouble.offline);
      expect(troubleOf(const HandshakeException('bad cert')),
          Trouble.offline);
    });

    test('a server that answered wrongly is the host', () {
      expect(troubleOf(const BadStatus(404)), Trouble.host);
      expect(troubleOf(const BadStatus(503, 'busy')), Trouble.host);
    });

    test('a full disk is storage, any other file error is the phone', () {
      expect(
          troubleOf(const FileSystemException('write failed', '/x',
              OSError('No space left on device', 28))),
          Trouble.storage);
      expect(
          troubleOf(const FileSystemException(
              'write failed', '/x', OSError('Permission denied', 13))),
          Trouble.device);
    });

    test('what isn\'t recognised is never blamed on the connection', () {
      expect(troubleOf(const FormatException('bad')), Trouble.device);
      expect(troubleOf(StateError('bad')), Trouble.device);
      expect(troubleOf(Exception('anything')), Trouble.device);
    });

    test('a typed failure says its own kind', () {
      expect(troubleOf(const TroubleException(Trouble.host, 'x')),
          Trouble.host);
      final gapped = reciters.firstWhere((r) => r.missingSurahs.isNotEmpty);
      expect(troubleOf(SurahUnavailable(gapped, gapped.missingSurahs.first)),
          Trouble.missing);
    });
  });

  group('the surah-file download says what failed', () {
    final url = Uri.parse('https://x/067.mp3');
    Future<void> fetchWith(http.Client client) async {
      final dir = Directory.systemTemp.createTempSync('trouble');
      addTearDown(() => dir.deleteSync(recursive: true));
      const lay = Mp3Layout(
          total: 1000000,
          dataStart: 0,
          kbps: 128,
          rate: 44100,
          samplesPerFrame: 1152,
          info: false);
      await SurahSlice.fetch(client, url, lay, File('${dir.path}/s.mp3'),
          fromMs: 1000, toMs: 5000, attempts: 1);
    }

    test('a 404 is the host', () async {
      await expectLater(
        fetchWith(MockClient.streaming((_, __) async =>
            http.StreamedResponse(const Stream.empty(), 404))),
        throwsA(isA<TroubleException>()
            .having((e) => e.trouble, 'trouble', Trouble.host)),
      );
    });

    test('no connection is offline', () async {
      await expectLater(
        fetchWith(MockClient.streaming(
            (_, __) async => throw http.ClientException('no route'))),
        throwsA(isA<TroubleException>()
            .having((e) => e.trouble, 'trouble', Trouble.offline)),
      );
    });

    test('a connection that closes halfway, and then no network, is offline',
        () async {
      Download.debugTiming(backoffUnit: const Duration(milliseconds: 10));
      addTearDown(Download.debugTiming);
      var calls = 0;
      await expectLater(
        fetchWith(MockClient.streaming((req, _) async {
          // The bytes that came are kept and the rest asked for, so a
          // try that brought some is never the one that gives up: what
          // fails the download is the network not coming back.
          if (calls++ > 0) throw http.ClientException('Network is unreachable');
          final m = RegExp(r'bytes=(\d+)-(\d+)')
              .firstMatch(req.headers['Range']!)!;
          final lo = int.parse(m.group(1)!), hi = int.parse(m.group(2)!);
          // A real frame header first, so the slice finds its start,
          // then far fewer bytes than the range promised.
          final head = Uint8List(4200);
          for (var i = 0; i + 418 <= head.length; i += 418) {
            head.setAll(i, [0xFF, 0xFB, 0x92, 0x44]);
          }
          return http.StreamedResponse(Stream.value(head), 206,
              headers: {'content-range': 'bytes $lo-$hi/1000000'});
        })),
        throwsA(isA<TroubleException>()
            .having((e) => e.trouble, 'trouble', Trouble.offline)),
      );
      expect(calls, 2);
    });

    test('a server that ignores the byte range is the host', () async {
      await expectLater(
        fetchWith(MockClient.streaming((_, __) async =>
            http.StreamedResponse(Stream.value(Uint8List(10)), 200))),
        throwsA(isA<TroubleException>()
            .having((e) => e.trouble, 'trouble', Trouble.host)),
      );
    });
  });

  test('a per-ayah voice with the network unreachable is offline',
      () async {
    final root = Directory.systemTemp.createTempSync('offline');
    addTearDown(() => root.deleteSync(recursive: true));
    RecitationService.debugRoot = root;
    RecitationService.debugFfmpeg = (_) async => true;
    RecitationService.debugProbeMs = (_) async => 1000;
    addTearDown(() {
      RecitationService.debugRoot = null;
      RecitationService.debugFfmpeg = null;
      RecitationService.debugProbeMs = null;
      RecitationService.debugReset();
    });
    final voice = reciters.firstWhere((r) =>
        r.source is AyahFiles && !r.hasBundledFatiha);
    await HttpOverrides.runWithHttpOverrides(() async {
      await expectLater(
        RecitationService.load(voice, 112, startAyah: 1, endAyah: 1),
        throwsA(isA<TroubleException>()
            .having((e) => e.trouble, 'trouble', Trouble.offline)),
      );
    }, _Unreachable());
  }, timeout: const Timeout(Duration(minutes: 1)));

  group('what the preview says', () {
    for (final lang in AppLang.values) {
      final l = L10n(lang);
      test('${lang.code}: one sentence per kind, and a way to report', () {
        final said = {for (final t in Trouble.values) t: l.recitationFailed(t)};
        expect(said.values.every((s) => s.isNotEmpty), isTrue);
        expect(said[Trouble.offline], isNot(said[Trouble.device]));
        expect(said[Trouble.host], isNot(said[Trouble.device]));
        expect(said[Trouble.storage], isNot(said[Trouble.device]));
        expect(l.reportInSettings, contains(l.settingsTitle));
        expect(l.reportInSettings, contains(l.feedbackRowTitle));
      });
    }

    test('in English, only the offline one mentions the connection', () {
      const l = L10n(AppLang.en);
      expect(l.recitationFailed(Trouble.offline).toLowerCase(),
          contains('connection'));
      for (final t in [Trouble.host, Trouble.storage, Trouble.device]) {
        expect(l.recitationFailed(t).toLowerCase(),
            isNot(contains('connection')), reason: t.name);
      }
      expect(l.surahTextFailed.toLowerCase(), isNot(contains('connection')));
    });
  });
}

/// Every connection goes through a proxy on a port nothing listens on:
/// the network, as far as the app can tell, isn't there.
class _Unreachable extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = ((_) => 'PROXY 127.0.0.1:9')
        ..connectionTimeout = const Duration(seconds: 2);
}
