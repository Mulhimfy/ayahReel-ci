import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/settings_service.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
import '../state/creation_state.dart'
    show TextPreset, accentOnDark, accentOnLight, inkOnLight, legibleInkOn;
import '../theme/app_theme.dart';
import 'verse_geometry.dart';

/// The verse card burned onto the video and shown in live preview.
/// This exact widget is rasterized to transparent PNG by the renderer,
/// so preview and export are pixel-identical by construction.
class AyahOverlay extends StatelessWidget {
  final Ayah ayah;

  /// Width the overlay is laid out at. Export uses 1080; preview scales.
  final double width;

  /// User-chosen verse color; the translation inherits it slightly dimmed.
  final Color textColor;

  /// User-chosen size multiplier on top of the base layout.
  final double textScale;

  /// Designed look; see [TextPreset].
  final TextPreset preset;

  /// Display tokens of the Arabic text (space-split) to render in the
  /// highlight color — the word being recited right now. Null renders
  /// the plain card. Color is the only difference, so the layout is
  /// identical with and without a highlight by construction.
  final ({int start, int end})? highlightTokens;

  /// The edition the translation line is in, which decides its face
  /// and its direction. Defaults to whatever Settings names, so every
  /// caller that does not care gets the right one; the rasterizer
  /// passes it explicitly so an export can never disagree with the
  /// preview the user approved.
  final VerseTranslation translation;

  /// Whether the rule and the translation line are drawn under the
  /// verse. False is "None" in the translation picker: the Arabic
  /// alone. Read off Settings like [translation], and passed by the
  /// rasterizer for the same reason.
  final bool showTranslation;

  /// The verse is sitting on a pale letterbox band rather than on
  /// darkened scenery. Every colour this card picks for itself — the
  /// shadows, the highlight — is chosen the other way round when it is
  /// set; see [isLightGround].
  final bool onLight;

  /// The face the Arabic is set in.
  final VerseFace verseFace;

  /// The face the translation line is set in. Defaults to the one its
  /// own script starts on, so a caller that does not care gets what
  /// the app has always drawn.
  final TranslationFace translationFace;

  /// The second colour of the card: the rule under the verse, and the
  /// word lit as it is recited. Null is the house gold, chosen for
  /// whichever ground the verse is on — which is what every caller
  /// that has not been given one wants.
  final Color? accent;

  /// The surah [ayah] belongs to. Only the reference line reads it,
  /// and 0 — a card that was never told — draws no reference at all
  /// rather than a wrong one.
  final int surah;

  /// Whether the card carries the verse's number, and how. Defaults
  /// to what Settings names, for the same reason [translation] does;
  /// the rasterizer passes it explicitly so the export and its cache
  /// key cannot disagree with the preview.
  final VerseNumbering numbering;

  /// A luminous ink the verse is drawn in instead of the flat
  /// [textColor], or [VerseInk.none]. [textColor] is still what the
  /// translation and the reference are set in, and a caller that sets
  /// an ink sets [textColor] to the ink's [VerseInk.base].
  final VerseInk ink;

  /// The same for the accent. The lit word and the verse-end sign glow
  /// in it and the rule takes its colours; [accent] is still the solid
  /// colour they are drawn in.
  final VerseInk accentInk;

  /// The size the card is set at, instead of the one it works out from
  /// its own length. Every part of a verse cut into lines is set at the
  /// one size (see `VersePart.fit`), so the type does not change size
  /// from one part to the next. Null for a whole verse.
  final double? fit;

  /// Whether the verse-end sign follows the last word, when [numbering]
  /// asks for one. False on every part of a cut verse but its last: the
  /// sign ends the verse, not each line of it.
  final bool endMark;

  /// Display tokens from this one on wait faint, for the unveil: the
  /// words the reciter has not reached yet. Colour only, so the layout
  /// is the same as the plain card's.
  final int? dimFrom;

  /// Draws the Arabic's letters alone, in light, with everything else
  /// laid out but transparent: the picture the band of light that
  /// passes through the words is cut from. Laid out exactly as the
  /// plain card, so the light lands on the letters it lights.
  final bool glint;

