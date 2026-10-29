import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/arena_engine.dart';
import 'package:ayah_reels/data/arena_service.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/verse_light.dart';
import 'package:ayah_reels/l10n/l10n.dart';
import 'package:ayah_reels/render/verses_story.dart';
import 'package:ayah_reels/widgets/quran_sun.dart';

/// The documents folder, somewhere the test can throw away.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docs);
  final String docs;

  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

/// "Your verses": every verse the user has met in the app — the reels
/// recite, the cards quote, the quiz asks — lit on the whole Quran.
/// Read off what the app keeps, so an old user's card is full the day
/// the card arrives.
void main() {
  SavedReel reel(String surah, int from, int to, DateTime at) => SavedReel(
        id: '${at.millisecondsSinceEpoch}',
        fileName: 'r.mp4',
        reciterName: 'Mishary Alafasy',
        surahName: surah,
        startAyah: from,
        endAyah: to,
        gradientArgb: const [0xFF000000, 0xFF111111],
        createdAt: at,
      );

  test('reels made before recipes were kept are read by their surah name',
      () {
    final light = VerseLight.of([
      reel('Al-Kahf', 1, 10, DateTime(2026, 3, 2)),
      reel('Al-Fatiha', 1, 7, DateTime(2026, 1, 5)),
      reel('Al-Kahf', 5, 12, DateTime(2026, 4, 1)),
      reel('Not a surah', 1, 3, DateTime(2026, 4, 2)),
    ]);
    // Oldest first: the order the card burns them in. The two Al-Kahf
    // reels overlap, so they burn as one run, when the first was made;
    // the unknown one is passed over.
    expect(light.order, [(1, 1, 7), (18, 1, 12)]);
    // Al-Kahf 1-12 once, however the two reels overlap, and Al-Fatiha.
    expect(light.verses, 12 + 7);
    expect(light.surahs, 2);
    expect(light.ranges[18], [(1, 12)]);
  });

  test('runs that meet are one; a gap keeps them two', () {
    VerseTouch at(int day, int surah, int from, int to) =>
        (at: DateTime(2026, 5, day), surah: surah, from: from, to: to);
    final light = VerseLight.ofTouches([
      at(3, 2, 255, 255),
      at(1, 2, 1, 5),
      at(2, 2, 6, 6), // meets 1-5
      at(4, 2, 8, 8), // a verse apart
      at(5, 2, 3, 3), // inside 1-6 already
      at(6, 115, 1, 1), // no such surah
    ]);
    expect(light.ranges[2], [(1, 6), (8, 8), (255, 255)]);
    expect(light.verses, 6 + 1 + 1);
    // In the order each run was first met: 1-6 on the 1st, 255 on the
    // 3rd, 8 on the 4th.
    expect(light.order, [(2, 1, 6), (2, 255, 255), (2, 8, 8)]);
  });

  test('a range past the end of its surah is held to it', () {
    final light = VerseLight.of([reel('Al-Ikhlas', 1, 9, DateTime(2026))]);
    expect(light.order.single, (112, 1, 4));
    expect(light.verses, 4);
  });

  group('gathered from the whole app', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('verse_light_test');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
      ArenaService.reset();
      ArenaService.fileOverride = File('${root.path}/arena.json');
    });

    tearDown(() {
      ArenaService.fileOverride = null;
      ArenaService.reset();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('the cards that quote a verse and the rounds the quiz asked',
        () async {
      // A deck: a card quoting Ayat al-Kursi, one quoting a hadith, one
      // in the user's own words.
      Directory('${root.path}/cards').createSync(recursive: true);
      File('${root.path}/cards/decks.json').writeAsStringSync(jsonEncode([
        {
          'id': 'd1',
          'createdAt': '2026-02-01T00:00:00.000',
          'slides': [
            {
              'id': 's1',
              'source': {'kind': 'verse', 'surah': 2, 'start': 255, 'end': 255},
            },
            {
              'id': 's2',
              'source': {'kind': 'hadith', 'collection': 'bukhari', 'number': 1},
            },
            {'id': 's3'},
          ],
        },
      ]));
      // A round that kept its verses, and one filed before rounds did.
      const setup = ArenaSetup(
          scope: ArenaScope.juz(30), games: {ArenaGame.missingWord});
      const result = ArenaResult(setup: setup, seed: 9, answers: [
        ArenaAnswer(chosen: 0, correct: true, points: 100),
      ]);
      await ArenaService.record(result,
          mode: ArenaMode.solo, verses: [(112, 1), (112, 2), (36, 58)]);
      await ArenaService.record(result, mode: ArenaMode.solo);

      final light = await VerseLight.gather(
          reels: [reel('Al-Fatiha', 1, 7, DateTime(2026, 1, 5))]);
      expect(light.ranges[1], [(1, 7)]);
      expect(light.ranges[2], [(255, 255)]);
      expect(light.ranges[112], [(1, 2)]);
      expect(light.ranges[36], [(58, 58)]);
      expect(light.verses, 7 + 1 + 2 + 1);
      expect(light.surahs, 4);
      // The reel first, then the card, then the round.
      expect(light.order.first, (1, 1, 7));
      expect(light.order[1], (2, 255, 255));
    });

    test('a source that cannot be read costs only itself', () async {
      File('${root.path}/cards').writeAsStringSync('not a folder');
      final light = await VerseLight.gather(
          reels: [reel('Al-Ikhlas', 1, 4, DateTime(2026))]);
      expect(light.ranges, {112: [(1, 4)]});
    });
  });

  test('the sun runs clockwise from the top, the long surahs longest', () {
    expect(QuranSun.angleOf(1), closeTo(-1.5708, 0.03));
    expect(QuranSun.lengthOf(2), closeTo(1, 1e-9));
    expect(QuranSun.lengthOf(108), lessThan(QuranSun.lengthOf(36)));
    expect(QuranSun.lengthOf(108), greaterThan(0.1));
  });

  testWidgets('the card says nothing unless asked, and only what it is '
      'asked', (t) async {
    final light = VerseLight.of([reel('Al-Mulk', 1, 5, DateTime(2026))]);
    Future<void> show({String name = '', bool numbers = false}) =>
        t.pumpWidget(MediaQuery(
          data: const MediaQueryData(),
          child: FittedBox(
            child: VersesCard(
                l: L10n.en, light: light, name: name, numbers: numbers),
          ),
        ));
    await show();
    expect(find.text('Yusuf'), findsNothing);
    expect(find.text(L10n.en.versesCardNumbers(5, 1)), findsNothing);
    await show(name: 'Yusuf', numbers: true);
    expect(find.text('Yusuf'), findsOneWidget);
    expect(find.text('5 verses · 1 surah'), findsOneWidget);
  });
}
