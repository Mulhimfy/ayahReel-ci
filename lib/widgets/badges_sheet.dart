import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/rewards_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'illumination.dart';
import 'night_sky.dart';

/// The shelf of badges: every one there is, the earned ones lit and
/// the rest dim with what they still want under them. Opened from the
/// streak cartouche on the home tab.
Future<void> showBadgesSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const BadgesSheet(),
  );
}

class BadgesSheet extends StatelessWidget {
  const BadgesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: Starfield(count: 40, seed: 17)),
          ),
          const Positioned(
            top: -90,
            right: -70,
            child: GlowOrb(size: 240, alpha: 0.15),
          ),
          Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1D2537), Color(0xFF131A28)],
              ),
              border: Border(
                top: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.3), width: 0.9),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
                child: ValueListenableBuilder<RewardsState>(
                  valueListenable: RewardsService.state,
                  builder: (context, s, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.stroke,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      A11yHeader(
                        child: Text(
                          l.badgesTitle,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium
                              ?.copyWith(fontSize: 22, height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.badgesBody,
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(height: 1.55),
                      ),
                      const SizedBox(height: 22),
                      for (final b in RewardBadge.all) ...[
                        _RewardBadgeRow(badge: b, state: s),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One badge: a seal, lit or not, with its name and either when it
/// was earned or what it still wants.
class _RewardBadgeRow extends StatelessWidget {
  final RewardBadge badge;
  final RewardsState state;
  const _RewardBadgeRow({required this.badge, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final earned = badge.earnedBy(state);
    final hint = earned
        ? null
        : badge.reels != null
            ? l.badgeReelsToGo(badge.reelsToGo(state))
            : l.badgeWidgetToGo;
    // One line per badge: its name, then earned, or what it still
    // wants. The seal and the check are the same fact drawn.
    return Semantics(
      container: true,
      // l.comma, not l.ar: Urdu takes the Arabic comma too.
      label: earned
          ? '${l.badgeName(badge.id)}${l.comma} ${l.a11yEarned}'
          : '${l.badgeName(badge.id)}${l.comma} $hint',
      excludeSemantics: true,
      child: Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: earned
            ? AppColors.gold.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.03),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: earned ? 0.42 : 0.14),
          width: 0.9,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: SealGlyph(
                size: earned ? 22 : 16,
                color: earned
                    ? AppColors.goldBright
                    : AppColors.gold.withValues(alpha: 0.35),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.badgeName(badge.id),
                  style: t.bodyMedium?.copyWith(
                    color: earned
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (earned)
            const Icon(Icons.check_rounded,
                size: 18, color: AppColors.goldBright),
        ],
      ),
      ),
    );
  }
}
