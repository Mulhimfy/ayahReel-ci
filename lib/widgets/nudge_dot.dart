import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The small gold dot that says "something here is waiting for you".
///
/// One shape, used on the Settings tab and on the two rows it points
/// at, so the eye follows the same mark from the bar to the row. It
/// fades and shrinks away rather than vanishing: a dot that is cut
/// reads as a glitch, and one that goes out reads as done.
class NudgeDot extends StatelessWidget {
  final bool on;
  final double size;
  const NudgeDot({super.key, required this.on, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // A lit dot says "new" to the reader, as part of whatever row or
      // tab it sits on. An unlit one says nothing at all.
      child: Semantics(
        label: on ? L10n.of(context).a11yNew : null,
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOut,
          child: AnimatedScale(
            scale: on ? 1 : 0.3,
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeOut,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.goldBright,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.75),
                    blurRadius: 6,
                    spreadRadius: 0.5,
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
