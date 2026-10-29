import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The three pieces of the app's illuminated-manuscript vocabulary,
/// shared rather than copied so that onboarding, the Home header and
/// the Create card are demonstrably the same place. What the onboarding
/// promises has to be what the user lands in, down to the ornament.

/// A sparse, deterministic star field — a hint of night sky, never
/// noise.
class Starfield extends StatelessWidget {
  final int count;

  /// Fixed per instance so the sky never flickers between frames.
  final int seed;

  /// Fades the stars out toward the bottom edge, for a field that sits
  /// behind content rather than under it.
  final bool fade;

  const Starfield({
    super.key,
    this.count = 46,
    this.seed = 7,
    this.fade = true,
  });

  @override
  Widget build(BuildContext context) {
    final field = CustomPaint(painter: _StarfieldPainter(count, seed));
    if (!fade) return field;
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.transparent],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: field,
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  final int count;
  final int seed;
  const _StarfieldPainter(this.count, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.5 + rnd.nextDouble() * 0.9;
      final gold = rnd.nextDouble() < 0.3;
      paint.color = (gold ? AppColors.gold : Colors.white)
          .withValues(alpha: 0.10 + rnd.nextDouble() * 0.22);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter old) =>
      old.count != count || old.seed != seed;
}

/// A hairline that fades toward the text it flanks, ending in a tiny
/// diamond — the manuscript divider, reduced to two strokes.
class OrnamentRule extends StatelessWidget {
  /// Direction the line fades: true = fades toward the end side (the
  /// right in a left-to-right layout), so it sits after whatever it
  /// flanks. The [Row] it is built from mirrors in a right-to-left
  /// layout, so the gap and the fade mirror with it; set physically,
  /// they faded the line away from its diamond in Arabic and Urdu.
  final bool leftToRight;
  const OrnamentRule({super.key, required this.leftToRight});

  @override
  Widget build(BuildContext context) {
    final diamond = Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
    // The gap lives inside the flexible half rather than beside it as a
    // fixed box: squeezed into a narrow slot the rule then shrinks to
    // nothing instead of overflowing the row it sits in.
    final line = Expanded(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: leftToRight ? 6 : 0,
          end: leftToRight ? 0 : 6,
        ),
        child: Container(
          height: 0.8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: leftToRight
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              end: leftToRight
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              colors: [
                AppColors.gold.withValues(alpha: 0.55),
                AppColors.gold.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
    return Row(
      children: leftToRight ? [diamond, line] : [line, diamond],
    );
  }
}

/// The Bismillah set between two ornament rules — the app's one piece
/// of letterhead. Scales down rather than overflowing on small phones.
class BismillahOrnament extends StatelessWidget {
  final double fontSize;
  final double maxTextWidth;
  const BismillahOrnament({
    super.key,
    this.fontSize = 16,
    this.maxTextWidth = 200,
  });

  @override
  Widget build(BuildContext context) {
    // Its own stop for a screen reader, in its place on the page.
    return Semantics(
      container: true,
      child: Row(
      children: [
        const Expanded(child: OrnamentRule(leftToRight: false)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxTextWidth),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
                style: AppTheme.quran(
                        size: fontSize, color: AppColors.goldBright)
                    .copyWith(height: 1.4),
              ),
            ),
          ),
        ),
        const Expanded(child: OrnamentRule(leftToRight: true)),
      ],
      ),
    );
  }
}

/// A soft lamp-glow: a radial gold wash with no hard edge. Used behind
/// emblems and in the corners of the Create card.
class GlowOrb extends StatelessWidget {
  final double size;
  final double alpha;
  const GlowOrb({super.key, required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.gold.withValues(alpha: alpha),
                AppColors.gold.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