  AyahOverlay({
    super.key,
    VerseTranslation? translation,
    TranslationFace? translationFace,
    VerseNumbering? numbering,
    bool? showTranslation,
    required this.ayah,
    this.surah = 0,
    this.width = 1080,
    this.textColor = Colors.white,
    this.textScale = 1.0,
    this.preset = TextPreset.classic,
    this.highlightTokens,
    this.onLight = false,
    this.verseFace = VerseFace.uthmani,
    this.accent,
    this.ink = VerseInk.none,
    this.accentInk = VerseInk.none,
    this.fit,
    this.endMark = true,
    this.dimFrom,
    this.glint = false,
  })  : numbering =
            numbering ?? SettingsService.state.value.verseNumbering,
        translation = translation ?? SettingsService.state.value.translation,
        showTranslation = showTranslation ??
            !SettingsService.state.value.verseTranslationOff,
        translationFace = translationFace ??
            TranslationFace.defaultFor(
                arabicScript: (translation ??
                        SettingsService.state.value.translation)
                    .arabicScript);

  /// The house accent for a card nobody has given one: gold, taken a
  /// shade deeper on a pale band, because bright gold on ivory is
  /// barely a colour at all.
  static Color defaultAccentFor({bool onLight = false}) =>
      onLight ? AppColors.gold : AppColors.goldBright;

  /// Deterministic function of the verse colour, the accent and the
  /// ground, so preview and export can never disagree: the accent,
  /// unless it is so close to the verse's own colour that lighting a
  /// word with it would not show — and then whichever of black and
  /// white the verse itself does not look like.
  ///
  /// The old form of this was an equality test against the one gold
  /// the app offered. A palette makes that the wrong question: gold on
  /// bright gold is the case it caught, and amber on gold is the same
  /// case with different literals.
  ///
  /// The house gold stands in before the contrast ink does, and that
  /// order is the whole of the fix. Straight to the contrast ink is
  /// how the first version of this could hand back the verse's own
  /// colour: a white verse with a sand accent is two pale colours 108
  /// apart, so the accent is refused — and the contrast colour for
  /// darkened scenery is white, which is exactly what the verse was
  /// already set in. The highlight vanished outright.
  ///
  /// Gold is the right thing to fall back to because it is what this
  /// app has always lit a word in, and because it reads on either
  /// ground — where near-black on a gold verse over dark scenery
  /// reads as a hole rather than as a highlight. The contrast ink is
  /// the last resort, for a verse that is itself gold.
  static Color highlightColorFor(Color textColor,
      {bool onLight = false, Color? accent}) {
    final house = defaultAccentFor(onLight: onLight);
    final a = accent ?? house;
    if (!_tooClose(a, textColor)) return a;
    if (!_tooClose(house, textColor)) return house;
    return onLight ? const Color(inkOnLight) : Colors.white;
  }

  /// Whether two colours are near enough that one cannot be seen
  /// against the other. Plain channel distance: the two golds sit at
  /// 96 of it and have to count as one colour, and so do the several
  /// other pairs of neighbours the palette offers — deep gold and
  /// amber are 36 apart. Being generous here is safe, because what a
  /// refused accent falls back to is a colour chosen to contrast with
  /// the verse rather than a fixed one that might not.
  static bool _tooClose(Color a, Color b) {
    final x = a.toARGB32(), y = b.toARGB32();
    var d = 0;
    for (var shift = 0; shift <= 16; shift += 8) {
      d += (((x >> shift) & 0xFF) - ((y >> shift) & 0xFF)).abs();
    }
    return d < 120;
  }

  /// The rule and the lit word, resolved.
  Color get _accent => accent ?? defaultAccentFor(onLight: onLight);

  /// What the text's own shadows are drawn in.
  ///
  /// Black everywhere the verse sits on scenery — the scrim guarantees
  /// a dark ground there, so a dark halo is what lifts the letters off
  /// it. On a pale band that same halo just smears: the ink has already
  /// flipped dark, and a black blur behind dark letters on ivory reads
  /// as dirt. So the halo follows the ink instead of the app's default,
  /// which also covers the case nobody plans for — a pale verse colour
  /// deliberately kept on a pale band, where a dark outline is the only
  /// thing holding it together.
  Color get _halo =>
      onLight ? Color(legibleInkOn(textColor.toARGB32())) : Colors.black;

  /// The gold rule between the verse and its translation. Named so a
  /// test can pin that every preset draws it.
  static const dividerKey = ValueKey('verse-divider');

