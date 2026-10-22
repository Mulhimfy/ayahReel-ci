
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/l10n.dart';
import '../render/letterbox_layout.dart';
import '../theme/app_theme.dart';
import 'measure_height.dart';

/// The AyahReel mark burned into every exported reel and mirrored in
/// the live preview. Deliberately quiet: a small gold spark and the
/// wordmark at ~60% white, sized so it reads on a phone feed without
/// ever competing with the verse.
///
/// *Where* it sits is a per-format decision, because the two formats
/// have nothing like the same free space — but in both it hangs off
/// the composition rather than off the frame, so a crop that reaches it
/// has to take something the user wanted with it. See [insetFor].
class ReelWatermark extends StatelessWidget {
  /// How low the mark is ever allowed to sit in full frame: the gap
  /// between its baseline box and the frame's bottom edge, at
  /// [ReelWatermarkMark.referenceWidth].
  ///
  /// Measured off a posted reel rather than guessed. In these
  /// coordinates TikTok's caption block runs from the audio row (79px
  /// above the bottom edge) up past the account name, whose top sits at
  /// 284px. The mark spent its first release at 92 — *inside* that
  /// block, wedged between two hashtag lines: burned into every frame,
  /// paid for on every frame, and read by nobody. This clears the
  /// account name by most of a caption line (~66px in these
  /// coordinates) — set lower at the user's request, 46px clear —
  /// which still carries it over Instagram's username row, drawn a
  /// little higher than TikTok's.
  ///
  /// It was the mark's *placement* until the crop found it, and is now
  /// only the floor under [verseGap] — see [insetFor].
  static const fullFrameInset = 330.0;

  /// Gap between the verse card's bottom edge and the top of the mark
  /// in full frame — and, because that is what it is, the entire
  /// margin for error a crop gets.
  ///
  /// The mark used to sit at [fullFrameInset] off the frame's own
  /// bottom edge with nothing under it but scenery, so a cut that
  /// reached it cost the reel nothing: drag the bottom handle up 391px,
  /// a fifth of the frame, and the mark is gone with no other damage.
  /// Users found that, and there was nothing clever about it — the only
  /// thing protecting a mark is the distance to the nearest thing worth
  /// keeping, and in full frame that distance was 219px of empty
  /// picture. Letterbox never had the hole: there the mark rides the
  /// card, *above* the band, so the cut that reaches it has already
  /// eaten the verse on the way up.
  ///
  /// Hanging the mark off the verse instead makes this number the
  /// distance, and 24px is not one anybody lands on by dragging a
  /// handle. Overshoot and you clip the translation's last line;
  /// undershoot and the mark is still there.
  static const verseGap = 24.0;

  /// Nominal height of the mark's shrink-wrapped box at
  /// [ReelWatermarkMark.referenceWidth].
  ///
  /// Only [insetFor] reads it, and only to turn the verse card's bottom
  /// edge into the mark's, so a pixel or two of drift against whatever
  /// line box the resolved font actually reports moves [verseGap] to 23
  /// or 25 and nothing else. What it must not become is a second
  /// opinion about *where the mark goes*: preview and export both place
  /// the mark from this same constant, so they cannot disagree with
  /// each other whatever the font does.
  static const markHeight = 30.0;

  /// Gap between the mark and the bottom edge of the *card* in
  /// letterbox, where the mark signs the picture instead of sitting at
  /// the bottom of the frame.
  ///
  /// It could not simply be raised the way full frame's was: everything
  /// between the card and the frame's bottom edge is the band the verse
  /// lives in, and a square card leaves that band only ~434px to begin
  /// with — verses already outgrow it, which is why
  /// [LetterboxGeometry.verseTop] overhangs rather than re-centres.
  /// Every pixel the mark climbed would have come straight out of the
  /// verse. The card is the one surface in the format with room going
  /// spare, and what it is made of is scenery, which is the ground this
  /// mark was drawn for.
  static const cardInset = 34.0;

