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
}
