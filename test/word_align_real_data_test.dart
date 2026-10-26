import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/word_align_service.dart';

/// Runs every real quran-align release file through the app's parser.
/// The files live outside the repo (they're a 5.8MB download), so this
/// suite skips silently on machines that don't have them; set
/// QURAN_ALIGN_DIR or drop the JSONs next to the repo to enable it.
void main() {
  final dir = Platform.environment['QURAN_ALIGN_DIR'] ??
      '${Platform.environment['LOCALAPPDATA']}/Temp/claude/'
          'C--Users-dell-ayah-reels/'
          '2d419efa-1774-41ca-933f-e412f8d07987/scratchpad/qalign';

  const folders = [
    'Alafasy_128kbps',
    'Minshawy_Murattal_128kbps',
    'Minshawy_Mujawwad_192kbps',
    'Abdurrahmaan_As-Sudais_192kbps',
    'Saood_ash-Shuraym_128kbps',
    'Abu_Bakr_Ash-Shaatree_128kbps',
    'Hani_Rifai_192kbps',
    'Mohammad_al_Tablaway_128kbps',
    'Abdul_Basit_Mujawwad_128kbps',
  ];

  for (final folder in folders) {
    test('real release file parses end-to-end: $folder', () {
      final f = File('$dir/$folder.json');
      if (!f.existsSync()) {
        markTestSkipped('release data not present at $dir');
        return;
      }
      final parsed = WordAlignService.parseAlignJson(f.readAsStringSync());
      // Every surah must be present with usable spans.
      expect(parsed.length, 114, reason: folder);
      // Spot-check spans exist and are sane at both ends of the mushaf.
      for (final probe in [(1, 1), (2, 255), (36, 1), (112, 1), (114, 6)]) {
        final spans = parsed[probe.$1]?[probe.$2];
        expect(spans, isNotNull, reason: '$folder ${probe.$1}:${probe.$2}');
        for (final s in spans!) {
          expect(s.endMs, greaterThan(s.startMs),
              reason: '$folder ${probe.$1}:${probe.$2}');
          expect(s.endWord, greaterThan(s.startWord),
              reason: '$folder ${probe.$1}:${probe.$2}');
        }
      }
    });
  }
}
