import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'download.dart';
import 'fatiha_data.dart';
import 'models.dart';
import 'surah_index.dart';
import 'trouble.dart';
import 'whole_file.dart';

/// Our own copy of every voice's files, for when the site a voice comes
/// from is down, refuses, or can't be reached from where the phone is.
///
/// Every voice the app offers comes from someone else's server —
/// EveryAyah, mp3quran, QuranicAudio, Tarteel, King Saud University,
/// archive.org — and a reel of it could only be made while that server
/// answered. The mirror, the public repository Mulhimfy/ayahreel-audio,
/// holds each voice's files exactly as their hosts serve them, packed
/// one after another in a release per voice, with an index of where
/// each is (tool/audio_mirror; its mirror.yml copies them and reads
/// every pack back against the hosts' bytes). A file is read out of its
/// pack with a Range request, so the code that fetches, resumes and
/// slices a recitation gets byte for byte what the host would have
/// sent, and can't tell which of them answered.
///
/// Verse tables a host publishes beside its surah files are mirrored
/// too, verse starts and ends only. Our own timing — the verse tables
/// and the word timing — is never in the mirror: it stays behind the
/// key-gated Worker ([WordsHost]), which is ours already.
abstract final class AudioMirror {
  /// Where each voice's release is: `<base>/voice-<id>/<asset>`.
  static const base =
      'https://github.com/Mulhimfy/ayahreel-audio/releases/download';

  /// Off under `flutter test`, whose fake servers stand in for the hosts
  /// and must not be routed round; a test of the mirror turns it on.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Every address of every voice the app can ask for.
  static final MirrorMap map = MirrorMap.of(reciters);

  static MirrorStore? _store;
  static MirrorStore get store => _store ??= MirrorStore(
        base: base,
        client: http.Client(),
        dir: () async => Directory(
            '${(await getApplicationSupportDirectory()).path}/mirror'),
      );

  /// A client for recitation files and tables: the host first, the
  /// mirror when the host fails (see [AudioMirrorClient]). Just [inner]
  /// when the mirror is off.
  static http.Client client([http.Client? inner]) {
    final c = inner ?? http.Client();
    if (!enabled) return c;
    return AudioMirrorClient(c, map: map, store: store);
  }

  @visibleForTesting
  static void debugStore(MirrorStore? s) => _store = s;
}

/// A file or table's place in the mirror: its voice, and its key there
/// — `SSSAAA` for a verse's file, `SSS` for a surah's file or table.
typedef MirrorSpot = ({String voice, String key});

/// The addresses the app asks the hosts for, and where each is in the
/// mirror. Built from the voices themselves, so a voice added to the
/// list is looked up the moment it is mirrored.
class MirrorMap {
  final Map<String, String> _ayahBases;
  final Map<String, MirrorSpot> _files;
  final Map<String, MirrorSpot> _tables;

  MirrorMap._(this._ayahBases, this._files, this._tables);

  factory MirrorMap.of(Iterable<Reciter> voices) {
    final bases = <String, String>{};
    final files = <String, MirrorSpot>{};
    final tables = <String, MirrorSpot>{};
    for (final r in voices) {
      switch (r.source) {
        case AyahFiles(:final host, :final folder):
          bases['$host/$folder'] = r.id;
        case final SurahFiles s:
          for (final info in surahIndex) {
            final n = info.number;
            if (s.missing.contains(n)) continue;
            final spot = (voice: r.id, key: n.toString().padLeft(3, '0'));
            files[s.url(n).toString()] = spot;
            if (s.timing is! OwnTiming) {
              tables[s.timing.url(n, info.ayahCount).toString()] = spot;
            }
          }
        case OwnAudio():
          break;
      }
    }
    return MirrorMap._(bases, files, tables);
  }

  static final _ayahName = RegExp(r'^(\d{6})\.mp3$');

  /// Where the file at [url] is in the mirror; null for an address that
  /// isn't a voice's.
  MirrorSpot? fileOf(Uri url) {
    final s = url.toString();
    final hit = _files[s];
    if (hit != null) return hit;
    final cut = s.lastIndexOf('/');
    if (cut < 0) return null;
    final voice = _ayahBases[s.substring(0, cut)];
    if (voice == null) return null;
    final m = _ayahName.firstMatch(s.substring(cut + 1));
    return m == null ? null : (voice: voice, key: m.group(1)!);
  }

  /// Where the verse table at [url] is in the mirror.
  MirrorSpot? tableOf(Uri url) => _tables[url.toString()];
}

/// A voice's index in the mirror: its packs, and where each file is.
class MirrorIndex {
  final List<String> packs;
  final Map<String, (int pack, int offset, int length)> files;

