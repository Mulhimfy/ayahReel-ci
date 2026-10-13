import 'package:flutter/material.dart';

import '../data/reel_effects.dart';
import '../render/ayah_rasterizer.dart';
import 'film_grain.dart';

/// The effect layers, in the order the exporter composites them.
///
/// Both screens that draw a reel — the style step's still frame and
/// the preview's playing one — stack these, so neither can drift from
/// the other or from the file. The order is the filtergraph's, and it
/// is not arbitrary:
///
///   scenery, graded   ← the only thing a colour grade touches
///   scrim             ← legibility, never graded
///   vignette          ← light falling off at the corners of the frame
///   the verse         ← ink
///   the mark
///   grain             ← over everything, as a film stock would be
///   fade              ← and the whole frame going to black
///
/// The scrim and the vignette are one PNG in full frame — see
/// [AyahRasterizer.rasterizeScrim] — which is what makes the vignette
/// free there. Everything else is its own layer on both sides.
abstract final class ReelFinish {
  /// The scenery, put through the reel's grade. Returns [child]
  /// untouched when there is no grade, so an ungraded reel pays for no
  /// filter at all.
  static Widget graded(ReelEffects effects, Widget child) {
    var out = child;
    // Wrapped in order, which nests each new filter *outside* the last
    // — and a colour filter runs on what its child already painted, so
    // the innermost runs first. Wrapping the list in order is
    // therefore what runs it in order: the mix, then the levels, which
    // is the order the FFmpeg chain applies them in.
    //
    // It read the other way round for one commit, and the cost of
    // getting it backwards is not subtle: saturated yellow through
    // Noir comes out 255 in the file and 237 on screen, because the
    // two stages clamp on opposite sides of each other. There is a
    // test that renders a pixel and compares it against the chain.
    for (final f in effects.grade.filters) {
      out = ColorFiltered(colorFilter: f, child: out);
    }
    return out;
  }

  /// The vignette, or null when it is off. Draw it directly over the
  /// scenery and under the verse, which is where the export puts it.
  static Widget? vignette(ReelEffects effects) => effects.vignette == 0
      ? null
      : IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AyahRasterizer.vignetteGradient(effects.vignette),
            ),
          ),
        );

  /// The grain, or null when it is off. Over everything.
  ///
  /// Drawn at [ReelEffects.previewGrain] rather than at the slider's
  /// own value: the encode rounds its noise strength to a whole step,
  /// so the bottom of the slider asks for grain the file will not
  /// have, and this is the screen that promises otherwise.
  static Widget? grain(ReelEffects effects) {
    final strength = effects.previewGrain;
    return strength == 0 ? null : FilmGrain(strength: strength);
  }

  /// The frame going to black, at [level] (0 = clear, 1 = black).
  static Widget fade(double level) => IgnorePointer(
        child: ColoredBox(color: Colors.black.withValues(alpha: level)),
      );

  /// How black the frame is [ms] into a reel [reelMs] long — the same
  /// linear ramp FFmpeg's `fade` draws at either end, so the preview
  /// dips exactly where the file does.
  static double fadeLevelAt(ReelEffects effects, int ms, int reelMs) {
    final d = effects.fadeMsFor(reelMs);
    if (d <= 0) return 0;
    if (ms <= 0 || ms >= reelMs) return 1;
    if (ms < d) return 1 - ms / d;
    final out = reelMs - d;
    if (ms > out) return (ms - out) / d;
    return 0;
  }
}
