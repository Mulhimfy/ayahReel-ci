import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/arena_constellation.dart';
import '../widgets/arena_fx.dart';
import '../widgets/illumination.dart' show SealGlyph;
import '../widgets/night_sky.dart';
import 'ayah_rasterizer.dart';
import 'invite_story_images.dart';

/// The picture a round becomes when it goes to an Instagram story.
///
/// A story is 1080×1920 with nothing on it but the picture, so the
/// picture is the round. At the head, the result in a book face: who
/// scored, the number and its one word, and how many were right and
/// where. Under it the round's constellation — every verse the player
/// met, lit or not, threaded in the order they came. Against a code,
/// the two scores stand either side of a line. No code: nobody can copy
/// one off a picture, so it travels in the message instead, and on to
/// the clipboard when the story goes to Instagram. Nothing else: no
/// mark, no dare, no store line. The app's icon and name at the foot
/// say where it came from.
abstract final class ArenaStory {
  static const width = 1080.0;
  static const height = 1920.0;

  /// Renders into the cache dir — the one root the direct-share
  /// FileProvider serves — and returns the file.
  static Future<File> render({
    required L10n l,
    required List<ConstellationNode> nodes,
    required int seed,
    required String name,
    required int score,
    required int correct,
    required int asked,
    required String scope,
    required int tier,
    String? rival,
    int? rivalScore,
    bool showScore = true,
    bool showScope = true,
  }) async {
    final bytes = await png(
      l: l,
      nodes: nodes,
      seed: seed,
      name: name,
      score: score,
      correct: correct,
      asked: asked,
      scope: scope,
      tier: tier,
      rival: rival,
      rivalScore: rivalScore,
      showScore: showScore,
      showScope: showScope,
    );
    final tmp = await getTemporaryDirectory();
    final f = File(
        '${tmp.path}/ayahreel_round_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// The picture as PNG bytes. Public so a preview can be drawn on a
  /// desk without a device — see test/tools/arena_preview_test.dart.
  static Future<List<int>> png({
    required L10n l,
    required List<ConstellationNode> nodes,
    required int seed,
    required String name,
    required int score,
    required int correct,
    required int asked,
    required String scope,
    required int tier,
    String? rival,
    int? rivalScore,
    bool showScore = true,
    bool showScope = true,
  }) async {
    _Type.all(l);
    try {
      await GoogleFonts.pendingFonts();
    } catch (_) {}
    final icon = await _decode(kInviteIconPng);
    try {
      return await AyahRasterizer.widgetToPng(ArenaStoryCard(
        l: l,
        nodes: nodes,
        seed: seed,
        name: name,
        score: score,
        correct: correct,
        asked: asked,
        scope: scope,
        tier: tier,
        rival: rival,
        rivalScore: rivalScore,
        showScore: showScore,
        showScope: showScope,
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

abstract final class _Type {
  /// The result's own face: a book serif, bundled, so the picture never
  /// waits on the network. Urdu is set in its own nastaliq, Arabic in
  /// El Messiri; both are the calligraphic cousins of the Latin one.
  static TextStyle _book(
    L10n l, {
    required double size,
    FontWeight weight = FontWeight.w600,
    double? height,
    double letterSpacing = 0,
    Color? color,
    List<Shadow>? shadows,
  }) =>
      TextStyle(
        fontFamily: switch (l.lang) {
          AppLang.ur => 'NotoNastaliqUrdu',
          _ when l.arabicScript => 'ElMessiri',
          _ => 'CormorantGaramond',
        },
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        height: height,
        letterSpacing: l.arabicScript ? 0 : letterSpacing,
        color: color,
        shadows: shadows,
        // Garamond's figures are old-style by default, which sets the
        // 1 of "10" as a small-capital I.
        fontFeatures: const [FontFeature.liningFigures()],
      );

  static TextStyle name(L10n l) => _book(
        l,
        size: 58,
        weight: FontWeight.w500,
        height: l.lang == AppLang.ur ? 1.9 : 1.2,
        color: AppColors.textPrimary.withValues(alpha: 0.92),
      );

  static TextStyle score(L10n l) => _book(
        l,
        size: 190,
        weight: FontWeight.w700,
        height: l.arabicScript ? 1.25 : 1.05,
        color: Colors.white,
        shadows: [
          Shadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 60),
        ],
      );

  /// The player's name, standing in for the number on a card that
  /// leaves the score off: smaller than the number, as gold.
  static TextStyle title(L10n l) => _book(
        l,
        size: l.arabicScript ? 112 : 104,
        weight: FontWeight.w700,
        height: l.lang == AppLang.ur ? 1.9 : (l.arabicScript ? 1.35 : 1.1),
        letterSpacing: 2,
        color: Colors.white,
        shadows: [
          Shadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 60),
        ],
      );

  static TextStyle tier(L10n l) => _book(
        l,
        size: 40,
        weight: FontWeight.w700,
        height: l.lang == AppLang.ur ? 1.9 : 1.2,
        letterSpacing: 12,
        color: AppColors.goldBright,
      );

  static TextStyle line(L10n l) => _book(
        l,
        size: 40,
        weight: FontWeight.w500,
        height: l.lang == AppLang.ur ? 2.0 : 1.3,
        color: AppColors.textSecondary,
      );

  static TextStyle versusName(L10n l) => _book(
        l,
        size: 36,
        weight: FontWeight.w500,
        height: l.lang == AppLang.ur ? 1.9 : 1.2,
        color: AppColors.textSecondary,
      );

  static TextStyle versusScore(L10n l) => _book(
        l,
        size: 88,
        weight: FontWeight.w700,
        height: l.arabicScript ? 1.25 : 1.05,
      );

  /// The bundled Inter, by name: the mark resolves offline, and the
  /// card on the result screen draws without asking the network.
  static TextStyle wordmark() => const TextStyle(
        fontFamily: 'Inter',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        fontVariations: [FontVariation('wght', 700)],
        letterSpacing: 6,
        color: AppColors.goldBright,
      );

  static void all(L10n l) {
    wordmark();
  }
}

/// The card itself, at its full 1080×1920 — what [ArenaStory.png]
/// rasterizes, and what the result screen shows scaled down in a frame
/// before anything is shared, so the menu's choices can be watched
/// landing on it.
class ArenaStoryCard extends StatelessWidget {
  final L10n l;
  final List<ConstellationNode> nodes;
  final int seed;
  final String name;
  final int score;
  final int correct;
  final int asked;
  final String scope;
  final int tier;
  final String? rival;
  final int? rivalScore;

  /// Whether the card carries the result — the number, its word, how
  /// many were right, the two scores of a versus — and the surah or
  /// juz it was played in. Turned off in the card's menu; with the
  /// score off the card is the round itself, under the player's name
  /// when it carries one. (The name is left off by passing none.)
  final bool showScore;
  final bool showScope;

  /// The app's icon at the foot, decoded — the rasterizer cannot wait
  /// on an image to decode itself. Null on screen, where it can.
  final ui.Image? icon;

  /// Stands in for the still constellation: on screen, the round is
  /// drawn in as it was played.
  final Widget? constellation;

  const ArenaStoryCard({
    super.key,
    required this.l,
    required this.nodes,
    required this.seed,
    required this.name,
    required this.score,
    required this.correct,
    required this.asked,
    required this.scope,
    required this.tier,
    required this.rival,
    required this.rivalScore,
    required this.showScore,
    required this.showScope,
    this.icon,
    this.constellation,
  });

  @override
  Widget build(BuildContext context) {
    final versus = showScore && rival != null && rivalScore != null;
    // What is left of the line under the number: how many were right,
    // where — either, both, or nothing at all.
    final line = [
      if (showScore) l.arenaRightOf(correct, asked),
      if (showScope) scope,
    ].join(' · ');
    return Directionality(
      textDirection: l.direction,
      child: SizedBox(
        width: ArenaStory.width,
        height: ArenaStory.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF151B2B), AppColors.bg],
                ),
              ),
            ),
            const MeshStill(alpha: 0.6, time: 5.3, seed: 8),
            const Starfield(count: 190, seed: 21, fade: false),
            Padding(
              padding: const EdgeInsets.fromLTRB(60, 200, 60, 170),
              child: Column(
                children: [
                  // The result, first: who, the number, its word, and
                  // how many were right and where. With the score off,
                  // the player's name stands where the number stood, in
                  // the same gold — or, nameless, only the seals.
                  if (showScore) ...[
                    Text(l.arenaStoryScored(name),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: _Type.name(l)),
                    const SizedBox(height: 6),
                    _Gilded(child: Text('$score', style: _Type.score(l))),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SealGlyph(size: 10, color: AppColors.gold),
                        const SizedBox(width: 22),
                        Text(
                            l.arabicScript
                                ? l.arenaTierName(tier)
                                : l.arenaTierName(tier).toUpperCase(),
                            style: _Type.tier(l)),
                        const SizedBox(width: 22),
                        const SealGlyph(size: 10, color: AppColors.gold),
                      ],
                    ),
                  ] else ...[
                    if (name.isNotEmpty) ...[
                      _Gilded(
                        child: Text(name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _Type.title(l)),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SealGlyph(size: 8, color: AppColors.gold),
                        SizedBox(width: 18),
                        SealGlyph(size: 12, color: AppColors.goldBright),
                        SizedBox(width: 18),
                        SealGlyph(size: 8, color: AppColors.gold),
                      ],
                    ),
                  ],
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(line, textAlign: TextAlign.center, style: _Type.line(l)),
                  ],
                  const Spacer(),
                  // The round, drawn — a little smaller when two scores
                  // have to stand under it.
                  SizedBox(
                    width: versus ? 760 : (showScore ? 900 : 940),
                    height: versus ? 760 : (showScore ? 900 : 940),
                    child: RepaintBoundary(
                      child: constellation ??
                          Constellation(nodes: nodes, seed: seed),
                    ),
                  ),
                  if (versus) ...[
                    const SizedBox(height: 24),
                    _Versus(
                      l: l,
                      me: name.isEmpty ? l.arenaYou : name,
                      score: score,
                      rival: rival!,
                      rivalScore: rivalScore!,
                    ),
                  ],
                  const Spacer(),
                  // Where it came from.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(58 * 0.2237),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.gold.withValues(alpha: 0.35),
                                blurRadius: 28),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(58 * 0.2237),
                          child: icon != null
                              ? RawImage(image: icon, fit: BoxFit.cover)
                              : Image.memory(_iconBytes,
                                  fit: BoxFit.cover, gaplessPlayback: true),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Text('AYAHREEL', style: _Type.wordmark()),
                    ],
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

/// Two scores either side of a hairline, the higher one lit: the whole
/// of "you competed against", said without a sentence.
class _Versus extends StatelessWidget {
  final L10n l;
  final String me;
  final int score;
  final String rival;
  final int rivalScore;
  const _Versus({
    required this.l,
    required this.me,
    required this.score,
    required this.rival,
    required this.rivalScore,
  });

  @override
  Widget build(BuildContext context) {
    Widget side(String who, int n, bool lit) => Expanded(
          child: Column(
            children: [
              Text(who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _Type.versusName(l)),
              const SizedBox(height: 6),
              Text('$n',
                  style: _Type.versusScore(l).copyWith(
                      color: lit ? AppColors.goldBright : AppColors.textSecondary)),
            ],
          ),
        );
    return Row(
      children: [
        side(me, score, score >= rivalScore),
        Column(
          children: [
            Container(
              width: 2,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.gold.withValues(alpha: 0),
                    AppColors.gold.withValues(alpha: 0.7),
                    AppColors.gold.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const SealGlyph(size: 12, color: AppColors.gold),
          ],
        ),
        side(rival, rivalScore, rivalScore >= score),
      ],
    );
  }
}

/// The app's icon for the card on screen, decoded once.
final _iconBytes = base64Decode(kInviteIconPng);

/// The gold the big words on the card are filled with: the score, or
/// the player's name when the score is left off.
class _Gilded extends StatelessWidget {
  final Widget child;
  const _Gilded({required this.child});

  @override
  Widget build(BuildContext context) => ShaderMask(
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
        child: child,
      );
}
