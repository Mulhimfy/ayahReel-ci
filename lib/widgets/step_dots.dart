import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Progress dots for the creation flow: voice -> verses -> scenery ->
/// reel. Turns four pushed screens into one legible wizard — the user
/// always knows where they are and how much is left.
class StepDots extends StatelessWidget {
  /// 1-based index of the active step.
  final int current;
  final int total;

  const StepDots({super.key, required this.current, this.total = 4});

  @override
  Widget build(BuildContext context) {
    // Read as "Step 2 of 4": the dots say it to the eye, and nothing
    // about a row of bars says it to a screen reader.
    return Semantics(
      label: L10n.of(context).a11yStep(current, total),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: i == current ? 22.0 : 7.0,
              height: 7,
              decoration: BoxDecoration(
                color: i == current
                    ? AppColors.gold
                    : i < current
                        ? AppColors.gold.withValues(alpha: 0.45)
                        : AppColors.stroke,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
