import 'package:flutter/foundation.dart';

/// How the blurred backdrop is toned down, so the card stays the
/// subject and the verse stays legible on the band.
///
/// Proportional, deliberately. What this replaces was a fixed
/// subtraction — `eq=brightness=-0.30`, which takes 76 of 255 off every
/// pixel — applied to a quantity that is nothing like fixed. Blurred
/// down to its average, a night sky sits near 5, a mosque at dusk near
/// 27, a bright coast near 120; subtracting 76 leaves the coast looking
/// like the intended backdrop and clips everything below the offset to
/// solid black. Eleven of the twenty bundled stills came out as an
/// unlit band indistinguishable from the flat-black backdrop, which is
/// what "some sceneries have no blur at all" was: the blur radius was
/// identical on every one of them, and on most of them nothing survived
/// to show it.
///
/// Scaling keeps each scenery's own structure — a dark scene stays a
/// dark version of itself rather than becoming nothing — and still
/// leaves the brightest verse band no lighter than the offset did,
/// which is the number white ink has to read against.
abstract final class BackdropTone {
  /// Pulled toward grey so the backdrop never competes with the card.
  static const saturation = 0.7;

  /// What the whole thing is multiplied by. Set from the brightest
  /// scenery in the library: any higher and its verse band ends up
  /// lighter than the offset used to leave it.
  static const gain = 0.55;

  /// Rec. 709 luma weights — the same ones `isLightSurface` judges by.
  static const _lumaWeights = [0.2126, 0.7152, 0.0722];

  /// Row-major 3x3: desaturate toward luma, then scale. One function so
  /// the preview's filter and FFmpeg's cannot drift apart.
  static double _cell(int row, int col) =>
      ((1 - saturation) * _lumaWeights[col] +
          (row == col ? saturation : 0.0)) *
      gain;

  /// The 4x5 matrix `ColorFilter.matrix` takes. Every offset is zero —
  /// that is the entire point.
  static List<double> get colorMatrix => <double>[
        _cell(0, 0), _cell(0, 1), _cell(0, 2), 0, 0, //
        _cell(1, 0), _cell(1, 1), _cell(1, 2), 0, 0, //
        _cell(2, 0), _cell(2, 1), _cell(2, 2), 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  /// The same matrix as FFmpeg `colorchannelmixer` arguments.
  static String get ffmpegMix {
    const names = [
      ['rr', 'rg', 'rb'],
      ['gr', 'gg', 'gb'],
      ['br', 'bg', 'bb'],
    ];
    final parts = <String>[];
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        parts.add('${names[row][col]}=${_cell(row, col).toStringAsFixed(4)}');
      }
    }
    return parts.join(':');
  }
}

/// Geometry of the letterbox ("cropped top and bottom") format, in the
/// 1080x1920 export space.
///
/// One class computes it and both the live preview and FFmpeg read from
/// it, for the same reason the exporter rasterizes the preview's own
/// widgets: two implementations of the same arithmetic drift, and the
/// drift only ever shows up in the finished file.
///
/// The preview works in the same coordinates and scales by
/// `stageWidth / frameW`.
@immutable
class LetterboxGeometry {
  /// Export frame, which every number here is expressed in.
  static const frameW = 1080.0;
  static const frameH = 1920.0;

  /// Gap between the card and the left/right frame edges. Fixes the
  /// card's width; its height is the only thing the source decides.
  static const inset = 36.0;

  /// Corner radius when rounded corners are on.
  static const radius = 28.0;

  /// The card follows the source's own aspect — that is what makes the
  /// format read as "the video, uncropped" — but only within these
  /// bounds. Past 2.4:1 a scope source would shrink to a slot; below
  /// 1:1 a portrait source would fill the frame and leave the verse
  /// nowhere to go, which is the one thing this format exists to give
  /// it. Outside the range the card centre-crops instead.
  static const minAspect = 1.0;
  static const maxAspect = 2.4;

  /// Share of the leftover vertical space that goes above the card.
  /// Below half, so the band under the card is the larger of the two:
  /// that band is where the verse lives.
  static const _topShare = 0.36;

  /// Bottom margin of the band — how much of the frame's lower edge the
  /// verse is kept off.
  ///
  /// Sized, originally, for a watermark that sat down there; the mark
  /// has since moved onto the card, and this is now simply the band's
  /// own margin. Left where it was rather than reclaimed: the number is
  /// baked into every saved `overlayAlign`, so growing the band would
  /// quietly slide every verse the user has already placed.
  static const bandBottomPadding = 150.0;

  final double cardW;
  final double cardH;
  final double cardX;
  final double cardY;

  const LetterboxGeometry._(this.cardW, this.cardH, this.cardX, this.cardY);

  /// Card box for a source whose displayed aspect is [sourceAspect]
  /// (width / height, rotation already applied).
  factory LetterboxGeometry.of(double sourceAspect) {
    final a = sourceAspect.isFinite && sourceAspect > 0
        ? sourceAspect.clamp(minAspect, maxAspect)
        : 16 / 9;
    const w = frameW - 2 * inset;
    // Even dimensions: an odd-sized intermediate is a warning at best
    // and a chroma-siting artefact at worst once it hits yuv420p.
    final h = _even(w / a);
    return LetterboxGeometry._(w, h, inset, _even((frameH - h) * _topShare));
  }

  static double _even(double v) => (v / 2).round() * 2.0;

  /// Bottom edge of the card. The watermark hangs off this rather than
  /// off the frame, so it travels with the picture instead of sitting
  /// in the band the verse needs.
  double get cardBottom => cardY + cardH;

  /// Top of the band the crop frees below the card — where the verse
  /// goes, and the reason the format is worth having.
  double get bandTop => cardBottom;

  double get bandHeight => frameH - bandTop - bandBottomPadding;

  /// Top edge for a verse card [overlayHeight] tall, given the user's
  /// 0..1 vertical placement. Anchored to the band: dragging the verse
  /// moves it within the space below the card rather than over the
  /// whole frame, so it can never end up back on the picture.
  ///
  /// Deliberately unclamped, and deliberately the same arithmetic
  /// Flutter's [Alignment] performs — the preview places the verse with
  /// an Align inside the band, and a card taller than the band has to
  /// overhang identically in both.
  double verseTop(double overlayHeight, double align) =>
      bandTop + (bandHeight - overlayHeight) * align.clamp(0.0, 1.0);

  /// FFmpeg overlay y-expression for a verse PNG: [verseTop] with `h`
  /// left to FFmpeg, which is the only one that knows the PNG's height.
  String verseYExpr(double align) =>
      '${bandTop.toStringAsFixed(0)}+(${bandHeight.toStringAsFixed(0)}-h)'
      '*${align.clamp(0.0, 1.0).toStringAsFixed(3)}';

  /// Identity of this geometry for a render cache key.
  String get key => '${cardW.round()}x${cardH.round()}';
}
