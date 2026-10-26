import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/reel_effects.dart';
import 'package:ayah_reels/render/scene_plan.dart';
import 'package:ayah_reels/render/video_renderer.dart';
import 'package:ayah_reels/widgets/reel_finish.dart';

/// The grade, checked on both sides of the wall.
///
/// A look is applied twice — once as Flutter colour filters over the
/// preview, once as an FFmpeg chain in the encode — and the entire
/// point of [PictureGrade] is that those two are one derivation. So
/// what is pinned here is not what any particular look looks like, but
/// that the two forms are the same transform, that the FFmpeg one is
/// something FFmpeg will actually accept, and that a reel nobody has
/// graded costs nothing at all.
void main() {
  /// The affine `colorlevels` is written as, read back out of the
  /// emitted string — which is the only way to check that what FFmpeg
  /// is told matches what the preview draws.
  ({double scale, double offset}) levelsFromChain(String chain, String ch) {
    final m = RegExp('${ch}imin=(-?[0-9.]+):${ch}imax=(-?[0-9.]+)')
        .firstMatch(chain);
    expect(m, isNotNull, reason: 'no $ch levels in: $chain');
    final imin = double.parse(m!.group(1)!);
    final imax = double.parse(m.group(2)!);
    final scale = 1 / (imax - imin);
    return (scale: scale, offset: -imin * scale);
  }

  group('a reel nobody graded', () {
    test('is neutral, and every path skips it', () {
      const e = ReelEffects.off;
      expect(e.isNeutral, isTrue);
      expect(e.gradesPicture, isFalse);
      expect(e.grade.isNeutral, isTrue);
      expect(e.grade.ffmpeg, '');
      expect(e.grade.filters, isEmpty);
      expect(e.vignetteAlpha, 0);
      expect(e.fadeMsFor(60000), 0);
      expect(e.key, 'n');
      // The de-banding dither the exporter has always laid on is not
      // an effect and does not go away with them.
      expect(e.noiseStrength, ReelEffects.baseNoise);
    });

    test('the preview wraps nothing around the picture', () {
      const marker = SizedBox();
      expect(identical(ReelFinish.graded(ReelEffects.off, marker), marker),
          isTrue);
      expect(ReelFinish.vignette(ReelEffects.off), isNull);
      expect(ReelFinish.grain(ReelEffects.off), isNull);
    });
  });

  group('the grade', () {
    test('every look is a real change, and none is a wild one', () {
      for (final look in ReelLook.values) {
        final e = ReelEffects(look: look);
        if (look == ReelLook.none) {
          expect(e.grade.isNeutral, isTrue);
          continue;
        }
        expect(e.grade.isNeutral, isFalse, reason: '${look.name} does nothing');
        // Nothing here may blow a channel out: the row sums are what
        // a flat white frame comes back as, and a look that pushed one
        // past 1 would clip every highlight in the reel to paper.
        for (var row = 0; row < 3; row++) {
          final sum = e.grade.mix[row * 3] +
              e.grade.mix[row * 3 + 1] +
              e.grade.mix[row * 3 + 2];
          expect(sum, lessThanOrEqualTo(1.12),
              reason: '${look.name} row $row clips');
          expect(sum, greaterThan(0.6));
        }
      }
    });

    test('noir takes the colour out and nothing else puts it back', () {
      final g = const ReelEffects(look: ReelLook.noir).grade;
      // Every row the same: three channels that answer only to luma.
      for (var col = 0; col < 3; col++) {
        expect(g.mix[col], closeTo(g.mix[3 + col], 1e-9));
        expect(g.mix[col], closeTo(g.mix[6 + col], 1e-9));
      }
    });

    test('warmth moves red and blue against each other', () {
      final warm = const ReelEffects(warmth: 1).grade;
      final cool = const ReelEffects(warmth: -1).grade;
      expect(warm.mix[0], greaterThan(cool.mix[0])); // red
      expect(warm.mix[8], lessThan(cool.mix[8])); // blue
      // And it is a shift, not a brightness knob: what it takes off
      // blue it puts on red, near enough that a white frame stays
      // white-ish.
      final warmSum = warm.mix[0] + warm.mix[4] + warm.mix[8];
      expect(warmSum, closeTo(3.0, 0.12));
    });

    test('a channel whose levels clamp keeps its own scale', () {
      // The clamp is what the class is built around and no shipped
      // look reaches it, so this is the one place it is exercised: a
      // lift big enough on one channel alone pushes that channel's
      // levels out of the range colorlevels takes, and the two that
      // did not clamp must not be dragged along with it.
      final g = PictureGrade.of(
        saturation: 1,
        gain: const [1, 1, 1],
        contrast: 0.5,
        lift: const [0, 0, 0.4],
      );
      expect(g.scaleOf(0), closeTo(g.scaleOf(1), 1e-9));
      expect(g.scaleOf(2), isNot(closeTo(g.scaleOf(0), 1e-3)));
      // And whatever it settled on, the string says the same thing —
      // the levels are stored in the form FFmpeg is handed, so there
      // is nothing left to derive twice.
      final chain = g.ffmpeg;
      for (var i = 0; i < 3; i++) {
        final l = levelsFromChain(chain, const ['r', 'g', 'b'][i]);
        expect(l.scale, closeTo(g.scaleOf(i), 1e-3));
        expect(l.offset, closeTo(g.offsetOf(i), 1e-3));
      }
    });

    test('vibrance opens and closes the saturation', () {
      double spread(PictureGrade g) => (g.mix[0] - g.mix[1]).abs();
      expect(spread(const ReelEffects(vibrance: 1).grade),
          greaterThan(spread(const ReelEffects(vibrance: -1).grade)));
    });
  });

  group('what FFmpeg is told', () {
    test('is the same transform the preview draws', () {
      for (final look in ReelLook.values) {
        for (final warmth in [0.0, 0.7, -0.7]) {
          final e = ReelEffects(look: look, warmth: warmth);
          final g = e.grade;
          if (g.isNeutral) continue;
          final chain = g.ffmpeg;
          expect(chain, startsWith('format=gbrp,'));
          expect(chain, endsWith(','),
              reason: 'the chain is spliced into a filter list');

          // The mix: the nine numbers in the string are the nine in
          // the matrix the preview uses.
          if (chain.contains('colorchannelmixer=')) {
            const names = [
              ['rr', 'rg', 'rb'],
              ['gr', 'gg', 'gb'],
              ['br', 'bg', 'bb'],
            ];
            for (var row = 0; row < 3; row++) {
              for (var col = 0; col < 3; col++) {
                final m = RegExp('${names[row][col]}=(-?[0-9.]+)')
                    .firstMatch(chain);
                expect(m, isNotNull);
                expect(double.parse(m!.group(1)!),
                    closeTo(g.mix[row * 3 + col], 1e-4));
              }
            }
          }
          // The levels: what `colorlevels` will compute is what the
          // second colour filter's matrix says.
          if (chain.contains('colorlevels=')) {
            const ch = ['r', 'g', 'b'];
            for (var i = 0; i < 3; i++) {
              final l = levelsFromChain(chain, ch[i]);
              expect(l.scale, closeTo(g.scaleOf(i), 1e-3),
                  reason: '${look.name} $warmth ${ch[i]} scale');
              expect(l.offset, closeTo(g.offsetOf(i), 1e-3),
                  reason: '${look.name} $warmth ${ch[i]} offset');
            }
          }
        }
      }
    });

    test('never asks for a level outside the range FFmpeg accepts', () {
      for (final look in ReelLook.values) {
        for (final v in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
          final chain =
              ReelEffects(look: look, warmth: v, vibrance: v).grade.ffmpeg;
          for (final m in RegExp(r'=(-?[0-9.]+)').allMatches(chain)) {
            final value = double.parse(m.group(1)!);
            expect(value, inInclusiveRange(-2.0, 2.0),
                reason: 'out of range in $chain');
          }
          for (final m
              in RegExp(r'[rgb]i(?:min|max)=(-?[0-9.]+)').allMatches(chain)) {
            expect(double.parse(m.group(1)!), inInclusiveRange(-1.0, 1.0),
                reason: 'colorlevels takes -1..1, got ${m.group(0)} in $chain');
          }
        }
      }
    });

    test('the preview nests the two filters so the mix runs first', () {
      // The order is not visible in `filters` — it is in how they are
      // wrapped. A ColorFiltered runs on what its child already
      // painted, so the *innermost* filter runs first, and the mix has
      // to be the inner one to match `colorchannelmixer` then
      // `colorlevels`.
      //
      // It was wrapped the other way round for one commit, and every
      // other test in this file passed: they all read `filters`, which
      // was in the right order, and none of them looked at the
      // nesting. Both stages clamp to eight bits, so getting it
      // backwards clips on the opposite side — rendered through
      // Flutter, saturated yellow under Noir came back 237 where the
      // filtergraph computes 255.
      for (final look in ReelLook.values) {
        final e = ReelEffects(look: look);
        final g = e.grade;
        const marker = SizedBox();
        final out = ReelFinish.graded(e, marker);
        if (g.isNeutral) {
          expect(identical(out, marker), isTrue);
          continue;
        }
        final outer = out as ColorFiltered;
        final inner = outer.child! as ColorFiltered;
        expect(inner.child, same(marker));
        expect(inner.colorFilter, ColorFilter.matrix(g.mixMatrix),
            reason: '${look.name}: the mix must run first');
        expect(outer.colorFilter, ColorFilter.matrix(g.levelMatrix),
            reason: '${look.name}: the levels must run second');
      }
    });

    test('the preview stacks the same two filters, in the same order', () {
      final g = const ReelEffects(look: ReelLook.golden, warmth: 0.5).grade;
      expect(g.filters, hasLength(2));
      expect(g.filters.first, isA<ColorFilter>());
      expect(g.mixMatrix, hasLength(20));
      expect(g.levelMatrix, hasLength(20));
      // The translation column of the second is the offset in 0..255,
      // which is the one place the two sides differ in units.
      expect(g.levelMatrix[4], closeTo(g.offsetOf(0) * 255, 1e-6));
      expect(g.levelMatrix[0], closeTo(g.scaleOf(0), 1e-9));
    });
  });

  group('the finish', () {
    test('grain rises above the exporter’s own dither, and only then', () {
      expect(const ReelEffects(grain: 0).noiseStrength,
          ReelEffects.baseNoise);
      expect(const ReelEffects(grain: 0.5).noiseStrength,
          greaterThan(ReelEffects.baseNoise));
      expect(const ReelEffects(grain: 1).noiseStrength, lessThanOrEqualTo(20));
    });

    test('the preview never draws grain the file will not have', () {
      // The encode rounds to a whole noise step, so the bottom of the
      // slider asks for a file that is bit-identical to no grain at
      // all. The preview has to agree, or this screen is lying on the
      // one knob it cannot show exactly.
      for (var i = 0; i <= 100; i++) {
        final e = ReelEffects.off.copyWith(grain: i / 100);
        final exports = e.noiseStrength > ReelEffects.baseNoise;
        expect(e.previewGrain > 0, exports,
            reason: 'grain ${i / 100}: preview and encode disagree');
        expect(ReelFinish.grain(e) != null, exports);
      }
    });

    test('the vignette never reaches black', () {
      expect(const ReelEffects(vignette: 0).vignetteAlpha, 0);
      expect(const ReelEffects(vignette: 1).vignetteAlpha, lessThan(0.8));
    });

    test('a fade is cut to fit a reel shorter than itself', () {
      const e = ReelEffects(fade: true);
      expect(e.fadeMsFor(60000), 600);
      expect(e.fadeMsFor(2000), 240);
      // Never more than a fraction of the reel, whatever its length.
      for (final ms in [500, 1000, 3000, 10000, 600000]) {
        expect(e.fadeMsFor(ms) * 2, lessThan(ms),
            reason: 'a $ms ms reel would be all fade');
      }
    });

    test('the fade ramps at both ends and is clear in between', () {
      const e = ReelEffects(fade: true);
      const reel = 10000;
      final d = e.fadeMsFor(reel);
      expect(ReelFinish.fadeLevelAt(e, 0, reel), 1);
      expect(ReelFinish.fadeLevelAt(e, d ~/ 2, reel), closeTo(0.5, 0.02));
      expect(ReelFinish.fadeLevelAt(e, d, reel), 0);
      expect(ReelFinish.fadeLevelAt(e, reel ~/ 2, reel), 0);
      expect(ReelFinish.fadeLevelAt(e, reel - d ~/ 2, reel),
          closeTo(0.5, 0.02));
      expect(ReelFinish.fadeLevelAt(e, reel, reel), 1);
      // And a reel with no fade never darkens.
      expect(ReelFinish.fadeLevelAt(ReelEffects.off, 0, reel), 0);
    });
  });

  graphTests();

  group('the render key', () {
    test('two different finishes never share one', () {
      final keys = <String>{};
      for (final look in ReelLook.values) {
        for (final v in [0.0, 0.5]) {
          for (final fade in [false, true]) {
            keys.add(ReelEffects(
              look: look,
              warmth: v,
              vignette: v,
              grain: v,
              fade: fade,
            ).key);
          }
        }
      }
      expect(keys.length, ReelLook.values.length * 2 * 2);
    });

    test('is exact: no two values that render differently share one',
        () {
      // The key is written in whole percent and the filtergraph reads
      // the value, so anything finer than a percent reaching the
      // graph is a reel served out of another reel's cache entry.
      // Every door in puts the value on a percent instead.
      const e = ReelEffects.off;
      for (var i = 0; i <= 100; i++) {
        final a = e.copyWith(grain: i / 1000);
        final b = e.copyWith(grain: i / 1000 + 0.0004);
        expect(a.key == b.key, a.noiseStrength == b.noiseStrength,
            reason: 'grain ${i / 1000}: key and noise disagree');
      }
      // And the same for the two that feed the colour matrix.
      for (var i = -100; i <= 100; i += 7) {
        final a = e.copyWith(warmth: i / 300);
        final b = e.copyWith(warmth: i / 300 + 0.0004);
        expect(a.key == b.key, a.grade.ffmpeg == b.grade.ffmpeg,
            reason: 'warmth ${i / 300}: key and chain disagree');
      }
    });

    test('survives the round trip through the recipe’s JSON', () {
      const e = ReelEffects(
        look: ReelLook.moonlight,
        warmth: -0.3,
        vibrance: 0.25,
        vignette: 0.75,
        grain: 0.2,
        fade: true,
      );
      expect(ReelEffects.fromJson(e.toJson()), e);
      // A file written by a build that offered a look this one does
      // not must open, not throw.
      expect(
          ReelEffects.fromJson(const {'look': 'sepia', 'warmth': 4.0}).look,
          ReelLook.none);
      expect(ReelEffects.fromJson(const {'warmth': 4.0}).warmth, 1.0);
      expect(ReelEffects.fromJson(null), ReelEffects.off);
    });
  });
}

