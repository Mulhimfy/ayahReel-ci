import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/data/scene_matcher.dart';

/// The matcher chooses sceneries by what the verses say, and the
/// whole feature is only worth having if it is right: a verse about
/// the sea over a picture of the sea reads as intended, and over a
/// picture of a road it reads as a fault. So what is pinned here is
/// the reading — which words reach which motif — against the real
/// library, and the two things the choice must always be: stable, and
/// never the same picture twice.
void main() {
  // The shipped catalog, exactly as the app loads it.
  final catalog = ((jsonDecode(File('assets/catalog.json').readAsStringSync())
          as Map<String, dynamic>)['scenes'] as List)
      .map((e) => Scene.fromJson(e as Map<String, dynamic>))
      .where((s) => !SceneCatalog.withdrawn.contains(s.id))
      .toList();

  Ayah ayah(int n, String arabic) =>
      Ayah(number: n, arabic: arabic, translation: '');

  group('reading a verse', () {
    test('strips the pointing and the article and finds the word', () {
      // Al-Baqarah 164, which names half the library in one verse.
      const v = 'إِنَّ فِى خَلْقِ ٱلسَّمَـٰوَٰتِ وَٱلْأَرْضِ وَٱخْتِلَـٰفِ ٱلَّيْلِ '
          'وَٱلنَّهَارِ وَٱلْفُلْكِ ٱلَّتِى تَجْرِى فِى ٱلْبَحْرِ';
      final motifs = SceneMatcher.read(v).map((e) => e.motif.id).toList();
      expect(motifs, containsAll(['sky', 'night', 'sea', 'land']));
    });

    test('the sea outranks a passing mention of the land', () {
      const v = 'وَهُوَ ٱلَّذِى سَخَّرَ ٱلْبَحْرَ لِتَأْكُلُوا۟ مِنْهُ لَحْمًا طَرِيًّا';
      expect(SceneMatcher.read(v).first.motif.id, 'sea');
    });

    test('mountains, from the plural with a conjunction and case ending',
        () {
      const v = 'وَٱلْجِبَالَ أَوْتَادًا';
      expect(SceneMatcher.read(v).first.motif.id, 'mountain');
    });

    test('a garden with rivers under it is a garden first', () {
      const v = 'جَنَّـٰتٍ تَجْرِى مِن تَحْتِهَا ٱلْأَنْهَـٰرُ';
      final r = SceneMatcher.read(v);
      expect(r.first.motif.id, 'garden');
      expect(r.map((e) => e.motif.id), contains('water'));
    });

    test('the straight path is a road', () {
      expect(SceneMatcher.read(fatiha[5].arabic).first.motif.id, 'road');
    });

    test('a verse that names nothing pictorial reads as nothing', () {
      // Al-Ikhlas 1.
      expect(SceneMatcher.read('قُلْ هُوَ ٱللَّهُ أَحَدٌ'), isEmpty);
    });

    test('words the lexicon would read in the wrong sense read as nothing',
        () {
      // "In His hand", "the comfort of eyes", "rank on rank", "the
      // accursed", "shaped you": none of them a desert, the snow, a
      // mountain or the fire, and each used to pick one.
      const misread = {
        'تَبَـٰرَكَ ٱلَّذِى بِيَدِهِ ٱلْمُلْكُ': 'desert',
        'هَبْ لَنَا مِنْ أَزْوَٰجِنَا وَذُرِّيَّـٰتِنَا قُرَّةَ أَعْيُنٍ': 'snow',
        'وَجَآءَ رَبُّكَ وَٱلْمَلَكُ صَفًّا صَفًّا': 'mountain',
        'فَٱسْتَعِذْ بِٱللَّهِ مِنَ ٱلشَّيْطَـٰنِ ٱلرَّجِيمِ': 'mountain',
        'وَصَوَّرَكُمْ فَأَحْسَنَ صُوَرَكُمْ': 'fire',
        'لَتُفْسِدُنَّ فِى ٱلْأَرْضِ مَرَّتَيْنِ وَلَتَعْلُنَّ عُلُوًّا كَبِيرًا':
            'mountain',
      };
      for (final e in misread.entries) {
        expect(SceneMatcher.read(e.key).map((r) => r.motif.id),
            isNot(contains(e.value)),
            reason: e.key);
      }
      // While the rain and the mountains are still read as themselves.
      expect(
          SceneMatcher.read('وَأَنزَلْنَا مِنَ ٱلْمُعْصِرَٰتِ مَآءً ثَجَّاجًا')
              .first
              .motif
              .id,
          'rain');
      expect(SceneMatcher.read('وَٱلْجِبَالَ أَوْتَادًا').first.motif.id,
          'mountain');
    });

    test('the evidence is the word as written in the verse', () {
      final r = SceneMatcher.read('وَٱلْجِبَالَ أَوْتَادًا').first;
      expect(r.evidence, 'وَٱلْجِبَالَ');
    });

    test('short stems match whole, never as a prefix', () {
      // `يم` is the sea (Ta-Ha 39) but must not fire on every word
      // beginning with those two letters.
      expect(SceneMatcher.read('يَمِينِكَ').map((e) => e.motif.id),
          isNot(contains('sea')));
    });

    test('a surah-long passage is matched well inside the five seconds '
        'Android gives the main thread', () {
      // Al-Baqarah's 286 verses of words that name nothing, the worst
      // case: every word is held against every stem. Normalizing the
      // stems per word made this an ANR on a slow phone (Play, 1.0.8).
      final long = [
        for (var n = 1; n <= 286; n++)
          ayah(n, List.filled(5, 'قُلْ هُوَ ٱللَّهُ أَحَدٌ').join(' ')),
      ];
      final clock = Stopwatch()..start();
      SceneMatcher.match(
        ayahs: long,
        startAyah: 1,
        endAyah: 286,
        count: 8,
        wide: false,
        catalog: catalog,
      );
      expect(clock.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('choosing scenes', () {
    final verses = [
      ayah(1, 'وَٱلْجِبَالَ أَوْتَادًا'),
      ayah(2, 'وَجَعَلْنَا ٱلَّيْلَ لِبَاسًا'),
      ayah(3, 'أَلَمْ تَرَ أَنَّ ٱلْفُلْكَ تَجْرِى فِى ٱلْبَحْرِ'),
      ayah(4, 'قُلْ هُوَ ٱللَّهُ أَحَدٌ'),
    ];

    test('one scene per verse, each from the family the verse named',
        () {
      final picks = SceneMatcher.match(
        ayahs: verses,
        startAyah: 1,
        endAyah: 4,
        count: 4,
        wide: false,
        catalog: catalog,
      );
      expect(picks, hasLength(4));
      expect(picks[0].motif, 'mountain');
      expect(picks[0].scene.family, isIn(['mountains', 'rock', 'snow']));
      expect(picks[1].motif, 'night');
      expect(picks[1].scene.family, isIn(['aurora', 'sky']));
      expect(picks[2].motif, 'sea');
      expect(picks[2].scene.family, isIn(['ocean', 'water']));
      // The last verse names nothing: it takes the passage's mood
      // rather than an unrelated default.
      expect(picks[3].motif, isIn(['sea', 'mountain', 'night']));
      expect(picks[3].evidence, isEmpty);
    });

    test('never the same scenery twice in one reel', () {
      final picks = SceneMatcher.match(
        ayahs: [for (var i = 1; i <= 12; i++) ayah(i, 'وَٱلْجِبَالَ أَوْتَادًا')],
        startAyah: 1,
        endAyah: 12,
        count: 12,
        wide: false,
        catalog: catalog,
      );
      expect(picks.map((p) => p.scene.id).toSet(), hasLength(12));
    });

    test('only the asked-for shape, whatever the verse says', () {
      for (final wide in [false, true]) {
        final picks = SceneMatcher.match(
          ayahs: verses,
          startAyah: 1,
          endAyah: 4,
          count: 4,
          wide: wide,
          catalog: catalog,
        );
        expect(picks, hasLength(4));
        for (final p in picks) {
          expect(p.scene.wide, wide, reason: p.toString());
        }
      }
    });

    test('fewer scenes than verses: each scene answers to its own run',
        () {
      final picks = SceneMatcher.match(
        ayahs: verses,
        startAyah: 1,
        endAyah: 4,
        count: 2,
        wide: false,
        catalog: catalog,
      );
      expect(picks, hasLength(2));
      expect(picks[0].firstAyah, 1);
      expect(picks[0].lastAyah, 2);
      expect(picks[1].firstAyah, 3);
      expect(picks[1].lastAyah, 4);
      expect(picks[1].motif, 'sea');
    });

    test('the same verses give the same reel every time', () {
      List<String> run() => SceneMatcher.match(
            ayahs: verses,
            startAyah: 1,
            endAyah: 4,
            count: 4,
            wide: false,
            catalog: catalog,
          ).map((p) => p.scene.id).toList();
      expect(run(), run());
    });

    test('sceneries already on the device come first', () {
      final ready = catalog.where((s) => s.bundled).map((s) => s.id).toSet();
      final picks = SceneMatcher.match(
        ayahs: [ayah(1, 'وَٱلْجِبَالَ أَوْتَادًا')],
        startAyah: 1,
        endAyah: 1,
        count: 1,
        wide: false,
        catalog: catalog,
        ready: ready,
      );
      expect(ready, contains(picks.single.scene.id));
    });

    test('a passage with no mood at all still gets a sky', () {
      final picks = SceneMatcher.match(
        ayahs: [ayah(1, 'قُلْ هُوَ ٱللَّهُ أَحَدٌ'), ayah(2, 'ٱللَّهُ ٱلصَّمَدُ')],
        startAyah: 1,
        endAyah: 2,
        count: 2,
        wide: false,
        catalog: catalog,
      );
      expect(picks, hasLength(2));
      for (final p in picks) {
        expect(p.motif, 'fallback');
        expect(p.scene.tab, 'sky');
      }
    });

    test('night verses prefer the darker skies', () {
      final picks = SceneMatcher.match(
        ayahs: [ayah(1, 'وَٱلَّيْلِ إِذَا يَغْشَىٰ')],
        startAyah: 1,
        endAyah: 1,
        count: 1,
        wide: false,
        catalog: catalog,
      );
      final chosen = picks.single.scene;
      final family = catalog.where((s) => s.family == chosen.family);
      final median = (family.map(SceneMatcher.luminance).toList()..sort())[
          family.length ~/ 2];
      expect(SceneMatcher.luminance(chosen), lessThanOrEqualTo(median));
    });
  });

  group('the library', () {
    test('every scene id resolves to a family the matcher can name', () {
      final known = <String>{
        for (final m in SceneMatcher.motifs) ...m.families,
        ...SceneMatcher.fallbackFamilies,
        ...SceneMatcher.fallbackFamiliesWide,
      };
      final families = catalog.map((s) => s.family).toSet();
      expect(families, everyElement(isIn(known)),
          reason: 'a family with no motif can never be chosen');
    });
  });
}
