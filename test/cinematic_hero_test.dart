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

  test('a new picture every twelve hours, and every picture before any '
      'comes round again', () {
    final library =
        CinematicHero.library([for (var i = 0; i < 20; i++) scene('s$i')]);
    final seen = <String>{};
    var t = DateTime(2026, 3, 1, 8);
    for (var i = 0; i < 20; i++) {
      seen.add(CinematicHero.pickFor(t, library)!.id);
      t = t.add(const Duration(hours: 12));
    }
    expect(seen, hasLength(20));
    // Within a half-day it holds; across noon it turns.
    expect(CinematicHero.pickFor(DateTime(2026, 3, 1, 8), library),
        CinematicHero.pickFor(DateTime(2026, 3, 1, 11, 59), library));
    expect(CinematicHero.pickFor(DateTime(2026, 3, 1, 8), library),
        isNot(CinematicHero.pickFor(DateTime(2026, 3, 1, 12), library)));
    expect(CinematicHero.slotOf(DateTime(2026, 1, 1, 13)), 1);
    expect(CinematicHero.pickFor(DateTime.now(), const []), isNull);
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
}
