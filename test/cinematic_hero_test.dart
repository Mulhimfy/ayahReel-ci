import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/scene_catalog.dart';
import 'package:ayah_reels/widgets/cinematic_hero.dart';

/// The opening frame's pictures: which of the library it draws on, and
/// how it walks through them.
Scene scene(
  String id, {
  String tab = 'sky',
  bool wide = false,
  bool video = false,
  int top = 0xFF202020,
  bool bundled = false,
}) =>
    Scene(
      id: id,
      tab: tab,
      wide: wide,
      isVideo: video,
      ext: video ? 'mp4' : 'jpg',
      bytes: 1,
      gradientArgb: [top, 0xFF000000],
      bundled: bundled,
    );

void main() {
  test('the library is every upright still of a place, dark enough at the '
      'top, in one fixed order', () {
    final all = [
      scene('a_sky'),
      scene('b_mountains', tab: 'mountains'),
      scene('c_abstract', tab: 'abstract'),
      scene('d_wide', tab: 'cinematic', wide: true),
      scene('e_video', video: true),
      scene('f_bright', top: 0xFFF0F0F0),
      scene('g_forest', tab: 'forest'),
    ];
    final library = CinematicHero.library(all);
    expect(library.map((s) => s.id).toSet(),
        {'a_sky', 'b_mountains', 'g_forest'});
    // The order does not depend on the order it was handed.
    expect(CinematicHero.library(all.reversed).map((s) => s.id).toList(),
        library.map((s) => s.id).toList());
  });

  test('every visit walks on to the next picture, every one in the '
      'library before any comes round again', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('walk');
    addTearDown(() => dir.deleteSync(recursive: true));
    SceneCatalog.configureForTest(baseUrl: '', cacheDir: dir);
    final library = CinematicHero.library(
        [for (var i = 0; i < 20; i++) scene('s$i', bundled: true)]);
    final seen = <String>{};
    var turn = 7;
    for (var i = 0; i < 20; i++) {
      final f = (await CinematicHero.onPhoneFrom(turn, library))!;
      seen.add((f.picture as AssetImage).assetName);
      turn = f.at + 1;
    }
    expect(seen, hasLength(20));
    expect(await CinematicHero.onPhoneFrom(0, const []), isNull);
    expect(CinematicHero.slotOf(DateTime(2026, 1, 1, 13)), 1);
  });

  test('the bundled shelf turns every twelve hours too, and never on one '
      'picture', () {
    final seen = <String>{};
    var t = DateTime(2026, 5, 1, 9);
    for (var i = 0; i < 12; i++) {
      seen.add(CinematicHero.sceneFor(t));
      t = t.add(const Duration(hours: 12));
    }
    expect(seen.length, CinematicHero.daytimeScenes.length +
        CinematicHero.nightScenes.length);
  });

  test('the real catalog gives the frame a couple of hundred pictures, '
      'the bundled shelves among them', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await SceneCatalog.load();
    final all = [
      for (final t in SceneCatalog.tabOrder) ...SceneCatalog.inTab(t),
    ];
    final library = CinematicHero.library(all);
    expect(library.length, greaterThan(150));
    expect(library.every((s) => !s.wide && !s.isVideo), isTrue);
    expect(library.every((s) => CinematicHero.heroTabs.contains(s.tab)),
        isTrue);
    for (final asset in [
      ...CinematicHero.daytimeScenes,
      ...CinematicHero.nightScenes,
    ]) {
      expect(library.any((s) => s.bundledAsset == asset), isTrue,
          reason: asset);
    }
  });

  test('a picture not on the phone yet is passed over for the next one '
      'that is, and the walk goes on from there', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final dir = Directory.systemTemp.createTempSync('hero');
    addTearDown(() => dir.deleteSync(recursive: true));
    SceneCatalog.configureForTest(baseUrl: '', cacheDir: dir);
    final library = [
      scene('a'),
      scene('b'),
      scene('c'),
      scene('d', bundled: true),
      scene('e'),
    ];
    // 'c' was fetched on an earlier visit.
    File('${dir.path}/c.jpg').writeAsBytesSync(List.filled(2048, 1));

    // Turn 0 is 'a', not on the phone: the walk finds 'c', at once.
    final first = (await CinematicHero.onPhoneFrom(0, library))!;
    expect(first.at, 2);
    expect((first.picture as FileImage).file.path, endsWith('c.jpg'));
    // The next visit goes on after it: 'd'.
    final second = (await CinematicHero.onPhoneFrom(first.at + 1, library))!;
    expect(second.at, 3);
    expect((second.picture as AssetImage).assetName,
        'assets/backgrounds/d.jpg');
    // And round again, past 'e' and 'a', 'b', which never came down.
    final third = (await CinematicHero.onPhoneFrom(second.at + 1, library))!;
    expect(third.at, 2);

    // Nothing on the phone at all: nothing to offer.
    expect(
        await CinematicHero.onPhoneFrom(0, [scene('x'), scene('y')]), isNull);
  });
}