  /// How far above the frame's bottom edge the mark's box sits, given
  /// the format's geometry ([letterbox] is null in full frame) and
  /// where the verse card's bottom edge landed ([verseBottom], in
  /// frame coordinates from the top; null before the card has laid out
  /// once).
  ///
  /// One function, because the preview, the FFmpeg overlay and the band
  /// geometry all need this answer and the mark is burned in — two
  /// implementations of it would drift, and the drift would only ever
  /// show up in the finished file.
  ///
  /// Both arms anchor the mark to the picture the user built rather
  /// than to an edge nobody cares about, which is what a crop has to
  /// pay for.
  ///
  /// The letterbox arm follows the card, so it travels with the
  /// source's shape: a 2.4:1 scope card bottoms out at 960 and puts the
  /// mark 1004 above the frame's edge; a portrait source — cropped
  /// square, the largest card the format can build — bottoms out at
  /// 1336 and puts it 628. Both ends of that range clear the feed's
  /// caption block twice over, which is the property that has to hold.
  /// It ignores [verseBottom] on purpose: the verse is *below* the mark
  /// in this format, in the band the crop freed, and following it down
  /// there would undo the whole arrangement.
  ///
  /// The full-frame arm stands at [fullFrameInset] whatever the verse
  /// does: at the foot of the frame, above the band the feeds draw
  /// their caption and account name over, and detached from the verse
  /// so a verse dragged up the frame does not drag the signature into
  /// the middle of the picture with it.
  ///
  /// A dedication does not enter into it: on a reel that line sits at
  /// the bottom of the frame on its own — see [ReelDedication] — so
  /// the mark is the same height, in the same place, dedicated or not.
  static double insetFor(LetterboxGeometry? letterbox,
      {double? verseBottom}) {
    if (letterbox != null) {
      return LetterboxGeometry.frameH - letterbox.cardBottom + cardInset;
    }
    // Full frame: the mark stands at the floor, wherever the verse is.
    // It used to hang one gap under the verse, which stopped a crop
    // taking it off for free — and put it wherever the verse happened
    // to be, which on a verse dragged high was the middle of the
    // picture. A mark is a signature, and a signature goes at the foot
    // of the page: above the band the feeds draw over, and no higher.
    // [verseBottom] is still taken so every caller keeps its shape.
    return fullFrameInset;
  }

  /// Width the frame is laid out at. Export uses 1080; preview scales.
  final double width;

  /// The card and band geometry when the frame is letterboxed, null in
  /// full frame. See [insetFor].
  final LetterboxGeometry? letterbox;

  /// Bottom edge of the verse card, in export-frame coordinates from
  /// the top — where the user's drag left it. The full-frame mark hangs
  /// off this; see [insetFor]. Null until the card has laid out once,
  /// and ignored in letterbox.
  final double? verseBottom;

  const ReelWatermark({
    super.key,
    required this.width,
    this.letterbox,
    this.verseBottom,
  });

  @override
  Widget build(BuildContext context) {
    // The mark is part of the picture, not something to read out of
    // the preview: a reader going over the reel gets the verse, not
    // the app's name after it.
    return ExcludeSemantics(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
              bottom: insetFor(letterbox, verseBottom: verseBottom) *
                  width /
                  ReelWatermarkMark.referenceWidth),
          child: ReelWatermarkMark(
            width: width,
            undimmed: letterbox != null,
          ),
        ),
      ),
    );
  }
}

/// Who a reel was made for, written along the bottom of the frame.
///
/// It used to ride above the app's mark, and on a card it still does
/// (see [ReelWatermarkMark.dedication]). On a reel the mark hangs off
/// the verse, which put the dedication wherever the verse happened to
/// be dragged to — mid-frame, more often than not, reading as a
/// caption to the verse rather than as the signature it is. Down here
/// it is where a dedication goes on anything: the last line on the
/// page.
///
/// Burned into the export by the same arithmetic — the exporter
/// overlays a shrink-wrapped PNG of [ReelDedicationLine] at
/// `H-h-inset`, see `AyahRasterizer.dedicationInset` — so the preview
/// and the file cannot disagree about where it sits.
///
/// That is where it starts. The user can drag it anywhere on the frame
/// ([at]), and then both sides place its centre at the same fraction
/// of the frame, held inside it by the same margin — see
/// [_CentredAt] here and `VideoRenderer`'s overlay for the export.
class ReelDedication extends StatelessWidget {
  /// Gap between the line's bottom edge and the frame's, at
  /// [ReelWatermarkMark.referenceWidth].
  ///
  /// Two things fix it. It has to read as the *bottom* of the reel,
  /// which rules out anything that climbs into the picture. And in
  /// letterbox the verse may come down as far as
  /// [LetterboxGeometry.bandBottomPadding] off the edge, so the line
  /// plus [ReelWatermark.verseGap] over it has to fit inside that
  /// margin or the two collide — see [lineHeight].
  static const frameInset = 90.0;

