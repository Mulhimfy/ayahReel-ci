import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'arena_fx.dart';
import 'illumination.dart';

/// The lobby's "?": how a round works, in four plain steps that lead
/// to the one that matters — the code at the end, sent to the people
/// you love, who then play your very questions. Words only: the lobby
/// under it already has the door, so the sheet ends on its last step.
Future<void> showArenaGuide(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const _GuideSheet(),
  );
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final steps = [
      (l.arenaGuidePickTitle, l.arenaGuidePickBody, null),
      (l.arenaGuidePlayTitle, l.arenaGuidePlayBody, null),
      (l.arenaGuideCodeTitle, l.arenaGuideCodeBody, const _SampleCode()),
      (l.arenaGuideSendTitle, l.arenaGuideSendBody, null),
    ];
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Stack(
        children: [
          const Positioned.fill(child: MeshBackdrop(alpha: 0.4, seed: 27)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF1D2537).withValues(alpha: 0.9),
                  const Color(0xFF131A28).withValues(alpha: 0.97),
                ],
              ),
              border: Border(
                  top: BorderSide(
                      color: AppColors.gold.withValues(alpha: 0.3),
                      width: 0.9)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
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
                    const SizedBox(height: 20),
                    Center(
                      child: A11yHeader(
                        child: GildedText(
                          l.arenaGuideTitle,
                          textAlign: TextAlign.center,
                          style: t.headlineMedium!
                              .copyWith(fontSize: 22, height: 1.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        l.arenaGuideLead,
                        textAlign: TextAlign.center,
                        style: t.bodyMedium?.copyWith(fontSize: 13, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (var i = 0; i < steps.length; i++)
                      Rise(
                        delay: Duration(milliseconds: 90 + 110 * i),
                        from: 12,
                        child: _Step(
                          number: i + 1,
                          title: steps[i].$1,
                          body: steps[i].$2,
                          extra: steps[i].$3,
                          last: i == steps.length - 1,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        l.arenaGuideHaveCode(l.arenaChallenge),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
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

/// One step: its number in a gold seal, a thread down to the next one,
/// the step in a few words and one line under them. The last seal is
/// filled — it is where the round goes out to somebody else.
class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final Widget? extra;
  final bool last;
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.extra,
    required this.last,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: last
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFFE7A6), AppColors.gold],
                          )
                        : null,
                    color: last ? null : AppColors.gold.withValues(alpha: 0.1),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: last ? 0.9 : 0.5)),
                    boxShadow: [
                      if (last)
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.45),
                          blurRadius: 14,
                        ),
                    ],
                  ),
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: last ? const Color(0xFF14100A) : AppColors.goldBright,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1.4,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.gold.withValues(alpha: 0.55),
                            AppColors.gold.withValues(alpha: 0.12),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 18 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: last ? AppColors.goldBright : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (extra != null) ...[
                    const SizedBox(height: 8),
                    extra!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a code looks like, so the word means something before the
/// first round has made one.
class _SampleCode extends StatelessWidget {
  const _SampleCode();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.bg.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_rounded, size: 13, color: AppColors.gold),
            SizedBox(width: 8),
            Text(
              'K7Q2-9XMA-3PDL',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: AppColors.goldBright,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
