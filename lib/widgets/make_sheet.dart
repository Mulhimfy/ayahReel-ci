import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/quran_verses.dart';
import '../l10n/l10n.dart';
import '../screens/cards_screen.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'day_verse_card.dart';

/// What to make with the verse that was just tapped.
///
/// The home screen's verse card used to be a door with one room behind
/// it: tapping it started a reel, because a reel was the only thing
/// the app made. There are two now, and guessing which one somebody
/// wanted is worse than asking — the ask is one tap, on two choices,
/// and it is the last time the question comes up for that verse.
Future<void> makeFromVerse(BuildContext context, QuranVerse verse) async {
  HapticFeedback.selectionClick();
  final choice = await showModalBottomSheet<_Make>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _MakeSheet(),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Make.reel:
      startVerseReel(context, verse);
    case _Make.card:
      await openCardStudio(context, deckForVerse(context, verse), fresh: true);
  }
}

enum _Make { reel, card }

class _MakeSheet extends StatelessWidget {
  const _MakeSheet();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            A11yHeader(child: Text(l.makeTitle, style: t.titleMedium)),
            const SizedBox(height: 4),
            Text(l.makeBlurb,
                style: t.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.45)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    icon: Icons.movie_creation_outlined,
                    title: l.makeReel,
                    hint: l.makeReelHint,
                    onTap: () => Navigator.of(context).pop(_Make.reel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Choice(
                    icon: Icons.crop_portrait_rounded,
                    title: l.makeCard,
                    hint: l.makeCardHint,
                    onTap: () => Navigator.of(context).pop(_Make.card),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two, as a tall tile rather than a list row: they are
/// equals, and a list makes the first one look like the answer.
class _Choice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  const _Choice({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: '$title. $hint',
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.38)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: AppColors.goldBright),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 3),
              Text(hint,
                  style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