  /// Nominal height of the line's box at the reference width, for the
  /// geometry above; the drawn box may differ by a pixel or two.
  static const lineHeight = 32.0;

  /// Extra room around the line for a finger, in logical pixels, when
  /// it can be dragged. A line of small type is a thin target.
  static const touchPad = 12.0;

  /// Whether a line centred at [at] lands on a pale ground.
  ///
  /// The ground is pale only on a letterbox band in white or ivory, and
  /// a line dragged up onto the card is on the photograph instead —
  /// where the deep gold and white halo a pale band asks for would be
  /// the wrong way round. One function, because the preview and the
  /// exporter both pick the line's ink from it.
  static bool onLightAt(
    Offset? at, {
    required bool onLightGround,
    LetterboxGeometry? letterbox,
  }) {
    if (!onLightGround || at == null || letterbox == null) {
      return onLightGround;
    }
    final centre = Offset(at.dx * LetterboxGeometry.frameW,
        at.dy * LetterboxGeometry.frameH);
    return !Rect.fromLTWH(letterbox.cardX, letterbox.cardY, letterbox.cardW,
            letterbox.cardH)
        .contains(centre);
  }

  /// Width the frame is laid out at. Export uses 1080; preview scales.
  final double width;

  /// The dedication as a sentence, or empty — in which case this draws
  /// nothing at all.
  final String line;

  /// Whether the bottom of the frame is a pale letterbox band, where
  /// bright gold on a white halo is a disappearance, not a colour. See
  /// [ReelDedicationLine.onLight].
  final bool onLight;

  /// Where the line's centre sits, as fractions of the frame's width
  /// and height. Null is its place at the foot of the frame.
  final Offset? at;

  /// Each move of a finger dragging the line, in logical pixels. Null
  /// leaves the line where it is and takes no touches.
  final ValueChanged<Offset>? onDrag;
  final VoidCallback? onDragEnd;

  /// A double tap on the line: the caller puts it back at the foot.
  final VoidCallback? onReset;

  /// Given to the line itself, so a caller can find it.
  final Key? lineKey;

  /// The line's laid-out size, each time it changes: what a caller
  /// that builds this during layout measures it by, since a
  /// [GlobalKey] there is not safe. See [MeasureSize].
  final ValueChanged<Size>? onLineSize;

  const ReelDedication({
    super.key,
    required this.width,
    required this.line,
    this.onLight = false,
    this.at,
    this.onDrag,
    this.onDragEnd,
    this.onReset,
    this.lineKey,
    this.onLineSize,
  });

  @override
  Widget build(BuildContext context) {
    if (line.isEmpty) return const SizedBox.shrink();
    final s = width / ReelWatermarkMark.referenceWidth;
    final pad = onDrag == null ? 0.0 : touchPad;
    Widget body = ReelDedicationLine(
      key: lineKey,
      width: width,
      line: line,
      onLight: onLight,
    );
    final measure = onLineSize;
    if (measure != null) body = MeasureSize(onChange: measure, child: body);
    if (onDrag != null) {
      body = RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          // A pan with half the usual slop. The frame under the line
          // drags the verse on a vertical drag, and in the arena the
          // first recognizer past its slop wins: at the stock slop the
          // frame's would, and the line could never be moved up or
          // down.
          PanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
            PanGestureRecognizer.new,
            (r) {
              r
                ..gestureSettings = const DeviceGestureSettings(touchSlop: 6)
                ..onUpdate = ((d) => onDrag!(d.delta))
                ..onEnd = (_) {
                  onDragEnd?.call();
                };
            },
          ),
          if (onReset != null)
            DoubleTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    DoubleTapGestureRecognizer>(
              DoubleTapGestureRecognizer.new,
              (r) => r.onDoubleTap = onReset,
            ),
        },
        child: Padding(padding: EdgeInsets.all(pad), child: body),
      );
    }
    final spot = at;
    // The one thing down here somebody put on the reel on purpose, so
    // a reader going over the frame hears it — after the verse, not
    // in it.
    return Semantics(
      label: L10n.of(context).a11yDedication(line),
      excludeSemantics: true,
      child: spot == null
          ? Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                    bottom: math.max(0.0, frameInset * s - pad)),
                child: body,
              ),
            )
          : CustomSingleChildLayout(
              delegate: _CentredAt(
                spot,
                margin: ReelWatermarkMark.shadowMargin * s,
                pad: pad,
              ),
              child: body,
            ),
    );
  }
}

