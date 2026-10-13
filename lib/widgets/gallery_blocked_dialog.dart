// Prefixed: the plugin exports an `AppSettings` that clashes with the
// app's own settings model elsewhere; keep the naming consistent.
import 'package:app_settings/app_settings.dart' as os_settings;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debug_log.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// Shown when the OS refuses to let a reel into the gallery.
///
/// A snackbar was the wrong shape for this: it is gone in seconds, and
/// what it has to say is the one thing the user must act on — a
/// permission denied for good never prompts again, on any app, so the
/// settings screen is the only route back. This stays on screen until
/// it is answered, and the button goes straight there.
Future<void> showGalleryBlockedDialog(BuildContext context) {
  final l = L10n.of(context);
  return showDialog<void>(
    context: context,
    // The whole point is that it is not dismissed by accident.
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: Text(l.galleryWriteBlockedTitle),
      content: Text(l.galleryWriteBlocked),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.notNow),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            openAppPermissionSettings();
          },
          child: Text(l.openSettings,
              style: const TextStyle(color: AppColors.gold)),
        ),
      ],
    ),
  );
}

/// Opens this app's own settings page, where the gallery permission
/// lives on both platforms.
Future<void> openAppPermissionSettings() async {
  HapticFeedback.selectionClick();
  try {
    await os_settings.AppSettings.openAppSettings(
        type: os_settings.AppSettingsType.settings);
  } catch (e) {
    rlogError('open app settings', e);
  }
}
