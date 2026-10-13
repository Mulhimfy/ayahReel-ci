import 'package:flutter/painting.dart';

/// A luminous ink: a verse colour that is more than a colour.
///
/// The palette's twenty-four swatches are flat. Flat reads as clean,
/// and next to a scenery it can also read as a caption. An ink is a
/// fill that moves across the letters (an iridescence, a metal's sheen,
/// fire cooling from white to red) plus the light it gives off, drawn
/// as the letters' own shadows. It is how the verse looks lit from
/// within rather than printed on top.
///
/// Every ink also carries a [base]: one solid colour that stands for
/// it. That is what the reel's `textArgb` is set to when an ink is
/// chosen, so everything that only knows about one verse colour (the
/// translation line, the highlight's contrast test, the cache key, a
/// build that predates inks reading a saved reel) still gets a colour
/// close to the one on screen.
///
/// Drawn by [AyahOverlay] in the preview and in the exporter's cards
/// alike, so the reel and the file cannot disagree about it.
enum VerseInk {
  /// A plain colour: the palette's swatch, and nothing else.
  none(fill: [], glow: 0, base: 0),

  /// Iridescence: lavender through sky and mint to pink, the colours
  /// an iris or a soap film shows when it turns in the light.
  iris(
    fill: [0xFFE7CCFF, 0xFFAFC9FF, 0xFFA9F2E1, 0xFFFFC8E8],
    glow: 0xFF9D7BFF,
    base: 0xFFD7CCF7,
  ),

  /// Fire cooling as it falls: white-hot at the top of the verse,
  /// embers at its foot, with an orange bloom around it.
  ember(
    fill: [0xFFFFF4C4, 0xFFFFC25C, 0xFFFF7A3D],
    glow: 0xFFFF5A1F,
    base: 0xFFFFB45A,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),

  /// The northern lights: green into teal into violet.
  aurora(
    fill: [0xFFA2FFD8, 0xFF5CE1E6, 0xFFB58EFF],
    glow: 0xFF36D39A,
    base: 0xFF8FE9DA,
  ),

  /// Gold leaf. Bands of light and shade across the verse, as on a
  /// gilded page turned to the lamp.
  gilded(
    fill: [0xFFC08A2E, 0xFFFFF0B3, 0xFFD9A441, 0xFFFFE7A3, 0xFFB27A24],
    glow: 0xFFE0A93A,
    base: 0xFFEEC96B,
    strength: 0.8,
  ),

  /// White, lit warm from behind.
  starlight(
    fill: [0xFFFFFFFF, 0xFFFFF5DC],
    glow: 0xFFFFC857,
    base: 0xFFFFFAEE,
  ),

  /// Silver, with a cold blue halo.
  moonlight(
    fill: [0xFFE9EFF9, 0xFFFFFFFF, 0xFFCBD5E8, 0xFFFFFFFF],
    glow: 0xFF8FB0FF,
    base: 0xFFE8EEF8,
  ),

  /// A star-forming cloud: pink, violet and blue, with a magenta glow.
  nebula(
    fill: [0xFFFFB7F0, 0xFFC38DFF, 0xFF7EA6FF],
    glow: 0xFFD65CFF,
    base: 0xFFC9A2FF,
  ),

  /// The last of the day: gold into coral into violet.
  sunset(
    fill: [0xFFFFD98C, 0xFFFF9090, 0xFFB880FF],
    glow: 0xFFFF6F91,
    base: 0xFFFFB08F,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),

  /// The first of it: cream, peach and pale gold, and a soft glow.
  dawn(
    fill: [0xFFFFF3E4, 0xFFFFCDB8, 0xFFFFE08C],
    glow: 0xFFFFB08A,
    base: 0xFFFFE2CC,
    strength: 0.8,
  ),

  /// Gold with copper and pink in it.
  roseGold(
    fill: [0xFFFFE3D8, 0xFFF4AA9C, 0xFFE0A383, 0xFFFFD8C8],
    glow: 0xFFFF8FA3,
    base: 0xFFF6C1B2,
    strength: 0.8,
  ),

