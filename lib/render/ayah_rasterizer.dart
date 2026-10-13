import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/models.dart';
import '../data/reel_effects.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
import '../data/whole_file.dart';
import '../state/creation_state.dart' show TextPreset;
import '../widgets/ayah_overlay.dart';
import '../widgets/reel_watermark.dart';
import 'letterbox_layout.dart';
import 'on_screen.dart';
import 'render_dir.dart';

/// A rasterized verse card and the height it laid out to.
///
/// How tall the card is used to be FFmpeg's business alone —
/// [LetterboxGeometry.verseYExpr] leaves `h` to it on purpose, since it
/// is the only one holding the PNG. But the mark now hangs off the
/// card's bottom edge in full frame, and the filter graph has to be
/// written knowing where that edge lands, so the height comes back with
/// the file.
typedef VerseCard = ({File file, double height});

/// Renders [AyahOverlay] widgets to transparent PNGs off-screen.
///
/// Because the exporter rasterizes the very widget the preview shows,
/// the exported video cannot drift from what the user approved.
abstract final class AyahRasterizer {
  static const exportWidth = 1080.0;

  static Future<void>? _fontWarmUp;

  /// Resolves the one face a capture still has to wait for.
  ///
  /// Every face a *verse card* is typeset in is bundled and registered
  /// at startup — see `lib/data/verse_font.dart`, which is largely
  /// about why — so the card itself resolves synchronously and cannot
  /// be shaped against a font that has not landed. The watermark is
  /// the exception: its wordmark is still set in google_fonts' Inter,
  /// which resolves asynchronously, and shaping against one that
  /// hasn't landed silently bakes the fallback into the PNG.
  ///
  /// Reading the style is what queues the load — `pendingFonts()` with
  /// no argument waits on what is already in flight, and waits on
  /// nothing at all if nothing has asked yet. So the mark's face is
  /// touched here rather than left to the capture that needs it: by
  /// the time that capture builds and paints, in one synchronous pass,
  /// it is far too late to start a download.
  ///
  /// It matters more here than anywhere else because the mark is
  /// rasterized once and *kept*: `ayah_wm_v4.png` is written on the
  /// first export and read back forever after. An install whose first
  /// export happened before the face landed would burn the fallback
  /// into every reel it ever made.
  ///
  /// Waiting on the load is exact where the fixed 60ms delay this
  /// replaces was a guess, and it happens once instead of once per
  /// capture — a word-highlighted reel rasterizes up to 120 cards, so
  /// that delay alone spent about seven seconds of every render doing
  /// nothing at all. Offline, the load completes as a failure and
  /// shaping falls back exactly as the preview's does, which is the
  /// picture the user approved.
  static Future<void> _warmFonts() => _fontWarmUp ??= () async {
        // The exact variant [ReelWatermarkMark] sets the wordmark in.
        // Not the app's own text theme, which asks for a different
        // weight — and, in Arabic and Urdu, a different family
        // altogether, so nothing else in the process would ever queue
        // this one.
        GoogleFonts.inter(fontWeight: FontWeight.w500);
        try {
          await GoogleFonts.pendingFonts();
        } catch (_) {}
      }();

