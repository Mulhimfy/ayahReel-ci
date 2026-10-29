import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// A luminous ink as a small square: its fill corner to corner and its
/// light around the edge. The strip's swatch, where a row of discs
/// would read as buttons of equal weight to the flat colours under it.
class InkSquare extends StatelessWidget {
  final VerseInk ink;
  final double size;

  const InkSquare({super.key, required this.ink, required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.26),
          gradient: ink.gradient,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Color(ink.glow).withValues(alpha: 0.5),
              blurRadius: size * 0.4,
            ),
          ],
        ),
      );
}

/// The luminous inks in one line that scrolls sideways: small squares,
/// each its own fill and light, ringed in gold when it is the one.
///
/// One line, not a grid: the inks are the special colours, and two rows
/// of discs above the palette made them the heaviest thing on the panel.
/// The chosen one is scrolled into view when the strip first shows, and
/// the ends fade so a finger knows there is more.
class InkStrip extends StatefulWidget {
  final List<VerseInk> inks;

  /// The ink in use, or null when the colour is a flat one.
  final VerseInk? selected;
  final ValueChanged<VerseInk> onPick;

  /// What a screen reader calls each square.
  final String Function(VerseInk ink) labelOf;

  /// Swatches before the inks that are not inks — the motion's gold —
  /// laid at the same size and in the same line.
  final List<Widget> leading;

  final double size;

  const InkStrip({
    super.key,
    required this.inks,
    required this.selected,
    required this.onPick,
    required this.labelOf,
    this.leading = const [],
    this.size = 24,
  });

  @override
  State<InkStrip> createState() => _InkStripState();
}

class _InkStripState extends State<InkStrip> {
  final _scroll = ScrollController();
  final _chosen = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _chosen.currentContext;
      if (!mounted || c == null) return;
      Scrollable.ensureVisible(c, alignment: 0.5);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final cell = s + 11;
    return SizedBox(
      height: cell,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        // A fade narrower than the padding, so it dims only what has
        // scrolled under the edge, never the first swatch at rest.
        shaderCallback: (r) {
          final f = r.width <= 0 ? 0.0 : (10 / r.width).clamp(0.0, 0.2);
          return LinearGradient(
            colors: const [
              Color(0x00FFFFFF),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0, f, 1 - f, 1],
          ).createShader(r);
        },
        child: ListView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final w in widget.leading)
              SizedBox(width: cell, height: cell, child: Center(child: w)),
            for (final ink in widget.inks)
              SizedBox(
                key: ink == widget.selected ? _chosen : null,
                width: cell,
                height: cell,
                child: Center(child: _square(ink)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _square(VerseInk ink) {
    final on = ink == widget.selected;
    final s = widget.size;
    return Semantics(
      button: true,
      selected: on,
      label: widget.labelOf(ink),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onPick(ink);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(s * 0.26 + 3),
            border: Border.all(
              color: on ? AppColors.gold : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: InkSquare(ink: ink, size: s),
        ),
      ),
    );
  }
}

/// The luminous inks as squares in [rows] rows sharing the width evenly:
/// every one in view at once, nothing to scroll to sideways or down, each
/// as large as the width allows, up to [most].
///
/// The verse colour's panel lays them out this way. One line of small
/// squares that scrolled hid most of them behind the edge; two rows of
/// wide squares show the whole set, and still leave the panel room for
/// the flat colours without a scroll.
class InkGrid extends StatelessWidget {
  final List<VerseInk> inks;
  final VerseInk? selected;
  final ValueChanged<VerseInk> onPick;
  final String Function(VerseInk ink) labelOf;
  final int rows;

  /// The largest a square grows, on a wide phone.
  final double most;

  const InkGrid({
    super.key,
    required this.inks,
    required this.selected,
    required this.onPick,
    required this.labelOf,
    this.rows = 2,
    this.most = 34,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const pad = 12.0;
        final perRow = (inks.length / rows).ceil();
        final cell = perRow == 0
            ? most + 6
            : math.min(most + 6, (box.maxWidth - 2 * pad) / perRow);
        final size = (cell - 6).clamp(16.0, most);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows; r++)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = r * perRow;
                      i < math.min(inks.length, (r + 1) * perRow);
                      i++)
                    SizedBox(
                      width: cell,
                      height: cell,
                      child: Center(
                        child: _InkButton(
                          ink: inks[i],
                          on: inks[i] == selected,
                          size: size,
                          label: labelOf(inks[i]),
                          onPick: onPick,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// One ink square that can be picked: a gold ring round the one in use.
class _InkButton extends StatelessWidget {
  final VerseInk ink;
  final bool on;
  final double size;
  final String label;
  final ValueChanged<VerseInk> onPick;

  const _InkButton({
    required this.ink,
    required this.on,
    required this.size,
    required this.label,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onPick(ink);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.26 + 3),
            border: Border.all(
              color: on ? AppColors.gold : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: InkSquare(ink: ink, size: size - 4),
        ),
      ),
    );
  }
}
