import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/surah_index.dart';
import '../data/surah_title_look.dart';
import '../data/verse_ink.dart';
import '../data/verse_translation.dart';
import '../l10n/l10n.dart';
import '../render/letterbox_layout.dart';
import '../theme/app_theme.dart';
import 'illumination.dart' show Khatam;
import 'reel_watermark.dart' show ReelWatermarkMark;
import 'resize_frame.dart';

/// The surah's name as a reel carries it: a heading in gold over the
/// verses, the way a mushaf heads each surah.
///
/// The Arabic name in Ruqaa between two small rules, and under it the
/// name in Latin capitals for a reader of a Latin-script translation.
/// Drawn by Flutter on both sides — live on the preview, and into a
/// shrink-wrapped PNG the exporter overlays — so the two are one
/// picture. Every face is bundled (see `verse_font.dart`), so a phone
/// with no connection exports the same title it previews.
class SurahTitleLine extends StatelessWidget {
  final int surah;

  /// Width of the frame it is drawn for: 1080 in the export.
  final double width;

  /// Decides the line under the Arabic: the Latin name for a translation
  /// in Latin script, nothing for one already in Arabic script.
  final VerseTranslation edition;

  /// On a pale letterbox band: deep gold, and a white halo.
  final bool onLight;

  /// Its face, colour and frame; the title the app has always set until
  /// another is chosen.
  final SurahTitleLook look;

  const SurahTitleLine({
    super.key,
    required this.surah,
    required this.width,
    required this.edition,
    this.onLight = false,
    this.look = SurahTitleLook.classic,
  });

  /// The width the type sizes below are authored at.
  static const referenceWidth = 1080.0;

  static SurahInfo? _info(int surah) =>
      surah >= 1 && surah <= surahIndex.length ? surahIndex[surah - 1] : null;

  /// The flat colour the name is set in: the house gold, deeper on a pale
  /// band, or the colour chosen — taken down toward ink on a pale band,
  /// where a pale colour would vanish.
  Color _flat() {
    if (look.argb == 0) return onLight ? AppColors.goldDeep : AppColors.goldBright;
    final c = Color(look.argb);
    return onLight ? Color.lerp(c, const Color(0xFF1B140A), 0.55)! : c;
  }

  @override
  Widget build(BuildContext context) {
    final info = _info(surah);
    if (info == null) return const SizedBox.shrink();
    final s = width / referenceWidth;
    final ink = look.ink;
    final inked = ink != VerseInk.none;
    final colour = inked ? Color(ink.base) : _flat();
    final haloColour =
        (onLight ? Colors.white : Colors.black).withValues(alpha: onLight ? 0.75 : 0.6);
    final halo = [
      Shadow(
        color: haloColour,
        blurRadius: 12 * s,
        offset: Offset(0, 2 * s),
      ),
    ];
    final face = look.face;
    final arabicStyle = TextStyle(
      fontFamily: face.arabic,
      fontSize: 58 * s * face.scale,
      height: face.height,
      color: colour,
      shadows: halo,
      decoration: TextDecoration.none,
    );
    final words = 'سورة ${info.nameArabic}';
    Widget arabic = Text(
      words,
      textDirection: TextDirection.rtl,
      maxLines: 1,
      style: arabicStyle,
    );
    if (inked) {
      // An ink is light, not a colour: its glow under the letters, and
      // its fill moving across them — the way the verse is inked.
      arabic = Stack(
        children: [
          Text(
            words,
            textDirection: TextDirection.rtl,
            maxLines: 1,
            style: arabicStyle.copyWith(
              color: const Color(0x00FFFFFF),
              shadows: ink.shadows(s * 0.9, halo: haloColour),
            ),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => ink.gradient.createShader(bounds),
            child: Text(
              words,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              style: arabicStyle.copyWith(
                  color: const Color(0xFFFFFFFF), shadows: const []),
            ),
          ),
        ],
      );
    }
    final latin = edition.arabicScript
        ? null
        : Text(
            info.nameEnglish.toUpperCase(),
            maxLines: 1,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontFamily: face.latin,
              fontSize: 21 * s,
              height: 1.2,
              letterSpacing: 6 * s,
              fontWeight: FontWeight.w500,
              color: (onLight ? const Color(0xFF2A2214) : Colors.white)
                  .withValues(alpha: 0.82),
              shadows: halo,
              decoration: TextDecoration.none,
            ),
          );
    final Widget name = switch (look.frame) {
      TitleFrame.rules => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Rule(s: s, colour: colour, towardsName: true, halo: halo),
            SizedBox(width: 16 * s),
            arabic,
            SizedBox(width: 16 * s),
            _Rule(s: s, colour: colour, towardsName: false, halo: halo),
          ],
        ),
      TitleFrame.plain => arabic,
      TitleFrame.cartouche => CustomPaint(
          painter: _CartouchePainter(
              colour: colour, onLight: onLight, s: s, halo: haloColour),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 46 * s, vertical: 8 * s),
            child: arabic,
          ),
        ),
      TitleFrame.band => CustomPaint(
          painter: _BandPainter(
              colour: colour, onLight: onLight, s: s, halo: haloColour),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 74 * s, vertical: 10 * s),
            child: arabic,
          ),
        ),
    };
    // A title drawn into the export is always laid out left to right,
    // whatever the app's own language, as the mark is: the rules sit
    // either side of the name, and in an RTL app the row would swap
    // nothing visible but the order the export and preview build it in.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          name,
          if (latin != null) ...[
            SizedBox(height: (look.frame == TitleFrame.rules ||
                        look.frame == TitleFrame.plain
                    ? 2
                    : 8) *
                s),
            latin,
          ],
        ],
      ),
    );
  }
}

