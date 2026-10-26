import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/reminder_service.dart';
import '../data/settings_service.dart';
import '../data/verse_translation.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'night_sky.dart';

/// The two language pickers, which are the same sheet twice.
///
/// Both lists have the same shape — a name in its own script, a second
/// line saying what it is, a check on the one in use — so they share a
/// row rather than being written twice and drifting.
///
/// Every row sets its own text direction and face from the language it
/// names, not from the app's. A picker that renders اردو left-to-right
/// in a Latin face is unreadable to exactly the person who came to it.

/// Which language the app itself is shown in.
Future<void> showAppLanguageSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const _LanguageSheet(verse: false),
  );
}

/// Which translation is printed under a verse.
Future<void> showVerseTranslationSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    isScrollControlled: true,
    builder: (_) => const _LanguageSheet(verse: true),
  );
}

class _LanguageSheet extends StatelessWidget {
  /// True for the translation picker, false for the app's own language.
  final bool verse;
  const _LanguageSheet({required this.verse});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final s = SettingsService.state.value;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
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
            constraints: BoxConstraints(maxHeight: maxHeight),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      verse ? l.chooseVerseTranslation : l.chooseAppLanguage,
                      textAlign: TextAlign.center,
                      style: t.headlineMedium?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      verse ? l.translationPickerNote : l.appLanguageSubtitle,
                      textAlign: TextAlign.center,
                      style: t.bodySmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (verse) ...[
                      // "None" reads in the app's own language, since
                      // it names no edition of its own.
                      _Row(
                        native: l.translationNone,
                        second: l.translationNoneNote,
                        rtl: s.lang.rtl,
                        arabicScript: s.lang.arabicScript,
                        chosen: s.verseTranslationOff,
                        onTap: () => _pickTranslation(context, null),
                      ),
                      for (final e in VerseTranslation.values)
                        _Row(
                          native: e.nativeName,
                          second: e.translator,
                          rtl: e.rtl,
                          arabicScript: e.arabicScript,
                          chosen: !s.verseTranslationOff && e == s.translation,
                          onTap: () => _pickTranslation(context, e),
                        ),
                    ] else
                      for (final e in AppLang.values)
                        _Row(
                          native: e.nativeName,
                          second: e.englishName,
                          rtl: e.rtl,
                          arabicScript: e.arabicScript,
                          chosen: e == s.lang,
                          onTap: () => _pickLang(context, e),
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

  /// Changing the app's language re-lays the scheduled reminders as
  /// well: a notification carries its wording from the moment it is
  /// scheduled, so tomorrow's would otherwise arrive in the language
  /// the user just left.
  ///
  /// The sheet closes first and the relay runs behind it. The relay is
  /// a platform call per queued reminder — hundreds on Android, a
  /// quarter of a minute on one phone — and a pop that waited for it
  /// landed after the user had long since swiped the sheet away, on
  /// the app's only route instead: an empty Navigator, which paints
  /// as a black screen, and a back press that then closed the app.
  Future<void> _pickLang(BuildContext context, AppLang lang) async {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    final s = SettingsService.state.value;
    if (lang == s.lang) return;
    await SettingsService.update(s.copyWith(lang: lang));
    unawaited(ReminderService.relayForLanguageChange());
  }

  /// Changing the translation only changes what is fetched next. The
  /// surahs already on disk are kept, each under its own edition's
  /// name, so switching back is instant and switching away costs one
  /// download per surah — see QuranTextService.
  ///
  /// Null is "None": the edition stays as it was underneath, and only
  /// the line under the verse goes.
  Future<void> _pickTranslation(
      BuildContext context, VerseTranslation? edition) async {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    final s = SettingsService.state.value;
    final off = edition == null;
    if (off == s.verseTranslationOff && (off || edition == s.translation)) {
      return;
    }
    await SettingsService.update(s.copyWith(
      translation: edition,
      verseTranslationOff: off,
    ));
  }
}

/// One language: its own name in its own script and direction, what it
/// is underneath, and a check when it is the one in use.
class _Row extends StatelessWidget {
  final String native;
  final String second;
  final bool rtl;
  final bool arabicScript;
  final bool chosen;
  final VoidCallback onTap;

  const _Row({
    required this.native,
    required this.second,
    required this.rtl,
    required this.arabicScript,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          children: [
            Expanded(
              // The row reads in the direction of the language it
              // offers, so its name sits where that language starts.
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      native,
                      style: AppTheme.translation(
                        size: 15,
                        arabic: arabicScript,
                        color: chosen
                            ? AppColors.goldBright
                            : AppColors.textPrimary,
                      ).copyWith(
                        fontStyle: FontStyle.normal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      second,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.translation(
                        size: 11.5,
                        arabic: arabicScript,
                        color: AppColors.textSecondary,
                      ).copyWith(fontStyle: FontStyle.normal),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (chosen)
              const Icon(Icons.check_rounded,
                  size: 18, color: AppColors.goldBright),
          ],
        ),
      ),
    );
  }
}
