import 'dart:math' as math;
import 'dart:ui' show Color, ColorFilter;

import 'package:flutter/foundation.dart';

/// A finished colour grade, as both halves of the app need it: a pair
/// of Flutter colour filters for the live preview, and a pair of
/// FFmpeg filters for the export.
///
/// One class, because two implementations of the same arithmetic drift
/// and the drift only ever shows up in the finished file. The same
/// reason [BackdropTone] exists, and the same shape: derive once, emit
/// twice.
///
/// ## Why two stages rather than one matrix
///
/// A grade is an affine transform of RGB — a 3x3 mix (saturation,
/// channel gain) followed by a per-channel scale and offset (contrast,
/// lift). Flutter would take all of it as one 4x5 matrix, but FFmpeg
/// needs two filters (`colorchannelmixer` has no offset), and it
/// clamps to 8 bits between them. Folding the two into one matrix on
/// the preview side would therefore *not* be the same picture wherever
/// the intermediate leaves 0..1 — so the preview chains two filters
/// too, and the two agree by construction rather than by arithmetic.
///
/// ## Why the numbers are read back out of the FFmpeg form
///
/// `colorlevels` takes input/output levels in -1..1 and the affine a
/// look asks for does not always fit. Rather than let FFmpeg clamp
/// silently into a grade the preview never showed, the clamp happens
/// here, and [scale]/[offset] are what the clamped levels actually
/// produce. Same for rounding: the emitted string carries four
/// decimals, so the matrix is built from the rounded values.
@immutable
class PictureGrade {
  /// Row-major 3x3, applied first.
  final List<double> mix;

  /// The second stage, held as the input levels `colorlevels` takes —
  /// per channel, already clamped into the range FFmpeg accepts and
  /// already rounded to what the emitted string carries.
  ///
  /// Held in *this* form rather than as a scale and an offset because
  /// this is the form one of the two sides has to be given, and a
  /// number derived twice is a number that can disagree with itself.
  /// The matrix the preview uses is derived from these, so it cannot.
  ///
  /// Per channel and not one scalar: the clamp is per channel — it is
  /// the channel's own lift that pushes its levels out of range — so a
  /// single scale could only ever be right for one of the three.
  final List<double> imin;
  final List<double> imax;

  const PictureGrade._(this.mix, this.imin, this.imax);

