import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/render/scene_plan.dart';
import 'package:ayah_reels/state/creation_state.dart';

/// The scene timeline is computed once and read by three things that
/// must agree to the millisecond: the live preview, the exporter's
/// filter graph, and the ribbon that draws it. So the plan is pinned
/// here rather than trusted to look right on a phone.
void main() {
  // Uneven on purpose: equal ayahs would hide every rounding bug.
  const rec = Recitation(
    reciterId: 'r',
    surah: 1,
    audioPath: 'x',
    timings: [
      AyahTiming(1, 0, 6000),
      AyahTiming(2, 6000, 11000),
      AyahTiming(3, 11000, 15000),
      AyahTiming(4, 15000, 22000),
      AyahTiming(5, 22000, 26000),
      AyahTiming(6, 26000, 33000),
      AyahTiming(7, 33000, 46000),
    ],
  );

  List<SceneCut> plan(
    int scenes, {
    ScenePacing pacing = ScenePacing.perAyah,
    List<int> weights = const [],
  }) =>
      ScenePlan.of(
        sceneCount: scenes,
        recitation: rec,
        startAyah: 1,
        endAyah: 7,
        pacing: pacing,
        weights: weights,
      );

  /// Whatever the pacing, a plan tiles its segment exactly: no gap, no
  /// overlap, no scene of zero length.
  void expectGapless(List<SceneCut> cuts, {int from = 0, int to = 46000}) {
    expect(cuts.first.startMs, from);
    expect(cuts.last.endMs, to);
    for (var i = 0; i < cuts.length; i++) {
      expect(cuts[i].scene, i);
      expect(cuts[i].durationMs, greaterThan(0), reason: 'cut $i is empty');
      if (i > 0) expect(cuts[i].startMs, cuts[i - 1].endMs);
    }
  }

  test('a scene per ayah lands one scene on each verse', () {
    final cuts = plan(7);
    expect(cuts, hasLength(7));
    expectGapless(cuts);
    for (var i = 0; i < 7; i++) {
      expect(cuts[i].firstAyah, i + 1);
      expect(cuts[i].lastAyah, i + 1);
      expect(cuts[i].startMs, rec.timing(i + 1).startMs);
      expect(cuts[i].endMs, rec.timing(i + 1).endMs);
    }
  });

  test('fewer scenes than verses deal the remainder to the front', () {
    // 7 verses over 3 scenes: 3, 2, 2 — never 3, 3, 1.
    final cuts = plan(3);
    expect(cuts.map((c) => c.lastAyah - c.firstAyah + 1).toList(), [3, 2, 2]);
    expect(cuts.map((c) => c.firstAyah).toList(), [1, 4, 6]);
    expectGapless(cuts);
    // Every boundary is an ayah boundary — the point of this pacing.
    for (final c in cuts) {
      expect(c.startMs, rec.timing(c.firstAyah).startMs);
      expect(c.endMs, rec.timing(c.lastAyah).endMs);
    }
  });

  test('one scene covers the whole reel', () {
    final cuts = plan(1);
    expect(cuts, hasLength(1));
    expect(cuts.single.firstAyah, 1);
    expect(cuts.single.lastAyah, 7);
    expectGapless(cuts);
  });

  test('even pacing slices the clock, not the verses', () {
    final cuts = plan(4, pacing: ScenePacing.even);
    expect(cuts, hasLength(4));
    expectGapless(cuts);
    expect(cuts.map((c) => c.startMs).toList(), [0, 11500, 23000, 34500]);
    // Slices are equal to the millisecond, last one included: rounding
    // is absorbed by walking boundaries, not by the final scene.
    for (final c in cuts) {
      expect(c.durationMs, 11500);
    }
  });

  test('even pacing over a span that does not divide stays gapless', () {
    // 46000 / 3 recurs; the plan still tiles the segment exactly.
    final cuts = plan(3, pacing: ScenePacing.even);
    expectGapless(cuts);
    expect(cuts.map((c) => c.durationMs).reduce((a, b) => a + b), 46000);
  });

  test('a plan of a middle range starts and ends on that range', () {
    final cuts = ScenePlan.of(
      sceneCount: 2,
      recitation: rec,
      startAyah: 3,
      endAyah: 6,
    );
    expectGapless(cuts, from: 11000, to: 33000);
    expect(cuts.map((c) => c.firstAyah).toList(), [3, 5]);
    expect(cuts.map((c) => c.lastAyah).toList(), [4, 6]);
  });

  test('the cap is the reel\'s own length, not its verse count', () {
    // A two-verse reel can still run twenty seconds, and two pictures
    // over twenty seconds is not a choice.
    expect(ScenePlan.maxScenes(2, segMs: 20000), 8);
    expect(ScenePlan.maxScenes(7, segMs: 46000), 18);
    // A scene per verse is always within reach, however brisk the
    // verses — it is the app's own default.
    expect(ScenePlan.maxScenes(7, segMs: 7000), 7);
    // A long reel takes as many as its own length allows, well past
    // the thirty this used to stop at.
    expect(ScenePlan.maxScenes(30, segMs: 90000), 36);
    expect(ScenePlan.maxScenes(60, segMs: 10 * 60 * 1000), 100);
    // And nothing takes more than the ceiling, however long it runs.
    expect(ScenePlan.maxScenes(300, segMs: 60 * 60 * 1000),
        ScenePlan.sceneCeiling);
    // Unmeasured — the picker before the audio lands — estimates off
    // the verse count rather than refusing to say.
    expect(ScenePlan.maxScenes(7), 16);
    expect(ScenePlan.recommended(7), 7);
  });

  test('past the cap the plan takes what it can hold', () {
    final cuts = plan(999);
    expect(cuts, hasLength(ScenePlan.maxScenes(7, segMs: 46000)));
    expectGapless(cuts);
  });

  test('more scenes than verses queue up inside a verse', () {
    // Two apiece: every ayah boundary is still a cut, with one more in
    // the middle of each verse.
    final cuts = plan(14);
    expect(cuts, hasLength(14));
    expectGapless(cuts);
    expect(cuts[0].firstAyah, 1);
    expect(cuts[1].firstAyah, 1);
    expect(cuts[0].startMs, 0);
    expect(cuts[0].endMs, 3000); // half of the 6s first verse
    expect(cuts[1].endMs, 6000); // and the verse's own end
    expect(cuts[2].startMs, 6000);
    for (final c in cuts) {
      expect(c.firstAyah, c.lastAyah, reason: 'a slice is inside one verse');
    }
  });

  test('spare scenes go to the verses at the front', () {
    // 10 scenes over 7 verses: one each, and the three left over open
    // the passage.
    final cuts = plan(10);
    expect(cuts, hasLength(10));
    expectGapless(cuts);
    final perAyah = <int, int>{};
    for (final c in cuts) {
      perAyah[c.firstAyah] = (perAyah[c.firstAyah] ?? 0) + 1;
    }
    expect(perAyah, {1: 2, 2: 2, 3: 2, 4: 1, 5: 1, 6: 1, 7: 1});
  });

  test('a heavier scene takes more verses', () {
    // 7 verses over 2 scenes, the first weighted three to one.
    final cuts = plan(2, weights: [3, 1]);
    expect(cuts.map((c) => c.lastAyah - c.firstAyah + 1).toList(), [5, 2]);
    expectGapless(cuts);
    // Still on ayah boundaries: weight changes the share, never the
    // kind of place a cut can fall.
    expect(cuts[1].startMs, rec.timing(6).startMs);
  });

  test('no scene is ever weighted out of existence', () {
    // Three scenes, one of them heavy, over four verses: the light
    // ones still get a verse each rather than none.
    final cuts = plan(3, weights: [9, 1, 1]);
    expect(cuts, hasLength(3));
    for (final c in cuts) {
      expect(c.lastAyah - c.firstAyah + 1, greaterThanOrEqualTo(1));
    }
    expectGapless(cuts);
  });

  test('weights split the clock under even pacing', () {
    final cuts = plan(2, pacing: ScenePacing.even, weights: [3, 1]);
    expect(cuts[0].durationMs, 34500); // three quarters of 46s
    expect(cuts[1].durationMs, 11500);
    expectGapless(cuts);
  });

  test('weights split a verse when the scenes are inside one', () {
    final cuts = ScenePlan.of(
      sceneCount: 2,
      recitation: rec,
      startAyah: 1,
      endAyah: 1,
      weights: [3, 1],
    );
    // The 6-second first verse, three quarters to one.
    expect(cuts.map((c) => c.durationMs).toList(), [4500, 1500]);
    expectGapless(cuts, from: 0, to: 6000);
  });

  group('cutAt: the reel ended early', () {
    test('drops the scenes past the cut and ends the one it lands in', () {
      final cuts = ScenePlan.cutAt(plan(7), 17000);
      // Verses 1-3 run to 15000; the cut falls inside verse 4's scene.
      expect(cuts, hasLength(4));
      expectGapless(cuts, to: 17000);
      expect(cuts.last.durationMs, 2000);
      expect(cuts.last.firstAyah, 4);
    });

    test('a cut on a boundary keeps the scene that ends there', () {
      final cuts = ScenePlan.cutAt(plan(7), 15000);
      expect(cuts, hasLength(3));
      expectGapless(cuts, to: 15000);
    });

    test('a cut at or past the end is the whole plan, untouched', () {
      final whole = plan(7);
      expect(ScenePlan.cutAt(whole, 46000), same(whole));
      expect(ScenePlan.cutAt(whole, 99000), same(whole));
    });

    test('one scenery is always left, however short the cut', () {
      final cuts = ScenePlan.cutAt(plan(7), 0);
      expect(cuts, hasLength(1));
      expect(cuts.single.startMs, 0);
      expect(cuts.single.durationMs, greaterThan(0));
    });
  });

  group('a scene per line', () {
    // Verse 4 (15–22 s) cut into three lines, verse 7 (33–46 s) into two.
    VersePart part(int ayah, int i, int n, int t0, int t1) => VersePart(
          ayah: ayah,
          index: i,
          count: n,
          tokenStart: i,
          tokenEnd: i + 1,
          startMs: t0,
          endMs: t1,
          arabic: 'x',
          translation: '',
          fit: 1,
        );
    final lines = VerseLinePlan(2, {
      4: [
        part(4, 0, 3, 15000, 17500),
        part(4, 1, 3, 17500, 19800),
        part(4, 2, 3, 19800, 22000),
      ],
      7: [part(7, 0, 2, 33000, 39000), part(7, 1, 2, 39000, 46000)],
    });
    final units = VerseUnit.of(rec, 1, 7, lines);

    test('lands a scene on every line', () {
      final cuts = ScenePlan.of(
        sceneCount: units.length,
        recitation: rec,
        startAyah: 1,
        endAyah: 7,
        pacing: ScenePacing.perLine,
        units: units,
      );
      expect(cuts, hasLength(10));
      expectGapless(cuts);
      for (var i = 0; i < cuts.length; i++) {
        expect(cuts[i].startMs, units[i].startMs);
        expect(cuts[i].endMs, units[i].endMs);
        expect(cuts[i].firstAyah, units[i].ayah);
      }
    });

    test('fewer scenes than lines deal the lines out', () {
      final cuts = ScenePlan.of(
        sceneCount: 4,
        recitation: rec,
        startAyah: 1,
        endAyah: 7,
        pacing: ScenePacing.perLine,
        units: units,
      );
      expect(cuts, hasLength(4));
      expectGapless(cuts);
      // Every cut on a line's edge.
      final edges = {for (final u in units) u.startMs};
      for (final c in cuts) {
        expect(edges.contains(c.startMs), isTrue);
      }
    });

    test('without lines it is the scene per verse it always was', () {
      expect(
        ScenePlan.of(
          sceneCount: 7,
          recitation: rec,
          startAyah: 1,
          endAyah: 7,
          pacing: ScenePacing.perLine,
        ),
        plan(7),
      );
      // And per verse ignores the lines.
      expect(
        ScenePlan.of(
          sceneCount: 7,
          recitation: rec,
          startAyah: 1,
          endAyah: 7,
          units: units,
        ),
        plan(7),
      );
    });

    test('a reel can hold a scene for every line', () {
      expect(ScenePlan.maxScenes(units.length, segMs: 46000),
          greaterThanOrEqualTo(10));
    });
  });

  test('indexAt finds the scene playing at a moment', () {
    final cuts = plan(3);
    expect(ScenePlan.indexAt(cuts, 0), 0);
    // A boundary millisecond belongs to the scene starting on it.
    expect(ScenePlan.indexAt(cuts, cuts[0].endMs - 1), 0);
    expect(ScenePlan.indexAt(cuts, cuts[0].endMs), 1);
    expect(ScenePlan.indexAt(cuts, cuts[2].startMs), 2);
    // Past the end — a player reporting a position beyond the segment
    // still gets the last scene rather than an index out of range.
    expect(ScenePlan.indexAt(cuts, 99000), 2);
  });

  group('a matched run stays on the verses it was matched for', () {
    List<SceneCut> anchored(
      List<SceneAnchor> anchors, {
      ScenePacing pacing = ScenePacing.perAyah,
      List<VerseUnit>? units,
      int start = 1,
      int end = 7,
    }) =>
        ScenePlan.of(
          sceneCount: anchors.length,
          recitation: rec,
          startAyah: start,
          endAyah: end,
          pacing: pacing,
          units: units,
          anchors: anchors,
        );

    test('a scenery that could not be had leaves its verse to the one '
        'before, and moves nothing else', () {
      // Matched a scenery per verse; verse 3's never arrived.
      final cuts = anchored([
        for (final a in [1, 2, 4, 5, 6, 7]) SceneAnchor(a),
      ]);
      expectGapless(cuts);
      expect([for (final c in cuts) (c.firstAyah, c.lastAyah)],
          [(1, 1), (2, 3), (4, 4), (5, 5), (6, 6), (7, 7)]);
      // Dealt out in order, the same six put verse 2's scenery on verse
      // 3, and verse 1's on verse 2: each a verse off its own.
      final dealt = plan(6);
      expect((dealt[1].firstAyah, dealt[1].lastAyah), (3, 3));
    });

    test('lines that come out other than estimated keep each scenery on '
        'its words', () {
      VersePart part(int ayah, int i, int n, int t0, int t1) => VersePart(
            ayah: ayah,
            index: i,
            count: n,
            tokenStart: i,
            tokenEnd: i + 1,
            startMs: t0,
            endMs: t1,
            arabic: 'x',
            translation: '',
            fit: 1,
          );
      // Verse 4 in three lines and verse 7 in two, where the estimate
      // the sceneries were matched on had verse 4 in two (tokens 0 and
      // 2) and verse 7 in three (tokens 0, 1, 2).
      final units = VerseUnit.of(
          rec,
          1,
          7,
          VerseLinePlan(2, {
            4: [
              part(4, 0, 3, 15000, 17500),
              part(4, 1, 3, 17500, 19800),
              part(4, 2, 3, 19800, 22000),
            ],
            7: [part(7, 0, 2, 33000, 39000), part(7, 1, 2, 39000, 46000)],
          }));
      final cuts = anchored(
        const [
          SceneAnchor(1),
          SceneAnchor(2),
          SceneAnchor(3),
          SceneAnchor(4),
          SceneAnchor(4, 2),
          SceneAnchor(5),
          SceneAnchor(6),
          SceneAnchor(7),
          SceneAnchor(7, 1),
          SceneAnchor(7, 2),
        ],
        pacing: ScenePacing.perLine,
        units: units,
      );
      expectGapless(cuts);
      expect([for (final c in cuts) (c.startMs, c.endMs)], [
        (0, 6000),
        (6000, 11000),
        (11000, 15000),
        // Its first two lines: the third has a scenery of its own.
        (15000, 19800),
        (19800, 22000),
        (22000, 26000),
        (26000, 33000),
        (33000, 39000),
        // Two sceneries for one line now: it is shared.
        (39000, 42500),
        (42500, 46000),
      ]);
    });

    test('the basmala\'s card opens on the first scenery', () {
      const units = [
        VerseUnit(0, null, 0, 3000),
        VerseUnit(1, null, 3000, 6000),
        VerseUnit(2, null, 6000, 11000),
      ];
      final cuts = anchored(
        const [SceneAnchor(1), SceneAnchor(2)],
        pacing: ScenePacing.perLine,
        units: units,
        end: 2,
      );
      expect([for (final c in cuts) (c.startMs, c.endMs, c.lastAyah)],
          [(0, 6000, 1), (6000, 11000, 2)]);
    });

    test('anchors for other verses, or out of order, are not used', () {
      final dealt = plan(3);
      for (final bad in [
        const [SceneAnchor(1), SceneAnchor(4), SceneAnchor(9)],
        const [SceneAnchor(4), SceneAnchor(2), SceneAnchor(6)],
        const [SceneAnchor(1), SceneAnchor(1), SceneAnchor(6)],
      ]) {
        expect(anchored(bad), dealt, reason: '$bad');
      }
    });

    test('an even pace is even slices, anchored or not', () {
      expect(
          anchored([for (var a = 1; a <= 7; a++) SceneAnchor(a)],
              pacing: ScenePacing.even),
          plan(7, pacing: ScenePacing.even));
    });
  });
}
