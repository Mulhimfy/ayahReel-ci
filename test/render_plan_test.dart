import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/render_plan.dart';

/// A long reel is encoded in passes and the passes are joined with a
/// stream copy, so the plan has to be exact in two ways at once: the
/// passes must tile the reel to the frame — a frame lost at a seam
/// slides every verse after it off the voice — and a boundary must
/// never fall where the picture would jump across it.
void main() {
  /// Overlay windows, one per `every` ms, tiling `[from, to)`.
  List<({int startMs, int endMs})> cards(int from, int to, int every) => [
        for (var t = from; t < to; t += every)
          (startMs: t, endMs: t + every > to ? to : t + every),
      ];

  void expectTiles(List<RenderPass> passes, int from, int to) {
    expect(passes, isNotEmpty);
    expect(passes.first.startMs, from);
    expect(passes.last.endMs, to);
    var frame = 0;
    for (var i = 0; i < passes.length; i++) {
      expect(passes[i].fromFrame, frame, reason: 'pass $i starts mid-frame');
      expect(passes[i].frames, greaterThan(0));
      frame += passes[i].frames;
      if (i > 0) {
        expect(passes[i].startMs, passes[i - 1].endMs,
            reason: 'gap or overlap before pass $i');
      }
    }
    // Every frame of the reel is drawn exactly once.
    expect(frame, ((to - from) * RenderPlan.fps / 1000).round());
  }

  group('short reels take the single pass they always took', () {
    test('a 90-second reel is one pass', () {
      final passes = RenderPlan.of(
        segStartMs: 12000,
        segEndMs: 102000,
        spans: const [
          PictureSpan(startMs: 12000, endMs: 102000, sourceMs: 8000)
        ],
        clips: cards(12000, 102000, 3000),
      );
      expect(passes.length, 1);
      expect(passes.single.frames, 2700);
      expectTiles(passes, 12000, 102000);
    });

    test('a busy 90-second reel — word highlighting on — is still one pass',
        () {
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: 90000,
        spans: const [PictureSpan(startMs: 0, endMs: 90000, isImage: true)],
        clips: cards(0, 90000, 750), // 120 windows, the highlight cap
      );
      expect(passes.length, 1);
    });
  });

  group('long reels are cut into passes', () {
    test('an hour on a still tiles the reel to the frame', () {
      const hour = 3600000;
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: hour,
        spans: const [PictureSpan(startMs: 0, endMs: hour, isImage: true)],
        clips: cards(0, hour, 6000),
      );
      expect(passes.length, greaterThan(20));
      expectTiles(passes, 0, hour);
      for (final p in passes) {
        expect(p.durationMs, lessThanOrEqualTo(RenderPlan.passTargetMs));
      }
    });

    test('no pass holds more cards than it can decode at once', () {
      const long = 1800000;
      final clips = cards(0, long, 1200); // 1500 windows
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: long,
        spans: const [PictureSpan(startMs: 0, endMs: long, isImage: true)],
        clips: clips,
      );
      expectTiles(passes, 0, long);
      for (final p in passes) {
        final held = clips
            .where((c) => c.endMs > p.startMs && c.startMs < p.endMs)
            .length;
        // One card can straddle the boundary and be drawn by both.
        expect(held, lessThanOrEqualTo(RenderPlan.clipsPerPass + 1));
      }
    });

    test('a phone that ran out of memory gets the reel in smaller pieces',
        () {
      // The retry's budget, on a reel the ordinary budget takes in one
      // pass: the same reel, cut into pieces each holding a third of
      // the cards, and still tiling the reel to the frame.
      const busy = 90000;
      final clips = cards(0, busy, 750); // 120 windows, one pass normally
      const spans = [PictureSpan(startMs: 0, endMs: busy, isImage: true)];
      final one = RenderPlan.of(
          segStartMs: 0, segEndMs: busy, spans: spans, clips: clips);
      expect(one.length, 1);

      final tight = RenderPlan.of(
        segStartMs: 0,
        segEndMs: busy,
        spans: spans,
        clips: clips,
        maxClips: RenderPlan.clipsPerPassLowMemory,
      );
      expect(tight.length, greaterThan(1));
      expectTiles(tight, 0, busy);
      for (final p in tight) {
        final held = clips
            .where((c) => c.endMs > p.startMs && c.startMs < p.endMs)
            .length;
        // One card can straddle the boundary and be drawn by both.
        expect(held, lessThanOrEqualTo(RenderPlan.clipsPerPassLowMemory + 1));
      }
    });

    test('the tight budget outranks the cut a jumpy picture would forbid',
        () {
      // A clip that loops every 14s leaves boundaries only at its loop
      // points; the ordinary plan lets a pass run long rather than
      // jump. Under the retry's budget it must cut anyway — a scenery
      // that restarts beats an encode that dies.
      const long = 300000;
      final clips = cards(0, long, 500); // 600 windows
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: long,
        // No source length: nowhere in the clip is a cut safe.
        spans: const [PictureSpan(startMs: 0, endMs: long)],
        clips: clips,
        maxClips: RenderPlan.clipsPerPassLowMemory,
      );
      expect(passes.length, greaterThan(1));
      expectTiles(passes, 0, long);
      for (final p in passes) {
        final held = clips
            .where((c) => c.endMs > p.startMs && c.startMs < p.endMs)
            .length;
        expect(held, lessThanOrEqualTo(RenderPlan.clipsPerPassLowMemory + 1));
      }
    });

    test('a looping clip is only ever cut where a loop starts', () {
      const long = 1200000;
      const loop = 14000;
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: long,
        spans: const [PictureSpan(startMs: 0, endMs: long, sourceMs: loop)],
        clips: cards(0, long, 6000),
      );
      expect(passes.length, greaterThan(5));
      expectTiles(passes, 0, long);
      for (final p in passes.skip(1)) {
        final phase = p.startMs % loop;
        // Snapped to a frame, so up to half a frame either side of the
        // loop point.
        expect(phase <= 17 || phase >= loop - 17, isTrue,
            reason: '${p.startMs} is ${phase}ms into a lap of the clip');
      }
    });

    test('a tight budget cuts a looping clip mid-lap only where it can '
        'be seeked into', () {
      // Cards every half second and sixteen to a pass: eight seconds a
      // pass, against a clip that loops every fourteen. No pass can
      // reach a loop point, so some must open part-way through a lap —
      // and each of those has to be over before that lap is, because it
      // reads the clip by seeking, not by looping it.
      const long = 120000;
      const loop = 14000;
      final clips = cards(0, long, 500);
      const span = PictureSpan(startMs: 0, endMs: long, sourceMs: loop);
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: long,
        spans: const [span],
        clips: clips,
        maxClips: RenderPlan.clipsPerPassLowMemory,
      );
      expectTiles(passes, 0, long);
      var midLap = 0;
      for (final p in passes) {
        final held = clips
            .where((c) => c.endMs > p.startMs && c.startMs < p.endMs)
            .length;
        expect(held, lessThanOrEqualTo(RenderPlan.clipsPerPassLowMemory + 1));
        final phase = p.startMs % loop;
        final onLap = phase <= 34 || phase >= loop - 34;
        final seek = RenderPlan.seekInto(
            isImage: false, sourceMs: loop, into: p.startMs, ms: p.durationMs);
        if (onLap) {
          expect(seek, phase <= 34 ? phase : 0,
              reason: 'a pass on a lap reads the clip from its top');
          continue;
        }
        midLap++;
        expect(p.endMs, lessThanOrEqualTo(p.startMs - phase + loop),
            reason: 'pass at ${p.startMs} runs past the end of its lap');
        expect(seek, phase,
            reason: 'pass at ${p.startMs} must seek ${phase}ms into the lap');
      }
      expect(midLap, greaterThan(0), reason: 'the case this test is for');
    });

    test('where a pass reads a clip from', () {
      int seek({bool image = false, int? len, required int into, int ms = 5000}) =>
          RenderPlan.seekInto(
              isImage: image, sourceMs: len, into: into, ms: ms);
      // A still, or a clip nobody could measure: always from the top.
      expect(seek(image: true, into: 30000), 0);
      expect(seek(into: 30000), 0);
      // The first pass, and a clip that covers the reel.
      expect(seek(len: 90000, into: 0), 0);
      expect(seek(len: 90000, into: 30000), 30000);
      // A looping clip: into the lap while the pass fits in it...
      expect(seek(len: 14000, into: 30000, ms: 4000), 2000);
      expect(seek(len: 14000, into: 30000, ms: 12000), 2000);
      // ...and from the top when it doesn't, or when it starts on one.
      expect(seek(len: 14000, into: 30000, ms: 12001), 0);
      expect(seek(len: 14000, into: 28000, ms: 20000), 0);
    });

    test('a clip long enough to cover the reel is cut wherever it suits', () {
      const long = 900000;
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: long,
        spans: const [
          PictureSpan(startMs: 0, endMs: long, sourceMs: long + 5000),
        ],
        clips: cards(0, long, 6000),
      );
      expectTiles(passes, 0, long);
      // Nothing forces the boundary earlier, so every pass runs the
      // full target length.
      for (final p in passes.take(passes.length - 1)) {
        expect(p.durationMs, RenderPlan.passTargetMs);
      }
    });

    test('an unmeasurable clip is left whole while it can be', () {
      // Nowhere in it is a safe cut, and 100 cards is a graph that
      // still fits: better one long pass than a picture that jumps.
      const long = 600000;
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: long,
        spans: const [PictureSpan(startMs: 0, endMs: long)],
        clips: cards(0, long, 6000),
      );
      expect(passes.length, 1);
      expectTiles(passes, 0, long);
    });

    test('and cut anyway once the alternative is an encode that dies', () {
      const hour = 3600000;
      final clips = cards(0, hour, 6000); // 600 cards
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: hour,
        spans: const [PictureSpan(startMs: 0, endMs: hour)],
        clips: clips,
      );
      expect(passes.length, greaterThan(1));
      expectTiles(passes, 0, hour);
      for (final p in passes) {
        final held = clips
            .where((c) => c.endMs > p.startMs && c.startMs < p.endMs)
            .length;
        expect(held, lessThanOrEqualTo(RenderPlan.clipsHardMax + 1));
      }
    });
  });

  group('a run of sceneries', () {
    /// Ten sceneries, two minutes each, all stills.
    List<PictureSpan> stills(int n, int each) => [
          for (var i = 0; i < n; i++)
            PictureSpan(
                startMs: i * each, endMs: (i + 1) * each, isImage: true),
        ];

    test('boundaries keep clear of a crossfade', () {
      const each = 120000;
      const fade = 600;
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: each * 10,
        spans: stills(10, each),
        clips: cards(0, each * 10, 6000),
        fadeMs: fade,
      );
      expectTiles(passes, 0, each * 10);
      for (final p in passes.skip(1)) {
        final intoScene = p.startMs % each;
        expect(intoScene, greaterThanOrEqualTo(fade),
            reason: '${p.startMs} lands inside the blend that opens a scene');
      }
    });

    test('a cut is used as a boundary when nothing else can be', () {
      // Every scene is a short loop that cannot be cut open anywhere
      // useful, so the scene changes themselves are the only boundaries
      // left — and with no crossfade to lose, they cost nothing.
      const each = 60000;
      final passes = RenderPlan.of(
        segStartMs: 0,
        segEndMs: each * 8,
        spans: [
          for (var i = 0; i < 8; i++)
            PictureSpan(startMs: i * each, endMs: (i + 1) * each),
        ],
        clips: cards(0, each * 8, 6000),
      );
      expectTiles(passes, 0, each * 8);
      for (final p in passes.skip(1)) {
        expect(p.startMs % each, 0);
      }
    });
  });
}