  /// The reference line under the translation, named for the same
  /// reason as [dividerKey].
  static const referenceKey = ValueKey('verse-reference');

  /// Long verses shrink smoothly so even the longest ayah fits the
  /// 9:16 frame; short verses keep the full display size. Pure function
  /// of the text, so preview and export always agree.
  static double _fit(int chars, int comfortable) {
    if (chars <= comfortable) return 1;
    return math.pow(comfortable / chars, 0.45).toDouble();
  }

  /// [_fit] for a translation of [chars] characters alone: what a part
  /// of a cut verse is set at, whose Arabic always fits at full size.
  static double translationFit(int chars) => _fit(chars, 220);

  /// The size factor a whole verse is set at.
  static double fitFor(Ayah ayah, {required bool showTranslation}) =>
      math.min(_fit(ayah.arabic.length, 120),
          _fit(showTranslation ? ayah.translation.length : 0, 220));

  /// The Arabic's text style, as [_arabic] sets it, for laying the
  /// verse out without building the card: what the splitter measures a
  /// part by. Shadows and colour change nothing about where a line
  /// breaks, so they are left out.
  static TextStyle verseLayoutStyle({
    required double width,
    required double textScale,
    required TextPreset preset,
    required VerseFace face,
    required double fit,
  }) {
    final ts = width / 1080 * textScale * fit * _presetSize(preset);
    return AppTheme.quran(size: 64 * ts, face: face);
  }

  /// The verse-end sign as [_markSpan] draws it, for the same purpose.
  static TextSpan endMarkLayoutSpan({
    required double width,
    required double textScale,
    required TextPreset preset,
    required VerseFace face,
    required double fit,
    required int ayah,
  }) {
    final ts = width / 1080 * textScale * fit * _presetSize(preset);
    final base = AppTheme.quran(size: 64 * ts, face: face);
    final m = ayahEndMark(face, ayah);
    final mf = AppTheme.quran(size: 64 * ts, face: m.face);
    return TextSpan(
      text: ' ${m.text}',
      style: base.copyWith(
        fontFamily: mf.fontFamily,
        fontFamilyFallback: mf.fontFamilyFallback,
        fontSize: mf.fontSize,
      ),
    );
  }

  /// How wide the verse's lines may run on a card [width] wide.
  static double lineWidth(double width) => width - 2 * 72 * (width / 1080);

  static double _presetSize(TextPreset p) =>
      p == TextPreset.minimal ? 0.85 : 1.0;

  /// The light the glint is drawn in: warm white, haloed in gold.
  static const glintColour = Color(0xFFFFF6DC);

  List<Shadow> _arabicShadows(double ts) {
    final halo = _halo;
    switch (preset) {
      case TextPreset.classic:
        return [
          Shadow(
            color: halo.withValues(alpha: 0.75),
            blurRadius: 24 * ts,
            offset: Offset(0, 3 * ts),
          ),
        ];
      case TextPreset.glow:
        // Colored halo around the letters plus a soft base in the
        // contrast colour, so it still reads on bright footage.
        return [
          Shadow(color: textColor.withValues(alpha: 0.85), blurRadius: 34 * ts),
          Shadow(color: textColor.withValues(alpha: 0.45), blurRadius: 70 * ts),
          Shadow(
            color: halo.withValues(alpha: 0.55),
            blurRadius: 18 * ts,
            offset: Offset(0, 3 * ts),
          ),
        ];
      case TextPreset.minimal:
        return [
          Shadow(
            color: halo.withValues(alpha: 0.6),
            blurRadius: 14 * ts,
            offset: Offset(0, 2 * ts),
          ),
        ];
    }
  }

  /// The verse line. With a highlight range the same string is emitted
  /// as per-token spans differing only in color — glyphs, spacing and
  /// shaping stay byte-identical to the plain rendering.
  Widget _arabic(double ts) => VerseTextAnchor(child: _arabicText(ts));

