import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_tables.dart';

/// Every voice the app offers has passed tool/verify_reciters.py — every
/// file there, every table matching its audio — as the app has it now.
/// A voice added, or moved to another source, without running the tool
/// fails here, not in someone's reel.
void main() {
  final verified = jsonDecode(
          File('tool/reciters_verified.json').readAsStringSync())
      as Map<String, dynamic>;

  /// What a table of our own is verified under: its content, as
  /// tool/verse_table.py's `digest` names it — the start of the sha256
  /// the app trusts it by.
  String digest(String table) => VerseTables.digests[table]!.substring(0, 12);

  /// The tool's `elsewhere_digest`: a voice's files from another host,
  /// named by the start of the sha256 of `<surah> <url>` lines.
  String elsewhereDigest(Map<int, String> el) {
    final text = [for (final s in el.keys.toList()..sort()) '$s ${el[s]}\n']
        .join();
    return sha256.convert(utf8.encode(text)).toString().substring(0, 12);
  }

  /// The tool's `source_key`, from the Dart side.
  String sourceKey(Reciter r) => switch (r.source) {
        AyahFiles(:final host, :final folder) => 'ayah $host/$folder',
        SurahFiles(
          :final base,
          :final padded,
          :final timing,
          :final openingMs,
          :final missing,
          :final elsewhere
        ) =>
          'surah $base ${padded ? 'SSS' : 'S'} ${switch (timing) {
            Mp3QuranTiming(:final read) => 'mp3quran $read',
            QulTiming(:final recitation) => 'qul $recitation',
            OwnTiming(:final table) => 'own $table ${digest(table)}',
          }}${openingMs == null ? '' : ' opening $openingMs'}'
              '${missing.isEmpty ? '' : ' missing ${(missing.toList()..sort()).join(',')}'}'
              '${elsewhere.isEmpty ? '' : ' elsewhere ${elsewhereDigest(elsewhere)}'}',
        OwnAudio() => 'own',
      };

  test('every voice passed verification, from the source it has now', () {
    for (final r in reciters) {
      final v = verified[r.id] as Map<String, dynamic>?;
      expect(v, isNotNull, reason: '${r.id} was never verified');
      expect(v!['problems'], isEmpty, reason: r.id);
      expect(v['source'], sourceKey(r),
          reason: '${r.id} has moved since it was verified');
    }
    expect(verified.keys.toSet(), reciters.map((r) => r.id).toSet(),
        reason: 'results for a voice the app no longer has');
  });

  test('a voice added since the tool carries the pace it measured', () {
    for (final r in reciters) {
      // The EveryAyah voices' paces were set by hand before the tool (see
      // Reciter.pace) — all but another recording, which came after it.
      final everyAyah = r.everyAyahFolder != null;
      if (everyAyah && r.recordingOf == null) continue;
      final measured = (verified[r.id]['pace'] as num).toDouble();
      expect(r.pace, closeTo(measured, 0.005), reason: r.id);
    }
  });

  test('another recording is another performance, not the same one from '
      'another host', () {
    // tool/verify_reciters.py compares each one with every other
    // recording of its voice, waveforms and verse lengths over 160-odd
    // verses (see 9. in its docstring), and records the verdict against
    // the source it compared with.
    for (final r in reciters) {
      if (r.recordingOf == null) continue;
      final v = verified[r.id] as Map<String, dynamic>;
      expect(v['recording_of'], r.recordingOf, reason: r.id);
      final distinct = v['distinct'] as Map<String, dynamic>?;
      for (final other in recordingsOf(r)) {
        if (other.id == r.id) continue;
        final d = distinct?[other.id] as Map<String, dynamic>?;
        expect(d, isNotNull,
            reason: '${r.id} was never compared with ${other.id}');
        expect(d!['ok'], isTrue, reason: '${r.id} against ${other.id}');
        expect(d['source'], sourceKey(other),
            reason: '${other.id} has moved since ${r.id} was compared '
                'with it');
        expect(d['wave_same'], 0, reason: '${r.id} against ${other.id}');
        expect(d['verses'] as int, greaterThanOrEqualTo(40),
            reason: '${r.id} against ${other.id}');
      }
    }
  });

  test('every table of our own a voice reads has its digest, and none is '
      'spare', () {
    // The tables themselves are served, not carried (VerseTables); that
    // each has every verse of every surah its recording has, one after
    // another, is checked where they live, by the private repository's
    // worker/put_tables.py before it serves one.
    final used = <String>{};
    for (final r in reciters) {
      final source = r.source;
      if (source is! SurahFiles) continue;
      final timing = source.timing;
      if (timing is! OwnTiming) continue;
      used.add(timing.table);
      expect(VerseTables.digests[timing.table], matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: '${r.id} reads a table with no digest');
    }
    expect(VerseTables.digests.keys.toSet(), used);
  });

  test('every voice has Al-Fatiha, where the list samples it and a reel '
      'starts when nothing else is chosen', () {
    for (final r in reciters) {
      expect(r.hasSurah(1), isTrue, reason: r.id);
      for (final s in r.missingSurahs) {
        expect(s, inInclusiveRange(2, 114), reason: r.id);
        expect(r.hasSurah(s), isFalse);
      }
    }
  });

  test('a file from elsewhere is an https address of an mp3, for a surah '
      'the voice offers, and is what url() reads', () {
    for (final r in reciters) {
      final source = r.source;
      if (source is! SurahFiles) continue;
      for (final MapEntry(key: s, value: u) in source.elsewhere.entries) {
        expect(s, inInclusiveRange(1, 114), reason: r.id);
        expect(source.missing, isNot(contains(s)), reason: '${r.id} $s');
        expect(u, matches(RegExp(r'^https://[^\s]+\.mp3$')),
            reason: '${r.id} $s');
        expect(source.url(s).toString(), u, reason: '${r.id} $s');
      }
    }
  });

  test('no two voices share an id or a recording', () {
    final ids = reciters.map((r) => r.id).toList();
    expect(ids.toSet().length, ids.length);
    final sources = reciters.map(sourceKey).toList();
    expect(sources.toSet().length, sources.length);
    for (final r in reciters) {
      // Ids live on in saved recipes and cache folders.
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(r.id), isTrue, reason: r.id);
      if (r.source case AyahFiles(:final folder)) {
        // Folder names become URL path segments verbatim.
        expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(folder), isTrue,
            reason: r.id);
      }
      if (r.source case SurahFiles(:final base)) {
        expect(base, startsWith('https://'), reason: r.id);
        expect(base.endsWith('/'), isFalse, reason: r.id);
      }
    }
  });

  test('another recording hangs under a voice the list has, and says '
      'what sets it apart', () {
    final byId = {for (final r in reciters) r.id: r};
    for (final r in reciters) {
      final of = r.recordingOf;
      if (of == null) {
        expect(r.recordingNote, isNull, reason: r.id);
        continue;
      }
      final voice = byId[of];
      expect(voice, isNotNull, reason: '${r.id}: no voice $of');
      // One level only: a recording of a recording would be a card the
      // pickers never draw.
      expect(voice!.recordingOf, isNull, reason: r.id);
      expect(r.name, voice.name, reason: r.id);
      expect(r.arabicName, voice.arabicName, reason: r.id);
      expect(r.recordingNote, isNotNull, reason: r.id);
      expect(r.recordingNote!.trim(), isNotEmpty, reason: r.id);
      // An alternate opens on Al-Fatiha like every voice (above). A surah
      // it can't serve (a table that doesn't fit its file) is in its
      // `missing`, as for any voice and no more of them than any voice
      // may lack (missing_surah_test.dart): the voice's card then greys
      // that recording's chip and opens on one that has the surah
      // (ReciterScreen's `usable`), and with the recording chosen the
      // verse picker greys the surah, as it does for any voice.
      expect(r.missingSurahs.length, lessThan(5), reason: r.id);
    }
    expect(voices.every((v) => v.recordingOf == null), isTrue);
    for (final v in voices) {
      final all = recordingsOf(v);
      expect(all.first.id, v.id);
      for (final r in all) {
        expect(voiceOf(r).id, v.id);
        expect(recordingsOf(r).map((x) => x.id), all.map((x) => x.id));
      }
    }
    expect(voices.fold<int>(0, (n, v) => n + recordingsOf(v).length),
        reciters.length);
  });
}
