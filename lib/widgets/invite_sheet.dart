import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/app_share.dart';
import '../data/debug_log.dart';
import '../data/instagram_share.dart';
import '../data/share_origin.dart';
import '../l10n/l10n.dart';
import '../render/invite_story.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'app_toast.dart';
import 'direct_share_button.dart';
import 'glow_button.dart';
import 'night_sky.dart';

/// The reason to pass the app on, said once, before the share sheet
/// opens.
///
/// Handing someone this app is not a referral — it is the same deed
/// they will go on to do, credited again to whoever pointed the way.
/// That is worth a screen of its own; a share sheet that opens with no
/// explanation is just a favour being asked.
Future<void> showInviteSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const _InviteSheet(),
  );
}

/// One gentle second thought before the sheet closes. Not a guilt trip:
/// a single question, and either answer ends it.
Future<void> _confirmLeave(BuildContext context) async {
  final navigator = Navigator.of(context);
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l = L10n.of(dialogContext);
      return AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Text(
          l.loseRewardsConfirm,
          textAlign: TextAlign.center,
          style: Theme.of(dialogContext)
              .textTheme
              .bodyMedium
              ?.copyWith(height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          QuietButton(
            label: l.leave,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
          QuietButton(
            label: l.stay,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      );
    },
  );
  if (leave ?? false) navigator.pop();
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  /// The story card is drawn on the way out, and the button shows the
  /// wait rather than going dead for it.
  bool _storyBusy = false;

  /// Straight into Instagram's story composer with the invite card as
  /// the story's background. The card is rendered first, while the
  /// sheet is still up; then the sheet closes and the hand-off runs
  /// exactly as the share button's does — nothing here may touch this
  /// context once the pop has happened.
  Future<void> _toStory(BuildContext buttonContext) async {
    final messenger = ScaffoldMessenger.of(buttonContext);
    final origin = shareOriginOf(buttonContext);
    final navigator = Navigator.of(buttonContext);
    HapticFeedback.selectionClick();
    setState(() => _storyBusy = true);
    final File card;
    try {
      card = await InviteStory.render();
    } catch (e, s) {
      rlogError('invite story', e, s);
      if (!mounted) return;
      setState(() => _storyBusy = false);
      messenger.showSnackBar(
        toast(L10n.current.shareFailed(e), tone: ToastTone.problem),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _storyBusy = false);
    // Only while this sheet is on top: after the render's wait a bare
    // pop could close whatever was opened over it instead.
    if (ModalRoute.of(context)?.isCurrent == true) navigator.pop();
    await shareAppStory(messenger, card, origin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: Starfield(count: 40, seed: 23)),
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
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.gold.withValues(alpha: 0.12),
                        border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.45)),
                      ),
                      child: const Icon(Icons.volunteer_activism_rounded,
                          size: 27, color: AppColors.goldBright),
                    ),
                    const SizedBox(height: 18),
                    A11yHeader(
                      child: Text(
                        l.inviteHeadline,
                        textAlign: TextAlign.center,
                        style: t.headlineMedium
                            ?.copyWith(fontSize: 22, height: 1.3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.inviteBody,
                      textAlign: TextAlign.center,
                      style: t.bodyMedium?.copyWith(height: 1.55),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            l.hadithGuidesToGood,
                            textAlign: TextAlign.center,
                            style: AppTheme.translation(
                                    size: 13.5, arabic: l.arabicScript)
                                .copyWith(
                                    color: AppColors.textPrimary,
                                    height: 1.5),
                          ),
                          const SizedBox(height: 7),
                          Text(l.sahihMuslim,
                              style: t.bodySmall?.copyWith(
                                color: AppColors.gold,
                                fontSize: 11,
                                letterSpacing: 0.6,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Two doors side by side: the share sheet, and
                    // Instagram's story composer in Instagram's own
                    // colours — the same mesh as the reel button under
                    // the preview, so it is recognisably the same app.
                    // Share keeps the gold and a little more of the row.
                    Row(
                      children: [
                        Expanded(
                          flex: 6,
                          // Builder so the origin rect measures the
                          // button itself rather than the whole sheet.
                          child: Builder(
                            builder: (buttonContext) => GlowButton(
                              label: l.shareAyahReel,
                              icon: Icons.ios_share_rounded,
                              height: 50,
                              dense: true,
                              onPressed: () async {
                                // Both grabbed before the pop: the
                                // sheet's context is gone by the time
                                // the OS share sheet returns, and a
                                // popped button has no render box left
                                // to measure.
                                final messenger =
                                    ScaffoldMessenger.of(buttonContext);
                                final origin = shareOriginOf(buttonContext);
                                Navigator.of(buttonContext).pop();
                                await shareApp(messenger, origin: origin);
                              },
                            ),
                          ),
                        ),
                        if (InstagramShare.supported) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 5,
                            child: Builder(
                              builder: (buttonContext) => DirectShareButton(
                                label: l.sendToInstagramStory,
                                icon: Icons.motion_photos_on_rounded,
                                colors: instagramMesh,
                                height: 50,
                                busy: _storyBusy,
                                onPressed: () => _toStory(buttonContext),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    QuietButton(
                      label: l.notNow,
                      onPressed: () => _confirmLeave(context),
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

/// The persistent invitation: bottom-right on every tab, floating above
/// the nav bar.
///
/// Deliberately NOT gold-filled. Gold in this app marks the one most
/// wanted action on a screen, and on Home that is the Create card — a
/// gold button down here would split the eye every time the app opens.
/// Glass with a gold edge reads as always-available, never as the ask.
class InviteFab extends StatelessWidget {
  const InviteFab({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Semantics(
      container: true,
      button: true,
      label: l.inviteSomeoneSemantics,
      child: Tooltip(
        message: l.inviteSomeone,
        excludeFromSemantics: true,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: AppColors.surfaceRaised.withValues(alpha: 0.88),
              shape: CircleBorder(
                side: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.42), width: 1),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => showInviteSheet(context),
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(Icons.volunteer_activism_rounded,
                      size: 23, color: AppColors.goldBright),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