  /// The red stone: pale rose to deep carnelian, glowing crimson.
  carnelian(
    fill: [0xFFFFD6D0, 0xFFFF7A6E, 0xFFD6333F],
    glow: 0xFFFF3355,
    base: 0xFFFF8C80,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),

  /// Mother-of-pearl: white with every pale colour in it, and only a
  /// breath of light around it.
  pearl(
    fill: [0xFFFFFFFF, 0xFFFBE7F1, 0xFFE3F1FF, 0xFFF6F1DA, 0xFFFFFFFF],
    glow: 0xFFFFD6EC,
    base: 0xFFF9F2F2,
    strength: 0.6,
  ),

  /// Violet quartz, pale at the top of the verse and deep at its foot.
  amethyst(
    fill: [0xFFF3DDFF, 0xFFBC82EC, 0xFF8A55D6],
    glow: 0xFF9B59FF,
    base: 0xFFC79BF0,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),

  /// Blue stone: ice white into deep blue, glowing blue.
  sapphire(
    fill: [0xFFE2EDFF, 0xFF86ADFF, 0xFF4B74FF],
    glow: 0xFF3D7BFF,
    base: 0xFF9DBBFF,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),

  /// Ice: white and the palest cyan, with a cold glow.
  frost(
    fill: [0xFFFFFFFF, 0xFFD2F5FF, 0xFFA0E2FF],
    glow: 0xFF62CFFF,
    base: 0xFFD6F3FF,
  ),

  /// Sea glass: the green-blue of shallow water over sand.
  seaGlass(
    fill: [0xFFDAFFF7, 0xFF84E9DA, 0xFF45B9CC],
    glow: 0xFF1FC6C6,
    base: 0xFF9EEBDF,
  ),

  /// The green stone, bright at the top of the verse and deep at its
  /// foot.
  emerald(
    fill: [0xFFD8FFDC, 0xFF72E8A3, 0xFF22B27B],
    glow: 0xFF19C27A,
    base: 0xFF8BE9B3,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),

  /// A firefly's yellow-green, and its light.
  firefly(
    fill: [0xFFF8FFC0, 0xFFD6FF6E],
    glow: 0xFFB2FF3B,
    base: 0xFFE9FF9A,
  ),

  /// A white tube and the coloured light that spills from it: the
  /// brightest glow on the list.
  neon(
    fill: [0xFFFFFFFF, 0xFFE9FFFF],
    glow: 0xFF00E5FF,
    base: 0xFFF2FFFF,
    strength: 1.25,
  ),

  // ---- for a pale ground --------------------------------------------
  // A letterbox band in white or ivory takes dark ink. These three are
  // dark, drawn with a light rim and a coloured aura, so the verse
  // still glows on paper where the bright inks above would disappear.

  /// Volcanic glass: charcoal to black, rimmed in light, with a gold
  /// aura.
  obsidian(
    fill: [0xFF3A3F48, 0xFF0B0D10],
    glow: 0xFFD4A947,
    base: 0xFF22262C,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    forLightGround: true,
  ),

  /// Henna: red-brown, with a warm amber aura.
  henna(
    fill: [0xFF8C3A22, 0xFF4E1B12],
    glow: 0xFFE8A33D,
    base: 0xFF6E2C1C,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    forLightGround: true,
  ),

  /// The deep sea: navy into ink, with a teal aura.
  deepSea(
    fill: [0xFF1D4A70, 0xFF0B2233],
    glow: 0xFF5BC0C6,
    base: 0xFF15364F,
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    forLightGround: true,
  );

  const VerseInk({
    required this.fill,
    required this.glow,
    required this.base,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
    this.strength = 1.0,
    this.forLightGround = false,
  });

  /// The colours the letters are filled with, in order along
  /// [begin]..[end]. Across the whole verse rather than per line: a
  /// sheen that restarted on every line would read as stripes.
  final List<int> fill;

