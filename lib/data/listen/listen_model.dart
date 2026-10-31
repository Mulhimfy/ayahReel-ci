import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../debug_log.dart';
import '../download.dart';
import '../trouble.dart';
import '../words_host.dart';

/// Where AyahReel Listen's model is served, with the same key as the
/// app's word timing ([WordsHost]): a Worker of its own
/// (`ayahreel-listen`, private repository Mulhimfy/ayahreel-listen) that
/// answers nothing without the key.
abstract final class ListenHost {
  static const base = 'https://ayahreel-listen.mulhimfy.workers.dev/v1';

  /// Whether this build can fetch the model at all (it has the key).
  static bool get enabled => WordsHost.enabled;

  static Map<String, String> get headers => WordsHost.headers;
}

/// What the manifest says the app should have.
class ListenManifest {
  /// The model's name: a new one is fetched when it changes.
  final String model;
  final String file;
  final int bytes;
  final String sha256;
  final List<({String name, int bytes, String sha256})> parts;

  /// The model's characters, in token order; the blank comes after them.
  final List<String> vocab;
  final double frameMs;

  /// Samples per output frame, and the window the model is run on.
  final int hop;
  final int windowS;
  final int overlapS;

  const ListenManifest({
    required this.model,
    required this.file,
    required this.bytes,
    required this.sha256,
    required this.parts,
    required this.vocab,
    required this.frameMs,
    required this.hop,
    required this.windowS,
    required this.overlapS,
  });

  static ListenManifest parse(Map<String, dynamic> j) => ListenManifest(
        model: j['model'] as String,
        file: j['file'] as String,
        bytes: (j['bytes'] as num).toInt(),
        sha256: j['sha256'] as String,
        parts: [
          for (final p in (j['parts'] as List).cast<Map<String, dynamic>>())
            (
              name: p['name'] as String,
              bytes: (p['bytes'] as num).toInt(),
              sha256: p['sha256'] as String,
            ),
        ],
        vocab: (j['vocab'] as List).cast<String>(),
        frameMs: (j['frame_ms'] as num?)?.toDouble() ?? 40.0,
        hop: (j['hop'] as num?)?.toInt() ?? 640,
        windowS: (j['window_s'] as num?)?.toInt() ?? 30,
        overlapS: (j['overlap_s'] as num?)?.toInt() ?? 3,
      );
}

/// The listening model on the phone: fetched once (about a hundred
/// megabytes, in parts), checked, kept under the app's support folder.
abstract final class ListenModel {
  static ListenManifest? _manifest;

