import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/card_deck.dart';
import '../data/card_style.dart';
import 'card_frames.dart';
import 'reel_finish.dart';
import 'reel_watermark.dart';

/// One card, drawn.
///
/// This is the only thing in the app that knows what a card looks
/// like. The composer puts it on screen at whatever width the phone
/// has room for, and the exporter rasterizes this very widget at 1080
/// — so the file cannot drift from what the user approved, the same
/// arrangement the reels' verse card has always had.
///
/// Everything it draws is measured in fractions of [width]: the type
/// sizes, the shadows, the frame, the mark and the gaps between them.
/// There is no other way for the two to agree at a three-to-one scale
/// difference.
class CardCanvas extends StatelessWidget {
  final CardSlide slide;
  final CardFormat format;
  final double width;

  /// The decoded background. Null while it is still being decoded — or
  /// for good, if it could not be — and the card stands on its paper
  /// instead, which is a card rather than a hole.
  final ui.Image? picture;

  /// The block the composer has selected, outlined while it is. Null
  /// everywhere else, including in every exported pixel.
  final String? selectedId;

  /// Guides drawn while a block is being dragged: the fractions of the
  /// card it has snapped to, across and down.
  final double? guideX;
  final double? guideY;

  /// Who the card was made for, already written as a sentence. Drawn
  /// above the mark by the mark's own widget, exactly as a reel draws
  /// it — see [ReelWatermarkMark].
  final String dedication;

  const CardCanvas({
    super.key,
    required this.slide,
    required this.format,
    required this.width,
    this.picture,
    this.selectedId,
    this.guideX,
    this.guideY,
    this.dedication = '',
  });

  double get height => width / format.aspect;