/// Puts the line's centre at a fraction of the frame, kept inside it.
///
/// The exporter overlays the line's PNG — the line plus
/// [ReelWatermarkMark.shadowMargin] of transparent slack all round —
/// centred on the same point and clamped to the frame, so the line
/// itself can come no nearer an edge than that margin. The same clamp
/// here, so a line dragged hard into a corner stops where the file
/// will have it.
class _CentredAt extends SingleChildLayoutDelegate {
  final Offset at;
  final double margin;

  /// The touch padding around the line, which is not part of it.
  final double pad;

  const _CentredAt(this.at, {required this.margin, required this.pad});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double place(double centre, double child, double frame) {
      final line = child - 2 * pad;
      final lo = margin;
      final hi = frame - line - margin;
      final start = hi < lo ? (frame - line) / 2 : (centre - line / 2).clamp(lo, hi);
      return start - pad;
    }

    return Offset(
      place(at.dx * size.width, childSize.width, size.width),
      place(at.dy * size.height, childSize.height, size.height),
    );
  }

  @override
  bool shouldRelayout(_CentredAt old) =>
      old.at != at || old.margin != margin || old.pad != pad;
}

/// The dedication line itself, shrink-wrapped to its glyphs: "A gift
/// for Aisha", "Sadaqah jariyah for Fatima". [ReelDedication] places
/// it on a reel, [ReelWatermarkMark] carries it on a card, and the
/// exporter rasterizes it to a small PNG for the same reason it does
/// the mark.
class ReelDedicationLine extends StatelessWidget {
  /// How wide the line may run before it is ellipsised. Names are
  /// capped at [Dedication.maxName], but a capped name in a language
  /// that spells the phrase long can still outrun the frame, and an
  /// overlay wider than the video is one FFmpeg silently clips.
  static const maxWidth = 0.78;

  final double width;
  final String line;

  /// The line is landing on a pale ground — a light letterbox band on
  /// a reel, an ivory paper on a card — so it takes the deep gold and
  /// a white halo instead of the bright gold and a black one.
  final bool onLight;

  /// The halo, when the caller has already decided it: a card's mark
  /// hands over its own so the line and the wordmark under it match.
  /// Null draws the reel's.
  final List<Shadow>? shadows;

  const ReelDedicationLine({
    super.key,
    required this.width,
    required this.line,
    this.onLight = false,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final s = width / ReelWatermarkMark.referenceWidth;
    // In gold, which is the one place the app's accent is spent on
    // something a user wrote. A gift and a sadaqah jariyah are the
    // two reasons somebody makes one of these for another person, and
    // the name is what the person receiving it looks for; white at
    // 80% made it read as a caption. The bright gold is for a dark
    // frame, the deep one for a pale band or paper — the same flip the
    // wordmark's [ReelWatermarkMark.ink] makes, for the same reason.
    //
    // [AppColors.goldDeep] rather than the accent gold, and that is
    // not a shade preference: the accent manages about 2:1 on the
    // ivory, sand and rose papers, which for the one line somebody is
    // meant to read is not a colour but a disappearance — and it is
    // burned into the export, so it cannot be fixed afterwards.
    final ink = onLight ? AppColors.goldDeep : AppColors.goldBright;
    final halo = shadows ??
        [
          Shadow(
            color: (onLight ? Colors.white : Colors.black)
                .withValues(alpha: onLight ? 0.72 : 0.55),
            blurRadius: (onLight ? 8 : 10) * s,
            offset: Offset(0, 1.5 * s),
          ),
        ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * maxWidth),
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        // The same variant the wordmark is set in, and that is not a
        // taste decision: Inter Medium is the one weight bundled under
        // the name google_fonts looks for (see pubspec,
        // assets/google_fonts). Any other weight resolves over the
        // network — and this line is burned into an export, where a
        // phone with no connection would bake in the system fallback
        // beside a wordmark that resolved. The hierarchy comes from
        // size, tracking and opacity instead, which cost nothing to
        // ship.
        style: GoogleFonts.inter(
          fontSize: 27 * s,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4 * s,
          height: 1.15,
          color: ink.withValues(alpha: 0.94),
          shadows: halo,
        ),
      ),
    );
  }
}

