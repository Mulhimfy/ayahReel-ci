import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'download.dart';
import 'models.dart';
import 'trouble.dart';
import 'whole_file.dart';
import 'words_host.dart';

/// The verse tables of our own, for the few surah-file recordings whose
/// host publishes none, or none that fits ([OwnTiming]).
///
/// Each was made from the recording itself by tool/verse_table.py: the
/// surah's file aligned whole against its text with a Quran acoustic
/// model, no published table guiding it, a verse starting where its
/// first word does. The method was measured first on recordings whose
/// verse starts are known word by word, and each table was then checked
/// against its audio like any published one (tool/verify_reciters.py:
/// every file, a breath at the verse starts, the same table shifted
/// scoring no better) before its voice was offered.
///
/// A table is not in the app. Like the app's own word timing it is
/// served only to the app ([WordsHost]): fetched the first time its
/// voice is used, checked against its digest here, and kept on the
/// phone, so the voice works offline from then on, and an offline
/// download fetches it with the voice. The digest is what the app
/// trusts: a table that doesn't match it is refused. A table made again
/// is a new digest and a new file beside the old on the host, which an
/// update brings. The tables themselves, and how they are put on the
/// host, are in the private Mulhimfy/ayahreel-words repository
/// (data/own_tables.json, worker/put_tables.py).
///
/// The form, from tool/verse_table.py's `encode`: base64 of, for each
/// surah 1..114, its verse count (0 for a surah the recording doesn't
/// have), then for each verse the gap since the previous verse ended
/// (for the first, since the file began) and the verse's length, in
/// 10 ms, each an LEB128 varint.
abstract final class VerseTables {
  /// Each table's sha256, of its text as `encode` writes it.
  static const digests = <String, String>{
    // 114 surahs, 6236 verses.
    'luhaidan':
        'afdef534ccfe683133e2a78711cd309ceb9a0798163782976d551675c5f1257f',
  };

  /// Stands in for [digests], and for the folder tables are kept in,
  /// in tests.
  @visibleForTesting
  static Map<String, String>? debugDigests;
  @visibleForTesting
  static Directory? debugDir;

  /// Surah [surah]'s windows in [table], 1..n in the surah file's own
  /// time. A [FormatException] when there is no such table or surah, or
  /// the table isn't the one its digest names; what the fetch threw when
  /// it can't be had (no network, the host down).
  static Future<List<AyahTiming>> surah(String table, int surah) async {
    final t = (await _table(table))[surah];
    if (t == null) {
      throw FormatException('verse table $table has no surah $surah');
    }
    return t;
  }

  static final _decoded = <String, Map<int, List<AyahTiming>>>{};
  static final _pending = <String, Future<Map<int, List<AyahTiming>>>>{};

  static Future<Map<int, List<AyahTiming>>> _table(String table) async {
    final done = _decoded[table];
    if (done != null) return done;
    return _pending[table] ??= _get(table)
        .then((t) => _decoded[table] = t)
        .whenComplete(() => _pending.remove(table));
  }

  static Future<Map<int, List<AyahTiming>>> _get(String table) async {
    final digest = (debugDigests ?? digests)[table];
    if (digest == null) {
      throw FormatException('there is no verse table $table');
    }
    final dir = debugDir ?? await getApplicationSupportDirectory();
    final kept = File('${dir.path}/verse_table_${table}_'
        '${digest.substring(0, 12)}.txt');
    if (kept.existsSync()) {
      final text = kept.readAsStringSync();
      if (digestOf(text) == digest) return decode(text);
      rlog('verse table $table: the kept copy is damaged; fetched again');
    }
    final text = await _fetch(table, digest);
    if (digestOf(text) != digest) {
      throw FormatException('verse table $table is not the one this '
          'build was made for');
    }
    final rows = decode(text);
    await writeWhole(kept, text);
    return rows;
  }

  static Future<String> _fetch(String table, String digest) async {
    if (!WordsHost.enabled) {
      throw FormatException('this build has no key for verse table $table');
    }
    final url = Uri.parse(
        '${WordsHost.base}/tables/$table-${digest.substring(0, 12)}.json');
    Object? last;
    final client = http.Client();
    try {
      for (var attempt = 1; attempt <= Download.attempts; attempt++) {
        try {
          final res =
              await Download.get(client, url, headers: WordsHost.headers);
          if (res.statusCode != 200) throw BadStatus(res.statusCode);
          final json = jsonDecode(res.body);
          final text = json is Map ? json['table'] : null;
          if (text is! String) {
            throw FormatException('no verse table $table in the answer');
          }
          return text;
        } on FormatException {
          rethrow;
        } catch (e) {
          last = e;
          rlog('verse table $table: try $attempt/${Download.attempts} '
              'failed — $e');
          if (Download.isFinal(e)) break;
          if (attempt < Download.attempts) {
            await Future<void>.delayed(Download.backoff(attempt));
          }
        }
      }
    } finally {
      client.close();
    }
    throw last!;
  }

  /// The sha256 [digests] name a table's [text] by.
  @visibleForTesting
  static String digestOf(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  /// [text] as surah -> windows (see the form above).
  @visibleForTesting
  static Map<int, List<AyahTiming>> decode(String text) {
    final b = base64.decode(text);
    var i = 0;
    int next() {
      var n = 0;
      var shift = 0;
      while (true) {
        if (i >= b.length) throw const FormatException('cut short');
        final x = b[i++];
        n |= (x & 0x7f) << shift;
        shift += 7;
        if (x & 0x80 == 0) return n;
      }
    }

    final out = <int, List<AyahTiming>>{};
    for (var s = 1; s <= 114; s++) {
      final n = next();
      var prev = 0;
      final rows = <AyahTiming>[];
      for (var a = 1; a <= n; a++) {
        final start = prev + next();
        final end = start + next();
        rows.add(AyahTiming(a, start * 10, end * 10));
        prev = end;
      }
      if (n > 0) out[s] = rows;
    }
    if (i != b.length) throw const FormatException('trailing bytes');
    return out;
  }

  /// Forgets what was read; tests only.
  @visibleForTesting
  static void debugReset() {
    _decoded.clear();
    _pending.clear();
  }
}