/// The half of the feature that only exists as a string.
///
/// The grade reaches FFmpeg as text spliced into a filtergraph, and
/// the fade as two filters that must land on the right *pass* of a
/// long reel. Neither can be seen without an encode on a device, so
/// both are pinned here instead.
void graphTests() {
  group('the filtergraph', () {
    test('a graded scene run carries the grade, once per scene', () {
      final grade = const ReelEffects(look: ReelLook.dusk).grade.ffmpeg;
      final g = VideoRenderer.sceneRunGraph(
        lengths: const [6, 5, 4],
        cuts: const [
          SceneCut(
              scene: 0, startMs: 0, endMs: 6000, firstAyah: 1, lastAyah: 1),
          SceneCut(
              scene: 1, startMs: 6000, endMs: 11000, firstAyah: 2,
              lastAyah: 2),
          SceneCut(
              scene: 2, startMs: 11000, endMs: 15000, firstAyah: 3,
              lastAyah: 3),
        ],
        fadeMs: 0,
        segStartMs: 0,
        grade: grade,
      );
      expect('colorchannelmixer='.allMatches(g).length, 3);
      // On the scenery and nothing else: the grade goes in before the
      // scenes are normalised and joined, never after.
      for (var i = 0; i < 3; i++) {
        expect(g, contains('crop=1080:1920,${grade}null[raw$i];'));
      }
    });

    test('an ungraded run is the graph it always was', () {
      final g = VideoRenderer.sceneRunGraph(
        lengths: const [6, 5],
        cuts: const [
          SceneCut(
              scene: 0, startMs: 0, endMs: 6000, firstAyah: 1, lastAyah: 1),
          SceneCut(
              scene: 1, startMs: 6000, endMs: 11000, firstAyah: 2,
              lastAyah: 2),
        ],
        fadeMs: 0,
        segStartMs: 0,
      );
      expect(g, isNot(contains('colorchannelmixer')));
      expect(g, isNot(contains('format=gbrp')));
    });

    test('a reel encoded in one pass fades at both its ends', () {
      const e = ReelEffects(fade: true);
      final chain = VideoRenderer.fadeChain(e, 60000, 0, 60000);
      expect(chain, contains('fade=t=in:st=0:d=0.600'));
      expect(chain, contains('fade=t=out:st=59.400:d=0.600'));
    });

    test('a reel encoded in several fades only at the two that are ends',
        () {
      const e = ReelEffects(fade: true);
      // Three passes of a 300s reel.
      const reel = 300000;
      final first = VideoRenderer.fadeChain(e, reel, 0, 100000);
      final middle = VideoRenderer.fadeChain(e, reel, 100000, 100000);
      final last = VideoRenderer.fadeChain(e, reel, 200000, 100000);
      expect(first, contains('t=in'));
      expect(first, isNot(contains('t=out')));
      expect(middle, '');
      expect(last, isNot(contains('t=in')));
      // In the last pass's own clock, not the reel's: the passes are
      // joined end to end, so a start time measured from the reel
      // would fade out a hundred seconds past the end of the file.
      expect(last, contains('fade=t=out:st=99.400:d=0.600'));
    });

    test('no fade at all when nobody asked for one', () {
      expect(VideoRenderer.fadeChain(ReelEffects.off, 60000, 0, 60000), '');
    });
  });
}
