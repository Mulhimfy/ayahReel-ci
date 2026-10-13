import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/scene_catalog.dart';

/// Three tabs open on their best sceneries rather than on whatever the
/// catalogue happened to list first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every leader is a live scenery of its own tab and shape, and the '
      'tab opens on them in order', () async {
    await SceneCatalog.load();
    for (final entry in SceneCatalog.leaders.entries) {
      final tab = entry.key;
      final scenes = SceneCatalog.inTab(tab);
      expect(scenes, isNotEmpty, reason: tab);
      final wide = scenes.first.wide;
      for (final id in entry.value) {
        final s = SceneCatalog.byId(id);
        expect(s, isNotNull, reason: '$id is not in the catalogue');
        expect(s!.tab, tab, reason: '$id is filed under ${s.tab}');
        expect(s.wide, wide, reason: '$id is the wrong shape for $tab');
      }
      expect(entry.value.toSet(), hasLength(entry.value.length),
          reason: 'a leader is listed twice in $tab');
      final live = [
        for (final id in entry.value)
          if (SceneCatalog.byId(id) != null) id,
      ];
      expect(scenes.take(live.length).map((s) => s.id).toList(), live);
      // Nothing is lost on the way: the tab still holds every scenery.
      expect(scenes.map((s) => s.id).toSet(), hasLength(scenes.length));
    }
  });
}
