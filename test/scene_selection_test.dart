import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/fatiha_data.dart';
import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/render/scene_plan.dart';
import 'package:ayah_reels/state/creation_state.dart';

/// Picking several sceneries has three rules the picker leans on and
/// never states: the run keeps the order it was tapped in, it never
/// grows past what the reel can hold, and it is never empty — a reel is
/// always made of something.
void main() {
  ReelBackground scene(String id) => ReelBackground.still(
        id: id,
        name: id,
        imageAsset: 'assets/backgrounds/$id.jpg',
        gradientArgb: const [0xFF000000, 0xFF111111],
      );

  setUp(() {
    // The singleton outlives a test; put it back to one scenery.
    creationState
      ..setMultiScene(false)
      ..selectBackground(backgrounds.first)
      ..setPacing(ScenePacing.perAyah)
      ..setTransition(SceneTransition.fade);
  });

  test('one scenery is a run of one, and every reel starts there', () {
    expect(creationState.scenes, hasLength(1));
    expect(creationState.hasMultipleScenes, isFalse);
    expect(creationState.background, backgrounds.first);
  });

  test('scenes join the run in the order they were tapped', () {
    creationState.setMultiScene(true);
    for (final id in ['a', 'b', 'c']) {
      expect(creationState.toggleScene(scene(id), limit: 7), isTrue);
    }
    expect(
      creationState.scenes.map((s) => s.id).toList(),
      [backgrounds.first.id, 'a', 'b', 'c'],
    );
    expect(creationState.hasMultipleScenes, isTrue);
    // The reel still opens on the first one, which is what everything
    // that only ever wanted one picture reads.
    expect(creationState.background!.id, backgrounds.first.id);
  });

  test('tapping a scene already in the run takes it out', () {
    creationState.setMultiScene(true);
    creationState.toggleScene(scene('a'), limit: 7);
    creationState.toggleScene(scene('b'), limit: 7);
    creationState.toggleScene(scene('a'), limit: 7);
    expect(
      creationState.scenes.map((s) => s.id).toList(),
      [backgrounds.first.id, 'b'],
    );
  });

  test('the last scene comes out too, and leaves nothing behind', () {
    // A tick the user cannot untick reads as a stuck app. So the run is
    // allowed to empty, and it is the picker's own button that waits
    // for a scenery instead.
    creationState.setMultiScene(true);
    final only = creationState.scenes.single;
    expect(creationState.toggleScene(only, limit: 7), isTrue);
    expect(creationState.scenes, isEmpty);
    expect(creationState.background, isNull);
    // And picking one puts the reel back together.
    expect(creationState.toggleScene(scene('a'), limit: 7), isTrue);
    expect(creationState.background!.id, 'a');
  });

  test('a reel takes one scene per verse and refuses the next', () {
    creationState.setMultiScene(true);
    // A three-verse reel: three scenes, and the fourth is turned away
    // rather than silently dropped or squeezed in.
    for (final id in ['a', 'b']) {
      expect(creationState.toggleScene(scene(id), limit: 3), isTrue);
    }
    expect(creationState.scenes, hasLength(3));
    expect(creationState.toggleScene(scene('c'), limit: 3), isFalse);
    expect(creationState.scenes, hasLength(3));
    // Refused, not swapped: what was picked is untouched.
    expect(creationState.scenes.last.id, 'b');
  });

  test('leaving multi-scene collapses to the scenery the reel opens on',
      () {
    creationState.setMultiScene(true);
    creationState.toggleScene(scene('a'), limit: 7);
    creationState.toggleScene(scene('b'), limit: 7);
    creationState.setMultiScene(false);
    expect(creationState.multiScene, isFalse);
    expect(creationState.scenes.map((s) => s.id).toList(),
        [backgrounds.first.id]);
    expect(creationState.hasMultipleScenes, isFalse);
  });

  test('picking one scenery outright replaces the whole run', () {
    creationState.setMultiScene(true);
    creationState.toggleScene(scene('a'), limit: 7);
    creationState.selectBackground(scene('z'));
    expect(creationState.scenes.map((s) => s.id).toList(), ['z']);
  });

  test('the limit follows the reel, and a scene per verse always fits',
      () {
    expect(ScenePlan.maxScenes(2, segMs: 20000), 8);
    expect(ScenePlan.maxScenes(7, segMs: 7000), 7);
    expect(ScenePlan.maxScenes(1, segMs: 2000), 1);
  });

  test('weights ride alongside the scenes they belong to', () {
    creationState.setMultiScene(true);
    creationState.toggleScene(scene('a'), limit: 7);
    creationState.toggleScene(scene('b'), limit: 7);
    expect(creationState.sceneWeights, [1, 1, 1]);
    creationState.setSceneWeight(1, 3);
    expect(creationState.sceneWeights, [1, 3, 1]);
    // Dropping a scene drops its weight with it, so the two lists can
    // never drift apart and hand scene 2 scene 1's share.
    creationState.toggleScene(scene('a'), limit: 7);
    expect(creationState.sceneWeights, [1, 1]);
    // Nudges only: nothing takes more than three shares.
    creationState.setSceneWeight(0, 99);
    expect(creationState.sceneWeights.first, 3);
  });

  test('pacing and blend are remembered across the wizard', () {
    creationState.setPacing(ScenePacing.even);
    creationState.setTransition(SceneTransition.cut);
    expect(creationState.pacing, ScenePacing.even);
    expect(creationState.transition, SceneTransition.cut);
  });

  test('a new reel starts on the defaults, not on the last reel', () {
    // Remembered across the wizard is one thing; remembered across
    // *reels* is another. This object lives as long as the app does, so
    // a single tap on Even used to make Even the opening state of every
    // reel after it — while the preview went on calling per-verse the
    // default, and the picker went on offering single-select over a run
    // of a dozen sceneries left behind by the reel before.
    creationState
      ..setMultiScene(true)
      ..toggleScene(scene('sky_a'), limit: 9)
      ..toggleScene(scene('sky_b'), limit: 9)
      ..setPacing(ScenePacing.even)
      ..setTransition(SceneTransition.cut);
    expect(creationState.hasMultipleScenes, isTrue);

    creationState.startNewReel();

    // What a new reel starts on: with Settings' default of one line at
    // a time and the scenery following the lines, per line.
    expect(creationState.pacing, ScenePacing.perLine);
    expect(creationState.transition, SceneTransition.fade);
    expect(creationState.multiScene, isFalse);
    // Collapsed, never emptied: the reel still opens on the scenery it
    // was opening on, and the wizard is never handed a null background.
    expect(creationState.scenes, hasLength(1));
    expect(creationState.background, isNotNull);
    expect(creationState.sceneWeights, [1]);
  });

  test('a new reel keeps what is a preference rather than a shape', () {
    // The verse's colour and size are chosen once and meant to stick;
    // wiping them on every reel would be a different bug in the other
    // direction.
    creationState
      ..setTextColor(0xFFEEC96B)
      ..setTextScale(1.4)
      ..setTextPreset(TextPreset.glow);
    creationState.startNewReel();
    expect(creationState.textArgb, 0xFFEEC96B);
    expect(creationState.textScale, 1.4);
    expect(creationState.textPreset, TextPreset.glow);
  });
}