  MirrorIndex(this.packs, this.files);

  factory MirrorIndex.parse(Map<String, dynamic> j) {
    final packs = [
      for (final p in (j['packs'] as List).cast<Map<String, dynamic>>())
        p['name'] as String,
    ];
    final files = <String, (int, int, int)>{};
    (j['files'] as Map<String, dynamic>).forEach((k, v) {
      final a = (v as List).cast<num>();
      final pack = a[0].toInt();
      if (pack < 0 || pack >= packs.length) {
        throw FormatException('$k is in pack $pack of ${packs.length}');
      }
      files[k] = (pack, a[1].toInt(), a[2].toInt());
    });
    return MirrorIndex(packs, files);
  }
}

/// Fetches a voice's index and verse tables from the mirror once, and
/// keeps them on the phone: a voice's index is what a fallback needs
/// first, and must not itself wait on a slow network every time.
class MirrorStore {
  final String base;
  final http.Client client;
  final Future<Directory> Function() dir;

  final _indexes = <String, Future<MirrorIndex>>{};
  final _timings = <String, Future<Map<String, dynamic>>>{};

  MirrorStore({required this.base, required this.client, required this.dir});

  Uri assetUrl(String voice, String name) =>
      Uri.parse('$base/voice-$voice/$name');

  Future<MirrorIndex> index(String voice) =>
      _once(_indexes, voice, () async =>
          MirrorIndex.parse(await _load(voice, 'index.json')));

  Future<Map<String, dynamic>> timing(String voice) =>
      _once(_timings, voice, () => _load(voice, 'timing.json'));

