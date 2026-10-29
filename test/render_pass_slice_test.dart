import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/render_plan.dart';
import 'package:ayah_reels/render/scene_plan.dart';
import 'package:ayah_reels/render/video_renderer.dart';

/// What one pass of a long reel is built from: the cards it draws and
/// the sceneries it reads. The reel is joined back together frame for
/// frame afterwards, so a pass that drops a card at a boundary, or
/// reads a clip from the wrong place, is a fault that only shows up in
/// the finished file.
void main() {
  RenderPass pass(int from, int to) => RenderPass(
        startMs: from,
        endMs: to,
        fromFrame: (from * 30 / 1000).round(),
        frames: ((to - from) * 30 / 1000).round(),
      );

  group('the cards a pass draws', () {
    final cards = [
      (startMs: 0, endMs: 5000),
      (startMs: 5000, endMs: 11000),
      (startMs: 11000, endMs: 15000),
      (startMs: 15000, endMs: 20000),
    ];

    test('only the ones on screen, clipped to the pass', () {
      expect(VideoRenderer.passClips(cards, pass(5000, 15000)), [
        (startMs: 5000, endMs: 11000),
        (startMs: 11000, endMs: 15000),
      ]);
    });

    test('a card across a boundary is drawn by both passes, once each', () {
      final before = VideoRenderer.passClips(cards, pass(0, 8000));
      final after = VideoRenderer.passClips(cards, pass(8000, 20000));
      expect(before.last, (startMs: 5000, endMs: 8000));
      expect(after.first, (startMs: 8000, endMs: 11000));
      // Together the two halves are the card's whole window, with
      // nothing drawn twice.
      expect(before.last.endMs, after.first.startMs);
    });
  });

  group('the sceneries a pass reads', () {
    SceneCut cut(int i, int from, int to) => SceneCut(
        scene: i, startMs: from, endMs: to, firstAyah: i + 1, lastAyah: i + 1);

    final cuts = [
      cut(0, 0, 60000),
      cut(1, 60000, 120000),
      cut(2, 120000, 180000),
    ];

    test('a pass inside one scene reads that scene alone', () {
      final r = VideoRenderer.passScenes(
        scenes: const [
          (isImage: true, sourceMs: null),
          (isImage: true, sourceMs: null),
          (isImage: true, sourceMs: null),
        ],
        cuts: cuts,
        fadeMs: 0,
        pass: pass(70000, 100000),
      );
      expect(r.lengths, [30.0]);
      expect(r.cuts.single.scene, 0); // renumbered for this pass
      expect(r.cuts.single.startMs, 70000);
      expect(r.cuts.single.endMs, 100000);
    });

    test(
        'every scene but the pass\'s last plays the crossfade it hands '
        'over on', () {
      final r = VideoRenderer.passScenes(
        scenes: const [
          (isImage: true, sourceMs: null),
          (isImage: true, sourceMs: null),
          (isImage: true, sourceMs: null),
        ],
        cuts: cuts,
        fadeMs: 600,
        pass: pass(30000, 150000),
      );
      expect(r.lengths, [30.6, 60.6, 30.0]);
      expect(r.cuts.map((c) => c.startMs), [30000, 60000, 120000]);
      expect(r.cuts.map((c) => c.endMs), [60000, 120000, 150000]);
    });

    test('a clip that covers its turn is seeked into, not restarted', () {
      final r = VideoRenderer.passScenes(
        // 90 seconds of footage for a 60-second turn.
        scenes: const [
          (isImage: false, sourceMs: 90000),
          (isImage: false, sourceMs: 90000),
          (isImage: false, sourceMs: 90000),
        ],
        cuts: cuts,
        fadeMs: 0,
        pass: pass(90000, 150000),
      );
      expect(r.seeks, [30.0, 0.0]); // 30s into scene 1, scene 2 from its top
      expect(r.lengths, [30.0, 30.0]);
    });

    test('a short clip is read from its top: the boundary is a loop point', () {
      final r = VideoRenderer.passScenes(
        // 15 seconds of footage looped through a 60-second turn; the
        // pass opens six laps in.
        scenes: const [
          (isImage: false, sourceMs: 15000),
          (isImage: false, sourceMs: 15000),
          (isImage: false, sourceMs: 15000),
        ],
        cuts: cuts,
        fadeMs: 0,
        pass: pass(90000, 150000),
      );
      expect(r.seeks, [0.0, 0.0]);
    });

    test('a still is never seeked into, however long the pass', () {
      final r = VideoRenderer.passScenes(
        scenes: const [(isImage: true, sourceMs: null)],
        cuts: [cut(0, 0, 3600000)],
        fadeMs: 0,
        pass: pass(1800000, 1890000),
      );
      expect(r.seeks, [0.0]);
      expect(r.lengths, [90.0]);
    });
  });
}
