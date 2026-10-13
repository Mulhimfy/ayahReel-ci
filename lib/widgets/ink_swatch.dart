import 'package:flutter/material.dart';

import '../data/verse_ink.dart';
import '../theme/app_theme.dart';

/// A luminous ink as a disc: its fill across the face, its light
/// around the rim. Where a flat swatch is one colour, this is the
/// smallest honest picture of an ink.
class InkDisc extends StatelessWidget {
  final VerseInk ink;
  final double size;
  final bool selected;

  const InkDisc({
    super.key,
    required this.ink,
    required this.size,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ink.gradient,
        border: Border.all(
          color: selected
              ? AppColors.gold
              : Colors.white.withValues(alpha: 0.18),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(ink.glow).withValues(alpha: 0.55),
            blurRadius: size * 0.45,
          ),
        ],
      ),
    );
  }
}

/// A word written in a luminous ink, the way [AyahOverlay] writes the
/// verse: the light from transparent letters underneath, the fill laid
/// into the letters on top. For the picker, which has to show what an
/// ink does to letters and not only what colours it is made of.
class InkSpecimen extends StatelessWidget {
  final String text;
  final VerseInk ink;

  /// The face and size to set [text] in. Its colour and shadows are the
  /// ink's business and are ignored.
  final TextStyle style;

  /// What the letters are lifted off, as [AyahOverlay] picks it: black
  /// on scenery, the ink's opposite on a pale band.
  final Color halo;

  /// The scale of the ink's shadows, against a verse at export size.
  final double scale;

  const InkSpecimen({
    super.key,
    required this.text,
    required this.ink,
    required this.style,
    required this.halo,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    Widget line(TextStyle s) => Text(
          text,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: s,
        );
    return Stack(
      alignment: Alignment.center,
      children: [
        line(style.copyWith(
          color: const Color(0x00000000),
          shadows: ink.shadows(scale, halo: halo),
        )),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => ink.gradient.createShader(bounds),
          child: line(style.copyWith(color: Colors.white, shadows: [])),
        ),
      ],
    );
  }
}