  @override
  Widget build(BuildContext context) {
    final e = slide.effects;
    final bg = slide.background;
    // The grade, the vignette and the grain are the reel's own — the
    // same values, the same arithmetic and the same layers, in the
    // same order the exporter composites them. [ReelFinish] is where
    // that order is written down, and a card asks it rather than
    // keeping a second opinion.
    // The paper is inside the grade, not behind it, and that is a
    // fix rather than a detail: a card standing on paper has no
    // photograph, so a grade wrapped around the picture alone had
    // nothing to work on — Golden hour, Dusk and Moonlight, and the
    // warmth and vibrance sliders under them, all did exactly nothing
    // on every card that was not on a scenery. Grading the ground
    // means grading whatever the ground happens to be.
    final ground = ReelFinish.graded(
      e,
      Stack(
        fit: StackFit.expand,
        children: [
          // The paper is always painted, whatever else lands on top:
          // it is the ground behind a picture that is still decoding,
          // and behind one with transparency in it.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: bg.groundColours,
              ),
            ),
          ),
          _picture(bg),
        ],
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      // A card is a picture, not chrome: it is laid out the same way
      // whichever way the app around it reads. Without this the
      // composer would mirror under Arabic and the export — which is
      // rasterized left to right — would not, and the two would be
      // different pictures.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ground,
              if (bg.hasPicture && bg.dim > 0)
                ColoredBox(
                  color: const Color(0xFF000000).withValues(alpha: bg.dim),
                ),
              if (e.vignette > 0) ReelFinish.vignette(e)!,
              if (slide.frame != CardFrame.none)
                CustomPaint(
                  painter: CardFramePainter(
                    frame: slide.frame,
                    colour: Color(slide.frameArgb),
                  ),
                ),
              for (final block in slide.blocks) _block(block),
              _mark(),
              // Over everything, as a film stock would be — the order
              // the exporter lays a reel's layers in.
              if (e.grain > 0) ReelFinish.grain(e)!,
              if (guideX != null || guideY != null)
                CustomPaint(painter: _GuidePainter(guideX, guideY)),
            ],
          ),
        ),
      ),
    );
  }

  /// The photograph, cropped to the card.
  ///
  /// The library is upright 9:16 and every card is squarer than that,
  /// so `cover` always crops the height rather than stretching
  /// anything — and which part of the height survives is the whole
  /// point of [CardBackground.focusY]. `alignment` is what expresses
  /// that: -1 keeps the top, 1 the bottom.
  Widget _picture(CardBackground bg) {
    final img = picture;
    if (img == null) return const SizedBox.shrink();
    final blur = bg.blur;
    Widget out = RawImage(
      image: img,
      fit: BoxFit.cover,
      alignment: Alignment(bg.focusX * 2 - 1, bg.focusY * 2 - 1),
      // The composer draws this at a third of export size; without a
      // filter that is a hard downsample, and the card looks sharper
      // in the preview than in the file.
      filterQuality: FilterQuality.medium,
      isAntiAlias: true,
    );
    if (bg.zoom > 1) {
      out = Transform.scale(scale: bg.zoom, child: out);
    }
    if (blur > 0) {
      // The blur is a fraction of the card's width for the same reason
      // everything else is: a sigma that looked right in the composer
      // would be a third of the blur in the file.
      final sigma = blur * width * 0.055;
      out = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          // Clamped, not decal: a decal blur samples transparency
          // outside the picture, so the card's own edges would fade
          // into the paper behind them — a white halo around a
          // full-bleed photograph.
          tileMode: TileMode.clamp,
        ),
        child: out,
      );
    }
    return ClipRect(child: out);
  }

  /// One block of words, placed by its centre.
  ///
  /// [FractionalTranslation] is what makes a centre possible at all: a
  /// block's height is whatever its text wraps to, so it cannot be
  /// positioned from the top without measuring it first. Positioned at
  /// its centre line and then shifted up by half of its own height,
  /// nothing has to be measured and the card is laid out in one pass.
  Widget _block(CardTextBlock block) {
    final w = block.width * width;
    final selected = block.id == selectedId;
    return Positioned(
      left: block.x * width - w / 2,
      top: block.y * height,
      width: w,
      child: FractionalTranslation(
        translation: const Offset(0, -0.5),
        child: Transform.rotate(
          angle: block.rotation * math.pi / 180,
          child: Opacity(
            opacity: block.opacity,
            child: _skinned(block, w, selected),
          ),
        ),
      ),
    );
  }

  Widget _skinned(CardTextBlock block, double w, bool selected) {
    final colour = Color(block.colourArgb);
    final text = Text(
      block.text,
      textAlign: block.align.resolve(rtl: block.rtl),
      textDirection: block.rtl ? TextDirection.rtl : TextDirection.ltr,
      style: block.face.style(
        size: block.size * width,
        color: colour,
        lineHeight: block.lineHeight,
        tracking: block.tracking,
        shadows: _shadows(block, colour),
      ),
    );
    Widget out = text;
    if (block.skin == CardSkin.plate) {
      out = DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF000000).withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(width * 0.028),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: width * 0.035, vertical: width * 0.028),
          child: text,
        ),
      );
    } else if (block.skin == CardSkin.rule) {
      out = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text,
          SizedBox(height: width * 0.036),
          Center(child: CardRule(width: w * 0.34, colour: colour)),
        ],
      );
    }
    if (!selected) return out;
    // The one thing on a card that is not in the exported picture: a
    // dashed outline around whatever is being worked on, drawn outside
    // the block's own box so it never moves the text by a pixel.
    return CustomPaint(
      foregroundPainter: _SelectionPainter(width * 0.012),
      child: out,
    );
  }

  /// How a block is lifted off whatever is behind it. Every radius and
  /// offset is a fraction of the card's width, so the file gets the
  /// same shadow the composer showed.
  List<Shadow> _shadows(CardTextBlock block, Color colour) =>
      switch (block.skin) {
        CardSkin.none || CardSkin.plate => const [],
        CardSkin.shadow || CardSkin.rule => [
            Shadow(
              color: const Color(0xFF000000).withValues(alpha: 0.55),
              blurRadius: width * 0.022,
              offset: Offset(0, width * 0.004),
            ),
          ],
        CardSkin.glow => [
            Shadow(
              color: colour.withValues(alpha: 0.55),
              blurRadius: width * 0.055,
            ),
            Shadow(
              color: const Color(0xFF000000).withValues(alpha: 0.45),
              blurRadius: width * 0.018,
              offset: Offset(0, width * 0.004),
            ),
          ],
      };

  /// The app's mark, on every card.
  ///
  /// Quiet and in the same corner every time — the point of a mark is
  /// that it is never the thing you look at. It hangs off the bottom
  /// edge rather than off the words, because a card has no verse for
  /// it to follow, and it takes the ink of the ground it lands on: a
  /// white wordmark on ivory is not a subtle mark, it is a missing one.
  Widget _mark() {
    final light = slide.background.isPaper && slide.background.groundLight;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: width * CardCanvasMetrics.markInsetFor(format)),
        child: ReelWatermarkMark(
          width: width * 0.86,
          undimmed: slide.background.hasPicture && slide.background.dim < 0.2,
          ink: light ? const Color(0xFF15181C) : null,
          dedication: dedication,
        ),
      ),
    );
  }

  /// See [CardCanvasMetrics.markInsetFor].
  static const markInset = CardCanvasMetrics.markInset;
}

