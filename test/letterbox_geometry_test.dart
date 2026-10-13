import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/render/letterbox_layout.dart';
import 'package:ayah_reels/state/creation_state.dart';
import 'package:ayah_reels/widgets/reel_watermark.dart';

/// The letterbox format's card box and verse band are computed once and
/// read twice: Flutter lays the preview out with them, FFmpeg composites
/// the export with them. Nothing at runtime would catch the two drifting
/// — the preview would keep looking right while every exported reel put
/// the verse somewhere else.
///
/// So: pin the geometry, and pin that the FFmpeg expression really is
/// the same arithmetic the preview's [Align] performs.
void main() {
  /// Evaluates the `TOP+(BAND-h)*ALIGN` form [LetterboxGeometry.verseYExpr]
  /// emits, so the test checks the string FFmpeg will actually be given
  /// rather than a Dart method that happens to sit beside it.
  double evalVerseY(String expr, double h) {
    final m = RegExp(r'^([\d.]+)\+\(([\d.]+)-h\)\*([\d.]+)$').firstMatch(expr);
    expect(m, isNotNull, reason: 'unexpected expression shape: $expr');
    return double.parse(m!.group(1)!) +
        (double.parse(m.group(2)!) - h) * double.parse(m.group(3)!);
  }

  group('card box', () {
    test('a 16:9 source keeps its shape, inset from both edges', () {
      final box = LetterboxGeometry.of(16 / 9);
      expect(box.cardW, LetterboxGeometry.frameW - 2 * LetterboxGeometry.inset);
      expect(box.cardW / box.cardH, closeTo(16 / 9, 0.01));
      expect(box.cardX, LetterboxGeometry.inset);
      // Sits above centre, so the band below it is the larger one.
      expect(box.cardY, lessThan((LetterboxGeometry.frameH - box.cardH) / 2));
    });

    test('dimensions stay even, whatever the source aspect', () {
      for (final a in [16 / 9, 4 / 3, 2.39, 1.0, 1.91, 0.5625]) {
        final box = LetterboxGeometry.of(a);
        expect(box.cardH % 2, 0, reason: 'aspect $a gave height ${box.cardH}');
        expect(box.cardY % 2, 0, reason: 'aspect $a gave top ${box.cardY}');
      }
    });

    test('a portrait source crops to a square rather than filling the frame',
        () {
      // The whole point of the format is the band under the card. A
      // 9:16 upload would swallow it whole if the aspect were honoured.
      final box = LetterboxGeometry.of(9 / 16);
      expect(box.cardH, box.cardW);
      expect(box.bandHeight, greaterThan(400));
    });

    test('a scope source never thins past the clamp', () {
      final box = LetterboxGeometry.of(3.5);
      expect(box.cardW / box.cardH,
          closeTo(LetterboxGeometry.maxAspect, 0.01));
    });

    test('a source of unknown shape falls back rather than dividing by zero',
        () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final box = LetterboxGeometry.of(bad);
        expect(box.cardH, greaterThan(0));
        expect(box.cardH.isFinite, isTrue);
      }
    });
  });

  group('verse band', () {
    final box = LetterboxGeometry.of(16 / 9);

    test('sits entirely below the card and clear of the watermark', () {
      expect(box.bandTop, box.cardY + box.cardH);
      // The mark hangs off the card's bottom edge, which is the band's
      // top edge — so the band is clear of it by construction, and the
      // whole band is the verse's. Pin the direction of that: the mark
      // sits above where the verse begins, never inside it.
      expect(LetterboxGeometry.frameH - ReelWatermark.insetFor(box),
          lessThanOrEqualTo(box.bandTop));
      expect(box.bandTop + box.bandHeight,
          lessThan(LetterboxGeometry.frameH));
    });

    test('the exporter expression is the arithmetic the preview uses', () {
      for (final align in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        for (final h in [120.0, 300.0, 900.0]) {
          expect(
            evalVerseY(box.verseYExpr(align), h),
            closeTo(box.verseTop(h, align), 0.6), // expression is rounded
            reason: 'align $align, overlay height $h',
          );
        }
      }
    });

    test('an overlay taller than the band overhangs, it does not re-centre',
        () {
      // Preview and export must agree even in the broken case; silently
      // centring in one of them is how they would stop agreeing.
      final tall = box.bandHeight + 200;
      expect(box.verseTop(tall, 0), box.bandTop);
      expect(evalVerseY(box.verseYExpr(0), tall), closeTo(box.bandTop, 0.6));
    });
  });

  testWidgets('the preview Align lands where verseTop says it will',
      (t) async {
    // The preview places the verse with an Align inside the band rather
    // than at an offset. This is the only test of the claim that those
    // are the same thing.
    final box = LetterboxGeometry.of(16 / 9);
    const align = 0.75;
    const overlayH = 260.0;

    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: LetterboxGeometry.frameW,
          height: LetterboxGeometry.frameH,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: box.bandTop,
                height: box.bandHeight,
                child: const Align(
                  alignment: Alignment(0, align * 2 - 1),
                  child: SizedBox(
                      key: ValueKey('verse'), height: overlayH, width: 400),
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    final stage = t.getRect(find.byType(Stack));
    final verse = t.getRect(find.byKey(const ValueKey('verse')));
    expect(verse.top - stage.top,
        closeTo(box.verseTop(overlayH, align), 0.01));
  });

  testWidgets('a verse too tall for the band overhangs it, unsqueezed',
      (t) async {
    // The band under a portrait source is the shortest this format
    // ever leaves — the card crops to a square — and the verse card at
    // the largest text size does not fit in it. The export places it
    // anyway, overhanging, because [verseTop] is deliberately
    // unclamped. The preview has to do the same thing, and an Align
    // cannot: it hands the card the band's height as a *limit*, so the
    // card came back squeezed to fit, landed at the wrong offset, and
    // Flutter drew the striped overflow bar over the preview to say
    // so. Hence the OverflowBox, which is this arithmetic exactly.
    final box = LetterboxGeometry.of(1080 / 1920);
    const align = 0.5;
    final overlayH = box.bandHeight + 300;

    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: LetterboxGeometry.frameW,
          height: LetterboxGeometry.frameH,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: box.bandTop,
                height: box.bandHeight,
                child: OverflowBox(
                  alignment: const Alignment(0, align * 2 - 1),
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: SizedBox(
                      key: const ValueKey('verse'),
                      height: overlayH,
                      width: 400),
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    expect(t.takeException(), isNull, reason: 'nothing overflows a flex');
    final stage = t.getRect(find.byType(Stack));
    final verse = t.getRect(find.byKey(const ValueKey('verse')));
    expect(verse.height, overlayH, reason: 'the card keeps its own height');
    expect(verse.top - stage.top,
        closeTo(box.verseTop(overlayH, align), 0.01));
  });

  group('legible ink', () {
    test('flips to dark only on backdrops light enough to need it', () {
      expect(legibleInkOn(0xFF000000), 0xFFFFFFFF);
      expect(legibleInkOn(0xFF14181D), 0xFFFFFFFF);
      expect(legibleInkOn(0xFF0E2A22), 0xFFFFFFFF);
      expect(legibleInkOn(0xFF101A2E), 0xFFFFFFFF);
      expect(legibleInkOn(0xFFFFFFFF), isNot(0xFFFFFFFF));
      expect(legibleInkOn(0xFFF3EADA), isNot(0xFFFFFFFF));
    });

    test('every offered swatch leaves the verse readable', () {
      for (final argb in letterboxBackdropSwatches) {
        final ink = legibleInkOn(argb);
        expect(ink == 0xFFFFFFFF || ink == 0xFF15181C, isTrue);
        // Whatever it picks must actually contrast with the band.
        double lum(int c) =>
            (0.2126 * ((c >> 16) & 0xFF) +
                0.7152 * ((c >> 8) & 0xFF) +
                0.0722 * (c & 0xFF)) /
            255;
        expect((lum(ink) - lum(argb)).abs(), greaterThan(0.5),
            reason: 'swatch ${argb.toRadixString(16)}');
      }
    });
  });

  group('creation state', () {
    test('a default white verse follows the backdrop; a chosen colour does not',
        () {
      final s = CreationState()
        ..setLayout(ReelLayout.letterbox)
        ..setBackdropColor(0xFFFFFFFF);
      expect(s.textArgb, isNot(0xFFFFFFFF),
          reason: 'white on white is not a choice anyone means to make');

      s.setBackdropColor(0xFF000000);
      expect(s.textArgb, 0xFFFFFFFF);

      s
        ..setTextColor(0xFFEEC96B) // gold: a decision
        ..setBackdropColor(0xFFFFFFFF);
      expect(s.textArgb, 0xFFEEC96B);
    });

    test('full frame leaves the verse colour alone', () {
      final s = CreationState()..setBackdropColor(0xFFFFFFFF);
      expect(s.textArgb, 0xFFFFFFFF);
    });

    // Leaving the letterbox puts the verse back on the darkened
    // picture, where the dark ink the pale band called for would all
    // but vanish.
    test('a default ink follows the verse back out of the letterbox', () {
      final s = CreationState()
        ..setLayout(ReelLayout.letterbox)
        ..setBackdropColor(0xFFFFFFFF);
      expect(s.textArgb, inkOnLight);

      s.setLayout(ReelLayout.fullFrame);
      expect(s.textArgb, inkOnDark);
    });

    test('a blurred backdrop is never treated as a pale ground', () {
      final s = CreationState()
        ..setLayout(ReelLayout.letterbox)
        ..setBackdropColor(0xFFFFFFFF);
      expect(s.onLightGround, isTrue);

      // The exporter darkens the blur by a fixed amount, so it is a
      // dark ground whatever the scenery underneath it was.
      s.setBackdrop(LetterboxBackdrop.blur);
      expect(s.onLightGround, isFalse);
      expect(s.textArgb, inkOnDark);
    });

    test('only a pale letterbox band counts as light ground', () {
      for (final argb in letterboxBackdropSwatches) {
        expect(
          isLightGround(
            layout: ReelLayout.fullFrame,
            backdrop: LetterboxBackdrop.colour,
            backdropArgb: argb,
          ),
          isFalse,
          reason: 'full frame always darkens the picture with the scrim',
        );
      }
      expect(
        isLightGround(
          layout: ReelLayout.letterbox,
          backdrop: LetterboxBackdrop.colour,
          backdropArgb: 0xFFF3EADA, // ivory
        ),
        isTrue,
      );
      expect(
        isLightGround(
          layout: ReelLayout.letterbox,
          backdrop: LetterboxBackdrop.colour,
          backdropArgb: 0xFF000000,
        ),
        isFalse,
      );
    });
  });
}
