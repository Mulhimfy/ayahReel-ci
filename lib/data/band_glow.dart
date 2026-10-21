import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A luminous ground for the band around a wide card: what the verse's
/// inks are to its letters, for the space above and below the card.
///
/// A flat colour there reads as a frame; the band was the one part of a
/// wide-card reel that could not be more than a colour. Each of these is
/// a deep gradient with a bloom of light behind the card and a softer
/// one where the verse sits, so the card sits in its own light and the
/// verse in a glow of the same colour.
///
/// Painted by [paint] alone: live on the style step and the reel screen,
/// and into the PNG the exporter lays the card on, so the saved reel's
/// band is the one on screen.
///
/// Every ground carries a [base]: one solid colour that stands for it,
/// which is what the reel's `backdropArgb` is set to while it is chosen.
/// Everything that only asks whether the band is pale — the ink the
/// verse falls back to, the watermark's halo — asks that, and gets the
/// right answer.
enum BandGlow {
  /// Deep night blue, with a cold blue light.
  midnight(
    top: 0xFF050A1C,
    middle: 0xFF10204A,
    bottom: 0xFF040817,
    glow: 0xFF4C74FF,
    base: 0xFF0C173A,
  ),

  /// The green of the stone in shadow, lit from within.
  emerald(
    top: 0xFF03140E,
    middle: 0xFF0A3526,
    bottom: 0xFF02100B,
    glow: 0xFF1FCB8A,
    base: 0xFF08281D,
  ),

  /// Violet quartz, deep and glowing.
  amethyst(
    top: 0xFF0D0619,
    middle: 0xFF2B1356,
    bottom: 0xFF0A0514,
    glow: 0xFF9C63FF,
    base: 0xFF1F0F3F,
  ),

  /// The northern lights: teal into violet.
  aurora(
    top: 0xFF03141A,
    middle: 0xFF0B3B44,
    bottom: 0xFF160C3A,
    glow: 0xFF3FE0B0,
    base: 0xFF0B2B35,
  ),

  /// Embers: a dark red ground, a fire's orange light.
  ember(
    top: 0xFF150604,
    middle: 0xFF431509,
    bottom: 0xFF110403,
    glow: 0xFFFF6B2C,
    base: 0xFF2F0E07,
  ),

  /// Gold leaf in lamplight.
  gold(
    top: 0xFF140D03,
    middle: 0xFF3D2B0B,
    bottom: 0xFF100A02,
    glow: 0xFFF0B744,
    base: 0xFF2C1F08,
  ),

  /// The last of the day: plum into rose.
  dusk(
    top: 0xFF14081C,
    middle: 0xFF4A1C3E,
    bottom: 0xFF100616,
    glow: 0xFFFF6F9A,
    base: 0xFF34142E,
  ),

  /// Deep water, lit from far above.
  ocean(
    top: 0xFF020E1C,
    middle: 0xFF0A2E57,
    bottom: 0xFF020B17,
    glow: 0xFF3D9BFF,
    base: 0xFF072240,
  ),

  /// Rose gold, dark and warm.
  rose(
    top: 0xFF180C0F,
    middle: 0xFF40222A,
    bottom: 0xFF12090B,
    glow: 0xFFFF9AAE,
    base: 0xFF2E181E,
  ),

  /// Volcanic glass: near black, with a gold aura.
  obsidian(
    top: 0xFF040405,
    middle: 0xFF15161B,
    bottom: 0xFF030304,
    glow: 0xFFD8AE4E,
    base: 0xFF0E0F12,
  ),

  /// Mother-of-pearl: white with every pale colour in it. A pale band,
  /// so the verse takes dark ink on it.
  pearl(
    top: 0xFFF3EEF6,
    middle: 0xFFFFFFFF,
    bottom: 0xFFEEF3F8,
    glow: 0xFFFFC9E6,
    base: 0xFFF7F4F7,
  ),

  /// The first light: cream into peach. Pale, as pearl is.
  dawn(
    top: 0xFFFFF4E6,
    middle: 0xFFFFE6D2,
    bottom: 0xFFFFF1E2,
    glow: 0xFFFFB27E,
    base: 0xFFFFEEDD,
  );

  const BandGlow({
    required this.top,
    required this.middle,
    required this.bottom,
    required this.glow,
    required this.base,
  });

  /// The ground's gradient, top to bottom of the frame.
  final int top;
  final int middle;
  final int bottom;

  /// The colour of its light.
  final int glow;

  /// One solid colour that stands for it; see the class doc.
  final int base;

  /// Short and stable: what a render's cache key carries.
  String get key => name;

  /// Whether the ground is pale: the verse takes dark ink on it.
  bool get light {
    final r = (base >> 16) & 0xFF, g = (base >> 8) & 0xFF, b = base & 0xFF;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.55;
  }

  static BandGlow? fromName(String? name) {
    for (final g in values) {
      if (g.name == name) return g;
    }
    return null;
  }

  /// Paints the ground over [rect]: the gradient, a bloom of light
  /// centred on [cardCentre] (fractions of the frame), and a softer one
  /// on [verseCentre], where the verse sits. The frame is the export's
  /// 9:16 at any scale, so the preview and the exported PNG are the same
  /// picture.
  void paint(
    Canvas canvas,
    Rect rect, {
    Offset cardCentre = const Offset(0.5, 0.38),
    Offset verseCentre = const Offset(0.5, 0.7),
  }) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [Color(top), Color(middle), Color(bottom)],
          const [0.0, 0.55, 1.0],
        ),
    );
    final h = rect.height;
    final lightAlpha = light ? 0.34 : 0.46;
    void bloom(Offset at, double radius, double alpha) {
      final c = Offset(rect.left + rect.width * at.dx, rect.top + h * at.dy);
      final g = Color(glow);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            radius,
            [
              g.withValues(alpha: alpha),
              g.withValues(alpha: alpha * 0.32),
              g.withValues(alpha: 0),
            ],
            const [0.0, 0.42, 1.0],
          ),
      );
    }

    bloom(cardCentre, h * 0.6, lightAlpha);
    bloom(verseCentre, h * 0.36, lightAlpha * 0.5);
    // A breath of light along the band's very top and bottom edges, so
    // the frame reads as lit glass rather than a cut-out.
    final edge = math.max(1.0, h * 0.004);
    final sheen = Paint()
      ..shader = ui.Gradient.linear(
        rect.centerLeft,
        rect.centerRight,
        [
          Color(glow).withValues(alpha: 0),
          Color(glow).withValues(alpha: light ? 0.18 : 0.28),
          Color(glow).withValues(alpha: 0),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, rect.width, edge), sheen);
    canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.bottom - edge, rect.width, edge), sheen);
  }
}
