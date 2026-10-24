import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/verse_light.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'glow_button.dart';
import 'quran_sun.dart';

/// Every tenth reel: the "Your verses" card rising, the verses made so
/// far burning in on it one by one, and one way on — to the card
/// itself, where it is shared.
///
/// The tenth, twentieth, thirtieth: there is no last one. Each says
/// more than the one before, which is the whole reason to offer the
/// card again. Not a badge and not a chore: one tap to the card, one to
/// let it be.
///
/// Returns whether it was shown; a library with nothing left in it has
/// no card to offer. [onSee] runs when the user asks for the card.
Future<bool> offerVersesMilestone(
  BuildContext context, {
  required int reels,
  required VoidCallback onSee,
}) async {
  final light = await VerseLight.gather();
  if (light.isEmpty || !context.mounted) return false;
  HapticFeedback.mediumImpact();
  final see = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.64),
    transitionDuration: const Duration(milliseconds: 460),
    pageBuilder: (_, __, ___) => _MilestoneCard(reels: reels, light: light),
    transitionBuilder: (context, a, _, child) {
      final rise = CurvedAnimation(
        parent: a,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: 0.86, end: 1.0).animate(rise),
          child: child,
        ),
      );
    },
  );
  if (see == true) onSee();
  return true;
}

class _MilestoneCard extends StatelessWidget {
  final int reels;
  final VerseLight light;

  const _MilestoneCard({required this.reels, required this.light});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF131B2E), Color(0xFF080B14)],
                ),
                border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.34), width: 0.9),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.16),
                    blurRadius: 44,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The card's own sun, coming up: what the button is
                  // about to show, before it is asked to.
                  ExcludeSemantics(
                    child: SizedBox(
                      height: 236,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 236,
                            height: 236,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0x3DD4A947),
                                  Color(0x126E50A0),
                                  Color(0x00000000),
                                ],
                                stops: [0, 0.5, 1],
                              ),
                            ),
                          ),
                          SizedBox.square(
                            dimension: 236,
                            child: QuranSunView(light: light, animate: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  A11yHeader(
                    child: ShaderMask(
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
                        l.versesMilestoneTitle(reels),
                        textAlign: TextAlign.center,
                        style: t.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.versesMilestoneBody,
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  GlowButton(
                    label: l.versesMilestoneCta,
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: Text(l.later),
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
