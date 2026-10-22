import 'package:flutter/widgets.dart';

import '../data/band_glow.dart';
import '../render/letterbox_layout.dart';

/// A luminous ground filling its box, as [BandGlow.paint] draws it: the
/// band behind a wide card on the style step and the reel screen, and
/// the picture the exporter rasterizes for the saved reel.
class BandGlowGround extends StatelessWidget {
  final BandGlow glow;

  /// The card it frames, which its light is centred on; null for a
  /// swatch, which is lit in the middle.
  final LetterboxGeometry? box;

  const BandGlowGround({super.key, required this.glow, this.box});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _BandPainter(glow, box),
          size: Size.infinite,
        ),
      );
}

class _BandPainter extends CustomPainter {
  final BandGlow glow;
  final LetterboxGeometry? box;

  const _BandPainter(this.glow, this.box);

  @override
  void paint(Canvas canvas, Size size) {
    final b = box;
    glow.paint(
      canvas,
      Offset.zero & size,
      cardCentre: b?.cardCentre ?? const Offset(0.5, 0.42),
      verseCentre: b?.bandCentre ?? const Offset(0.5, 0.72),
    );
  }

  @override
  bool shouldRepaint(covariant _BandPainter old) =>
      old.glow != glow || old.box?.key != box?.key;
}