  static Future<Directory> _dir() async {
    final d = Directory(
        '${(await getApplicationSupportDirectory()).path}/listen');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// The manifest: from the host, or the copy kept from the last time
  /// when the host can't be reached (the model on the phone still
  /// works offline).
  static Future<ListenManifest?> manifest({http.Client? client}) async {
    final held = _manifest;
    if (held != null) return held;
    final dir = await _dir();
    final kept = File('${dir.path}/manifest.json');
    if (ListenHost.enabled) {
      final c = client ?? http.Client();
      try {
        final res = await Download.get(
            c, Uri.parse('${ListenHost.base}/manifest.json'),
            headers: ListenHost.headers);
        if (res.statusCode == 200) {
          final m = ListenManifest.parse(
              jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
          await kept.writeAsBytes(res.bodyBytes, flush: true);
          return _manifest = m;
        }
        rlog('listen: manifest ${res.statusCode}');
      } catch (e) {
        rlog('listen: manifest failed ($e)');
      } finally {
        if (client == null) c.close();
      }
    }
    if (kept.existsSync()) {
      try {
        return _manifest = ListenManifest.parse(
            jsonDecode(kept.readAsStringSync()) as Map<String, dynamic>);
      } catch (_) {}
    }
    return null;
  }

  /// The model file if it is on the phone and whole, else null.
  static Future<File?> local() async {
    final m = await manifest();
    if (m == null) return null;
    final dir = await _dir();
    final f = File('${dir.path}/${m.file}');
    final ok = File('${f.path}.ok');
    if (f.existsSync() && ok.existsSync() && f.lengthSync() == m.bytes) {
      return f;
    }
    return null;
  }

  /// The model, fetched if it isn't on the phone yet. [onProgress]
  /// hears the share fetched (0..1). Throws when it can't be had.
  static Future<File> ensure({
    void Function(double share)? onProgress,
    bool Function()? keepGoing,
  }) async {
    final m = await manifest();
    if (m == null) throw const ListenUnavailable('manifest');
    final dir = await _dir();
    final f = File('${dir.path}/${m.file}');
    final ok = File('${f.path}.ok');
    if (f.existsSync() && ok.existsSync() && f.lengthSync() == m.bytes) {
      return f;
    }
    // Older models go: one model on the phone at a time.
    for (final e in dir.listSync()) {
      final name = e.uri.pathSegments.last;
      if (e is File &&
          name != 'manifest.json' &&
          !name.startsWith(m.file)) {
        try {
          e.deleteSync();
        } catch (_) {}
      }
    }
    final part = File('${f.path}.part');
    // Parts already in the .part file: kept across tries and launches,
    // each checked when it arrived.
    var done = 0;
    var have = part.existsSync() ? part.lengthSync() : 0;
    var at = 0;
    for (final p in m.parts) {
      if (at + p.bytes <= have) {
        at += p.bytes;
        done++;
      } else {
        break;
      }
    }
    if (part.existsSync() && have != at) {
      // A part cut short: back to the last whole one.
      final raf = part.openSync(mode: FileMode.append);
      raf.truncateSync(at);
      raf.closeSync();
      have = at;
    }
    final client = http.Client();
    try {
      for (var i = done; i < m.parts.length; i++) {
        final p = m.parts[i];
        var miss = 0;
        while (true) {
          if (keepGoing != null && !keepGoing()) {
            throw const ListenUnavailable('cancelled');
          }
          try {
            final bytes = await _fetchPart(client, p.name, p.bytes,
                (got) => onProgress?.call((at + got) / m.bytes));
            final digest = sha256.convert(bytes).toString();
            if (digest != p.sha256) {
              throw FormatException('part ${p.name} sha256');
            }
            await part.writeAsBytes(bytes, mode: FileMode.append, flush: true);
            at += p.bytes;
            onProgress?.call(at / m.bytes);
            break;
          } catch (e) {
            if (e is ListenUnavailable) rethrow;
            if (Download.isFinal(e) || ++miss >= Download.attempts) {
              rlog('listen: part ${p.name} failed ($e)');
              throw ListenUnavailable('download', e);
            }
            await Future<void>.delayed(Download.backoff(miss));
          }
        }
      }
    } finally {
      client.close();
    }
    // The whole file once more, then it is the model.
    final whole = await part.openRead().transform(sha256).first;
    if (whole.toString() != m.sha256) {
      part.deleteSync();
      throw const ListenUnavailable('checksum');
    }
    if (f.existsSync()) f.deleteSync();
    part.renameSync(f.path);
    ok.writeAsStringSync(m.sha256, flush: true);
    rlog('listen: model ${m.model} on the phone (${m.bytes} bytes)');
    return f;
  }

  static Future<Uint8List> _fetchPart(http.Client client, String name,
      int bytes, void Function(int got) progress) async {
    final res = await Download.send(
        client, Uri.parse('${ListenHost.base}/$name'),
        headers: ListenHost.headers);
    if (res.statusCode != 200) {
      Download.discard(res);
      throw BadStatus(res.statusCode);
    }
    final out = BytesBuilderLite(bytes);
    await for (final chunk in Download.body(res)) {
      out.add(chunk);
      progress(out.length);
    }
    if (out.length != bytes) {
      throw FormatException('part $name: ${out.length} of $bytes bytes');
    }
    return out.bytes;
  }
}

/// A byte buffer of a known size, filled in place.
class BytesBuilderLite {
  final Uint8List bytes;
  int length = 0;
  BytesBuilderLite(int size) : bytes = Uint8List(size);
  void add(List<int> chunk) {
    final n = chunk.length;
    if (length + n > bytes.length) {
      throw const FormatException('more bytes than the part has');
    }
    bytes.setRange(length, length + n, chunk);
    length += n;
  }
}

/// The model can't be had right now: no key in this build, no
/// network, a damaged download, or the user stopped it.
class ListenUnavailable implements Exception {
  final String why;
  final Object? cause;
  const ListenUnavailable(this.why, [this.cause]);
  @override
  String toString() => 'ListenUnavailable($why${cause == null ? '' : ': $cause'})';
}