/// The few numbers about a card that something other than the canvas
/// has to know — the exporter's checks, mostly. Kept apart from the
/// widget so reading one costs nothing.
abstract final class CardCanvasMetrics {
  /// How far the mark sits above the bottom edge, as a fraction of the
  /// card's width. Clear of the frame at every format — the frames are
  /// inset by at most 5.8% — and clear of the caption row a feed draws
  /// over the bottom of a post.
  ///
  /// Nudged up from 0.075: at the old value the mark read as having
  /// slipped off the bottom of the card rather than as being signed
  /// into it, and a dedication above it sat lower still.
  static const markInset = 0.098;

  /// The same, on a card cut for a story.
  ///
  /// A story is not a post: Instagram draws its own bar across the
  /// bottom of one — the reply field, the send row — and anything in
  /// that band is covered on every phone that opens it. The reels hit
  /// this first and answered it by measuring off a posted reel; the
  /// number is [ReelWatermark.fullFrameInset], 360 of 1080 across,
  /// and a story card is the same frame so it takes the same floor.
  static const storyMarkInset =
      ReelWatermark.fullFrameInset / ReelWatermarkMark.referenceWidth;

  static double markInsetFor(CardFormat format) =>
      format == CardFormat.story ? storyMarkInset : markInset;
}

/// The dashed outline around the selected block.
class _SelectionPainter extends CustomPainter {
  final double pad;
  const _SelectionPainter(this.pad);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-pad, -pad, size.width + pad * 2, size.height + pad * 2),
      Radius.circular(pad),
    );
    final paint = Paint()
      ..color = const Color(0xFFEEC96B).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, pad * 0.16);
    // A dashed rectangle, drawn as a run of short arcs along the path
    // rather than with a dash effect Flutter does not have.
    final metrics = (Path()..addRRect(rect)).computeMetrics();
    for (final m in metrics) {
      var d = 0.0;
      final dash = math.max(4.0, m.length / 48);
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash * 2;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) => old.pad != pad;
}

/// The gold lines that appear under a block while it snaps to the
/// middle or to a third of the card.
class _GuidePainter extends CustomPainter {
  final double? x;
  final double? y;
  const _GuidePainter(this.x, this.y);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEEC96B).withValues(alpha: 0.6)
      ..strokeWidth = 1;
    if (x != null) {
      canvas.drawLine(
          Offset(x! * size.width, 0), Offset(x! * size.width, size.height),
          paint);
    }
    if (y != null) {
      canvas.drawLine(
          Offset(0, y! * size.height), Offset(size.width, y! * size.height),
          paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => old.x != x || old.y != y;
}