  /// Lets go of [voice]'s index, kept or held: one that names a pack
  /// the mirror no longer has (the voice copied again since).
  Future<void> forget(String voice) async {
    _indexes.remove(voice);
    try {
      final f = File('${(await dir()).path}/$voice.index.json');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  static Future<T> _once<T>(
      Map<String, Future<T>> held, String voice, Future<T> Function() load) {
    final known = held[voice];
    if (known != null) return known;
    final f = load();
    held[voice] = f;
    // A fetch that failed is asked again next time, not remembered.
    f.then<void>((_) {}, onError: (Object _) {
      if (identical(held[voice], f)) held.remove(voice);
    });
    return f;
  }

  Future<Map<String, dynamic>> _load(String voice, String name) async {
    final d = await dir();
    final f = File('${d.path}/$voice.$name');
    if (f.existsSync()) {
      try {
        return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        // Cut short or unreadable: fetched again.
      }
    }
    final res = await Download.get(client, assetUrl(voice, name));
    if (res.statusCode != 200) {
      throw BadStatus(res.statusCode, 'mirror $voice/$name');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    try {
      if (!d.existsSync()) d.createSync(recursive: true);
      await writeWhole(f, res.body);
    } catch (_) {
      // Kept in memory for the session all the same.
    }
    return j;
  }
}

/// Asks a voice's host first, as the app always has, and the mirror
/// when the host fails it: a dropped or refused connection, an error
/// answer (a 404, a 5xx, "too many requests"), or no answer within
/// [patience] — then both are asked and the first good answer is used.
///
/// A host that failed is passed over for [downFor]: its next requests go
/// to the mirror first, so a voice whose server is down doesn't wait out
/// each file's failure in turn. Any other address goes straight to
/// [inner].
class AudioMirrorClient extends http.BaseClient {
  final http.Client inner;
  final MirrorMap map;
  final MirrorStore store;
  final Duration patience;

  AudioMirrorClient(this.inner,
      {required this.map,
      required this.store,
      this.patience = const Duration(seconds: 8)});

  static const downFor = Duration(minutes: 10);
  static final _hostDown = <String, DateTime>{};
  static DateTime? _mirrorDown;

  /// Files and tables the mirror has given since the app started.
  static int get served => _served;
  static int _served = 0;

  /// The hosts that failed in the last [downFor].
  static List<String> get hostsDown => [
        for (final e in _hostDown.entries)
          if (DateTime.now().difference(e.value) < downFor) e.key,
      ];

  @visibleForTesting
  static void debugReset() {
    _hostDown.clear();
    _mirrorDown = null;
    _served = 0;
    _told.clear();
  }

  static final _told = <String>{};

  static bool _isDown(DateTime? at) =>
      at != null && DateTime.now().difference(at) < downFor;

  static void _markDown(String host, Object why) {
    if (!_isDown(_hostDown[host])) {
      rlog('mirror: $host failed ($why) — its voices come from the mirror '
          'for ${downFor.inMinutes} min');
    }
    _hostDown[host] = DateTime.now();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'GET') return inner.send(request);
    final file = map.fileOf(request.url);
    final spot = file ?? map.tableOf(request.url);
    if (spot == null) return inner.send(request);
    final host = request.url.host;

    final hostAbort = Completer<void>();
    final mirrorAbort = Completer<void>();
    void abortBoth() {
      if (!hostAbort.isCompleted) hostAbort.complete();
      if (!mirrorAbort.isCompleted) mirrorAbort.complete();
    }

    if (request case http.Abortable(:final abortTrigger?)) {
      abortTrigger.then((_) => abortBoth()).ignore();
    }

    Future<_Outcome> fromHost() =>
        _settle(_fromHost(request, host, hostAbort.future));
    Future<_Outcome> fromMirror() => _settle(file != null
        ? _mirrorFile(spot, request, mirrorAbort.future)
        : _mirrorTable(spot, request));

    // The host has failed lately: the mirror first, the host if the
    // mirror can't.
    if (_isDown(_hostDown[host]) && !_isDown(_mirrorDown)) {
      final m = await fromMirror();
      if (m.good) return _mirrored(m, spot);
      m.drop();
      return (await fromHost()).give();
    }

    final hostTry = fromHost();
    final early = await Future.any<_Outcome?>(
        [hostTry, Future<_Outcome?>.delayed(patience, () => null)]);
    if (early != null) {
      if (early.good) return early.give();
      if (early.hard) _markDown(host, early.why);
      if (_isDown(_mirrorDown)) return early.give();
      final m = await fromMirror();
      if (m.good) return _mirrored(m, spot);
      m.drop();
      return early.give();
    }

    // No answer yet: ask the mirror beside it; the first good answer wins.
    final done = Completer<(_Outcome, bool)>();
    var left = 2;
    _Outcome? hostOut;
    void take(_Outcome o, bool fromTheHost) {
      if (done.isCompleted) {
        o.drop();
        return;
      }
      if (o.good) {
        done.complete((o, fromTheHost));
        return;
      }
      if (fromTheHost) {
        hostOut = o;
      } else {
        o.drop();
      }
      if (--left == 0) done.complete((hostOut ?? o, true));
    }

    hostTry.then((o) => take(o, true)).ignore();
    if (_isDown(_mirrorDown)) {
      left = 1;
    } else {
      fromMirror().then((o) => take(o, false)).ignore();
    }
    final (won, wonByHost) = await done.future;
    if (wonByHost) {
      if (!mirrorAbort.isCompleted) mirrorAbort.complete();
      if (!won.good && won.hard) _markDown(host, won.why);
      return won.give();
    }
    if (!hostAbort.isCompleted) hostAbort.complete();
    _markDown(host, 'no answer in ${patience.inMilliseconds} ms');
    return _mirrored(won, spot);
  }

  http.StreamedResponse _mirrored(_Outcome m, MirrorSpot spot) {
    _served++;
    if (_told.add(spot.voice)) {
      rlog('mirror: ${spot.voice} ${spot.key} from the mirror');
    }
    return m.give();
  }

  /// The host's answer, its body watched: a body that breaks off marks
  /// the host as failing, so the caller's next try (a resume) goes to
  /// the mirror, which has the same bytes.
  Future<http.StreamedResponse> _fromHost(
      http.BaseRequest original, String host, Future<void> abort) async {
    final res = await inner.send(_get(original.url, original.headers, abort,
        like: original));
    return http.StreamedResponse(
      res.stream.transform(StreamTransformer.fromHandlers(
          handleError: (Object e, StackTrace s, EventSink<List<int>> sink) {
        _markDown(host, e);
        sink.addError(e, s);
      })),
      res.statusCode,
      contentLength: res.contentLength,
      request: original,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  }

  static final _rangeAsked = RegExp(r'^bytes=(\d*)-(\d*)$');

  /// The file at [spot], or the part of it [original] asks for, read out
  /// of its pack and answered as its host answers: 200 with the whole
  /// file, or 206 with the range in the file's own bytes.
  Future<http.StreamedResponse> _mirrorFile(
      MirrorSpot spot, http.BaseRequest original, Future<void> abort) async {
    final MirrorIndex idx;
    try {
      idx = await store.index(spot.voice);
    } catch (e) {
      _mirrorFailed(e);
      rethrow;
    }
    final at = idx.files[spot.key];
    if (at == null) {
      return http.StreamedResponse(const Stream.empty(), 404,
          request: original);
    }
    final (pack, offset, length) = at;
    final asked = original.headers['Range'] ?? original.headers['range'];
    var from = 0;
    var to = length - 1;
    if (asked != null) {
      final m = _rangeAsked.firstMatch(asked.trim());
      final a = m?.group(1) ?? '';
      final b = m?.group(2) ?? '';
      if (m == null || (a.isEmpty && b.isEmpty)) return _unsatisfiable(length);
      if (a.isEmpty) {
        from = math.max(0, length - int.parse(b));
      } else {
        from = int.parse(a);
        if (b.isNotEmpty) to = math.min(int.parse(b), length - 1);
      }
      if (from >= length || from > to) return _unsatisfiable(length);
    }
    final lo = offset + from;
    final hi = offset + to;
    final http.StreamedResponse res;
    try {
      res = await inner.send(_get(store.assetUrl(spot.voice, idx.packs[pack]),
          {'Range': 'bytes=$lo-$hi'}, abort));
    } catch (e) {
      _mirrorFailed(e);
      rethrow;
    }
    if (res.statusCode != 206 ||
        !(res.headers['content-range'] ?? '').startsWith('bytes $lo-$hi/')) {
      Download.discard(res);
      // A pack that is gone or shorter: the voice was copied again, and
      // its index is asked for afresh next time.
      if (res.statusCode == 404 || res.statusCode == 416) {
        await store.forget(spot.voice);
      } else if (res.statusCode >= 500) {
        _mirrorFailed(BadStatus(res.statusCode));
      }
      throw BadStatus(res.statusCode, 'mirror pack of ${spot.voice}');
    }
    final n = to - from + 1;
    return http.StreamedResponse(
      res.stream,
      asked == null ? 200 : 206,
      contentLength: n,
      request: original,
      headers: {
        'content-type': 'audio/mpeg',
        'content-length': '$n',
        'accept-ranges': 'bytes',
        if (asked != null) 'content-range': 'bytes $from-$to/$length',
      },
    );
  }

  /// The host's verse table for [spot], as the host answers it.
  Future<http.StreamedResponse> _mirrorTable(
      MirrorSpot spot, http.BaseRequest original) async {
    final Map<String, dynamic> t;
    try {
      t = await store.timing(spot.voice);
    } catch (e) {
      _mirrorFailed(e);
      rethrow;
    }
    final table = t[spot.key];
    if (table == null) {
      return http.StreamedResponse(const Stream.empty(), 404,
          request: original);
    }
    final bytes = utf8.encode(jsonEncode(table));
    return http.StreamedResponse(Stream.value(bytes), 200,
        contentLength: bytes.length,
        request: original,
        headers: {
          'content-type': 'application/json',
          'content-length': '${bytes.length}',
        });
  }

  static void _mirrorFailed(Object e) {
    if (e is BadStatus && e.code < 500) return;
    if (!_isDown(_mirrorDown)) rlog('mirror: unreachable ($e)');
    _mirrorDown = DateTime.now();
  }

  static http.StreamedResponse _unsatisfiable(int length) =>
      http.StreamedResponse(const Stream.empty(), 416,
          headers: {'content-range': 'bytes */$length'});

  static http.BaseRequest _get(
      Uri url, Map<String, String> headers, Future<void> abort,
      {http.BaseRequest? like}) {
    final r = http.AbortableRequest('GET', url, abortTrigger: abort)
      ..headers.addAll(headers);
    if (like != null) {
      r
        ..followRedirects = like.followRedirects
        ..maxRedirects = like.maxRedirects
        ..persistentConnection = like.persistentConnection;
    }
    return r;
  }

  static Future<_Outcome> _settle(Future<http.StreamedResponse> f) => f.then(
      (r) => _Outcome(r, null, null),
      onError: (Object e, StackTrace s) => _Outcome(null, e, s));

  @override
  void close() => inner.close();
}

/// How one ask went: an answer, or what went wrong.
class _Outcome {
  final http.StreamedResponse? res;
  final Object? error;
  final StackTrace? stack;

  _Outcome(this.res, this.error, this.stack);

  /// An answer to use: the file or the part asked for, or a 416 — an
  /// answer about the range itself, which the mirror would give too.
  bool get good {
    final c = res?.statusCode;
    return c != null && ((c >= 200 && c < 300) || c == 416);
  }

  /// A failure of the host rather than of the file: no connection, a
  /// server error, "too many requests". A 404 is the file's alone.
  bool get hard {
    final c = res?.statusCode;
    return error != null || (c != null && (c >= 500 || c == 429));
  }

  Object get why => error ?? 'HTTP ${res?.statusCode}';

  http.StreamedResponse give() {
    final r = res;
    if (r != null) return r;
    Error.throwWithStackTrace(error!, stack ?? StackTrace.current);
  }

  /// Lets go of an answer that won't be used.
  void drop() {
    final r = res;
    if (r != null) Download.discard(r);
  }
}