/// The name in a cartouche: a rounded frame with pointed shoulders, the
/// ground inside it darkened a little, and a second, fainter line just
/// inside the first.
class _CartouchePainter extends CustomPainter {
  final Color colour;
  final bool onLight;
  final double s;
  final Color halo;

  const _CartouchePainter({
    required this.colour,
    required this.onLight,
    required this.s,
    required this.halo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2 * s);
    final outer = Khatam.cartouche(rect);
    canvas.drawPath(
      outer,
      Paint()
        ..color = halo.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * s),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..color = (onLight ? Colors.white : Colors.black)
            .withValues(alpha: onLight ? 0.35 : 0.30),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * s
        ..color = colour,
    );
    canvas.drawPath(
      Khatam.cartouche(rect.deflate(7 * s)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * s
        ..color = colour.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _CartouchePainter old) =>
      old.colour != colour || old.onLight != onLight || old.s != s;
}

/// The name on a band with pointed ends, as a mushaf heads a surah: a
/// darkened ground, a line round it and a fainter one inside, and an
/// eight-pointed star at each end.
class _BandPainter extends CustomPainter {
  final Color colour;
  final bool onLight;
  final double s;
  final Color halo;

  const _BandPainter({
    required this.colour,
    required this.onLight,
    required this.s,
    required this.halo,
  });

  static Path _shape(Rect r) {
    final h = r.height / 2;
    return Path()
      ..moveTo(r.left, r.center.dy)
      ..lineTo(r.left + h, r.top)
      ..lineTo(r.right - h, r.top)
      ..lineTo(r.right, r.center.dy)
      ..lineTo(r.right - h, r.bottom)
      ..lineTo(r.left + h, r.bottom)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2 * s);
    final band = _shape(rect);
    canvas.drawPath(
      band,
      Paint()
        ..color = halo.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * s),
    );
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: onLight
              ? [
                  Colors.white.withValues(alpha: 0.55),
                  Colors.white.withValues(alpha: 0.30),
                ]
              : [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.24),
                ],
        ).createShader(rect),
    );
    canvas.drawPath(
      band,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * s
        ..strokeJoin = StrokeJoin.round
        ..color = colour,
    );
    canvas.drawPath(
      _shape(rect.deflate(7 * s)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 * s
        ..strokeJoin = StrokeJoin.round
        ..color = colour.withValues(alpha: 0.45),
    );
    final star = Paint()..color = colour;
    final r = rect.height * 0.16;
    final inset = rect.height * 0.55;
    canvas.drawPath(
        Khatam.star(Offset(rect.left + inset, rect.center.dy), r), star);
    canvas.drawPath(
        Khatam.star(Offset(rect.right - inset, rect.center.dy), r), star);
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) =>
      old.colour != colour || old.onLight != onLight || old.s != s;
}

