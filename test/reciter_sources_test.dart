import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';

/// Every voice the app offers has passed tool/verify_reciters.py — every
/// file there, every table matching its audio — as the app has it now.
/// A voice added, or moved to another source, without running the tool
/// fails here, not in someone's reel.
void main() {
  final verified = jsonDecode(
          File('tool/reciters_verified.json').readAsStringSync())
      as Map<String, dynamic>;

  /// The tool's `source_key`, from the Dart side.
  String sourceKey(Reciter r) => switch (r.source) {
        AyahFiles(:final host, :final folder) => 'ayah $host/$folder',
        SurahFiles(
          :final base,
          :final padded,
          :final timing,
          :final openingMs,
          :final missing
        ) =>
          'surah $base ${padded ? 'SSS' : 'S'} ${switch (timing) {
            Mp3QuranTiming(:final read) => 'mp3quran $read',
            QulTiming(:final recitation) => 'qul $recitation',
          }}${openingMs == null ? '' : ' opening $openingMs'}'
              '${missing.isEmpty ? '' : ' missing ${(missing.toList()..sort()).join(',')}'}',
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
      final everyAyah = r.everyAyahFolder != null;
      if (everyAyah) continue; // hand-set before the tool; see Reciter.pace
      final measured = (verified[r.id]['pace'] as num).toDouble();
      expect(r.pace, closeTo(measured, 0.005), reason: r.id);
    }
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
      // An alternate is offered for whatever its voice is: it opens on
      // Al-Fatiha like every voice (above), and lacks nothing the voice
      // has.
      for (final s in r.missingSurahs) {
        expect(voice.hasSurah(s), isFalse, reason: '${r.id} lacks $s');
      }
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
