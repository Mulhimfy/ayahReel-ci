import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/l10n.dart';
import '../widgets/app_toast.dart';
import 'debug_log.dart';
import 'instagram_share.dart';
import 'rewards_service.dart';

/// What the user sends when they invite someone. Leads with the reward
/// rather than the feature list — the reason to pass this app on is
/// never that it exports mp4s. Localized to the app language at the
/// moment of sharing.
String get appShareMessage => L10n.current.appShareMessage;

/// Hand the app itself to someone else, and award the ✦ for it.
///
/// Inviting someone in IS the reward loop, so it earns like sharing a
/// reel does. The OS reports whether the user picked an app in the
/// share sheet (success) or backed out (dismissed); nothing deeper is
/// visible to any app. Some devices can't report at all (unavailable) —
/// those get the benefit of the doubt, and the once-per-day cap in
/// RewardsService keeps that honest.
///
/// Single implementation on purpose: the floating button and the
/// Settings row must never drift apart on copy or on reward.
///
/// Takes the messenger rather than a BuildContext because the caller
/// that starts this — the invite sheet — closes itself first, and its
/// context is gone by the time the OS share sheet returns. [origin] is
/// measured by the caller for the same reason: on iPad the sheet is a
/// popover and simply never opens without it (see `shareOriginOf`).
Future<void> shareApp(
  ScaffoldMessengerState messenger, {
  required Rect origin,
}) async {
  final l = L10n.current;
  final ShareResult result;
  try {
    result = await SharePlus.instance.share(
        ShareParams(text: appShareMessage, sharePositionOrigin: origin));
  } catch (e, s) {
    // Nothing above this catches, so without it a refused share sheet
    // is indistinguishable from a button that does nothing — which is
    // exactly how the missing sharePositionOrigin presented.
    rlogError('app share', e, s);
    _snack(messenger, l.shareFailed(e), ToastTone.problem);
    return;
  }
  rlog('app share: ${result.status} raw=${result.raw}');
  await _settle(messenger, result);
}

/// Hand the app on as an Instagram story — [card] laid over the whole
/// story as its background — and award the ✦ for it.
///
/// Straight into Instagram's story composer when it is there (see
/// [InstagramShare.shareStory]); when it is not, the same card goes to
/// the share sheet with the invite message, so the tap never ends in
/// nothing. Instagram does not report back whether the story was
/// posted, any more than the share sheet reports what was done in the
/// app it opened, so a hand-off that landed earns the way a share
/// does — and the once-a-day cap keeps that honest.
///
/// Same contract as [shareApp] on the messenger and the origin, and
/// for the same reason: the sheet that starts this is gone by the time
/// anything returns.
Future<void> shareAppStory(
  ScaffoldMessengerState messenger,
  File card, {
  required Rect origin,
}) async {
  final l = L10n.current;
  if (await InstagramShare.shareStory(card)) {
    await _settle(messenger, null);
    return;
  }
  _snack(messenger, l.instagramUnavailable, ToastTone.problem);
  final ShareResult result;
  try {
    result = await SharePlus.instance.share(ShareParams(
      files: [XFile(card.path, mimeType: 'image/png')],
      text: appShareMessage,
      sharePositionOrigin: origin,
    ));
  } catch (e, s) {
    rlogError('app story share', e, s);
    _snack(messenger, l.shareFailed(e), ToastTone.problem);
    return;
  }
  rlog('app story share: ${result.status} raw=${result.raw}');
  await _settle(messenger, result);
}

/// The end of both invitations: a share the user backed out of earns
/// nothing and says so; anything else is a share, awarded once a day.
/// Null is a hand-off that never came back through the share sheet —
/// a direct one — and counts as done.
Future<void> _settle(
    ScaffoldMessengerState messenger, ShareResult? result) async {
  final l = L10n.current;
  if (result?.status == ShareResultStatus.dismissed) {
    _snack(messenger, l.shareCancelled, ToastTone.info);
    return;
  }
  final awarded = await RewardsService.recordAppShared();
  _snack(
    messenger,
    awarded
        ? l.shareAwarded(RewardsService.pointsPerShare)
        : l.shareAlreadyEarned,
  );
}

void _snack(ScaffoldMessengerState messenger, String message,
    [ToastTone tone = ToastTone.done]) {
  if (!messenger.mounted) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(toast(message, tone: tone));
}
