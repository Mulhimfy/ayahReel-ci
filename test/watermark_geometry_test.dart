import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/ayah_rasterizer.dart';
import 'package:ayah_reels/render/letterbox_layout.dart';
import 'package:ayah_reels/widgets/reel_watermark.dart';

/// The exported watermark is not a full-frame PNG that lands at 0:0 —
/// it is cropped to the mark and *positioned* by FFmpeg, using
/// arithmetic that lives half in the widget and half in the render
/// graph. Nothing at runtime would catch the two drifting apart: the
/// mark would just quietly move in every exported reel while the
/// preview kept showing it where it belongs.
///
/// So: pin the preview's placement, pin the identity the exporter
/// relies on to reproduce it, and pin the thing neither of them can
/// see — where the feed's own UI lands on top of the finished file.
void main() {
  const frame = Size(AyahRasterizer.exportWidth, 1920);

  /// Where TikTok's caption block starts, in export-frame pixels above
  /// the bottom edge: the top of the account-name row, measured off a
  /// posted reel. The audio row sits at 79 and the first hashtag line
  /// at 207, so anything below this is *inside* the caption.
  ///
  /// The mark shipped its first release at 92 — between two hashtag
  /// lines. Nothing in the app could catch that: the mark was exactly
  /// where the code said, and the code had never been told where the
  /// feed draws.
  const captionBlockTop = 284.0;

  /// Every card shape the format can build. A source's aspect is
  /// clamped into [LetterboxGeometry.minAspect]..maxAspect, so a
  /// portrait upload crops to a square — the largest card there is, and
  /// the one that pushes the mark lowest down the frame.
  const aspects = <String, double>{
    'portrait 9:16 (crops square)': 9 / 16,
    'square': 1.0,
    'photo 4:3': 4 / 3,
    'video 16:9': 16 / 9,
    'scope 2.4:1': 2.4,
    'wider than scope (clamps)': 3.5,
  };

  /// A stage that is genuinely the export frame.
  ///
  /// The [OverflowBox] is load-bearing: the default test surface is
  /// 800x600, and a plain Center would clamp the stage to it — leaving
  /// an Align to place the mark inside a 600px box pretending to be a
  /// 1920px frame. The old 92px inset fit inside 600 and so never
  /// noticed; a card-anchored mark sits at up to 1004 and does.
  Widget host(Widget child) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: frame, devicePixelRatio: 1.0),
          child: Center(
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: SizedBox(
                width: frame.width,
                height: frame.height,
                child: child,
              ),
            ),
          ),
        ),
      );

  /// Where a full-frame verse card's bottom edge lands, given its
  /// height and the user's 0..1 drag — the arithmetic FFmpeg runs as
  /// `(H-h)*align`, which is what [ReelWatermark.insetFor] is handed.
  double verseBottom(double cardH, double align) =>
      (frame.height - cardH) * align + cardH;

  testWidgets('preview draws the mark its format\'s inset above the edge',
      (t) async {
    for (final box in [null, ...aspects.values.map(LetterboxGeometry.of)]) {
      await t.pumpWidget(host(
          ReelWatermark(width: AyahRasterizer.exportWidth, letterbox: box)));

      final frameBox = t.getRect(find.byType(ReelWatermark));
      final markBox = t.getRect(find.byType(ReelWatermarkMark));

      expect(frameBox.bottom - markBox.bottom,
          closeTo(ReelWatermark.insetFor(box), 0.01));
      expect(markBox.center.dx, closeTo(frameBox.center.dx, 0.01));
    }

    // And with a verse card under it, which is the full-frame case the
    // app actually draws: the mark stays at the floor wherever the
    // card is dragged.
    for (final align in [0.0, 0.35, 0.5, 1.0]) {
      final bottom = verseBottom(700, align);
      await t.pumpWidget(host(ReelWatermark(
          width: AyahRasterizer.exportWidth, verseBottom: bottom)));

      expect(
        t.getRect(find.byType(ReelWatermark)).bottom -
            t.getRect(find.byType(ReelWatermarkMark)).bottom,
        closeTo(ReelWatermark.insetFor(null, verseBottom: bottom), 0.01),
        reason: 'align $align',
      );
    }
  });

  // The mark stands at the foot of the frame, above the band the feeds
  // draw over, and nowhere else: a signature belongs at the foot of the
  // page, and a verse dragged up the frame must not take it along.
  group('the full-frame mark stands at the floor, whatever the verse does',
      () {
    test('every card, every drag, one inset', () {
      for (var cardH = 200.0; cardH <= 1400; cardH += 100) {
        for (var align = 0.0; align <= 1.0; align += 0.1) {
          expect(
            ReelWatermark.insetFor(null,
                verseBottom: verseBottom(cardH, align)),
            ReelWatermark.fullFrameInset,
            reason: 'card ${cardH.round()} at align '
                '${align.toStringAsFixed(1)}',
          );
        }
      }
      expect(ReelWatermark.insetFor(null), ReelWatermark.fullFrameInset);
    });

    test('the floor clears the feeds\' caption block', () {
      // Above TikTok's account-name row by most of a caption line,
      // which also carries it over Instagram's, drawn a little higher.
      expect(ReelWatermark.fullFrameInset, greaterThan(captionBlockTop + 40.0));
      // And nowhere near the middle of the picture.
      expect(ReelWatermark.fullFrameInset, lessThan(frame.height * 0.25));
    });

    test('letterbox keeps signing the card, whatever the verse does', () {
      // The verse is *below* the mark in this format, in the band the
      // crop freed. Following it down there would undo the whole
      // arrangement, so the arm must ignore it.
      for (final box in aspects.values.map(LetterboxGeometry.of)) {
        for (var align = 0.0; align <= 1.0; align += 0.25) {
          expect(
            ReelWatermark.insetFor(box,
                verseBottom: box.verseTop(500, align) + 500),
            ReelWatermark.insetFor(box),
          );
        }
      }
    });

    testWidgets('the nominal mark height is the height the mark draws at',
        (t) async {
      await t.pumpWidget(host(const Center(
          child: ReelWatermarkMark(width: AyahRasterizer.exportWidth))));
      expect(
        t.getRect(find.byType(ReelWatermarkMark)).height,
        closeTo(ReelWatermark.markHeight, 8),
      );
    });
  });

  test('the exporter offsets the mark by the margin baked into its PNG', () {
    // FFmpeg places the *padded* PNG at H-h-watermarkInsetFor(...),
    // which puts the glyphs at H-insetFor(...) only while these agree —
    // in every format, since they no longer share a number.
    for (final box in [null, ...aspects.values.map(LetterboxGeometry.of)]) {
      expect(
        AyahRasterizer.watermarkInsetFor(box) + ReelWatermarkMark.shadowMargin,
        ReelWatermark.insetFor(box),
      );
    }
    // Including with a verse under it, where the answer is the floor
    // whatever the card's height.
    for (var cardH = 300.0; cardH <= 1300; cardH += 200) {
      for (final align in [0.0, 0.5, 1.0]) {
        final bottom = verseBottom(cardH, align);
        expect(
          AyahRasterizer.watermarkInsetFor(null, verseBottom: bottom) +
              ReelWatermarkMark.shadowMargin,
          ReelWatermark.insetFor(null, verseBottom: bottom),
        );
      }
    }
    // The margin exists to hold the mark's drop shadow inside the
    // shrink-wrapped boundary — sized for the wider of the two halos.
    expect(ReelWatermarkMark.shadowMargin, greaterThanOrEqualTo(13.0 + 1.5));
  });

  test('the full-frame mark clears the feed\'s caption block', () {
    expect(ReelWatermark.fullFrameInset, greaterThan(captionBlockTop),
        reason: 'the mark must sit above the account name, not in the '
            'caption with it');
    // Above it by most of a caption line (~66px in these coordinates),
    // so the account name never touches it.
    expect(ReelWatermark.fullFrameInset - captionBlockTop, greaterThan(40.0));
    // Quiet, still: this is a watermark, not a lower third. It stays in
    // the bottom quarter of the frame.
    expect(ReelWatermark.fullFrameInset, lessThan(frame.height / 4));
  });

  // The letterbox mark hangs off the card rather than the frame, so its
  // height off the bottom edge is different for every source shape —
  // 1004 for a scope card, 628 for a square one. A vertical background
  // makes the card as large as it can be, which is the case that pushes
  // the mark closest to both the band and the feed's caption; walk the
  // whole range rather than trusting one aspect.
  testWidgets('the letterbox mark signs the card, in every card shape',
      (t) async {
    await t.pumpWidget(host(
        const Center(child: ReelWatermarkMark(width: AyahRasterizer.exportWidth))));
    final markHeight = t.getRect(find.byType(ReelWatermarkMark)).height;

    for (final entry in aspects.entries) {
      final box = LetterboxGeometry.of(entry.value);
      final markBottom = frame.height - ReelWatermark.insetFor(box);
      final markTop = markBottom - markHeight;
      final why = 'aspect: ${entry.key}';

      // Inside the picture, both edges. Off the bottom of the card and
      // the mark hangs over the verse; off the top and it is riding up
      // the middle of someone's scenery.
      expect(markBottom, lessThanOrEqualTo(box.cardBottom), reason: why);
      expect(markTop, greaterThan(box.cardY), reason: why);

      // The band is the whole reason the mark moved. It must not take
      // back so much as a pixel of it.
      expect(markBottom, lessThanOrEqualTo(box.bandTop), reason: why);

      // And the point of the exercise: clear of the caption block, by a
      // margin, for every shape a background can be.
      expect(ReelWatermark.insetFor(box),
          greaterThan(captionBlockTop + 66.0), reason: why);
    }
  });

  // On the card there is no scrim between the mark and the picture —
  // full frame keeps 15-45% of black there, the card is composited with
  // none. White at 60% on a bright scenery is then held together by the
  // halo alone, so the halo has to be the stronger of the two.
  testWidgets('the mark on the card carries a heavier halo', (t) async {
    Shadow haloOf(WidgetTester t) => t
        .widgetList<Text>(find.descendant(
          of: find.byType(ReelWatermarkMark),
          matching: find.byType(Text),
        ))
        .firstWhere((w) => w.data == 'AyahReel')
        .style!
        .shadows!
        .single;

    await t.pumpWidget(host(
        const ReelWatermarkMark(width: AyahRasterizer.exportWidth)));
    final onScrim = haloOf(t);

    await t.pumpWidget(host(const ReelWatermarkMark(
        width: AyahRasterizer.exportWidth, undimmed: true)));
    final onCard = haloOf(t);

    expect(onCard.color.a, greaterThan(onScrim.color.a));
    expect(onCard.blurRadius, greaterThan(onScrim.blurRadius));
    // Quiet either way — that is the point of it. The halo carries the
    // mark; it does not become the mark.
    expect(onCard.color.a, lessThan(0.85));
  });

  testWidgets('the mark shrink-wraps, so the exported PNG stays small',
      (t) async {
    // Loose constraints, as the rasterizer's centered boundary gives
    // it — a tight box would stretch the Row and hide the shrink-wrap.
    await t.pumpWidget(host(
        const Center(child: ReelWatermarkMark(width: AyahRasterizer.exportWidth))));

    // Cropping only pays if the mark is small relative to the frame —
    // that is the entire point of it.
    final markBox = t.getRect(find.byType(ReelWatermarkMark));
    expect(markBox.width, lessThan(frame.width / 2));
    expect(markBox.height, lessThan(frame.height / 8));
  });
}
