import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/scene_catalog.dart';

/// The picker's Preview button blocks on the scene tap it was given, so
/// a fetch that never finishes is not a slow download — it is a frozen
/// screen with no way off it.
///
/// That is what shipped: the only timeout covered [Client.send], which
/// resolves when the response *headers* arrive, and the body stream
/// under it had none. A connection that opened, answered 200 and then
/// went quiet — the ordinary mobile case on a four megabyte clip — left
/// the future uncompleted for good.
///
/// So: pin that every path out of a download completes, and that a
/// killed one leaves nothing behind that a later run would mistake for
/// a finished file.
void main() {
  late Directory cache;
  HttpServer? server;

  Scene sceneNamed(String id) => Scene(
        id: id,
        tab: 'water',
        wide: false,
        isVideo: true,
        ext: 'mp4',
        bytes: 4000000,
        gradientArgb: const [0xFF000000, 0xFF101010],
        bundled: false,
      );

  /// Starts a server on a free port and points the catalog at it.
  Future<void> serve(void Function(HttpRequest) handler) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen(handler);
    SceneCatalog.configureForTest(
      baseUrl: 'http://127.0.0.1:${server!.port}',
      cacheDir: cache,
      idle: const Duration(milliseconds: 300),
    );
  }

  setUp(() {
    cache = Directory.systemTemp.createTempSync('ayah_scene_cache');
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    try {
      if (cache.existsSync()) cache.deleteSync(recursive: true);
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
  });

  test('a connection that answers and then goes silent still completes',
      () async {
    // Headers, a first chunk, and then nothing — never closed. This is
    // the shape of the hang: the response arrives, so any timeout on
    // the response alone is satisfied and the body waits forever.
    await serve((req) {
      req.response.headers.contentLength = 4000000;
      req.response.add(List.filled(2048, 7));
      req.response.flush();
    });

    final file = await SceneCatalog.download(sceneNamed('water_stall_01'))
        .timeout(
      const Duration(seconds: 15),
      onTimeout: () => fail(
          'download never completed — a stalled body hangs every caller'),
    );
    expect(file, isNull, reason: 'a stalled fetch is a failed fetch');
  });

  test('a stalled fetch leaves no part file to be mistaken for a scene',
      () async {
    await serve((req) {
      req.response.headers.contentLength = 4000000;
      req.response.add(List.filled(2048, 7));
      req.response.flush();
    });

    await SceneCatalog.download(sceneNamed('water_stall_02'))
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    expect(
      cache.listSync().map((e) => e.path.split(Platform.pathSeparator).last),
      isEmpty,
      reason: 'a half-written file left behind is a broken scene later',
    );
  });

  test('a server that never responds at all completes too', () async {
    // Accepted and then ignored: no headers, no status, nothing.
    await serve((req) {/* hold the request open */});

    final file = await SceneCatalog.download(sceneNamed('water_dead_01'))
        .timeout(
      const Duration(seconds: 15),
      onTimeout: () => fail('a silent server hung the future'),
    );
    expect(file, isNull);
  });

  test('an error status gives up rather than retrying into a wall',
      () async {
    var hits = 0;
    await serve((req) {
      hits++;
      req.response.statusCode = HttpStatus.notFound;
      req.response.close();
    });

    final file = await SceneCatalog.download(sceneNamed('water_404_01'))
        .timeout(const Duration(seconds: 15),
            onTimeout: () => fail('a 404 hung the future'));
    expect(file, isNull);
    expect(hits, lessThanOrEqualTo(2), reason: 'no retry storm on a 404');
  });

  test('a served file lands in the cache and reports progress to 1',
      () async {
    final body = List.filled(8192, 3);
    await serve((req) {
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      req.response.close();
    });

    final seen = <double>[];
    final file = await SceneCatalog.download(
      sceneNamed('water_ok_01'),
      onProgress: seen.add,
    ).timeout(const Duration(seconds: 15),
        onTimeout: () => fail('a healthy download did not finish'));

    expect(file, isNotNull);
    expect(file!.existsSync(), isTrue);
    expect(file.lengthSync(), body.length);
    expect(seen.last, 1.0);
    expect(file.path.endsWith('.part'), isFalse,
        reason: 'the finished file is renamed off the part path');
  });

  test('one stalled attempt does not spend the whole tap', () async {
    // The first connection goes quiet; the second is served. A stall is
    // almost always the network rather than the file, so the tap should
    // still land the scenery.
    final body = List.filled(4096, 9);
    var attempt = 0;
    await serve((req) {
      attempt++;
      if (attempt == 1) {
        req.response.headers.contentLength = 4000000;
        req.response.add(List.filled(512, 1));
        req.response.flush();
        return;
      }
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      req.response.close();
    });

    final file = await SceneCatalog.download(sceneNamed('water_retry_01'))
        .timeout(const Duration(seconds: 15),
            onTimeout: () => fail('the retry never completed'));
    expect(file, isNotNull, reason: 'the second attempt should have landed');
    expect(file!.lengthSync(), body.length);
  });

  test('two taps on one tile share a fetch, and both callers are answered',
      () async {
    // The in-flight map exists so a double tap does not race two writes
    // to the same path. Sharing the future is also where it went wrong:
    // the completion callback removed the entry with `Map.remove`, whose
    // return value is the future itself, and `whenComplete` awaits what
    // its callback returns. Every caller then waited on a future waiting
    // on itself, while the bytes landed on disk regardless — a scenery
    // that only ever turned up on the next visit.
    final body = List.filled(4096, 5);
    var requests = 0;
    await serve((req) {
      requests++;
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      req.response.close();
    });

    final scene = sceneNamed('water_shared_01');
    final both = await Future.wait([
      SceneCatalog.download(scene),
      SceneCatalog.download(scene),
    ]).timeout(
      const Duration(seconds: 15),
      onTimeout: () => fail('the shared fetch never answered its callers'),
    );

    expect(both[0], isNotNull);
    expect(both[1], isNotNull);
    expect(requests, 1, reason: 'one fetch, not two writes to one path');
  });

  test('a finished fetch releases its slot, so the next tap is served',
      () async {
    // The same entry left behind would answer a later tap with a future
    // that had already completed — or never let a retry happen at all.
    final body = List.filled(4096, 6);
    await serve((req) {
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      req.response.close();
    });

    final scene = sceneNamed('water_again_01');
    final first = await SceneCatalog.download(scene).timeout(
        const Duration(seconds: 15), onTimeout: () => fail('first hung'));
    final second = await SceneCatalog.download(scene).timeout(
        const Duration(seconds: 15), onTimeout: () => fail('second hung'));

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(second!.path, first!.path);
  });

  test('a truncated body is rejected rather than cached as a scene',
      () async {
    // Under the sanity floor: an error page or a cut-off transfer must
    // never become a file that later looks downloaded.
    await serve((req) {
      req.response.add(List.filled(64, 1));
      req.response.close();
    });

    final file = await SceneCatalog.download(sceneNamed('water_short_01'))
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    expect(file, isNull);
    expect(cache.listSync(), isEmpty);
  });
}
