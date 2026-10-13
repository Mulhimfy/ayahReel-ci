import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/render/letterbox_layout.dart';
import 'package:ayah_reels/render/scene_plan.dart';
import 'package:ayah_reels/render/video_renderer.dart';
import 'package:ayah_reels/state/creation_state.dart';

/// The filter graph that joins a reel's sceneries is only ever proved
/// by an encode on a device, and by then a wrong offset is a reel that
/// cuts in the wrong place. These pin the arithmetic instead: every
/// label defined once and consumed once, every trim the length of its
/// own cut, every crossfade offset the cut time itself.
void main() {
  const rec = Recitation(
    reciterId: 'r',
    surah: 1,
    audioPath: 'x',
    timings: [
      AyahTiming(1, 0, 6000),
      AyahTiming(2, 6000, 11000),
      AyahTiming(3, 11000, 15000),
    ],
  );

  final cuts = ScenePlan.of(
    sceneCount: 3,
    recitation: rec,
    startAyah: 1,
    endAyah: 3,
  );

  /// Lengths the renderer reads from each scenery: its own cut, plus
  /// the blend it hands over on.
  List<double> lengths(int fadeMs) => [
        for (var i = 0; i < cuts.length; i++)
          (cuts[i].durationMs + (i == cuts.length - 1 ? 0 : fadeMs)) / 1000,
      ];

  String graph({required int fadeMs, int? scrimIdx = 9}) =>
      VideoRenderer.sceneRunGraph(
        lengths: lengths(fadeMs),
        cuts: cuts,
        fadeMs: fadeMs,
        segStartMs: 0,
        scrimIdx: scrimIdx,
      );

  /// Every `[label]` the graph writes to, in order.
  List<String> defined(String g) =>
      RegExp(r'\][a-z0-9]+\];|\[([a-z][a-z0-9]*)\];')
          .allMatches(g)
          .map((m) => m.group(0)!)
          .toList();

  test('a straight cut concatenates every scene in order', () {
    final g = graph(fadeMs: 0);
    expect(g, contains('[b0][b1][b2]concat=n=3:v=1:a=0[joined];'));
    expect(g, isNot(contains('xfade')));
    // One trim per scene, each the length of its own cut.
    expect(g, contains('trim=duration=6.000'));
    expect(g, contains('trim=duration=5.000'));
    expect(g, contains('trim=duration=4.000'));
  });

  test('a blend crossfades at the cut times, and only there', () {
    final g = graph(fadeMs: 500);
    // Offsets are the boundaries themselves: 6s and 11s.
    expect(g, contains('[b0][b1]xfade=transition=fade:duration=0.500:'
        'offset=6.000[xf1];'));
    expect(g, contains('[xf1][b2]xfade=transition=fade:duration=0.500:'
        'offset=11.000[joined];'));
    // Every scene but the last is read half a second longer than its
    // cut — that overlap is what the blend is played out of.
    expect(g, contains('trim=duration=6.500'));
    expect(g, contains('trim=duration=5.500'));
    expect(g, contains('trim=duration=4.000'));
  });

  test('two scenes blend straight into the joined label', () {
    final two = ScenePlan.of(
      sceneCount: 2,
      recitation: rec,
      startAyah: 1,
      endAyah: 3,
    );
    final g = VideoRenderer.sceneRunGraph(
      lengths: [(two[0].durationMs + 500) / 1000, two[1].durationMs / 1000],
      cuts: two,
      fadeMs: 500,
      segStartMs: 0,
      scrimIdx: 9,
    );
    expect(g, contains('[b0][b1]xfade='));
    expect(g, contains('[joined];'));
    expect(g, isNot(contains('xf1')));
  });

  test('the scrim goes on once, after the join', () {
    expect(graph(fadeMs: 500), endsWith('[joined][9:v]overlay=0:0[v0];'));
    // Letterbox has no scrim: the verse sits on the band, not the
    // picture, so the run ends straight at the base label.
    expect(graph(fadeMs: 500, scrimIdx: null), endsWith('[joined]null[v0];'));
  });

  test('a plan whose cuts start mid-recording offsets from the segment',
      () {
    final middle = ScenePlan.of(
      sceneCount: 2,
      recitation: rec,
      startAyah: 2,
      endAyah: 3,
    );
    final g = VideoRenderer.sceneRunGraph(
      lengths: [(middle[0].durationMs + 400) / 1000,
          middle[1].durationMs / 1000],
      cuts: middle,
      fadeMs: 400,
      // The reel starts 6s into the recording, so its first cut is at
      // zero — an offset measured from the recording would be 5s late.
      segStartMs: 6000,
      scrimIdx: 9,
    );
    expect(g, contains('offset=5.000'));
  });

  test('each letterbox scene builds its own card, on its own labels', () {
    final g = VideoRenderer.sceneRunGraph(
      lengths: lengths(0),
      cuts: cuts,
      fadeMs: 0,
      segStartMs: 0,
      letterbox: LetterboxGeometry.of(16 / 9),
      colourBackdrop: true,
      maskIdx: 7,
      scrimIdx: null,
    );
    // One mask, split as many ways as there are cards: a filter input
    // can only be consumed once.
    expect(g, contains('[7:v]split=3[m0][m1][m2];'));
    for (var i = 0; i < 3; i++) {
      expect(g, contains('[m$i]format=gray[cardmasks$i];'));
      expect(g, contains('[bgbases$i][cards$i]overlay='));
    }
    // No label is written twice — the whole reason the scenes carry a
    // tag of their own.
    final labels = defined(g);
    expect(labels.toSet(), hasLength(labels.length));
  });

  test('a blurred backdrop splits each scene, not the reel', () {
    final g = VideoRenderer.sceneRunGraph(
      lengths: lengths(0),
      cuts: cuts,
      fadeMs: 0,
      segStartMs: 0,
      letterbox: LetterboxGeometry.of(16 / 9),
      colourBackdrop: false,
      scrimIdx: null,
    );
    for (var i = 0; i < 3; i++) {
      expect(g, contains('[$i:v]split=2[bgsrcs$i][cardsrcs$i];'));
    }
    expect(g, isNot(contains('color=c=')));
  });

  test('the fade a plan can afford never outruns its shortest scene', () {
    // Cuts of 6s, 5s and 4s: half of the shortest still clears the
    // 500ms default, so the default stands.
    expect(ScenePlan.fadeMsFor(cuts, SceneTransition.fade), sceneFadeMs);
    expect(ScenePlan.fadeMsFor(cuts, SceneTransition.cut), 0);
    const tight = [
      SceneCut(scene: 0, startMs: 0, endMs: 600, firstAyah: 1, lastAyah: 1),
      SceneCut(scene: 1, startMs: 600, endMs: 1400, firstAyah: 2, lastAyah: 2),
    ];
    // Half of a 600ms scene, not the 500ms a longer reel would take.
    expect(ScenePlan.fadeMsFor(tight, SceneTransition.fade), 300);
    const strobe = [
      SceneCut(scene: 0, startMs: 0, endMs: 200, firstAyah: 1, lastAyah: 1),
      SceneCut(scene: 1, startMs: 200, endMs: 900, firstAyah: 2, lastAyah: 2),
    ];
    // Too short to read as a blend at all — it becomes the cut it
    // already looked like.
    expect(ScenePlan.fadeMsFor(strobe, SceneTransition.fade), 0);
  });
}
