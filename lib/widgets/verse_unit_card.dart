import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../data/verse_lines.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
import '../state/creation_state.dart' show TextPreset;
import 'ayah_overlay.dart';

/// The card for one unit of a reel: a whole verse, or one part of a
/// verse cut into lines.
///
/// A part is set at its verse's one size ([VersePart.fit]), carries the
/// verse-end sign only if it is the last, and is held to the height of
/// the tallest part of its verse, centred in it. So the type keeps its
/// size from one part to the next, and the mark that hangs off the
/// card's bottom edge stays put while the parts change above it.
///
/// The preview draws this and the exporter rasterizes it, which is the
/// same guarantee [AyahOverlay] gives: what is approved is what is made.
class VerseUnitCard extends StatelessWidget {
  final Ayah ayah;

  /// Null for the whole verse.
  final VersePart? part;
  final double width;
  final Color textColor;
  final double textScale;
  final TextPreset preset;
  final bool onLight;
  final VerseTranslation translation;
  final VerseNumbering numbering;
  final bool showTranslation;
  final int surah;
  final VerseFace verseFace;
  final TranslationFace translationFace;
  final Color? accent;
  final VerseInk ink;
  final VerseInk accentInk;

  /// Tokens of the unit's own text (the part's, for a part) lit, faint,
  /// or the glint — see [AyahOverlay].
  final ({int start, int end})? highlightTokens;
  final int? dimFrom;
  final bool glint;

  const VerseUnitCard({
    super.key,
    required this.ayah,
    this.part,
    required this.width,
    required this.textColor,
    required this.textScale,
    required this.preset,
    required this.onLight,
    required this.translation,
    required this.numbering,
    required this.showTranslation,
    required this.surah,
    required this.verseFace,
    required this.translationFace,
    this.accent,
    this.ink = VerseInk.none,
    this.accentInk = VerseInk.none,
    this.highlightTokens,
    this.dimFrom,
    this.glint = false,
  });

  /// The unit's text as a card shows it: the part's own, or the verse.
  static Ayah textOf(Ayah ayah, VersePart? part) => part == null
      ? ayah
      : Ayah(
          number: ayah.number,
          arabic: part.arabic,
          translation: part.translation);

  @override
  Widget build(BuildContext context) {
    final p = part;
    final card = AyahOverlay(
      ayah: textOf(ayah, p),
      width: width,
      textColor: textColor,
      textScale: textScale,
      preset: preset,
      onLight: onLight,
      translation: translation,
      numbering: numbering,
      showTranslation: showTranslation,
      surah: surah,
      verseFace: verseFace,
      translationFace: translationFace,
      accent: accent,
      ink: ink,
      accentInk: accentInk,
      fit: p?.fit,
      endMark: p == null || p.isLast,
      highlightTokens: highlightTokens,
      dimFrom: dimFrom,
      glint: glint,
    );
    if (p == null || p.height <= 0) return card;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: p.height * width / 1080),
      child: Align(widthFactor: 1, heightFactor: 1, child: card),
    );
  }
}