  Widget _arabicText(double ts) {
    if (glint) return _glinted(ts);
    final style = AppTheme.quran(size: 64 * ts, color: textColor, face: verseFace)
        .copyWith(
            shadows:
                ink.isNone ? _arabicShadows(ts) : ink.shadows(ts, halo: _halo));
    final mark = endMark ? _markSpan(ts, style) : null;
    if (!ink.isNone) return _inked(style, _litStyle(ts, style), mark);
    final hl = highlightTokens;
    final dim = dimFrom;
    if (hl == null && dim == null) {
      if (mark == null) {
        return Text(
          ayah.arabic,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: style,
        );
      }
      return Text.rich(
        TextSpan(children: [TextSpan(text: ayah.arabic), mark]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: style,
      );
    }
    final hlStyle = _litStyle(ts, style);
    final faint = _faint(style);
    final tokens = ayah.arabic.split(' ');
    final spans = <TextSpan>[];
    for (var i = 0; i < tokens.length; i++) {
      final lit = hl != null && i >= hl.start && i < hl.end;
      final waiting = !lit && dim != null && i >= dim;
      spans.add(TextSpan(
        text: i == 0 ? tokens[i] : ' ${tokens[i]}',
        style: lit ? hlStyle : (waiting ? faint : style),
      ));
    }
    if (mark != null) spans.add(mark);
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      style: style,
    );
  }

  /// A word the reciter has not reached yet, in the unveil: the verse's
  /// own style, faint, its halo faded with it so no dark smudge is left
  /// around letters that are barely there.
  static TextStyle _faint(TextStyle style) {
    const share = 0.28;
    final c = style.color ?? Colors.white;
    return style.copyWith(
      color: c.withValues(alpha: c.a * share),
      shadows: [
        for (final s in style.shadows ?? const <Shadow>[])
          Shadow(
            color: s.color.withValues(alpha: s.color.a * share),
            blurRadius: s.blurRadius,
            offset: s.offset,
          ),
      ],
    );
  }

