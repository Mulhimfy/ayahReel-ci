import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/arena_engine.dart';
import '../data/arena_service.dart';
import '../l10n/l10n.dart';
import '../screens/arena_result_screen.dart';
import '../screens/arena_screen.dart' show arenaScopeLabel;
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'arena_constellation.dart';
import 'arena_fx.dart';
import 'glow_button.dart';
import 'illumination.dart';

/// The rounds a player has kept, as a shelf of small constellations.
///
/// Each card is the round's own picture at thumbnail size with the
/// score in its middle; a tap opens the round's page — the same page
/// the round ended on, with the story and the share and the code — and
/// a long press takes it off the shelf. A card that is being taken
/// off folds away rather than vanishing.
class ArenaHistoryStrip extends StatefulWidget {
  /// How many to show; the whole history when null.
  final int? limit;
  const ArenaHistoryStrip({super.key, this.limit});

  @override
  State<ArenaHistoryStrip> createState() => _ArenaHistoryStripState();
}

class _ArenaHistoryStripState extends State<ArenaHistoryStrip> {
  ArenaCorpus? _corpus;
  final _rounds = <String, ArenaRound>{};
  final _leaving = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(ArenaService.init());
    ArenaCorpus.load().then((c) {
      if (mounted) setState(() => _corpus = c);
    });
  }

  ArenaRound? _roundOf(ArenaRecord r) {
    final corpus = _corpus;
    if (corpus == null) return null;
    return _rounds[r.id] ??= ArenaRound.generate(corpus, r.setup, r.seed);
  }

  Future<void> _open(ArenaRecord r) async {
    final round = _roundOf(r);
    if (round == null) return;
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(BloomRoute(
      builder: (_) => ArenaResultScreen(
        round: round,
        result: r.result,
        mode: r.mode,
        me: r.me,
        challenge: r.challenge,
        rival: r.rival,
        file: false,
        playedAt: r.at,
      ),
    ));
  }

  Future<void> _delete(ArenaRecord r) async {
    HapticFeedback.mediumImpact();
    final l = L10n.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(l.arenaDeleteRound,
            textAlign: TextAlign.center,
            style: Theme.of(d).textTheme.titleMedium),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          QuietButton(label: l.arenaKeep, onPressed: () => Navigator.of(d).pop(false)),
          QuietButton(label: l.arenaDelete, onPressed: () => Navigator.of(d).pop(true)),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _leaving.add(r.id));
    await Future<void>.delayed(const Duration(milliseconds: 380));
    await ArenaService.remove(r.id);
    if (mounted) {
      setState(() => _leaving.remove(r.id));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surfaceRaised,
          content: Text(l.arenaRoundDeleted,
              style: const TextStyle(color: AppColors.textPrimary)),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ValueListenableBuilder<ArenaState>(
      valueListenable: ArenaService.state,
      builder: (context, s, _) {
        var rounds = s.history.where((r) => r.answers.isNotEmpty).toList();
        if (widget.limit != null) rounds = rounds.take(widget.limit!).toList();
        if (rounds.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(l.arenaNoRounds,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary, height: 1.5)),
          );
        }
        return SizedBox(
          height: RoundCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: rounds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final r = rounds[i];
              final leaving = _leaving.contains(r.id);
              return AnimatedSize(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeInOutCubic,
                alignment: AlignmentDirectional.centerStart,
                child: leaving
                    ? const SizedBox(height: RoundCard.height)
                    : Rise(
                        delay: Duration(milliseconds: 60 * (i.clamp(0, 6))),
                        from: 10,
                        child: RoundCard(
                          key: ValueKey(r.id),
                          record: r,
                          round: _roundOf(r),
                          onTap: () => _open(r),
                          onHold: () => _delete(r),
                        ),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

/// One kept round: its constellation, its score, where it was played.
class RoundCard extends StatelessWidget {
  final ArenaRecord record;
  final ArenaRound? round;
  final VoidCallback onTap;
  final VoidCallback onHold;

  static const height = 196.0;
  static const width = 150.0;

  const RoundCard({
    super.key,
    required this.record,
    required this.round,
    required this.onTap,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final r = record;
    final scope = ArenaScope.fromKey(r.scopeKey);
    final radius = BorderRadius.circular(20);
    final verdict = r.mode != ArenaMode.challenge
        ? null
        : r.drew
            ? l.arenaDraw
            : r.won
                ? l.arenaWon
                : l.arenaLost;
    return A11yTap(
      label: '${scope == null ? '' : arenaScopeLabel(l, scope)}, '
          '${l.arenaRightOf(r.correct, r.asked)}, ${l.arenaScore} ${r.score}'
          '${verdict == null ? '' : ', $verdict'}',
      hint: l.a11yOpensRound,
      onTap: onTap,
      onLongPress: onHold,
      child: Pressable(
        onTap: onTap,
        child: GestureDetector(
          onLongPress: onHold,
          child: TouchLight(
            radius: radius,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.72),
                borderRadius: radius,
                border: Border.all(
                    color: r.won
                        ? AppColors.gold.withValues(alpha: 0.55)
                        : AppColors.stroke),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 108,
                    height: 108,
                    child: round == null
                        ? const GlareBlock(
                            height: 108,
                            radius: BorderRadius.all(Radius.circular(54)))
                        : Constellation(
                            nodes: ConstellationNode.ofRound(
                                round!.questions, r.answers),
                            seed: r.seed,
                            labels: false,
                          ),
                  ),
                  // The score, small, under the picture and not in it.
                  GildedText(
                    '${r.score}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      scope == null ? r.scopeKey : arenaScopeLabel(l, scope),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l.arenaRightOf(r.correct, r.asked),
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.textSecondary),
                      ),
                      if (verdict != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          verdict,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: r.won
                                ? AppColors.goldBright
                                : r.drew
                                    ? AppColors.textSecondary
                                    : ArenaPalette.wrong,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The arena's pitch: the six words and the line under them, on the
/// lobby and on the Cards tab.
class ArenaPitch extends StatelessWidget {
  final bool centered;
  const ArenaPitch({super.key, this.centered = true});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        A11yHeader(
          child: Sheen(
            period: const Duration(milliseconds: 6500),
            strength: 0.45,
            child: GildedText(
              l.arenaPitch,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: t.headlineMedium!.copyWith(
                fontSize: 24,
                height: 1.25,
                letterSpacing: l.arabicScript ? 0 : -0.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.arenaPitchBody,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: t.bodyMedium?.copyWith(fontSize: 13.5, height: 1.5),
        ),
      ],
    );
  }
}

/// Shown once, the first time the arena opens: what it is, in three
/// lines, and the door.
Future<void> showArenaIntro(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const _IntroSheet(),
  );
}

class _IntroSheet extends StatelessWidget {
  const _IntroSheet();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    Widget line(IconData icon, String text, int i) => Rise(
          delay: Duration(milliseconds: 120 + 90 * i),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.12),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Icon(icon, size: 17, color: AppColors.goldBright),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(text,
                      style: t.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          height: 1.5,
                          color: AppColors.textPrimary)),
                ),
              ),
            ],
          ),
        );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Stack(
        children: [
          const Positioned.fill(child: MeshBackdrop(alpha: 0.4, seed: 21)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF1D2537).withValues(alpha: 0.9),
                  const Color(0xFF131A28).withValues(alpha: 0.96),
                ],
              ),
              border: Border(
                  top: BorderSide(
                      color: AppColors.gold.withValues(alpha: 0.3), width: 0.9)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppColors.stroke,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Center(child: TanafusMark(size: 64)),
                    const SizedBox(height: 18),
                    Center(
                      child: A11yHeader(
                        child: GildedText(
                          l.arenaIntroTitle,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium!.copyWith(fontSize: 22, height: 1.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    line(Icons.play_arrow_rounded, l.arenaIntroPlay, 0),
                    const SizedBox(height: 14),
                    line(Icons.auto_awesome_rounded, l.arenaIntroScore, 1),
                    const SizedBox(height: 14),
                    line(Icons.bolt_rounded, l.arenaIntroDare, 2),
                    const SizedBox(height: 26),
                    GlowButton(
                      label: l.arenaIntroGo,
                      icon: Icons.play_arrow_rounded,
                      breathe: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
