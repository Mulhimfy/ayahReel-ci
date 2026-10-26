import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/debug_log.dart';
import '../data/store_links.dart';
import '../data/update_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Offers the store when the phone is running an older build than the
/// one on sale, and does nothing at all otherwise.
///
/// Safe to call from anywhere on any launch: [UpdateService.due] answers
/// once per run and stays silent unless a newer version is genuinely
/// downloadable.
///
/// "Not now" is not a snooze. It closes this launch's dialog and the ask
/// comes back on the next one, and every one after it, until the phone
/// is on the published version — an update nobody is told about twice is
/// an update nobody installs.
///
/// Nothing here blocks the app. Apple rejects update walls with no way
/// past them, and a user who opened the app to hear a verse should be
/// able to, whatever version they are on.
Future<void> maybePromptUpdate(BuildContext context) async {
  final version = await UpdateService.due();
  if (version == null || !context.mounted) return;
  final l = L10n.of(context);
  final take = await showDialog<bool>(
    context: context,
    // Answered rather than dismissed — a prompt tapped away by accident
    // would be gone for a day it was never given.
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: Text(l.updateTitle),
      content: Text(l.updateBody(version)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.notNow),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.updateNow,
              style: const TextStyle(color: AppColors.gold)),
        ),
      ],
    ),
  );
  if (take == true) await openStoreListing();
}

/// Opens this app's listing in the real store app.
///
/// `canLaunchUrl` is skipped for the same reason it is everywhere else
/// in this app: on Android 11+ it needs a `<queries>` manifest entry to
/// answer truthfully, and launching an https URL never needs one.
Future<void> openStoreListing() async {
  HapticFeedback.selectionClick();
  final url = UpdateService.platformKey == 'ios' ? appStoreUrl : playStoreUrl;
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    rlogError('open store listing', e);
  }
}