  /// The glint: the letters alone, in light. The verse-end sign is laid
  /// out but not drawn, so the lines break exactly where the card's do.
  Widget _glinted(double ts) {
    final tint = lightTintOf(_accent, accentInk);
    final style = AppTheme.quran(
            size: 64 * ts, color: glintColourFor(tint), face: verseFace)
        .copyWith(shadows: glintGlowFor(ts, tint));
    final mark = endMark ? _markSpan(ts, style) : null;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: ayah.arabic),
        if (mark != null)
          TextSpan(
            text: mark.text,
            style: mark.style!
                .copyWith(color: const Color(0x00000000), shadows: const []),
          ),
      ]),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      style: style,
    );
  }

  /// The word being recited: the verse's own style in the highlight
  /// colour, and glowing when the accent is an ink — unless the accent
  /// was refused as too close to the verse, in which case what lights
  /// the word is not the ink's colour and its glow would be a stranger.
  TextStyle _litStyle(double ts, TextStyle style) {
    final lit =
        highlightColorFor(textColor, onLight: onLight, accent: accent);
    if (accentInk.isNone || lit != _accent) {
      // On a dark ground the word being recited glows a little in its
      // own colour, as if lit from within; on a pale band a glow only
      // muddies it, so there it is the colour alone.
      if (onLight) return style.copyWith(color: lit);
      return style.copyWith(color: lit, shadows: [
        ...?style.shadows,
        Shadow(color: lit.withValues(alpha: litGlowAlpha), blurRadius: 16 * ts),
      ]);
    }
    return style.copyWith(
        color: lit, shadows: [...?style.shadows, ...accentInk.accentGlow(ts)]);
  }

  /// How strongly the recited word's glow shows on a dark ground.
  static const litGlowAlpha = 0.5;

  /// The glow the glint's letters are drawn with, at type scale [ts]:
  /// close about each letter, so a band cut from the glint lights the
  /// letters it crosses and not a box of haze around them. One
  /// definition for the preview's light and the exported glint card.
  static List<Shadow> glintGlow(double ts) => [
        Shadow(
            color: const Color(0xFFFFD27A).withValues(alpha: 0.8),
            blurRadius: 10 * ts),
        Shadow(
            color: const Color(0xFFE8A93A).withValues(alpha: 0.3),
            blurRadius: 20 * ts),
      ];

  /// The colour the light passing through the letters takes: the
  /// accent's, which is the motion's colour too — the reel's own gold
  /// unless another was chosen, and a luminous accent's own light.
  static Color lightTintOf(Color accent, VerseInk accentInk) =>
      accentInk.isNone ? accent : Color(accentInk.glow);

  /// Whether [tint] is one of the reel's own two golds: those keep the
  /// light exactly as it was drawn before it could take a colour, so the
  /// default look, and every reel cached with it, is unchanged.
  static bool isHouseGold(Color tint) {
    final v = tint.toARGB32() & 0xFFFFFF;
    return v == (accentOnDark & 0xFFFFFF) || v == (accentOnLight & 0xFFFFFF);
  }

  /// The glint's letters in the light's [tint]: nearly white, warmed (or
  /// cooled) by the tint, the way a bright light keeps a little of its
  /// colour at its core.
  static Color glintColourFor(Color tint) => isHouseGold(tint)
      ? glintColour
      : Color.lerp(tint, const Color(0xFFFFFFFF), 0.8)!;

  /// [glintGlow] in the light's [tint].
  static List<Shadow> glintGlowFor(double ts, Color tint) {
    if (isHouseGold(tint)) return glintGlow(ts);
    return [
      Shadow(
          color: Color.lerp(tint, const Color(0xFFFFFFFF), 0.35)!
              .withValues(alpha: 0.8),
          blurRadius: 10 * ts),
      Shadow(color: tint.withValues(alpha: 0.3), blurRadius: 20 * ts),
    ];
  }

  /// The verse in a luminous ink.
  ///
  /// Two copies of one paragraph, stacked. They differ only in colour,
  /// so they lay out to the same glyphs on the same pixels, which is
  /// the same guarantee the word highlight already rests on. The lower
  /// one draws the light: every plain letter transparent with its
  /// shadows still painted, and the lit word and the verse-end sign in
  /// their own solid colours. The upper one draws the plain letters
  /// only, in white, and the ink's gradient is laid into exactly those
  /// pixels. The fill never covers the lit word, and the glow is never
  /// drawn over the fill.
  Widget _inked(TextStyle style, TextStyle litStyle, TextSpan? mark) {
    const clear = Color(0x00000000);
    final hl = highlightTokens;
    final dim = dimFrom;
    final tokens = hl == null && dim == null
        ? [ayah.arabic]
        : ayah.arabic.split(' ');
    bool lit(int i) => hl != null && i >= hl.start && i < hl.end;
    bool waiting(int i) => !lit(i) && dim != null && i >= dim;
    String text(int i) => i == 0 ? tokens[i] : ' ${tokens[i]}';

    final glow = style.copyWith(color: clear);
    final fill = style.copyWith(color: const Color(0xFFFFFFFF), shadows: []);
    final hole = style.copyWith(color: clear, shadows: []);
    final faintGlow = _faint(glow);
    final faintFill = fill.copyWith(color: const Color(0x47FFFFFF));

    Widget paragraph(List<TextSpan> spans, TextStyle root) => Text.rich(
          TextSpan(children: spans),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: root,
        );

    return Stack(
      children: [
        paragraph([
          for (var i = 0; i < tokens.length; i++)
            TextSpan(
                text: text(i),
                style: lit(i) ? litStyle : (waiting(i) ? faintGlow : glow)),
          if (mark != null) mark,
        ], glow),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => ink.gradient.createShader(bounds),
          child: paragraph([
            for (var i = 0; i < tokens.length; i++)
              TextSpan(
                  text: text(i),
                  style: lit(i) ? hole : (waiting(i) ? faintFill : fill)),
            if (mark != null)
              TextSpan(
                  text: mark.text,
                  style: mark.style!.copyWith(color: clear, shadows: [])),
          ], fill),
        ),
      ],
    );
  }

  /// The numbered end-of-verse sign, after the last word, when
  /// [numbering] asks for it.
  ///
  /// Its own span, after the verse's tokens rather than inside
  /// [Ayah.arabic], so the word highlight's token indices still count
  /// the verse's words and nothing else. Joined to the last word by a
  /// no-break space: a sign wrapped onto a line of its own would be
  /// ending nothing. In the accent, as a mushaf sets its ornaments
  /// apart from the text, and never lit by the highlight — it is not a
  /// word anybody recites.
  TextSpan? _markSpan(double ts, TextStyle verseStyle) {
    if (!numbering.showsMark) return null;
    final m = ayahEndMark(verseFace, ayah.number);
    final face = AppTheme.quran(size: 64 * ts, face: m.face);
    return TextSpan(
      text: '\u00A0${m.text}',
      style: verseStyle.copyWith(
        fontFamily: face.fontFamily,
        fontFamilyFallback: face.fontFamilyFallback,
        fontSize: face.fontSize,
        color: _accent,
        shadows: accentInk.isNone
            ? null
            : [...?verseStyle.shadows, ...accentInk.accentGlow(ts)],
      ),
    );
  }

  /// The reference line — "Al-Baqarah 2:255" — when [numbering] asks
  /// for it and the card knows its surah; null otherwise.
  Widget? _reference(double ts) {
    if (!numbering.showsReference) return null;
    final line = verseReferenceLine(surah, ayah.number, translation);
    if (line.isEmpty) return null;
    return Text(
      line,
      key: referenceKey,
      textAlign: TextAlign.center,
      textDirection: translation.direction,
      style: AppTheme.translation(
        size: 24 * ts,
        arabic: translation.arabicScript,
        face: translationFace,
        color: glint ? Colors.transparent : textColor.withValues(alpha: 0.7),
      ).copyWith(
        fontStyle: FontStyle.normal,
        letterSpacing: translation.arabicScript ? 0 : 1.2 * ts,
        shadows: glint
            ? const []
            : [
                Shadow(
                  color: _halo.withValues(alpha: 0.8),
                  blurRadius: 14 * ts,
                  offset: Offset(0, 2 * ts),
                ),
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = width / 1080;
    // Text grows/shrinks with the user setting; frame padding does not,
    // so resizing never changes the usable line width. One shared fit
    // factor keeps the Arabic and translation proportioned.
    final fit = this.fit ?? fitFor(ayah, showTranslation: showTranslation);
    final ts = scale * textScale * fit * _presetSize(preset);
    final reference = _reference(ts);
    // One thing to a screen reader — the verse and its meaning — not
    // two lines of text with a rule between them. The exporter
    // rasterizes this offscreen, where semantics cost nothing.
    return MergeSemantics(
      child: SizedBox(
      width: width,
      child: Padding(
        // An ink's light reaches above the first line's letters, and
        // the exporter captures the card shrink-wrapped, so without
        // room for it the file would show the glow cut flat across the
        // top while the preview did not. Only for an ink, so every
        // other card keeps the box it has always had.
        padding: EdgeInsets.fromLTRB(
            72 * scale, ink.isNone ? 0 : 36 * scale, 72 * scale, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _arabic(ts),
            if (showTranslation) ...[
              SizedBox(height: 28 * scale),
              // The gold rule sits under every preset, not just the
              // classic one: it is what tells the eye where the verse
              // ends and the translation begins, and glow and minimal
              // need that reading just as much.
              Container(
                key: dividerKey,
                width: 120 * scale,
                height: 2 * scale,
                decoration: glint
                    ? null
                    : BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.transparent,
                    // Whatever the reel's accent is — the house gold
                    // unless the user chose otherwise, and on a pale
                    // band the deeper of the two, because the bright one
                    // is all but invisible on ivory. An inked accent
                    // lays its whole fill along the rule instead.
                    if (accentInk.isNone)
                      _accent.withValues(alpha: 0.9)
                    else
                      for (final c in accentInk.fill)
                        Color(c).withValues(alpha: 0.9),
                    Colors.transparent,
                  ]),
                ),
              ),
              SizedBox(height: 28 * scale),
              Text(
                ayah.translation,
                textAlign: TextAlign.center,
                // The line runs in its own edition's direction, not the
                // card's: the Arabic above is always RTL, but an Urdu
                // translation is RTL where a German one is not, and a
                // right-to-left line laid out left-to-right puts its
                // punctuation on the wrong end.
                textDirection: translation.direction,
                style: AppTheme.translation(
                  size: 30 * ts,
                  arabic: translation.arabicScript,
                  face: translationFace,
                  color: glint
                      ? Colors.transparent
                      : textColor.withValues(
                          alpha: preset == TextPreset.minimal ? 0.75 : 0.85),
                ).copyWith(
                  shadows: glint
                      ? const []
                      : [
                          Shadow(
                            color: _halo.withValues(alpha: 0.8),
                            blurRadius: 16 * ts,
                            offset: Offset(0, 2 * ts),
                          ),
                          if (!ink.isNone) ink.translationGlow(ts),
                        ],
                ),
              ),
            ],
            if (reference != null) ...[
              SizedBox(height: 20 * scale),
              reference,
            ],
          ],
        ),
      ),
      ),
    );
  }
}