  /// Returns one PNG file per ayah — with the height it shrink-wrapped
  /// to, see [VerseCard] — transparent background, laid out at export
  /// resolution. [fileTag] namespaces the files so renders with
  /// different styling never overwrite each other mid-session.
  ///
  /// [onProgress] reports 0..1 across the set. A handful of cards is
  /// done before anything could show it; a long reel's few hundred are
  /// a real wait, and one the export's progress bar should be spending
  /// rather than sitting at zero through.
  static Future<List<VerseCard>> rasterize(
    List<Ayah> ayahs, {
    Color textColor = Colors.white,
    double textScale = 1.0,
    TextPreset preset = TextPreset.classic,
    bool onLight = false,
    ReelTypography typography = const ReelTypography(),
    Color? accent,

    /// The luminous inks, if any; see [VerseInk].
    VerseInk ink = VerseInk.none,
    VerseInk accentInk = VerseInk.none,

    /// The edition the translation line is in. Passed rather than read
    /// off Settings so an export cannot disagree with the preview the
    /// user approved — and so the caller is obliged to put it in its
    /// cache key, which is the half of this that was missing.
    VerseTranslation? edition,

    /// The verse numbering and the surah its reference names. Passed
    /// for the same reason [edition] is, and owed to the cache key for
    /// the same reason.
    VerseNumbering numbering = VerseNumbering.off,
    int surah = 0,

    /// False leaves the rule and the translation line off the card.
    /// Owed to the cache key, like [edition].
    bool showTranslation = true,
    String fileTag = '',
    void Function(double progress)? onProgress,

    /// Asked before each card: false stops the drawing there, and what
    /// was drawn so far comes back. A render cancelled with hundreds of
    /// cards to go would otherwise keep the UI isolate drawing them all.
    bool Function()? keepGoing,
  }) async {
    final dir = await renderDir();
    final out = <VerseCard>[];
    for (final ayah in ayahs) {
      if (keepGoing != null && !keepGoing()) break;
      final shot = await _capture(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(exportWidth, 1920),
            devicePixelRatio: 1.0,
          ),
          // No Center wrapper: the boundary must shrink-wrap the text so
          // the PNG is tight to content — vertical placement in FFmpeg
          // positions the PNG itself, not empty padding around it.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: AyahOverlay(
              ayah: ayah,
              width: exportWidth,
              textColor: textColor,
              textScale: textScale,
              preset: preset,
              onLight: onLight,
              translation: edition,
              numbering: numbering,
              showTranslation: showTranslation,
              surah: surah,
              verseFace: typography.verse,
              translationFace: typography.translation,
              accent: accent,
              ink: ink,
              accentInk: accentInk,
            ),
          ),
        ),
      );
      final f = File('${dir.path}/ayah_$fileTag${ayah.number}.png');
      await writeWholeBytes(f, shot.bytes);
      out.add((file: f, height: shot.height));
      onProgress?.call(out.length / ayahs.length);
    }
    return out;
  }


  /// One PNG of [ayah] with display tokens [tokenStart, tokenEnd) in
  /// the highlight color — the exporter shows it during that word's
  /// window. Color-only variant of the base card, so it lands on the
  /// exact same pixels.
  static Future<File> rasterizeHighlight(
    Ayah ayah, {
    required int tokenStart,
    required int tokenEnd,
    Color textColor = Colors.white,
    double textScale = 1.0,
    TextPreset preset = TextPreset.classic,
    bool onLight = false,
    ReelTypography typography = const ReelTypography(),
    Color? accent,
    VerseInk ink = VerseInk.none,
    VerseInk accentInk = VerseInk.none,
    VerseTranslation? edition,
    VerseNumbering numbering = VerseNumbering.off,
    int surah = 0,
    bool showTranslation = true,
    String fileTag = '',
  }) async {
    final dir = await renderDir();
    final bytes = await widgetToPng(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(exportWidth, 1920),
          devicePixelRatio: 1.0,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AyahOverlay(
            ayah: ayah,
            width: exportWidth,
            textColor: textColor,
            textScale: textScale,
            preset: preset,
            onLight: onLight,
            translation: edition,
            numbering: numbering,
            showTranslation: showTranslation,
            surah: surah,
            verseFace: typography.verse,
            translationFace: typography.translation,
            accent: accent,
            ink: ink,
            accentInk: accentInk,
            highlightTokens: (start: tokenStart, end: tokenEnd),
          ),
        ),
      ),
    );
    final f = File(
        '${dir.path}/ayah_$fileTag${ayah.number}_w${tokenStart}_$tokenEnd.png');
    await writeWholeBytes(f, bytes);
    return f;
  }

  /// The AyahReel mark, shrink-wrapped to its own glyphs plus a margin
  /// wide enough for the text shadow. The exporter overlays it where
  /// [ReelWatermark] draws it in the preview — see [watermarkInsetFor]
  /// for the shared arithmetic.
  ///
  /// Cropped rather than full-frame because FFmpeg's overlay blends the
  /// overlay's entire area on every frame: a 1080x1920 mostly-empty PNG
  /// spent a full-frame alpha blend per frame to draw a mark that
  /// occupies about 2% of it.
  ///
  /// [undimmed] draws the variant for the inside of a letterbox card,
  /// which no scrim darkens; the two are cached side by side, since a
  /// reel can be exported either way in one session.
  ///
  /// The _v4 in the name versions the design: bump it if the mark ever
  /// changes, or exports would reuse the old PNG.
  static Future<File> rasterizeWatermark({bool undimmed = false}) async {
    final dir = await renderDir();
    final f = File('${dir.path}/ayah_wm_v4${undimmed ? '_card' : ''}.png');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    final bytes = await widgetToPng(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(exportWidth, 1920),
          devicePixelRatio: 1.0,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.all(ReelWatermarkMark.shadowMargin),
            child: ReelWatermarkMark(
              width: exportWidth,
              undimmed: undimmed,
            ),
          ),
        ),
      ),
    );
    await writeWholeBytes(f, bytes);
    return f;
  }

  /// Distance from the bottom of the frame to the bottom of the
  /// *watermark PNG* — the mark's own inset less the transparent
  /// shadow margin baked into the PNG. FFmpeg positions the overlay at
  /// `H-h-watermarkInsetFor(...)`, landing the glyphs exactly where
  /// [ReelWatermark] puts them in the preview — which is why this takes
  /// the same geometry the preview lays out from.
  static double watermarkInsetFor(LetterboxGeometry? letterbox,
          {double? verseBottom}) =>
      ReelWatermark.insetFor(letterbox, verseBottom: verseBottom) -
      ReelWatermarkMark.shadowMargin;

  /// The dedication — "A gift for Aisha" — shrink-wrapped to its
  /// glyphs plus the shadow margin, exactly as [rasterizeWatermark]
  /// does the mark and for the same reason. The exporter lays it along
  /// the bottom of the frame where [ReelDedication] draws it in the
  /// preview; see [dedicationInset].
  ///
  /// The line is in the file name because these PNGs are written once
  /// and read back forever: two dedications sharing a name would mean
  /// the second reel was signed with the first one's. So is the
  /// ground, since a pale band flips the line's ink and halo.
  ///
  /// The _v1 versions the design: bump it if the line ever changes.
  static Future<File> rasterizeDedication(String line,
      {bool onLight = false}) async {
    final dir = await renderDir();
    final tag = line.hashCode.toUnsigned(32).toRadixString(36);
    final f = File(
        '${dir.path}/ayah_ded_v1_$tag${onLight ? '_lt' : ''}.png');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    final bytes = await widgetToPng(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(exportWidth, 1920),
          devicePixelRatio: 1.0,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.all(ReelWatermarkMark.shadowMargin),
            child: ReelDedicationLine(
              width: exportWidth,
              line: line,
              onLight: onLight,
            ),
          ),
        ),
      ),
    );
    await writeWholeBytes(f, bytes);
    return f;
  }

  /// Distance from the bottom of the frame to the bottom of the
  /// *dedication PNG*: [ReelDedication.frameInset] less the shadow
  /// margin baked into the PNG, the same arithmetic as
  /// [watermarkInsetFor]. FFmpeg overlays it at `H-h-dedicationInset`.
  static const double dedicationInset =
      ReelDedication.frameInset - ReelWatermarkMark.shadowMargin;

  /// A white rounded rectangle on black, exactly the size of the
  /// letterbox card. FFmpeg's `alphamerge` reads its luma as the card's
  /// alpha, so the corners are shaped once, here, instead of being
  /// computed per pixel on every frame of the encode — and they are cut
  /// by the same rasterizer that draws the preview's, so the two curves
  /// match.
  static Future<File> rasterizeCardMask({
    required double width,
    required double height,
    required double radius,
  }) async {
    final dir = await renderDir();
    final f = File('${dir.path}/ayah_cardmask_${width.round()}x'
        '${height.round()}_r${radius.round()}.png');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    final bytes = await widgetToPng(
      SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _CardMaskPainter(radius)),
      ),
    );
    await writeWholeBytes(f, bytes);
    return f;
  }

  /// The legibility scrim the preview draws over every background:
  /// black fading 15% -> 45% top to bottom. Exported as a translucent
  /// full-frame PNG so FFmpeg composites exactly what the user saw
  /// (a flat darken looks completely different).
  ///
  /// A vignette is painted into this same PNG rather than overlaid
  /// separately, which is what makes it free: full frame already
  /// blends one translucent layer over every frame, and darkening the
  /// corners of that layer costs the encode nothing at all. The
  /// preview stacks the two decorations in the same order, and alpha
  /// compositing is associative, so the two agree.
  static Future<File> rasterizeScrim({double vignette = 0}) async {
    final dir = await renderDir();
    final f = File('${dir.path}/ayah_scrim'
        '${vignette == 0 ? '' : '_v${(vignette * 100).round()}'}.png');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    final bytes = await widgetToPng(
      SizedBox(
        width: exportWidth,
        height: 1920,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: scrimGradient),
          child: vignette == 0
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(gradient: vignetteGradient(vignette)),
                ),
        ),
      ),
    );
    await writeWholeBytes(f, bytes);
    return f;
  }

  /// The scrim's own gradient, so the preview and every rasterized
  /// copy of it are one definition.
  static const scrimGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x26000000), Color(0x73000000)], // 15% -> 45%
  );

  /// The vignette, at [strength]. Drawn by Flutter on both sides — laid
  /// live over the preview, and rasterized into a PNG the exporter
  /// composites — so the falloff is the same curve by construction
  /// rather than by a matched pair of formulas.
  static RadialGradient vignetteGradient(double strength) => RadialGradient(
        radius: Vignette.radius,
        stops: const [Vignette.innerStop, 1.0],
        colors: Vignette.colours(
            ReelEffects(vignette: strength).vignetteAlpha),
      );

  /// The vignette alone, full frame, for the one format that has no
  /// scrim to paint it into: letterbox, where the verse sits on a band
  /// rather than on the picture and nothing is darkened for it.
  static Future<File> rasterizeVignette(double strength) async {
    final dir = await renderDir();
    final f = File('${dir.path}/ayah_vig_${(strength * 100).round()}.png');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    final bytes = await widgetToPng(
      SizedBox(
        width: exportWidth,
        height: 1920,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: vignetteGradient(strength)),
        ),
      ),
    );
    await writeWholeBytes(f, bytes);
    return f;
  }

  /// The gradient backdrop (used when a background has no video), with
  /// the scrim baked in — Flutter's dithered gradient, not FFmpeg's
  /// banded approximation.
  ///
  /// [withScrim] is false for a letterbox card, where the gradient is
  /// the picture inside the card rather than the ground the verse has
  /// to read against, so darkening it would be for nothing.
  static Future<File> rasterizeGradientBackdrop(
    List<int> argb, {
    bool withScrim = true,
    double vignette = 0,

    /// The reel's grade, as the preview's own colour filters.
    ///
    /// The gradient is what the frame falls back to when the scenery
    /// file has gone, and both previews grade it — it is the bottom
    /// layer of the picture, not chrome. Graded here rather than in
    /// the filtergraph because this PNG *is* the finished base frame:
    /// the graph reads it untouched.
    List<ColorFilter> grade = const [],
  }) async {
    final dir = await renderDir();
    // Named by what the filters print, hashed with a fixed function:
    // Object.hashAll is seeded afresh in every process, so a name made
    // from it changed at every launch, the file was never found again,
    // and a new full-frame PNG piled up in the cache each time.
    final gradeKey = grade.isEmpty ? '' : '_g${_stableHash('$grade')}';
    final f = File('${dir.path}/ayah_grad_${argb[0].toRadixString(16)}_'
        '${argb[1].toRadixString(16)}${withScrim ? '' : '_plain'}'
        '${vignette == 0 ? '' : '_v${(vignette * 100).round()}'}'
        '$gradeKey.png');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    // The grade goes under the scrim and the vignette, which is where
    // the preview puts it: those two are legibility and light, not
    // picture, and neither is graded.
    Widget graded(Widget child) {
      var out = child;
      for (final filter in grade) {
        out = ColorFiltered(colorFilter: filter, child: out);
      }
      return out;
    }

    final bytes = await widgetToPng(
      SizedBox(
        width: exportWidth,
        height: 1920,
        child: Stack(
          fit: StackFit.expand,
          children: [
            graded(DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(argb[0]), Color(argb[1])],
                ),
              ),
            )),
            if (withScrim)
              const DecoratedBox(
                decoration: BoxDecoration(gradient: scrimGradient),
              ),
            if (vignette > 0)
              DecoratedBox(
                decoration:
                    BoxDecoration(gradient: vignetteGradient(vignette)),
              ),
          ],
        ),
      ),
    );
    await writeWholeBytes(f, bytes);
    return f;
  }

  /// [_capture] for everything that only wants the pixels.
  ///
  /// Public because it is the app's one way of turning a widget into a
  /// picture off-screen, and the invite's story card wants exactly
  /// that: drawn with the same faces and ornaments as the app, at
  /// story resolution, without ever being on screen.
  static Future<List<int>> widgetToPng(Widget widget) async =>
      (await _capture(widget)).bytes;

  /// Standard off-screen widget capture: attach the widget to a private
  /// render tree, lay it out at export size, capture the repaint
  /// boundary as a PNG.
  ///
  /// Reports the captured height as well, because a shrink-wrapped
  /// boundary is the only thing that knows how tall the widget decided
  /// to be — see [VerseCard].
  static Future<({List<int> bytes, double height})> _capture(
      Widget widget) async {
    await _warmFonts();
    final boundary = RenderRepaintBoundary();
    final view = ui.PlatformDispatcher.instance.views.first;

    final renderView = RenderView(
      view: view,
      configuration: const ViewConfiguration(
        logicalConstraints: BoxConstraints.tightFor(
          width: exportWidth,
          height: 1920,
        ),
        devicePixelRatio: 1.0,
      ),
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: boundary,
      ),
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: widget,
    ).attachToRenderTree(buildOwner);

    buildOwner
      ..buildScope(rootElement)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    await OnScreen.settle('capture');
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    // Captured at pixelRatio 1.0, so the image's pixels are the
    // widget's logical pixels and this is the height FFmpeg will be
    // positioning.
    final height = image.height.toDouble();
    image.dispose();
    return (bytes: data!.buffer.asUint8List(), height: height);
  }
}

/// Black field, white rounded rect — the letterbox card's alpha, drawn
/// with Flutter's antialiasing so the corner is a curve rather than a
/// staircase.
class _CardMaskPainter extends CustomPainter {
  final double radius;
  const _CardMaskPainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _CardMaskPainter old) =>
      old.radius != radius;
}

/// FNV-1a over [s]'s UTF-16 code units: the same number for the same
/// text in every run, which [Object.hash] promises not to be.
String _stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}
