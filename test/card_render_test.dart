import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/card_compose.dart';
import 'package:ayah_reels/data/card_deck.dart';
import 'package:ayah_reels/data/card_style.dart';
import 'package:ayah_reels/data/dedication.dart';
import 'package:ayah_reels/data/reel_effects.dart';
import 'package:ayah_reels/render/card_exporter.dart';
import 'package:ayah_reels/theme/app_theme.dart' show AppColors;
import 'package:ayah_reels/widgets/card_canvas.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getTemporaryPath() async => dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// What comes out of the exporter, in pixels.
///
/// The composer is the only preview a card ever gets, so "the file is
/// what was on screen" is not a nicety — it is the whole contract. It
/// holds because both sides rasterize the same widget at different
/// widths, and the only way to check that it still holds is to
/// rasterize both and measure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    // The runner has no network, and the app's mark is set in a
    // google_fonts face. On a phone it resolves; here it cannot, and
    // asking anyway produces a late exception per capture. Turning
    // fetching off makes the mark fall back exactly as it would on a
    // phone with no connection — which is a picture the app is
    // expected to draw correctly anyway.
    GoogleFonts.config.allowRuntimeFetching = false;
    const files = {
      'HafsUthmani': ['assets/fonts/UthmanicHafs.ttf'],
      'AmiriQuran': ['assets/fonts/AmiriQuran.ttf'],
      'NotoNaskhArabic': ['assets/fonts/NotoNaskhArabic.ttf'],
      'CormorantGaramond': ['assets/fonts/CormorantGaramond.ttf'],
      'Inter': ['assets/fonts/Inter.ttf'],
    };
    for (final entry in files.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('card_render_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDown(() {
    try {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {/* Windows holds the handle; the runner cleans up */}
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
  });

  /// google_fonts reports a disabled fetch as an error per face. Those
  /// are noise here; anything else still fails the test.
  void drainFontComplaints(WidgetTester t) {
    for (var e = t.takeException(); e != null; e = t.takeException()) {
      if (!e.toString().contains('allowRuntimeFetching') &&
          !e.toString().contains('Failed to load font')) {
        throw e;
      }
    }
  }

  const ayah = 'وَقُل رَّبِّ زِدْنِى عِلْمًا';

  CardDeck deckOf(CardFormat format,
      {CardTemplate template = CardTemplate.classic, int cards = 1}) {
    return CardDeck(
      id: 'deck',
      format: format,
      slides: [
        for (var i = 0; i < cards; i++)
          CardCompose.quote(
            id: 'card$i',
            text: ayah,
            translation: 'And say, "My Lord, increase me in knowledge."',
            reference: 'Ta-Ha · 20:114',
            format: format,
            template: template,
            quran: true,
          ),
      ],
      createdAt: DateTime(2026, 3, 12, 9, 5),
      updatedAt: DateTime(2026, 3, 12, 9, 5),
    );
  }

  Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  /// How much of the card is not the paper it was drawn on — the ink,
  /// the frame and the mark together, as a fraction of the whole.
  ///
  /// Measured against the *row's own* left edge rather than against
  /// one corner: every paper here is a gradient, so a card compared
  /// against its top pixel reads as half-covered before anything has
  /// been drawn on it. Nothing a card draws reaches x = 0 — the widest
  /// frame is inset by 4.8% — so the first pixel of a row is that
  /// row's paper by construction.
  Future<double> inkFraction(ui.Image image) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = data.buffer.asUint8List();
    var drawn = 0;
    for (var y = 0; y < image.height; y++) {
      final row = y * image.width * 4;
      final r0 = px[row], g0 = px[row + 1], b0 = px[row + 2];
      for (var x = 0; x < image.width; x++) {
        final i = row + x * 4;
        final d = (px[i] - r0).abs() + (px[i + 1] - g0).abs() +
            (px[i + 2] - b0).abs();
        if (d > 24) drawn++;
      }
    }
    return drawn / (image.width * image.height);
  }

  /// The red, green and blue of one pixel of bare paper — the top-left
  /// corner, which nothing a card draws ever reaches.
  Future<(int, int, int)> paperCorner(ui.Image image) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final px = data.buffer.asUint8List();
    return (px[0], px[1], px[2]);
  }

  testWidgets('a card is exported at 1080 across, in the shape asked for',
      (t) async {
    await t.runAsync(() async {
      for (final format in CardFormat.values) {
        final files = await CardExporter.render(deckOf(format));
        expect(files, hasLength(1));
        final image = await decode(await files.first.readAsBytes());
        expect(image.width, 1080);
        expect(image.height, format.exportHeight.round());
        image.dispose();
      }
    });
    drainFontComplaints(t);
  });

  testWidgets('every card of a deck is exported, in order and named for '
      'its place', (t) async {
    await t.runAsync(() async {
      final deck = deckOf(CardFormat.portrait, cards: 3);
      final files = await CardExporter.render(deck);
      expect(files, hasLength(3));
      for (var i = 0; i < 3; i++) {
        expect(files[i].existsSync(), isTrue);
        expect(files[i].lengthSync(), greaterThan(1000));
        expect(CardExporter.name(deck, i), endsWith('_0${i + 1}'));
      }
      // A deck of one is not a carousel and is not numbered like one.
      expect(CardExporter.name(deckOf(CardFormat.square), 0),
          isNot(contains('_01')));
    });
    drainFontComplaints(t);
  });

  testWidgets('the same card at a third of the size is the same picture',
      (t) async {
    await t.runAsync(() async {
      final deck = deckOf(CardFormat.portrait);
      final full = await decode(
          Uint8List.fromList(await (await CardExporter.render(deck)).first
              .readAsBytes()));
      final small = await decode(Uint8List.fromList(await CardExporter.cover(
        deck: deck,
        slide: deck.slides.first,
      )));
      expect(small.width, 360);
      expect(small.height, (360 / deck.format.aspect).round());
      final a = await inkFraction(full);
      final b = await inkFraction(small);
      expect(a, greaterThan(0.01), reason: 'nothing was drawn at all');
      // Antialiasing spends proportionally more of a small card on
      // edges, so the two are never equal — but a card whose type did
      // not scale with it would be out by a multiple, not by a third.
      expect(b, closeTo(a, a * 0.45));
      full.dispose();
      small.dispose();
    });
    drainFontComplaints(t);
  });

  testWidgets('a frame, a vignette and grain all reach the file',
      (t) async {
    await t.runAsync(() async {
      // Same card three times over, with one thing changed each time,
      // measured in pixels. A control that does nothing to the file is
      // worse than no control: the composer showed it working.
      final base = deckOf(CardFormat.square, template: CardTemplate.page);
      Future<ui.Image> shot(CardSlide slide) async => decode(
          await (await CardExporter.render(base.copyWith(slides: [slide])))
              .first
              .readAsBytes());

      final plain = base.slides.first.copyWith(frame: CardFrame.none);
      final bare = await shot(plain);
      final framed = await shot(plain.copyWith(frame: CardFrame.khatam));
      expect(await inkFraction(framed), greaterThan(await inkFraction(bare)),
          reason: 'the frame drew nothing');

      // The vignette darkens the corners and leaves the middle alone.
      final vignetted = await shot(
          plain.copyWith(effects: const ReelEffects(vignette: 0.8)));
      expect(await _luma(vignetted, 12, 12),
          lessThan(await _luma(bare, 12, 12) - 12),
          reason: 'the vignette did not darken the corner');
      expect(await _luma(vignetted, bare.width ~/ 2, 40),
          closeTo(await _luma(bare, bare.width ~/ 2, 40), 14),
          reason: 'the vignette reached the middle of the card');

      // Grain is texture rather than tone: it raises the variation
      // across a patch of flat paper without moving its average.
      final grained =
          await shot(plain.copyWith(effects: const ReelEffects(grain: 0.9)));
      expect(await _spread(grained), greaterThan(await _spread(bare) + 1.5),
          reason: 'the grain drew nothing');

      for (final image in [bare, framed, vignetted, grained]) {
        image.dispose();
      }
    });
    drainFontComplaints(t);
  });

  testWidgets('a dedication is drawn above the mark, and reaches the '
      'file', (t) async {
    await t.runAsync(() async {
      // A template with no frame: a frame's side rules run through
      // every band of the card, including the one being measured.
      final plain = deckOf(CardFormat.square, template: CardTemplate.quiet);
      final gifted = CardDeck(
        id: plain.id,
        format: plain.format,
        slides: plain.slides,
        createdAt: plain.createdAt,
        updatedAt: plain.updatedAt,
        dedication: const Dedication(name: 'Maryam'),
      );
      final bare = await decode(
          await (await CardExporter.render(plain)).first.readAsBytes());
      final signed = await decode(
          await (await CardExporter.render(gifted)).first.readAsBytes());
      expect(await inkFraction(signed), greaterThan(await inkFraction(bare)),
          reason: 'the dedication drew nothing');
      // Above the mark, not over it. The mark's own box bottoms out
      // at [markInset] of the width; the strip above that is empty on
      // a card nobody dedicated and carries the line on one that is.
      final markTop = signed.height -
          (CardCanvasMetrics.markInset * signed.width).round() -
          34;
      expect(await _drawnBetween(bare, markTop - 70, markTop - 6),
          lessThan(80),
          reason: 'something was already drawn above the mark');
      expect(await _drawnBetween(signed, markTop - 70, markTop - 6),
          greaterThan(300),
          reason: 'the dedication was not drawn above the mark');
      bare.dispose();
      signed.dispose();
    });
    drainFontComplaints(t);
  });

  test('the dedication can be read off every paper a card stands on',
      () {
    // The gold the dedication is set in on a light paper. It is the
    // one line on the frame somebody is meant to read after the verse
    // — a name, on a card made as a gift — and it is burned into the
    // export, so a colour that disappears into the paper cannot be
    // fixed afterwards. [AppColors.gold] is tuned against the app's own
    // night and manages about 2:1 on these three.
    double luminance(int argb) {
      double channel(int c) {
        final v = c / 255;
        return v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * channel((argb >> 16) & 0xFF) +
          0.7152 * channel((argb >> 8) & 0xFF) +
          0.0722 * channel(argb & 0xFF);
    }

    double contrast(int a, int b) {
      final la = luminance(a), lb = luminance(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    final light = CardPaper.values.where((p) => p.light);
    expect(light, isNotEmpty);
    for (final paper in light) {
      expect(contrast(AppColors.goldDeep.toARGB32(), paper.topArgb),
          greaterThanOrEqualTo(4.5),
          reason: 'the dedication is unreadable on ${paper.name}');
    }
  });

  testWidgets('a look grades a card that stands on paper, not only one '
      'on a photograph', (t) async {
    await t.runAsync(() async {
      // The grade used to be wrapped around the photograph alone, so
      // on every card that was not on a scenery — which is five of the
      // six templates — Golden hour, Dusk and Moonlight, and the
      // warmth and vibrance sliders under them, changed nothing at
      // all. The paper is the ground when there is no picture, and the
      // grade is a grade of the ground.
      final plain = deckOf(CardFormat.portrait);
      final lit = plain.copyWith(slides: [
        for (final slide in plain.slides)
          slide.copyWith(
            effects: ReelEffects.off.copyWith(look: ReelLook.golden),
          ),
      ]);
      final before = await decode(
          await (await CardExporter.render(plain)).first.readAsBytes());
      final after = await decode(
          await (await CardExporter.render(lit)).first.readAsBytes());

      // The corner, which is paper and nothing else: no ink, no frame,
      // no mark. Warmer than it was, and warmer by more than rounding.
      final a = await paperCorner(before);
      final b = await paperCorner(after);
      expect(b, isNot(a), reason: 'the paper was not graded at all');
      // Golden hour holds the reds and gives away the blues, so the
      // corner comes out warmer than it went in. Measured as the gap
      // between the two channels rather than as either one on its
      // own: the night paper's corner is nearly black, and on a pixel
      // that dark a 7% gain is worth less than a whole step.
      expect(b.$1 - b.$3, greaterThan(a.$1 - a.$3),
          reason: 'the grade did not warm the paper');
      expect(b.$3, lessThan(a.$3), reason: 'the blues were not given away');
      before.dispose();
      after.dispose();
    });
    drainFontComplaints(t);
  });

  testWidgets('a card re-cuts itself for a story, and the mark climbs '
      'clear of Instagram', (t) async {
    await t.runAsync(() async {
      final deck = deckOf(CardFormat.portrait);
      final story = await CardExporter.render(deck, asStory: true);
      final image = await decode(await story.first.readAsBytes());
      expect(image.width, 1080);
      expect(image.height, 1920, reason: 'it was not re-cut');

      // The mark sits where the reels put theirs: above the bar
      // Instagram draws along the bottom of a story.
      final band = image.height -
          (CardCanvasMetrics.storyMarkInset * image.width).round() -
          8;
      expect(await _drawnBetween(image, band - 12, band + 12),
          greaterThan(120),
          reason: 'no mark in the story band');
      expect(CardCanvasMetrics.storyMarkInset,
          greaterThan(CardCanvasMetrics.markInset));
      image.dispose();
    });
    drainFontComplaints(t);
  });

  testWidgets('the mark is on every card, in every shape', (t) async {
    await t.runAsync(() async {
      for (final format in CardFormat.values) {
        final deck = deckOf(format, template: CardTemplate.page);
        final image = await decode(
            await (await CardExporter.render(deck)).first.readAsBytes());
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final px = data.buffer.asUint8List();
        // The band the mark sits in, measured the way the canvas
        // places it: [markInset] of the width above the bottom edge.
        final centre = (image.height -
                (CardCanvasMetrics.markInset * image.width).round() -
                8)
            .clamp(0, image.height - 1);
        var drawn = 0;
        for (var y = centre - 10; y <= centre + 10; y++) {
          final row = y * image.width * 4;
          final r0 = px[row], g0 = px[row + 1], b0 = px[row + 2];
          for (var x = 0; x < image.width; x++) {
            final i = row + x * 4;
            final d = (px[i] - r0).abs() + (px[i + 1] - g0).abs() +
                (px[i + 2] - b0).abs();
            if (d > 24) drawn++;
          }
        }
        expect(drawn, greaterThan(120),
            reason: 'no mark on a ${format.name} card');
        image.dispose();
      }
    });
    drainFontComplaints(t);
  });
}

/// The brightness of one pixel, 0..255.
Future<double> _luma(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = data.buffer.asUint8List();
  final i = (y * image.width + x) * 4;
  return 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
}

/// How much the brightness varies across a patch of the card that
/// should be flat paper — the middle-left, above the words.
Future<double> _spread(ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = data.buffer.asUint8List();
  final values = <double>[];
  for (var y = 90; y < 150; y++) {
    for (var x = 90; x < 150; x++) {
      final i = (y * image.width + x) * 4;
      values.add(0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2]);
    }
  }
  final mean = values.reduce((a, b) => a + b) / values.length;
  var sum = 0.0;
  for (final v in values) {
    sum += (v - mean) * (v - mean);
  }
  return math.sqrt(sum / values.length);
}

/// Pixels between two rows that differ from their own row's left edge —
/// the strip of card between [from] and [to], measured the way
/// `inkFraction` measures the whole of it.
Future<int> _drawnBetween(ui.Image image, int from, int to) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = data.buffer.asUint8List();
  var drawn = 0;
  for (var y = from.clamp(0, image.height - 1);
      y <= to.clamp(0, image.height - 1);
      y++) {
    final row = y * image.width * 4;
    final r0 = px[row], g0 = px[row + 1], b0 = px[row + 2];
    for (var x = 0; x < image.width; x++) {
      final i = row + x * 4;
      final d = (px[i] - r0).abs() + (px[i + 1] - g0).abs() +
          (px[i + 2] - b0).abs();
      if (d > 24) drawn++;
    }
  }
  return drawn;
}