  /// The colour of the light the letters give off.
  final int glow;

  /// The one solid colour that stands for this ink; see the class
  /// comment.
  final int base;

  final Alignment begin;
  final Alignment end;

  /// How strongly the ink glows, against the others: pearl only
  /// breathes, neon floods.
  final double strength;

  /// A dark ink, drawn for a pale letterbox band. The picker leads with
  /// these when the verse sits on one.
  final bool forLightGround;

  bool get isNone => this == VerseInk.none;

  /// The fill as a gradient over [begin]..[end].
  LinearGradient get gradient => LinearGradient(
        begin: begin,
        end: end,
        colors: [for (final c in fill) Color(c)],
      );

  /// The light around the letters, at text scale [ts], over the
  /// legibility halo the card already draws in [halo]. The halo goes
  /// first: shadows are painted in order, and the glow has to sit on
  /// top of the dark that lifts the letters off the picture, not
  /// under it.
  ///
  /// Kept inside a line's own leading on purpose. The exporter captures
  /// the card shrink-wrapped, so light reaching past the card's edge
  /// would be cut off in the file while the preview still showed it.
  List<Shadow> shadows(double ts, {required Color halo}) {
    final g = Color(glow);
    final k = strength;
    if (forLightGround) {
      return [
        Shadow(
          color: halo.withValues(alpha: 0.85),
          blurRadius: 3 * ts,
        ),
        Shadow(
          color: g.withValues(alpha: (0.45 * k).clamp(0.0, 1.0)),
          blurRadius: 22 * ts,
        ),
        Shadow(
          color: const Color(0xFF000000).withValues(alpha: 0.18),
          blurRadius: 8 * ts,
          offset: Offset(0, 3 * ts),
        ),
      ];
    }
    return [
      Shadow(
        color: halo.withValues(alpha: 0.5),
        blurRadius: 16 * ts,
        offset: Offset(0, 3 * ts),
      ),
      // A tight bloom that hugs the strokes, then the wide aura that
      // makes the verse read as lit rather than printed.
      Shadow(
        color: g.withValues(alpha: (0.95 * k).clamp(0.0, 1.0)),
        blurRadius: 12 * ts,
      ),
      Shadow(
        color: g.withValues(alpha: (0.7 * k).clamp(0.0, 1.0)),
        blurRadius: 34 * ts,
      ),
    ];
  }

  /// The light around the lit word and the verse-end sign when this is
  /// the accent. Tighter than a verse's: it marks one word, and a bloom
  /// the size of the verse's would light its neighbours too.
  List<Shadow> accentGlow(double ts) => [
        Shadow(
          color: Color(glow).withValues(alpha: (0.9 * strength).clamp(0.0, 1.0)),
          blurRadius: 8 * ts,
        ),
        Shadow(
          color: Color(glow).withValues(alpha: (0.5 * strength).clamp(0.0, 1.0)),
          blurRadius: 20 * ts,
        ),
      ];

  /// A softer glow for the translation line under an inked verse:
  /// enough to belong to it, not so much that it competes.
  Shadow translationGlow(double ts) => Shadow(
        color: Color(glow).withValues(
            alpha: ((forLightGround ? 0.25 : 0.35) * strength)
                .clamp(0.0, 1.0)),
        blurRadius: 18 * ts,
      );

  /// For a cache key. Empty for [none], so every reel rendered before
  /// inks existed keeps the key it was cached under.
  String get key => isNone ? '' : name;

  /// The inks in the order the picker shows them: the ones drawn for
  /// the ground the verse is actually on come first.
  static List<VerseInk> ordered({required bool onLight}) {
    final all = [for (final i in values) if (!i.isNone) i];
    return [
      for (final i in all) if (i.forLightGround == onLight) i,
      for (final i in all) if (i.forLightGround != onLight) i,
    ];
  }

  static VerseInk fromName(String? name) => values
      .firstWhere((i) => i.name == name, orElse: () => VerseInk.none);
}
