import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ayah_reels/data/download.dart';
import 'package:ayah_reels/data/recitation_service.dart';
import 'package:ayah_reels/data/trouble.dart';

/// A per-ayah file over a phone's network: it drops, it stalls, it comes
/// back. Every break used to cost the file from its first byte, a whole
/// file had thirty seconds however slow the link, and three tries less
/// than a second and a half apart were the most any file got.
void main() {
  setUp(() => Download.debugTiming(
      stall: const Duration(milliseconds: 300),
      backoffUnit: const Duration(milliseconds: 10)));
  tearDown(Download.debugTiming);

  // Not a real mp3: nothing here reads it, and distinct bytes show up
  // any that land in the wrong place.
  final file = Uint8List.fromList(List.generate(250000, (i) => i * 7 % 251));

  Future<Uint8List> fetch(http.Client client) async {
    final dir = Directory.systemTemp.createTempSync('ayah');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/002255.mp3');
    await RecitationService.debugDownload(
        client, Uri.parse('https://x/002255.mp3'), f);
    expect(dir.listSync().whereType<File>().map((e) => e.path),
        [f.path], reason: 'no part file left behind');
    return f.readAsBytesSync();
  }

  test('a whole file, in one go', () async {
    final asked = <String?>[];
    expect(await fetch(_server(file, asked)), file);
    expect(asked, [null]);
  });

  test('a dropped connection carries on from the byte it reached',
      () async {
    final asked = <String?>[];
    final got = await fetch(_server(file, asked,
        plan: [(100000, _Break.drop), (50000, _Break.drop)]));
    expect(got, file);
    expect(asked, [null, 'bytes=100000-', 'bytes=150000-']);
  });

  test('so does a body that stops coming', () async {
    final asked = <String?>[];
    expect(
        await fetch(_server(file, asked, plan: [(120000, _Break.stall)])),
        file);
    expect(asked, [null, 'bytes=120000-']);
  });

  test('a body that ends short of its length is noticed, and the rest '
      'asked for', () async {
    final asked = <String?>[];
    expect(
        await fetch(_server(file, asked, plan: [(90000, _Break.close)])),
        file);
    expect(asked, [null, 'bytes=90000-']);
  });

  test('a server that answers a resume with the whole file is taken from '
      'the top', () async {
    final asked = <String?>[];
    final got = await fetch(_server(file, asked,
        plan: [(100000, _Break.drop)], ranges: false));
    expect(got, file);
    expect(asked, [null, 'bytes=100000-']);
  });

  test('a link that cuts every answer short still gets there', () async {
    final asked = <String?>[];
    final got = await fetch(_server(file, asked,
        plan: List.filled(20, (30000, _Break.drop))));
    expect(got, file);
    expect(asked, hasLength(9));
  });

  test('says how far along it is as the bytes come, and carries the count '
      'on across a resume', () async {
    final dir = Directory.systemTemp.createTempSync('ayah');
    addTearDown(() => dir.deleteSync(recursive: true));
    final seen = <double>[];
    await RecitationService.debugDownload(
        _server(file, <String?>[], plan: [(100000, _Break.drop)]),
        Uri.parse('https://x/002255.mp3'),
        File('${dir.path}/002255.mp3'),
        onFraction: seen.add);
    expect(seen.length, greaterThan(10));
    expect(seen.last, 1.0);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]),
          reason: 'never goes back, though the connection dropped');
    }
  });

  test('a file the server does not have is asked for once', () async {
    final asked = <String?>[];
    await expectLater(
      fetch(_server(file, asked, status: [404])),
      throwsA(isA<TroubleException>()
          .having((e) => e.trouble, 'trouble', Trouble.host)),
    );
    expect(asked, hasLength(1));
  });

  test('a server error is asked again', () async {
    final asked = <String?>[];
    expect(await fetch(_server(file, asked, status: [503, 502])), file);
    expect(asked, hasLength(3));
  });

  test('tries in a row that bring nothing end it, as offline', () async {
    var calls = 0;
    await expectLater(
      fetch(MockClient.streaming((_, __) async {
        calls++;
        throw const SocketException('Network is unreachable');
      })),
      throwsA(isA<TroubleException>()
          .having((e) => e.trouble, 'trouble', Trouble.offline)),
    );
    expect(calls, Download.attempts);
  });

  test('a request that never answers is given up on, not waited for',
      () async {
    final client = MockClient.streaming(
        (_, __) => Completer<http.StreamedResponse>().future);
    final watch = Stopwatch()..start();
    await expectLater(
      fetch(client),
      throwsA(isA<TroubleException>()
          .having((e) => e.trouble, 'trouble', Trouble.offline)),
    );
    // Four stalls and the pauses between them, not for ever.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('the waits: a second after progress, then 1, 2, 4, 8 units', () {
    Download.debugTiming();
    expect(Download.stall, const Duration(seconds: 30));
    expect([for (var m = 0; m <= 5; m++) Download.backoff(m).inSeconds],
        [1, 1, 2, 4, 8, 8]);
  });

  test('only a refusal is final', () {
    expect(Download.isFinal(const BadStatus(404)), isTrue);
    expect(Download.isFinal(const BadStatus(403)), isTrue);
    expect(Download.isFinal(const BadStatus(429)), isFalse);
    expect(Download.isFinal(const BadStatus(408)), isFalse);
    expect(Download.isFinal(const BadStatus(503)), isFalse);
    expect(Download.isFinal(const BadStatus(200, 'not a byte range')),
        isFalse);
    expect(Download.isFinal(TimeoutException('slow')), isFalse);
    expect(Download.isFinal(const SocketException('gone')), isFalse);
  });
}

/// How an answer breaks off: the connection dropped, the bytes stopped
/// coming, or the body simply ended early.
enum _Break { drop, stall, close }

/// A server holding [file]. The nth answer breaks off as [plan]'s nth
/// entry says, after so many bytes; past the end of [plan] answers are
/// whole. [status] answers the first requests with those codes instead.
/// [ranges] false: a resume is answered with the whole file, as a server
/// that ignores byte ranges does. Each request's Range (or null) goes
/// into [asked].
http.Client _server(
  Uint8List file,
  List<String?> asked, {
  List<(int, _Break)> plan = const [],
  List<int> status = const [],
  bool ranges = true,
}) =>
    MockClient.streaming((req, _) async {
      final n = asked.length;
      asked.add(req.headers['Range']);
      if (n < status.length) {
        return http.StreamedResponse(const Stream.empty(), status[n]);
      }
      final faults = plan.length;
      final fault = n - status.length < faults ? plan[n - status.length] : null;
      final m = RegExp(r'bytes=(\d+)-').firstMatch(req.headers['Range'] ?? '');
      final from = ranges && m != null ? int.parse(m.group(1)!) : 0;
      final body = Uint8List.sublistView(file, from);
      final out = StreamController<List<int>>();
      final upTo = fault == null ? body.length : min(fault.$1, body.length);
      for (var i = 0; i < upTo; i += 4096) {
        out.add(body.sublist(i, min(i + 4096, upTo)));
      }
      switch (fault?.$2) {
        case null || _Break.close:
          out.close();
        case _Break.drop:
          out
            ..addError(
                http.ClientException('Connection closed while receiving data'))
            ..close();
        case _Break.stall:
        // Nothing more, ever.
      }
      return http.StreamedResponse(out.stream, from > 0 ? 206 : 200,
          contentLength: body.length,
          headers: from > 0
              ? {'content-range': 'bytes $from-${file.length - 1}/${file.length}'}
              : const {});
    });
