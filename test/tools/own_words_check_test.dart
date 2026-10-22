import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ayah_reels/data/own_words.dart';
import 'package:ayah_reels/data/qul_words.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/word_align_service.dart';

/// The app's own word timing, read the way a phone reads it, against the
/// text the phone shows: the published index through [OwnWords.parseIndex],
/// a sample of each voice's surahs through [QulWords.decodeCompact], and
/// every verse of them through [WordAlignService.fromMushafWords] on the
/// Uthmani text quran.com serves the app. A verse whose words do not land
/// on its tokens would light the wrong word; this counts them. Needs the
/// network, so skipped unless pointed somewhere:
///
///   STYLE_PREVIEW_OUT=/tmp/own flutter test test/tools/own_words_check_test.dart
void main() {
  final out = Platform.environment['STYLE_PREVIEW_OUT'];

  test('the published word timing lands on the app\'s own text', () async {
    // The test binding answers every request with a 400; this one has to
    // reach the hosts for real.
    HttpOverrides.global = null;
    final client = http.Client();
    final report = StringBuffer();
    try {
      final index = jsonDecode(
          (await client.get(Uri.parse(OwnWords.indexUrl))).body);
      final voices = OwnWords.parseIndex(index);
      report.writeln('index: ${(index as Map)['voices']?.length} listed, '
          '${voices.length} the app would use');
      final text = <int, Map<int, String>>{};
      Future<Map<int, String>> textOf(int surah) async =>
          text[surah] ??= await () async {
            final r = await client.get(Uri.parse(
                'https://api.quran.com/api/v4/quran/verses/uthmani'
                '?chapter_number=$surah'));
            final verses = (jsonDecode(r.body) as Map)['verses'] as List;
            return {
              for (final v in verses)
                int.parse((v['verse_key'] as String).split(':')[1]):
                    (v['text_uthmani'] as String).trim(),
            };
          }();
      var verses = 0, landed = 0;
      for (final e in voices.entries) {
        final have = [
          for (var s = 1; s <= 114; s++)
            if (!e.value.skip.contains(s)) s,
        ];
        // A spread of each voice's surahs: its first, its longest
        // published, and a few between.
        final sample = <int>{
          have.first,
          have.last,
          for (final s in const [2, 18, 36, 67, 112])
            if (have.contains(s)) s,
        };
        var v = 0, ok = 0;
        for (final s in sample) {
          final r = await client
              .get(Uri.parse('${QulWords.ownHost}/${e.key}/$s.json'));
          if (r.statusCode != 200) {
            report.writeln('  ${e.key} $s: HTTP ${r.statusCode}');
            continue;
          }
          final parsed = QulWords.decodeCompact(jsonDecode(r.body));
          final arabic = await textOf(s);
          for (final p in parsed.entries) {
            final verse = arabic[p.key];
            if (verse == null) continue;
            v++;
            final placed = (count: p.value.count, words: p.value.words);
            final spans = WordAlignService.fromMushafWords(verse, placed);
            final tokens = VerseText.tokens(verse);
            if (spans != null && spans.isNotEmpty) {
              ok++;
            } else {
              report.writeln('  ${e.key} $s:${p.key}: ${p.value.count} '
                  'words for ${tokens.where(VerseText.isWord).length} '
                  'tokens');
            }
          }
        }
        verses += v;
        landed += ok;
        report.writeln('${e.key} (${e.value.fit.name}): $ok of $v sampled '
            'verses land, surahs ${sample.toList()..sort()}');
      }
      report.writeln('all: $landed of $verses verses land');
    } finally {
      client.close();
      Directory(out!).createSync(recursive: true);
      File('$out/own_words_check.txt').writeAsStringSync(report.toString());
      // ignore: avoid_print
      print(report);
    }
  }, skip: out == null, timeout: const Timeout(Duration(minutes: 20)));
}
