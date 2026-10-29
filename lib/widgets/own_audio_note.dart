import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// For a reel on the user's own recording: nothing times its words, so
/// the light and the thread follow the recording's own pauses, a best
/// guess (BreathPace), and Still is always there. Said kindly at the top
/// of Make it yours' motion and of the reel screen (the owner's ask,
/// 2026-10-26). It stays until the user puts it away, never fading by
/// itself, and a small lightbulb then brings it back.
class OwnAudioNote extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const OwnAudioNote({super.key, this.padding = EdgeInsets.zero});

  static void _show(bool shown) {
    HapticFeedback.selectionClick();
    SettingsService.update(SettingsService.state.value
        .copyWith(ownAudioNoteHidden: !shown));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) => Padding(
        padding: padding,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: s.ownAudioNoteHidden ? _again(l) : _note(context, l),
        ),
      ),
    );
  }

  /// The note put away: one small pill that opens it again.
  Widget _again(L10n l) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: A11yTap(
          label: l.ownAudioNoteAgain,
          onTap: () => _show(true),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _show(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColors.gold.withValues(alpha: 0.08),
                border:
                    Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 14, color: AppColors.goldBright),
                  const SizedBox(width: 5),
                  Text(
                    l.ownAudioNoteAgain,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.goldBright,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _note(BuildContext context, L10n l) => Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.gold.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.lightbulb_outline_rounded,
                  size: 16, color: AppColors.goldBright),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.ownAudioMotionNote(l.motionPresetName('still')),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            IconButton(
              tooltip: l.howToGotIt,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: AppColors.textSecondary),
              onPressed: () => _show(false),
            ),
          ],
        ),
      );
}
