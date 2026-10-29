import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/qul_words.dart';
import 'package:ayah_reels/data/word_align_service.dart';

/// Every voice QUL's word timing is put on was verified against the
/// app's own audio by tool/verify_word_timing.py, and carries the rules
/// the tool measured for it. A voice added to the table without the
/// tool, or given rules it never measured, fails here, not in someone's
/// reel by lighting a word a second late.
void main() {
  final verified = (jsonDecode(
              File('tool/word_timing_verified.json').readAsStringSync())
          as Map<String, dynamic>)['voices'] as Map<String, dynamic>;

  test('every voice QUL times was verified to be its recording', () {
    for (final e in QulWords.sources.entries) {
      final v = verified[e.key] as Map<String, dynamic>?;
      expect(v, isNotNull, reason: '${e.key} was never verified');
      expect(v!['recommend'], 'on', reason: e.key);
      final use = v['use'] as String;
      final src = e.value;
      expect(use,
          '${src.fit == QulFit.ayahFiles ? 'ayah' : 'surah'} ${src.recitation}',
          reason: e.key);
      expect(reciters.any((r) => r.id == e.key), isTrue,
          reason: '${e.key} is not a voice of the app');
    }
  });

  test('and carries the rules the tool measured for it', () {
    for (final e in QulWords.sources.entries) {
      final v = verified[e.key] as Map<String, dynamic>;
      final run = v['runtime'] as Map<String, dynamic>;
      final src = e.value;
      final method = run['method'] as String;
      switch (src.fit) {
        case QulFit.ayahFiles:
          expect(v['verdict'], 'exact', reason: e.key);
        case QulFit.surahFile:
          expect(['offset', 'qul_times'], contains(method), reason: e.key);
          // One shift for the surah, from the verses' onsets, with the
          // bias the tool found between those and QUL's first words.
          final shift = (((v['sample'] as Map)[v['use']] as Map)['variants']
              as Map)['shift'] as Map;
          expect(src.biasMs, shift['bias_ms'] ?? 0, reason: e.key);
          if (method == 'offset') {
            // Where QUL's file is in the voice's, surah by surah.
            final offsets = run['offset_ms'] as Map<String, dynamic>;
            expect(src.offsets, {
              for (final o in offsets.entries) int.parse(o.key): o.value as int,
            }, reason: e.key);
            expect(src.driftPpm, (run['drift_ppm'] as num?)?.toDouble() ?? 0,
                reason: e.key);
            expect(src.onsetFallback, isFalse, reason: e.key);
          } else {
            expect(src.offsets, isEmpty, reason: e.key);
            expect(src.onsetFallback, isTrue, reason: e.key);
          }
        case QulFit.perVerse:
          expect(method, 'shift', reason: e.key);
          expect(src.biasMs, run['bias_ms'] ?? 0, reason: e.key);
          final one = run['verse1'] as Map<String, dynamic>;
          expect(src.verseOne.name, one['rule'], reason: e.key);
          if (one['rule'] != 'none') {
            expect(src.verseOneBiasMs, one['bias_ms'] ?? 0, reason: e.key);
            expect(src.verseOneOff,
                {for (final s in (one['off'] as List? ?? const [])) s as int},
                reason: e.key);
          }
      }
      expect(src.skip,
          {for (final s in (run['surahs_off'] as List? ?? const [])) s as int},
          reason: e.key);
    }
  });

  test('every voice the tool passed is in the table', () {
    for (final e in verified.entries) {
      final v = e.value as Map<String, dynamic>;
      if (v['recommend'] != 'on') continue;
      expect(QulWords.sources.containsKey(e.key), isTrue,
          reason: '${e.key} passed but has no words in the app');
    }
  });

  test('a voice with QUL words is one the app counts as word-timed', () {
    for (final id in QulWords.sources.keys) {
      final r = reciters.firstWhere((r) => r.id == id);
      expect(WordAlignService.supports(r), isTrue, reason: id);
    }
  });
}
