import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'arena_fx.dart' show Rise;

/// One line of a "?" sheet: a small mark and a sentence.
typedef HowToStep = (Widget mark, String text);

/// The "?" a screen keeps in its corner: how to use it, in a handful of
/// plain lines and nothing else — no heading paragraph, no tips about
/// tips. Each line is one thing to do, with the mark the screen itself
/// uses for it, so the eye can match the line to the control.
Future<void> showHowTo(
  BuildContext context, {
  required String title,
  required List<HowToStep> steps,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (_) => _HowToSheet(title: title, steps: steps),
  );
}

class _HowToSheet extends StatelessWidget {
  final String title;
  final List<HowToStep> steps;
  const _HowToSheet({required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D2537), Color(0xFF131A28)],
          ),
          border: Border(
              top: BorderSide(
                  color: AppColors.gold.withValues(alpha: 0.3), width: 0.9)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                const SizedBox(height: 18),
                A11yHeader(
                  child: Text(title,
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(fontSize: 18)),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < steps.length; i++)
                  Rise(
                    delay: Duration(milliseconds: 60 + 70 * i),
                    from: 10,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.gold.withValues(alpha: 0.1),
                              border: Border.all(
                                  color: AppColors.gold.withValues(alpha: 0.4)),
                            ),
                            child: steps[i].$1,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Text(
                                steps[i].$2,
                                style: t.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.goldBright,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: AppColors.gold.withValues(alpha: 0.45)),
                    ),
                  ),
                  child: Text(l.howToGotIt,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round "?" a screen keeps in its top corner.
class HowToButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const HowToButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold.withValues(alpha: 0.10),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            child: const Text(
              '?',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 15,
                height: 1,
                fontWeight: FontWeight.w800,
                color: AppColors.goldBright,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
