import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/illumination.dart';
import '../widgets/night_sky.dart';
import 'ayah_rasterizer.dart';
import 'invite_story_images.dart';

/// The picture the invite hands to Instagram's story composer.
///
/// A story is a full-bleed 1080×1920 image with nothing else on it, so
/// the invitation has to be the picture: the app's icon and name, one
/// screen of the app itself, the hadith the invite sheet opens with,
/// and one line saying what the app is. It is drawn off-screen from
/// the same faces and ornaments the app is made of — the seal, the
/// starfield, the gold hairline — so a story shared from here looks
/// like the app it points at, and never like a banner made for it.
///
/// The store links are deliberately not on the picture. A url in a
/// story background is a picture of a url; Instagram's own link
/// sticker is the thing that opens, and that is the user's to add.
abstract final class InviteStory {
  static const width = 1080.0;
  static const height = 1920.0;

  /// Renders the card in the app's current language and writes it into
  /// the cache dir — the one root the direct-share FileProvider serves.
  /// A card rendered once is rendered again next time: it is cheap, and
  /// a stale one from before a language switch would be the wrong
  /// picture.
  static Future<File> render() async {
    final l = L10n.current;
    final bytes = await png(l);
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}/ayahreel_story_${l.lang.code}.png');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// The card as PNG bytes, in language [l]. Public so a preview can be
  /// drawn on a desk without a device — see
  /// test/tools/invite_story_preview_test.dart.
  static Future<List<int>> png(L10n l) async {
    // The card's faces are other weights than anything the rasterizer
    // warms on its own; reading every style it draws with queues their
    // loads, and the wait is what stops the PNG shaping in a fallback
    // face.
    _Type.all(l);
    try {
      await GoogleFonts.pendingFonts();
    } catch (_) {}
    // The capture paints exactly once, so a picture that has not
    // decoded by then is a blank; both are decoded up front and handed
    // to the card as pixels.
    // Both come out of Dart constants rather than assets: a Shorebird
    // patch carries code and never a new asset file, and the card is
    // exactly the thing that gets redrawn between store builds. See
    // tool/invite_story_images.py.
    final icon = await _decode(kInviteIconPng);
    final screen = await _decode(kInviteScreenJpg);
    try {
      return await AyahRasterizer.widgetToPng(
        _StoryCard(l, icon: icon, screen: screen),
      );
    } finally {
      icon.dispose();
      screen.dispose();
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

/// Every face on the card, in one place, so the warm-up and the layout
/// cannot disagree about what gets drawn.
abstract final class _Type {
  /// The Latin face or the Arabic one, as a function to call with the
  /// same arguments either way.
  static TextStyle Function({
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
    Color? color,
    List<Shadow>? shadows,
  }) _sans(L10n l) =>
      l.arabicScript ? GoogleFonts.ibmPlexSansArabic : GoogleFonts.inter;

  static TextStyle wordmark() => GoogleFonts.inter(
        fontSize: 38,
        fontWeight: FontWeight.w700,
        letterSpacing: 7,
        color: AppColors.goldBright,
      );

  /// The hadith, set small and quiet: it is the reason the invite is
  /// sent, not the thing that sells the app, so it reads as a caption
  /// under the screen rather than a panel of its own.
  static TextStyle hadith(L10n l) =>
      AppTheme.translation(size: 28, arabic: l.arabicScript).copyWith(
        color: AppColors.textPrimary.withValues(alpha: 0.86),
        height: 1.5,
      );

  static TextStyle source(L10n l) => _sans(l)(
        fontSize: 20,
        letterSpacing: l.arabicScript ? 0 : 2.6,
        color: AppColors.gold,
      );

  static TextStyle tagline(L10n l) => _sans(l)(
        fontSize: 50,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: l.arabicScript ? 0 : -0.7,
        color: AppColors.textPrimary,
      );

  static TextStyle footer(L10n l) => _sans(l)(
        fontSize: 27,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: AppColors.textSecondary,
      );

  /// The card's h1: the biggest thing on it, gold, with the glow
  /// drawn as text shadows so it lights the sky behind the letters.
  static TextStyle cta(L10n l) => _sans(l)(
        fontSize: 54,
        fontWeight: FontWeight.w800,
        height: 1.2,
        letterSpacing: l.arabicScript ? 0 : -0.9,
        color: AppColors.goldBright,
        shadows: [
          Shadow(color: AppColors.gold.withValues(alpha: 0.9), blurRadius: 18),
          Shadow(color: AppColors.gold.withValues(alpha: 0.55), blurRadius: 60),
          Shadow(color: AppColors.gold.withValues(alpha: 0.30), blurRadius: 140),
        ],
      );

  /// Touches every style once, which is what queues their font loads.
  static void all(L10n l) {
    wordmark();
    hadith(l);
    source(l);
    tagline(l);
    footer(l);
    cta(l);
  }
}

/// The card itself, laid out in story pixels. It is never on screen,
/// so it carries its own directionality and every style explicitly:
/// there is no theme above it to inherit from.
///
/// Instagram lays its own controls over the top and bottom ~250px of a
/// story, so everything that has to be read sits inside the middle.
/// Top to bottom: the icon and name (who this is), the screen (what it
/// looks like), the hadith (why it is being sent), the pitch, the ask.
class _StoryCard extends StatelessWidget {
  final L10n l;
  final ui.Image icon;
  final ui.Image screen;
  const _StoryCard(this.l, {required this.icon, required this.screen});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: l.direction,
      child: SizedBox(
        width: InviteStory.width,
        height: InviteStory.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _Sky(),
            Padding(
              padding: const EdgeInsets.fromLTRB(96, 236, 96, 236),
              child: Column(
                children: [
                  _Identity(icon: icon),
                  const Spacer(),
                  _Screen(screen),
                  const SizedBox(height: 40),
                  _Hadith(l),
                  const Spacer(),
                  Text(
                    l.storyTagline,
                    textAlign: TextAlign.center,
                    style: _Type.tagline(l),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.storyFooter,
                    textAlign: TextAlign.center,
                    style: _Type.footer(l),
                  ),
                  const SizedBox(height: 34),
                  const _Rule(),
                  const SizedBox(height: 34),
                  Text(
                    l.storyCta,
                    textAlign: TextAlign.center,
                    style: _Type.cta(l),
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

/// The night behind everything: the app's gradient, its starfield,
/// and two of its orbs — unfaded, because here the sky is the whole
/// picture rather than a field above content.
class _Sky extends StatelessWidget {
  const _Sky();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1D2537), AppColors.bg],
            ),
          ),
        ),
        Starfield(count: 170, seed: 23, fade: false),
        Positioned(
          top: -320,
          right: -260,
          child: GlowOrb(size: 900, alpha: 0.16),
        ),
        Positioned(
          bottom: -380,
          left: -300,
          child: GlowOrb(size: 820, alpha: 0.10),
        ),
      ],
    );
  }
}

/// The app's icon over its name — the same pair a phone's home screen
/// shows, which is what the ask at the foot of the card sends the
/// viewer to look for.
class _Identity extends StatelessWidget {
  final ui.Image icon;
  const _Identity({required this.icon});

