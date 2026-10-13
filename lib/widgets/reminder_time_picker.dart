import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The clock, dressed in the app's night palette. Shared by onboarding
/// and Settings so choosing a time feels like the same act in both —
/// and so the dial can only ever be restyled in one place.
Future<TimeOfDay?> pickReminderTime(
  BuildContext context, {
  required TimeOfDay initial,
  String? helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: initial,
    helpText: helpText ?? L10n.of(context).remindMeHelpText,
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        timePickerTheme: const TimePickerThemeData(
          backgroundColor: AppColors.surfaceRaised,
          hourMinuteColor: AppColors.surface,
          hourMinuteTextColor: AppColors.textPrimary,
          dayPeriodTextColor: AppColors.textPrimary,
          dialBackgroundColor: AppColors.surface,
          dialHandColor: AppColors.gold,
          dialTextColor: AppColors.textPrimary,
          entryModeIconColor: AppColors.textSecondary,
          helpTextStyle: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            letterSpacing: 1.1,
          ),
        ),
      ),
      child: child!,
    ),
  );
}
