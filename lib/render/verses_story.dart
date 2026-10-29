import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/verse_light.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/quran_sun.dart';
import 'ayah_rasterizer.dart';
import 'invite_story_images.dart';

/// The "Your verses" card: the whole Quran as a sun, a ray for every
/// surah, the verses this person has made reels of burning on it.
///
/// A story is 1080×1920 with nothing on it but the picture, so the
/// picture is the card: no title, no dare. A line of words only when
/// asked for — the name, the count — and the app's mark at the foot so
/// a stranger knows where it came from.
abstract final class VersesStory {
  static const width = 1080.0;
  static const height = 1920.0;

  /// Renders into the cache dir — the one root the direct-share
  /// FileProvider serves — and returns the file.
  static Future<File> render({
    required L10n l,
    required VerseLight light,
    String name = '',
    bool numbers = false,
  }) async {
    final bytes = await png(l: l, light: light, name: name, numbers: numbers);
    final tmp = await getTemporaryDirectory();
    final f = File(
        '${tmp.path}/ayahreel_verses_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<List<int>> png({
    required L10n l,
    required VerseLight light,
    String name = '',
    bool numbers = false,
  }) async {
    final icon = await _decode(kInviteIconPng);
    try {
      return await AyahRasterizer.widgetToPng(VersesCard(
        l: l,
        light: light,
        name: name,
        numbers: numbers,
        icon: icon,
      ));
    } finally {
      icon.dispose();
    }
  }

  static Future<ui.Image> _decode(String base64) async {
    final codec = await ui.instantiateImageCodec(base64Decode(base64));
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}

/// The card at its full 1080×1920: what [VersesStory.png] rasterizes,
/// and what the Reels tab shows scaled into a frame, live, before it is
/// shared.
class VersesCard extends StatelessWidget {
  final L10n l;
  final VerseLight light;

  /// The name under the sun; empty for none.
  final String name;

  /// Whether the count goes under it — verses and surahs.
  final bool numbers;

  /// The app's icon, decoded, for the rasterizer; null on screen.
  final ui.Image? icon;

  /// On screen the sun comes up and its verses burn in; in the
  /// picture it is simply there.
  final bool live;

  const VersesCard({
    super.key,
    required this.l,
    required this.light,
    this.name = '',
    this.numbers = false,
    this.icon,
    this.live = false,
  });

  TextStyle _book(double size,
          {FontWeight weight = FontWeight.w600, Color? color}) =>
      TextStyle(
        fontFamily: switch (l.lang) {
          AppLang.ur => 'NotoNastaliqUrdu',
          _ when l.arabicScript => 'ElMessiri',
          _ => 'CormorantGaramond',
        },
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        height: l.lang == AppLang.ur ? 1.9 : 1.25,
        color: color,
        fontFeatures: const [FontFeature.liningFigures()],
      );

  @override
  Widget build(BuildContext context) {
    final words = name.isNotEmpty || numbers;
    // The sun sits a little above the middle with words under it, and
    // in the middle without.
    final sunTop = words ? 300.0 : 380.0;
    return Directionality(
      textDirection: l.direction,
      child: SizedBox(
        width: VersesStory.width,
        height: VersesStory.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RepaintBoundary(
              child: CustomPaint(painter: _Night(), size: Size.infinite),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: sunTop,
              height: VersesStory.width,
              child: QuranSunView(light: light, animate: live),
            ),
            if (words)
              Positioned(
                left: 80,
                right: 80,
                top: sunTop + VersesStory.width + 40,
                child: Column(
                  children: [
                    if (name.isNotEmpty)
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFF2CE),
                            Color(0xFFEEC96B),
                            Color(0xFFC9973B),
                          ],
                        ).createShader(rect),
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _book(66, color: Colors.white),
                        ),
                      ),
                    if (numbers)
                      Text(
                        l.versesCardNumbers(light.verses, light.surahs),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: _book(42,
                            weight: FontWeight.w500,
                            color: const Color(0xD9C8D0DC)),
                      ),
                  ],
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 110,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(48 * 0.2237),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.3),
                            blurRadius: 24),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(48 * 0.2237),
                      child: icon != null
                          ? RawImage(image: icon, fit: BoxFit.cover)
                          : Image.memory(_iconBytes,
                              fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'AYAHREEL',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      fontVariations: [FontVariation('wght', 700)],
                      letterSpacing: 6,
                      color: AppColors.goldBright,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _iconBytes = base64Decode(kInviteIconPng);

/// The ground: a night sky, a warm pool of light where the sun will
/// stand, and a sprinkle of stars — the same stars on every card.
class _Night extends CustomPainter {
  const _Night();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, const [
          Color(0xFF0E1424),
          Color(0xFF090D18),
          Color(0xFF05070D),
        ], const [0, 0.55, 1]),
    );
    final c = Offset(size.width / 2, size.height * 0.44);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(c, size.width * 0.66, const [
          Color(0x33D4A947),
          Color(0x146E50A0),
          Color(0x00000000),
        ], const [0, 0.45, 1]),
    );
    var seed = 11;
    double rnd() => (seed = (seed * 16807) % 2147483647) / 2147483647;
    final star = Paint();
    final unit = size.width / 1080;
    for (var i = 0; i < 160; i++) {
      final p = Offset(rnd() * size.width, rnd() * size.height);
      final r = (rnd() * 1.3 + 0.3) * unit;
      star.color = Colors.white.withValues(alpha: 0.12 + rnd() * 0.35);
      canvas.drawCircle(p, math.max(0.4, r), star);
    }
  }

  @override
  bool shouldRepaint(_Night old) => false;
}
