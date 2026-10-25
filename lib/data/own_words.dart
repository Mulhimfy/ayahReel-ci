import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'download.dart';
import 'fatiha_data.dart' show reciters;
import 'qul_words.dart';
import 'trouble.dart';
import 'whole_file.dart';
import 'words_host.dart';

/// The voices the app times itself, word by word, and how their timing
/// lies on the audio each one plays.
///
/// Neither quran-align nor the Quranic Universal Library times most of
/// the app's voices, and without word timing a voice has no recited word
/// to light, no Gilded or Unveil, and its long verses are cut only where
/// its breaths can be heard. So the app's own timing is computed by
/// forced alignment against the very files the app plays, checked
/// against the voices that do have timing, and published verse by verse
/// where it passed (the private Mulhimfy/ayahreel-words repository),
/// served only to the app ([WordsHost]).
///
/// Which voices it covers is not written into the app: it is read from
/// the index served beside the timing ([indexUrl]), kept on the phone
/// and looked at again once a day. A voice that passes later is timed
/// from then on, in this build, with nothing to install; and one that
/// was found wanting can be taken off the same way. A voice the index
/// names is used only if the app has it, nothing else times it, and its
/// measured error is within [mostMedianMs] and [mostP90Ms].
abstract final class OwnWords {
  static const indexUrl = '${WordsHost.base}/index.json';

  /// How old the kept index may be before it is asked for again.
  static const refreshEvery = Duration(hours: 20);

  /// The most a voice's measured word-start error may be, at the median
  /// and at the 90th percentile, for its timing to be used: about what
  /// QUL's verified voices measure (12–27 ms, 36–111 ms), with room.
  static const mostMedianMs = 60;
  static const mostP90Ms = 160;

  static Map<String, QulSource> _sources = const {};

  /// Voice id → its own timing, as the index last said.
  static Map<String, QulSource> get sources => _sources;

  static Future<void>? _started;

  /// Reads the kept index, then — when it is a day old, or there is
  /// none — asks for it again. Never throws; at worst no voice is timed
  /// this way until the next launch.
  static Future<void> init() => _started ??= _start();

  static Future<void> _start() async {
    try {
      final f = await _file();
      if (f.existsSync()) {
        _sources = parseIndex(jsonDecode(await f.readAsString()));
        if (DateTime.now().difference(f.lastModifiedSync()) < refreshEvery) {
          return;
        }
      }
    } catch (e) {
      rlog('own words: kept index unreadable ($e)');
    }
    // A build without the key (tests, a local run) can't ask the host.
    if (!WordsHost.enabled) return;
    await _refresh();
  }

  static Future<void> _refresh() async {
    final client = http.Client();
    try {
      final res = await Download.get(client, Uri.parse(indexUrl),
          headers: WordsHost.headers);
      if (res.statusCode != 200) throw BadStatus(res.statusCode);
      final parsed = parseIndex(jsonDecode(res.body));
      _sources = parsed;
      await writeWhole(await _file(), res.body);
      rlog('own words: ${parsed.length} voice(s) timed');
    } catch (e) {
      rlog('own words: index not fetched ($e)');
    } finally {
      client.close();
    }
  }

  /// The index as the app uses it: `{"v": 1, "voices": {"<id>": {"fit":
  /// "ayahFiles" | "surahFile", "surahs": [...], "medianMs": …, "p90Ms":
  /// …}}}`. Anything it can't vouch for is left out rather than refused
  /// whole: an unknown voice, a fit it doesn't know, an error over the
  /// bar, a voice something else already times.
  @visibleForTesting
  static Map<String, QulSource> parseIndex(Object? json) {
    if (json is! Map || json['v'] != 1) return const {};
    final voices = json['voices'];
    if (voices is! Map) return const {};
    final known = {for (final r in reciters) r.id};
    final out = <String, QulSource>{};
    for (final e in voices.entries) {
      final id = '${e.key}';
      final v = e.value;
      if (v is! Map || !known.contains(id)) continue;
      if (QulWords.sources.containsKey(id)) continue;
      final fit = switch (v['fit']) {
        'ayahFiles' => QulFit.ayahFiles,
        'surahFile' => QulFit.surahFile,
        _ => null,
      };
      if (fit == null) continue;
      final median = v['medianMs'];
      final p90 = v['p90Ms'];
      if (median is! num || p90 is! num) continue;
      if (median > mostMedianMs || p90 > mostP90Ms) continue;
      final surahs = v['surahs'];
      if (surahs is! List) continue;
      final have = {
        for (final s in surahs)
          if (s is int && s >= 1 && s <= 114) s,
      };
      if (have.isEmpty) continue;
      final rev = v['rev'];
      final near = v['near'];
      out[id] = QulSource(
        0,
        fit,
        own: id,
        ownRev: rev is String && _rev.hasMatch(rev) ? rev : null,
        near: {
          if (near is List)
            for (final s in near)
              if (s is int && s >= 1 && s <= 114) s,
        },
        skip: {
          for (var s = 1; s <= 114; s++)
            if (!have.contains(s)) s,
        },
      );
    }
    return out;
  }

  /// What a revision may look like: it becomes part of a file name.
  static final _rev = RegExp(r'^[0-9a-f]{1,40}$');

  static Future<File> _file() async {
    final dir = debugDir ?? await getApplicationSupportDirectory();
    return File('${dir.path}/own_words_index.json');
  }

  @visibleForTesting
  static Directory? debugDir;

  /// Sets the voices outright, as a parsed index would.
  @visibleForTesting
  static void debugSet(Map<String, QulSource> sources) => _sources = sources;

  @visibleForTesting
  static void debugReset() {
    _sources = const {};
    _started = null;
  }
}
