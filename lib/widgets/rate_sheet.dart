import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/review_prompt.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'glow_button.dart';
import 'night_sky.dart';

/// The route to the store that no quota can close.
///
/// The OS rating sheet is the only thing allowed to interrupt a user
/// to ask for a rating, and both stores ration it — three times a year
/// on iOS, an undisclosed and changeable allowance on Play — with no
/// way for the app to learn whether any given call showed anything at
/// all. So a user who wants to leave a rating, or who declined the
/// system sheet once and changed their mind, has no way back in.
///
/// This is that way back: a sheet that only ever opens because someone
/// tapped the Settings row, and whose one button is a link to the
/// listing rather than a request for stars. That distinction is the
/// whole design — see [ReviewPrompt] for why the automatic path stays
/// native-only.
Future<void> showRateSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const _RateSheet(),
  );
}

class _RateSheet extends StatelessWidget {
  const _RateSheet();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: Starfield(count: 40, seed: 11)),
          ),
          const Positioned(
            top: -90,
            right: -70,
            child: GlowOrb(size: 240, alpha: 0.15),
          ),
          Container(
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.stroke,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Five filled stars, and no way to tap four.
                    // Nothing here collects an opinion: a sheet that
                    // asked for a rating and then routed the low ones
                    // somewhere private is the exact pattern guideline
                    // 1.1.7 was written to stop. This is decoration
                    // that says which button is about to be pressed.
                    const _Stars(),
                    const SizedBox(height: 18),
                    A11yHeader(
                      child: Text(
                        l.rateSheetTitle,
                        textAlign: TextAlign.center,
                        style: t.headlineMedium
                            ?.copyWith(fontSize: 22, height: 1.3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.rateSheetBody,
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(height: 1.55),
                    ),
                    const SizedBox(height: 22),
                    GlowButton(
                      label: Platform.isIOS
                          ? l.openAppStore
                          : l.openPlayStore,
                      icon: Icons.open_in_new_rounded,
                      onPressed: () async {
                        // Captured before the pop: the sheet's context
                        // is gone by the time the browser hand-off
                        // returns, and the snack has to outlive it.
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.of(context).pop();
                        if (await ReviewPrompt.openListing()) return;
                        if (!messenger.mounted) return;
                        messenger
                          ..clearSnackBars()
                          ..showSnackBar(SnackBar(
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.surfaceRaised,
                            content: Text(L10n.current.storeOpenFailed,
                                style: const TextStyle(
                                    color: AppColors.textPrimary)),
                          ));
                      },
                    ),
                    const SizedBox(height: 6),
                    QuietButton(
                      label: l.notNow,
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

class _Stars extends StatelessWidget {
  const _Stars();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        5,
        (_) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 3),
          child:
              Icon(Icons.star_rounded, size: 30, color: AppColors.goldBright),
        ),
      ),
    );
  }
}