  @override
  Widget build(BuildContext context) {
    const size = 140.0;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.2237),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.35),
                blurRadius: 70,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            // iOS's squircle ratio, so the icon reads as the icon
            // rather than as a picture of it.
            borderRadius: BorderRadius.circular(size * 0.2237),
            child: RawImage(image: icon, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 24),
        Text('AYAHREEL', style: _Type.wordmark()),
      ],
    );
  }
}

/// One screen of the app, in the thinnest frame that still says
/// "phone": a gold hairline around rounded corners, lit softly from
/// behind so it floats on the sky rather than sitting in a box.
class _Screen extends StatelessWidget {
  final ui.Image screen;
  const _Screen(this.screen);

  @override
  Widget build(BuildContext context) {
    const h = 540.0;
    final w = h * screen.width / screen.height;
    const radius = 46.0;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.45),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.18),
            blurRadius: 90,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 60,
            offset: const Offset(0, 30),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2.5),
        child: RawImage(image: screen, fit: BoxFit.cover),
      ),
    );
  }
}

/// The hadith the invite is built on, as a caption under the screen:
/// a small seal, the words, the source — no panel, so it is read as a
/// reason and not as the headline.
class _Hadith extends StatelessWidget {
  final L10n l;
  const _Hadith(this.l);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        children: [
          const SealGlyph(size: 18, color: AppColors.gold),
          const SizedBox(height: 18),
          Text(
            l.hadithGuidesToGood,
            textAlign: TextAlign.center,
            style: _Type.hadith(l),
          ),
          const SizedBox(height: 14),
          Text(l.sahihMuslim, style: _Type.source(l)),
        ],
      ),
    );
  }
}

/// A hairline fading out to both margins with a seal at its centre —
/// the divider the app's sections end on, closing the card.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    Widget half(bool towardsEnd) => Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: towardsEnd
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                end: towardsEnd
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                colors: [
                  AppColors.gold.withValues(alpha: 0.55),
                  AppColors.gold.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        half(false),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 22),
          child: SealGlyph(size: 22, color: AppColors.gold),
        ),
        half(true),
      ],
    );
  }
}