/// The mark itself, shrink-wrapped to its glyphs — no frame, no
/// positioning. Split out so the exporter can rasterize a small PNG
/// instead of a full 1080x1920 one: FFmpeg blends the overlay's whole
/// area on every frame, so a full-frame transparent watermark costs a
/// 1080x1920 alpha blend per frame to draw a mark a few hundred pixels
/// wide.
class ReelWatermarkMark extends StatelessWidget {
  /// The width the type sizes below are authored at.
  static const referenceWidth = 1080.0;

  /// Slack the exporter pads around the shrink-wrapped mark so the text
  /// shadow is never clipped by the boundary. Sized for the wider of
  /// the two halos — see [undimmed].
  static const shadowMargin = 16.0;

  final double width;

  /// The mark is landing on scenery that nothing has darkened: the
  /// inside of a letterbox card, which is the picture at full
  /// brightness.
  ///
  /// Full frame always keeps 15–45% of black between the mark and the
  /// picture — the legibility scrim, ~39% of it at [fullFrameInset].
  /// The card is composited without one, on purpose: it is the
  /// photograph, not a ground for text. So on the card the halo is the
  /// only thing standing between a white wordmark at 60% and a bright
  /// scenery, and it carries that alone.
  final bool undimmed;

  /// What the wordmark is drawn in, when white is the wrong answer.
  ///
  /// A reel never passes this: it is burned over a photograph or into
  /// a darkened frame, and white at 60% is the mark. A card can stand
  /// on ivory, where a white mark is not a discreet one but an absent
  /// one — so the card layer hands it the ink of the ground instead,
  /// and the halo under it flips with it.
  final Color? ink;

  /// Who this was made for, already written as a sentence — "A gift
  /// for Aisha", "Sadaqah jariyah for Fatima". Empty for everything
  /// nobody dedicated, which is the default and costs nothing.
  ///
  /// This is how a *card* carries it: above the mark, at the card's
  /// bottom edge, one widget and one PNG. A reel no longer passes it
  /// — there the line sits at the bottom of the frame on its own, see
  /// [ReelDedication] — so a reel's mark is the bare mark whatever the
  /// dedication is.
  final String dedication;

  const ReelWatermarkMark({
    super.key,
    required this.width,
    this.undimmed = false,
    this.ink,
    this.dedication = '',
  });

  /// How much taller the mark's box is when it carries a dedication,
  /// at [referenceWidth]: the line itself plus the gap under it.
  ///
  /// A constant for the same reason [ReelWatermark.markHeight] is one:
  /// the preview and the export both place the mark from it, so they
  /// cannot disagree with each other whatever the resolved font does
  /// with a line box.
  static const dedicationBlock = 46.0;

  @override
  Widget build(BuildContext context) {
    final s = width / referenceWidth;
    final onLight = ink != null;
    final shadow = [
      Shadow(
        color: (onLight ? Colors.white : Colors.black)
            .withValues(alpha: undimmed ? 0.72 : 0.55),
        blurRadius: (onLight ? 8 : (undimmed ? 13 : 10)) * s,
        offset: Offset(0, 1.5 * s),
      ),
    ];
    // Always left to right, as the export rasterizes it: in the app's
    // own direction an Arabic interface previewed the star on the
    // wrong side of the word, unlike the reel it then saved.
    final mark = Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '✦',
          style: TextStyle(
            fontSize: 19 * s,
            color: (ink == null ? AppColors.goldBright : AppColors.gold)
                .withValues(alpha: 0.72),
            shadows: shadow,
          ),
        ),
        SizedBox(width: 8 * s),
        Text(
          'AyahReel',
          style: GoogleFonts.inter(
            fontSize: 25 * s,
            fontWeight: FontWeight.w500,
            letterSpacing: 3.2 * s,
            color: (ink ?? Colors.white).withValues(alpha: 0.6),
            shadows: shadow,
          ),
        ),
      ],
      ),
    );
    if (dedication.isEmpty) return mark;
    // On a card the dedication reads above the mark, not beside it: it
    // belongs to the verse, and the mark belongs to the app. Set
    // brighter and larger than the wordmark — this is the one line on
    // the card somebody is meant to read after the verse itself — and
    // in the mark's own halo, so the two sit on the paper as one block.
    // The wordmark under it keeps the accent; it is a mark, not a line
    // to read.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReelDedicationLine(
          width: width,
          line: dedication,
          onLight: onLight,
          shadows: shadow,
        ),
        SizedBox(height: 12 * s),
        mark,
      ],
    );
  }
}