/// One of the two rules either side of the name: a line fading in from
/// the outside, and a small diamond where it meets the name.
class _Rule extends StatelessWidget {
  final double s;
  final Color colour;

  /// True for the left rule, whose diamond is at its right end.
  final bool towardsName;
  final List<Shadow> halo;

  const _Rule({
    required this.s,
    required this.colour,
    required this.towardsName,
    required this.halo,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(78 * s, 18 * s),
        painter: _RulePainter(colour, towardsName, halo.first.color),
      );
}

class _RulePainter extends CustomPainter {
  final Color colour;
  final bool diamondRight;
  final Color halo;

  const _RulePainter(this.colour, this.diamondRight, this.halo);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final d = size.height * 0.30;
    final near = diamondRight ? size.width - d : d;
    final far = diamondRight ? 0.0 : size.width;
    final line = Paint()
      ..strokeWidth = size.height * 0.085
      ..shader = LinearGradient(
        begin: diamondRight ? Alignment.centerLeft : Alignment.centerRight,
        end: diamondRight ? Alignment.centerRight : Alignment.centerLeft,
        colors: [colour.withValues(alpha: 0), colour],
      ).createShader(Offset.zero & size);
    final glow = Paint()
      ..color = halo
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.25);
    final diamond = Path()
      ..moveTo(near, y - d)
      ..lineTo(near + d, y)
      ..lineTo(near, y + d)
      ..lineTo(near - d, y)
      ..close();
    canvas.drawPath(diamond, glow);
    canvas.drawLine(Offset(far, y), Offset(near - d * 1.4, y), line);
    canvas.drawPath(diamond, Paint()..color = colour);
    // A dot further out, where the line is still faint.
    final dot = diamondRight ? size.width * 0.32 : size.width * 0.68;
    canvas.drawCircle(Offset(dot, y), size.height * 0.07,
        Paint()..color = colour.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _RulePainter old) =>
      old.colour != colour || old.diamondRight != diamondRight;
}

/// The title on a reel: where it starts, the drag that moves it, and
/// the pinch that sizes it.
///
/// Placed the way the dedication is (see `ReelDedication`): its centre
/// at a fraction of the frame, held inside it by the PNG's shadow
/// margin, by the same arithmetic the exporter's overlay runs. [scale]
/// lays the whole line out that much larger or smaller, as the exporter
/// rasterizes it (see `AyahRasterizer.rasterizeSurahTitle`).
class ReelSurahTitle extends StatelessWidget {
  final double width;
  final int surah;
  final VerseTranslation edition;
  final bool onLight;

  /// Its face, colour and frame.
  final SurahTitleLook look;

  /// Where its centre is, as fractions of the frame; null for its place
  /// at the head of the frame (see [defaultCentre]).
  final Offset? at;
  final LetterboxGeometry? letterbox;

  /// Its size against its own: 1 until it is pinched.
  final double scale;

  /// One finger moving it, by this much.
  final ValueChanged<Offset>? onDrag;

  /// Two fingers sizing it: the size they ask for, against its own.
  final ValueChanged<double>? onResize;

  /// The finger, or the fingers, lifted.
  final VoidCallback? onDragEnd;

  /// A double tap: back to the head of the frame, at its own size.
  final VoidCallback? onReset;

  /// The title's laid-out size, each time it changes.
  final ValueChanged<Size>? onSize;

  const ReelSurahTitle({
    super.key,
    required this.width,
    required this.surah,
    required this.edition,
    this.onLight = false,
    this.look = SurahTitleLook.classic,
    this.at,
    this.letterbox,
    this.scale = 1.0,
    this.onDrag,
    this.onResize,
    this.onDragEnd,
    this.onReset,
    this.onSize,
  });