  static const _identityMix = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];

  /// The grade that changes nothing.
  static const none =
      PictureGrade._(_identityMix, [0.0, 0.0, 0.0], [1.0, 1.0, 1.0]);

  /// `out = in * scale + offset` for one channel, which is what the
  /// levels above come to.
  double scaleOf(int channel) => 1 / (imax[channel] - imin[channel]);
  double offsetOf(int channel) => -imin[channel] * scaleOf(channel);

  /// Rec. 709 luma weights — the same ones [BackdropTone] and
  /// `isLightSurface` judge by.
  static const _luma = [0.2126, 0.7152, 0.0722];

  static double _r4(double v) => (v * 10000).roundToDouble() / 10000;

  /// Builds the grade for a saturation, a per-channel gain, a contrast
  /// and a per-channel lift — the four things a look is made of.
  factory PictureGrade.of({
    required double saturation,
    required List<double> gain,
    required double contrast,
    required List<double> lift,
  }) {
    // Desaturate toward luma, then scale each channel. One matrix:
    // gain is diagonal, so it is a row-wise multiply of the other.
    final mix = <double>[];
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final sat = (1 - saturation) * _luma[col] +
            (row == col ? saturation : 0.0);
        mix.add(_r4(gain[row] * sat));
      }
    }
    // Contrast pivots on mid-grey so it does not double as a
    // brightness knob; the lift is what moves the whole channel.
    final imin = <double>[];
    final imax = <double>[];
    for (var i = 0; i < 3; i++) {
      final l = _levels(contrast, 0.5 * (1 - contrast) + lift[i]);
      imin.add(l.imin);
      imax.add(l.imax);
    }
    return PictureGrade._(mix, imin, imax);
  }

  /// `out = in * scale + offset`, written as the input levels
  /// `colorlevels` takes, clamped into the range it accepts and
  /// rounded to the four decimals the string will carry — so what is
  /// stored here is exactly what FFmpeg will be handed.
  static ({double imin, double imax}) _levels(double scale, double offset) {
    var lo = _r4((-offset / scale).clamp(-1.0, 1.0));
    var hi = _r4(((1 - offset) / scale).clamp(-1.0, 1.0));
    // A span that has closed on itself is not a grade, it is a divide
    // by zero. Nothing the app offers gets near it; the guard is for
    // the look somebody adds later.
    if (hi - lo < 0.01) {
      lo = 0;
      hi = 1;
    }
    return (imin: lo, imax: hi);
  }

  bool get _mixIsIdentity {
    for (var i = 0; i < 9; i++) {
      if ((mix[i] - _identityMix[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  bool get _levelsAreIdentity {
    for (var i = 0; i < 3; i++) {
      if (imin[i].abs() > 1e-6 || (imax[i] - 1).abs() > 1e-6) return false;
    }
    return true;
  }

  /// Nothing to apply, on either side.
  bool get isNeutral => _mixIsIdentity && _levelsAreIdentity;

  /// The 4x5 matrix `ColorFilter.matrix` takes for the first stage.
  List<double> get mixMatrix => <double>[
        mix[0], mix[1], mix[2], 0, 0, //
        mix[3], mix[4], mix[5], 0, 0, //
        mix[6], mix[7], mix[8], 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  /// The same, for the second — derived from the very levels FFmpeg is
  /// given. Offsets are unnormalised (0..255) in this form, which is
  /// the one place the two sides differ in units.
  List<double> get levelMatrix => <double>[
        scaleOf(0), 0, 0, 0, offsetOf(0) * 255, //
        0, scaleOf(1), 0, 0, offsetOf(1) * 255, //
        0, 0, scaleOf(2), 0, offsetOf(2) * 255, //
        0, 0, 0, 1, 0, //
      ];

  /// The filters the preview stacks, outermost first. Empty when the
  /// grade is neutral, so a reel with no look on it pays nothing.
  List<ColorFilter> get filters => [
        if (!_mixIsIdentity) ColorFilter.matrix(mixMatrix),
        if (!_levelsAreIdentity) ColorFilter.matrix(levelMatrix),
      ];

  /// The same grade as an FFmpeg filter chain, ready to splice into a
  /// filtergraph — with a trailing comma, or empty when there is
  /// nothing to do.
  ///
  /// `format=gbrp` because both filters are RGB-only; what follows in
  /// the graph names the pixel format it needs, so nothing is
  /// converted back here.
  String get ffmpeg {
    if (isNeutral) return '';
    const names = [
      ['rr', 'rg', 'rb'],
      ['gr', 'gg', 'gb'],
      ['br', 'bg', 'bb'],
    ];
    final parts = <String>[];
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        parts.add('${names[row][col]}=${mix[row * 3 + col].toStringAsFixed(4)}');
      }
    }
    final out = StringBuffer('format=gbrp,');
    if (!_mixIsIdentity) out.write('colorchannelmixer=${parts.join(':')},');
    if (!_levelsAreIdentity) {
      const ch = ['r', 'g', 'b'];
      final lv = <String>[];
      for (var i = 0; i < 3; i++) {
        lv.add('${ch[i]}imin=${imin[i].toStringAsFixed(4)}');
        lv.add('${ch[i]}imax=${imax[i].toStringAsFixed(4)}');
      }
      out.write('colorlevels=${lv.join(':')},');
    }
    return out.toString();
  }
}

/// A whole designed look for the picture: one tap, one coherent grade.
///
/// Each is a saturation, a channel gain, a contrast and a lift —
/// deliberately gentle. A reel is a verse with a picture behind it,
/// and a look that announces itself has stopped serving either.
enum ReelLook {
  /// The scenery as it was shot. The default, and the only one that
  /// costs the encode nothing at all.
  none(saturation: 1.0, gain: [1, 1, 1], contrast: 1.0, lift: [0, 0, 0]),

  /// Late afternoon: warm highlights, a shade more colour, blacks
  /// lifted just enough to read as film rather than video.
  golden(
    saturation: 1.10,
    gain: [1.070, 1.010, 0.910],
    contrast: 1.05,
    lift: [0.018, 0.010, 0.000],
  ),

  /// The blue half-hour after sunset. Cool, clean, a little deeper.
  dusk(
    saturation: 0.96,
    gain: [0.945, 0.985, 1.090],
    contrast: 1.07,
    lift: [0.000, 0.004, 0.020],
  ),

  /// Night: most of the colour gone, what is left pulled blue. The
  /// quietest ground a gold verse ever sits on.
  moonlight(
    saturation: 0.55,
    gain: [0.930, 0.975, 1.110],
    contrast: 1.03,
    lift: [0.000, 0.006, 0.026],
  ),

  /// Green held and everything else given way — for forest, field and
  /// rain.
  emerald(
    saturation: 1.08,
    gain: [0.935, 1.055, 0.985],
    contrast: 1.04,
    lift: [0.000, 0.010, 0.006],
  ),

  /// Desert light: warm, dry, a little washed, the way sand actually
  /// photographs at noon.
  sand(
    saturation: 0.88,
    gain: [1.080, 1.005, 0.870],
    contrast: 1.02,
    lift: [0.026, 0.018, 0.006],
  ),

  /// A soft warm-pink cast over a lifted, low-contrast frame — the
  /// matte look, and the gentlest thing here to read a verse against.
  rose(
    saturation: 0.94,
    gain: [1.055, 0.975, 1.025],
    contrast: 0.97,
    lift: [0.030, 0.022, 0.026],
  ),

  /// Black and white, with the contrast a monochrome frame needs to
  /// stop looking like a mistake.
  noir(
    saturation: 0.0,
    gain: [1, 1, 1],
    contrast: 1.16,
    lift: [0.004, 0.004, 0.004],
  );

  const ReelLook({
    required this.saturation,
    required this.gain,
    required this.contrast,
    required this.lift,
  });

  final double saturation;
  final List<double> gain;
  final double contrast;
  final List<double> lift;

  static ReelLook fromName(String? name) => ReelLook.values
      .firstWhere((l) => l.name == name, orElse: () => ReelLook.none);
}

/// Everything the user can do to the picture, in one immutable value.
///
/// Held on [CreationState], written into the recipe, and folded into
/// the render key — a reel graded one way must never be served out of
/// the cache for a reel graded another.
///
/// Each knob is off at zero and every one of them is off by default,
/// so a user who never opens the effects panel pays for none of it:
/// [isNeutral] takes the whole feature out of the filtergraph.
@immutable
class ReelEffects {
  final ReelLook look;

  /// Colour temperature, -1 (cool) to 1 (warm). Independent of the
  /// look, and applied on top of it.
  final double warmth;

  /// Colour depth, -1 (drained) to 1 (rich).
  final double vibrance;

  /// How dark the corners go, 0 to 1.
  final double vignette;

  /// Film grain, 0 to 1. Zero is not "no noise" — the exporter has
  /// always laid a trace of luma dither over the frame to keep smooth
  /// gradients from banding after quantization. This raises it into
  /// something you can see.
  final double grain;

  /// Whether the reel opens out of black and closes back into it.
  final bool fade;

  const ReelEffects({
    this.look = ReelLook.none,
    this.warmth = 0,
    this.vibrance = 0,
    this.vignette = 0,
    this.grain = 0,
    this.fade = false,
  });

  static const off = ReelEffects();

  ReelEffects copyWith({
    ReelLook? look,
    double? warmth,
    double? vibrance,
    double? vignette,
    double? grain,
    bool? fade,
  }) =>
      ReelEffects(
        look: look ?? this.look,
        warmth: _step(warmth ?? this.warmth, -1),
        vibrance: _step(vibrance ?? this.vibrance, -1),
        vignette: _step(vignette ?? this.vignette, 0),
        grain: _step(grain ?? this.grain, 0),
        fade: fade ?? this.fade,
      );

  /// Clamped, and settled onto a whole percent.
  ///
  /// The sliders are continuous and [key] is written in percent, so
  /// without this two reels a thousandth apart share a cache key while
  /// the filtergraph reads the raw value — and the second of them is
  /// served the first one's file. Rounding here rather than widening
  /// the key: a percent is finer than anyone can see, and a key that
  /// has to carry seventeen digits of a double is a key that will
  /// eventually be written wrong.
  static double _step(double v, double min) =>
      (v.clamp(min, 1.0) * 100).roundToDouble() / 100;

  /// How far a warmth of 1 moves the red and blue channels. Ten per
  /// cent either way is a shift anyone can see and nobody would call
  /// broken; green rides a fraction of it so the midtones do not go
  /// magenta.
  static const _warmthGain = 0.10;

  /// The grade the look, the warmth and the vibrance come to together.
  PictureGrade get grade {
    if (look == ReelLook.none && warmth == 0 && vibrance == 0) {
      return PictureGrade.none;
    }
    final w = warmth * _warmthGain;
    return PictureGrade.of(
      saturation: (look.saturation * (1 + 0.5 * vibrance)).clamp(0.0, 2.0),
      gain: [
        look.gain[0] * (1 + w),
        look.gain[1] * (1 + 0.15 * w),
        look.gain[2] * (1 - w),
      ],
      contrast: look.contrast,
      lift: look.lift,
    );
  }

  /// Whether anything at all is on. The whole feature is skipped when
  /// nothing is — no extra filter, no extra input, no extra PNG.
  bool get isNeutral =>
      grade.isNeutral && vignette == 0 && grain == 0 && !fade;

  /// Whether the picture itself is graded — what decides whether the
  /// colour filters ride the filtergraph at all.
  bool get gradesPicture => !grade.isNeutral;

  /// How dark the vignette's outer ring is drawn. The whole range is
  /// deliberately short of black: past this it stops reading as light
  /// falling off and starts reading as a hole in the picture.
  double get vignetteAlpha => 0.62 * vignette;

  /// FFmpeg's luma-noise strength.
  ///
  /// Two even with no grain asked for: smooth gradients band badly
  /// after x264 quantization at full-screen scale, and a trace of
  /// dither is what breaks the bands up. See the exporter, which has
  /// laid it on since long before this panel existed.
  static const baseNoise = 2;

  int get noiseStrength =>
      grain == 0 ? baseNoise : (baseNoise + 16 * grain).round();

  /// The grain the *preview* draws, expressed on the same 0..1 the
  /// slider uses — and derived from [noiseStrength] rather than from
  /// the slider, so the two cannot say different things.
  ///
  /// Zero wherever the encode would come back at the baseline dither
  /// every reel already gets. Read off the slider directly, the bottom
  /// two hundredths of the range drew visible grain over a preview of
  /// a file that would have none, which is the one thing this screen
  /// is not allowed to do.
  double get previewGrain {
    final extra = noiseStrength - baseNoise;
    return extra <= 0 ? 0 : extra / 16;
  }

  /// How long the reel fades in and out of black, in milliseconds,
  /// given its own length. Short reels get a shorter fade rather than
  /// a fade that eats them.
  int fadeMsFor(int reelMs) {
    if (!fade) return 0;
    return math.min(600, (reelMs * 0.12).round());
  }

  /// Everything that changes a pixel, for the render key.
  ///
  /// Exact, not approximate: every value here has been put on a whole
  /// percent by [_step] on the way in, so nothing is rounded away at
  /// this point. See [_step] for what happens when it is.
  String get key {
    if (isNeutral) return 'n';
    String q(double v) => (v * 100).round().toString();
    return '${look.name}_${q(warmth)}_${q(vibrance)}_${q(vignette)}'
        '_${q(grain)}${fade ? '_f' : ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is ReelEffects &&
      other.look == look &&
      other.warmth == warmth &&
      other.vibrance == vibrance &&
      other.vignette == vignette &&
      other.grain == grain &&
      other.fade == fade;

  @override
  int get hashCode =>
      Object.hash(look, warmth, vibrance, vignette, grain, fade);

  Map<String, dynamic> toJson() => {
        'look': look.name,
        'warmth': warmth,
        'vibrance': vibrance,
        'vignette': vignette,
        'grain': grain,
        'fade': fade,
      };

  factory ReelEffects.fromJson(Map<String, dynamic>? j) => j == null
      ? ReelEffects.off
      : ReelEffects(
          look: ReelLook.fromName(j['look'] as String?),
          // Through the same step as every other way in, so a recipe
          // written by a build that stored raw slider values comes
          // back on a key it can be rendered under.
          warmth: _step((j['warmth'] as num?)?.toDouble() ?? 0, -1),
          vibrance: _step((j['vibrance'] as num?)?.toDouble() ?? 0, -1),
          vignette: _step((j['vignette'] as num?)?.toDouble() ?? 0, 0),
          grain: _step((j['grain'] as num?)?.toDouble() ?? 0, 0),
          fade: j['fade'] as bool? ?? false,
        );
}

/// The one place the vignette's shape is written down.
///
/// Drawn by Flutter in both halves — painted live over the preview,
/// and rasterized to a PNG the exporter overlays — so the two are the
/// same curve by construction rather than by a matched pair of
/// formulas, which is how the scrim has always been done.
abstract final class Vignette {
  /// Where the darkening starts, as a fraction of the radius.
  static const innerStop = 0.38;

  /// How far out the ring reaches. The corners of a 9:16 frame sit at
  /// 1.02 of the short side, so this carries the falloff just past
  /// them — anything less leaves a visible arc across the corner.
  static const radius = 1.12;

  /// The gradient stops, for a box of any size.
  static List<Color> colours(double alpha) => [
        const Color(0x00000000),
        Color(((alpha.clamp(0.0, 1.0) * 255).round() << 24)),
      ];
}