  /// Extra room around the title for a finger, when it can be dragged:
  /// enough for two of them to land on it for a pinch, and for the
  /// corner handles that size it with one.
  static const touchPad = 22.0;

  /// Where the title sits until it is moved: high in a full frame, clear
  /// of the feed's own header; in the middle of the band over a
  /// letterbox card when that band has room for it.
  static Offset defaultCentre(LetterboxGeometry? letterbox) {
    if (letterbox != null && letterbox.cardY >= 220) {
      return Offset(0.5, letterbox.cardY / 2 / LetterboxGeometry.frameH);
    }
    return const Offset(0.5, 0.122);
  }

  @override
  Widget build(BuildContext context) {
    final s = width / SurahTitleLine.referenceWidth;
    final pad = onDrag == null ? 0.0 : touchPad;
    // Rounded as the exporter rounds it, to the percent, so the line on
    // screen and the one in the file are laid out at one size.
    final sized = (scale * 100).round() / 100;
    Widget body = SurahTitleLine(
      surah: surah,
      width: width * sized,
      edition: edition,
      onLight: onLight,
      look: look,
    );
    final measure = onSize;
    if (measure != null) body = _ReportSize(onChange: measure, child: body);
    if (onDrag != null) {
      // One finger moves it, a corner or two fingers size it, a double
      // tap puts it back; crop marks frame it while it is touched.
      body = ResizableBox(
        scale: scale,
        onMove: onDrag,
        onResize: onResize,
        onEnd: onDragEnd,
        onDoubleTap: onReset,
        pad: pad,
        inset: 5,
        child: body,
      );
    }
    final info = surah >= 1 && surah <= surahIndex.length
        ? surahIndex[surah - 1]
        : null;
    return Semantics(
      label: info == null
          ? null
          : L10n.of(context).surahTitle(info),
      excludeSemantics: true,
      child: CustomSingleChildLayout(
        delegate: _CentredAt(
          at ?? defaultCentre(letterbox),
          margin: ReelWatermarkMark.shadowMargin * s,
          pad: pad,
        ),
        child: body,
      ),
    );
  }
}

/// Puts the title's centre at a fraction of the frame, kept inside it,
/// as the exporter clamps the PNG (which carries the shadow margin all
/// round) to the frame.
class _CentredAt extends SingleChildLayoutDelegate {
  final Offset at;
  final double margin;
  final double pad;

  const _CentredAt(this.at, {required this.margin, required this.pad});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double place(double centre, double child, double frame) {
      final body = child - 2 * pad;
      final lo = margin;
      final hi = frame - body - margin;
      final start =
          hi < lo ? (frame - body) / 2 : (centre - body / 2).clamp(lo, hi);
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

/// Reports its child's size straight out of layout.
class _ReportSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const _ReportSize({required this.onChange, required Widget super.child});

  @override
  _RenderReportSize createRenderObject(BuildContext context) =>
      _RenderReportSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderReportSize r) =>
      r.onChange = onChange;
}

class _RenderReportSize extends RenderProxyBox {
  _RenderReportSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      onChange(size);
    }
  }
}

/// The arithmetic the exporter places the title's PNG by: its centre at
/// [at] (fractions of the frame), clamped so the PNG stays inside it.
/// The PNG carries the shadow margin all round, which is what keeps the
/// title itself that far off an edge — the same clamp [ReelSurahTitle]
/// applies on the preview.
String surahTitleOverlay(Offset at) {
  final cx = (at.dx * LetterboxGeometry.frameW).toStringAsFixed(0);
  final cy = (at.dy * LetterboxGeometry.frameH).toStringAsFixed(0);
  return "x='max(0,min(W-w,$cx-w/2))':y='max(0,min(H-h,$cy-h/2))'";
}

/// Keeps a dragged centre inside the frame's fractions.
Offset clampTitleCentre(Offset c) =>
    Offset(math.min(1, math.max(0, c.dx)), math.min(1, math.max(0, c.dy)));
