import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/debug_log.dart';
import '../data/home_widget_service.dart';
import '../data/reminder_service.dart';
import '../data/rewards_service.dart';
import '../data/settings_service.dart';
import '../data/verse_lines.dart';
import '../data/verse_motion.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/language_sheet.dart';
import '../widgets/ambient_motion.dart';
import '../widgets/illumination.dart';
import '../widgets/discover_sheet.dart';
import '../widgets/feedback_sheet.dart';
import '../widgets/name_dialog.dart';
import '../widgets/nudge_dot.dart';
import '../widgets/rate_sheet.dart';
import '../widgets/reminder_time_picker.dart';
import '../widgets/storage_sheet.dart';
import '../widgets/widget_sheet.dart';
import 'customize_screen.dart';

/// Both stores require a reachable privacy policy URL in the listing.
/// The EULA row is not required while the app is free — guideline 3.1.2 only
/// demands an in-app Terms of Use link once there are auto-renewable
/// subscriptions. It ships early so that day needs no store release, and
/// points at Apple's standard agreement since the app has no terms of its own.
const _privacyPolicyUrl = 'https://cat-tank-a00.notion.site/'
    'ayahReel-Privacy-Policys-3a79170a715b80e09496f76f5e3bb6ba';
const _termsOfUseUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const _telegramChannelUrl = 'https://t.me/AyahReel';

/// Quiet control room: notifications, storage, about. No gold CTA
/// here — nothing on this screen competes with creation.
class SettingsScreen extends StatefulWidget {
  /// How the screen finds out whether the OS will deliver anything.
  ///
  /// Injectable purely so the blocked-notifications banner is testable:
  /// the notification plugin resolves its Android implementation off
  /// `Platform.isAndroid`, which is false on a desktop test host, so a
  /// mocked method channel is never even consulted there.
  final Future<bool> Function() permissionCheck;

  /// Whether the home-screen widget is placed; injectable for the
  /// same reason as [permissionCheck].
  final Future<bool> Function() widgetCheck;

  const SettingsScreen({
    super.key,
    this.permissionCheck = ReminderService.permitted,
    this.widgetCheck = HomeWidgetService.isInstalled,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  /// Whether the OS will deliver anything we schedule. Null until the
  /// first check comes back — the banner stays hidden until then rather
  /// than flashing an accusation the user may not deserve.
  bool? _permitted;

  /// Whether the verse widget is on the home screen. Only changes the
  /// row's subtitle, so a late answer costs nothing.
  bool? _widgetInstalled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
    _refreshWidget();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The banner sends people out to the system settings, so the answer
  /// has to be re-asked when they come back — otherwise it keeps
  /// telling them to fix something they have just fixed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
      _refreshWidget();
    }
  }

  Future<void> _refreshPermission() async {
    final ok = await widget.permissionCheck();
    if (mounted && ok != _permitted) setState(() => _permitted = ok);
  }

  Future<void> _refreshWidget() async {
    final on = await widget.widgetCheck();
    if (on) {
      RewardsService.recordWidgetPlaced();
      // A widget already on the home screen has nothing left to be
      // pointed at, whether or not the row was ever opened.
      _seen(widgetNudge: true);
    }
    if (mounted && on != _widgetInstalled) {
      setState(() => _widgetInstalled = on);
    }
  }

  /// Puts out a nudge dot for good. A no-op once it is out, so the
  /// settings file is not rewritten on every visit.
  void _seen({
    bool rateNudge = false,
    bool widgetNudge = false,
    bool telegramNudge = false,
    bool nameNudge = false,
  }) {
    final s = SettingsService.state.value;
    if ((rateNudge && !s.rateNudgeSeen) ||
        (widgetNudge && !s.widgetNudgeSeen) ||
        (telegramNudge && !s.telegramNudgeSeen) ||
        (nameNudge && !s.nameNudgeSeen)) {
      SettingsService.update(s.copyWith(
        rateNudgeSeen: rateNudge ? true : null,
        widgetNudgeSeen: widgetNudge ? true : null,
        telegramNudgeSeen: telegramNudge ? true : null,
        nameNudgeSeen: nameNudge ? true : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final motion = AmbientScope.maybeOf(context);
    final body = SafeArea(
      bottom: false,
      child: ValueListenableBuilder<AppSettings>(
        valueListenable: SettingsService.state,
        builder: (context, s, _) => ListView(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 128),
          children: [
            A11yHeader(child: Text(l.settingsTitle, style: t.headlineMedium)),
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(child: OrnamentHairline(towardsEnd: true)),
                SizedBox(width: 8),
                SealGlyph(size: 7, color: Color(0x99D4A947)),
              ],
            ),
            const SizedBox(height: 18),
            // Three cards, no headings: you and the app, what it
            // sends you, and the small print. A settings page short
            // enough to be read whole needs no signposts, only a gap.
            _Card(children: [
              const SizedBox(height: 6),
              // Two languages, not one setting: the app's own, and
              // the translation under a verse. They are set apart
              // because they are chosen apart — somebody reading the
              // buttons in English very often wants the verse in Urdu.
              _NavRow(
                icon: Icons.translate_rounded,
                title: l.appLanguageTitle,
                hint: l.a11ySetsLanguage,
                trailing: s.lang.nativeName,
                onTap: () => showAppLanguageSheet(context),
              ),
              _NavRow(
                icon: Icons.menu_book_outlined,
                title: l.verseTranslationTitle,
                hint: l.a11ySetsTranslation,
                trailing: s.verseTranslationOff
                    ? l.translationNone
                    : s.translation.nativeName,
                onTap: () => showVerseTranslationSheet(context),
              ),
              _NavRow(
                icon: Icons.person_outline_rounded,
                title: l.yourNameTitle,
                trailing: s.name,
                dot: s.nameNudgePending,
                onTap: () {
                  _seen(nameNudge: true);
                  _editName(context, SettingsService.state.value);
                },
              ),
              // Always the instructions, never a switch: neither OS
              // lets an app place a widget by itself. A check at the
              // end of the row is the one thing that changes once it
              // is there.
              _NavRow(
                icon: Icons.widgets_outlined,
                title: l.widgetRowTitle,
                dot: !s.widgetNudgeSeen,
                trailingIcon:
                    _widgetInstalled == true ? Icons.check_rounded : null,
                onTap: () {
                  _seen(widgetNudge: true);
                  showWidgetSheet(context);
                },
              ),
              // The half of the rating story that always works. The OS
              // sheet after an export is rationed and silent about it;
              // this row is a link to the listing, so it opens whether
              // or not that quota is spent. See [ReviewPrompt].
              _NavRow(
                icon: Icons.star_rounded,
                title: l.rateAppTitle,
                dot: !s.rateNudgeSeen,
                onTap: () {
                  _seen(rateNudge: true);
                  showRateSheet(context);
                },
              ),
              // Right under Rate: the two things a user can do for the
              // app sit together. The invite and its reward still live
              // on the home screen's button.
              _NavRow(
                icon: Icons.send_rounded,
                title: l.joinTelegramTitle,
                dot: !s.telegramNudgeSeen,
                onTap: () {
                  _seen(telegramNudge: true);
                  _openUrl(context, _telegramChannelUrl);
                },
              ),
              // Not small print, which is why it is up here with the
              // rest of what a person can do rather than down beside
              // the privacy policy: everything it lists is already on
              // screen somewhere, unlabelled, and this is the only
              // place that says so.
              _NavRow(
                icon: Icons.lightbulb_outline_rounded,
                title: l.discoverRow,
                onTap: () => showDiscoverSheet(context),
              ),
              const SizedBox(height: 6),
            ]),
            const SizedBox(height: 14),
            _Card(children: [
              const SizedBox(height: 6),
              // Shown only when the user has asked for a reminder that
              // the OS is currently swallowing — the one case where
              // the switches below say yes and nothing actually
              // arrives.
              if (_permitted == false &&
                  (s.streakReminderOn || s.personalReminderOn))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  // Live: it appears when a promise has just broken,
                  // and a reader should hear so without hunting.
                  child: A11yLive(
                    child: _BlockedBanner(onOpen: _openSystemSettings),
                  ),
                ),
              _SwitchRow(
                icon: Icons.local_fire_department_outlined,
                title: l.streakNudgeTitle,
                value: s.streakReminderOn,
                onChanged: (on) => _toggleStreak(context, s, on),
              ),
              _SwitchRow(
                icon: Icons.notifications_active_outlined,
                title: l.myReminderTitle,
                trailing: s.personalReminderOn ? _fmt(context, s) : null,
                value: s.personalReminderOn,
                onChanged: (on) => _togglePersonal(context, s, on),
                onTap: s.personalReminderOn
                    ? () => _pickTime(context, s)
                    : null,
                hint: s.personalReminderOn ? l.a11yChangesReminderTime : null,
              ),
              // Last in the card of switches: set-it-once choices about
              // the reels themselves, on a page of their own with a reel
              // playing them (see CustomizeScreen). The line after the
              // name says the two that shape a reel most. Its icons are
              // ones the app already draws: Flutter subsets
              // MaterialIcons to the glyphs in use, so a new one changes
              // the font and Shorebird refuses the patch.
              ListenableBuilder(
                listenable: creationState,
                builder: (context, _) => _NavRow(
                  icon: Icons.tune_rounded,
                  title: l.customizeTitle,
                  trailing: _customizeSummary(l, s),
                  hint: l.a11yCustomizeHint,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CustomizeScreen()));
                  },
                ),
              ),
              const SizedBox(height: 6),
            ]),
            const SizedBox(height: 14),
            _Card(children: [
              const SizedBox(height: 6),
              // The permanent half of the feedback story. The prompt
              // during the first few renders asks twice and then stops
              // for good; this row never goes away, which is what
              // makes it safe for that one to be so quiet. See
              // [FeedbackService].
              _NavRow(
                icon: Icons.forum_outlined,
                title: l.feedbackRowTitle,
                onTap: () => showFeedbackSheet(context),
              ),
              _NavRow(
                icon: Icons.storage_rounded,
                title: l.manageStorage,
                onTap: () => showStorageSheet(context),
              ),
              _NavRow(
                icon: Icons.privacy_tip_outlined,
                title: l.privacyPolicy,
                onTap: () => _openUrl(context, _privacyPolicyUrl),
              ),
              if (Platform.isIOS)
                _NavRow(
                  icon: Icons.description_outlined,
                  title: l.termsOfUse,
                  onTap: () => _openUrl(context, _termsOfUseUrl),
                ),
              const SizedBox(height: 8),
            ]),
          ],
        ),
      ),
    );
    if (motion == null) return body;
    // Scrolling Settings pushes the shell's sky exactly as Home does.
    return AmbientScrollSensor(motion: motion, child: body);
  }

  /// "1 line · Light": how a long verse appears, and how the verse
  /// moves — the two choices on the Customize page a reel shows most.
  static String _customizeSummary(L10n l, AppSettings s) {
    final lines = s.verseLines > VerseLines.whole
        ? l.linesCount(s.verseLines)
        : l.versesWhole;
    final m = creationState.motion;
    final preset = MotionPreset.of(m);
    final motion = preset != null
        ? l.motionPresetName(preset.name)
        : l.motionCustom;
    return '$lines · $motion';
  }

  /// Asks for the name the home screen greets them with. Saving an
  /// empty field is how you take it back off — the same row, no
  /// separate "remove" state to explain.
  Future<void> _editName(BuildContext context, AppSettings s) async {
    HapticFeedback.selectionClick();
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(initial: s.name),
    );
    if (picked == null) return; // dismissed: nothing changes
    // The settings as they are now, not as they were when the dialog
    // opened: a change made meanwhile (on resume, say) would be undone.
    await SettingsService.update(
        SettingsService.state.value.copyWith(name: picked));
  }

  static String _fmt(BuildContext context, AppSettings s) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: s.personalHour, minute: s.personalMinute),
    );
  }

  Future<void> _toggleStreak(
      BuildContext context, AppSettings s, bool on) async {
    HapticFeedback.selectionClick();
    final ok = await ReminderService.setStreakReminder(on);
    if (!ok && on) {
      if (context.mounted) _permissionSnack(context);
      return; // switch stays off
    }
    // The settings as they are now, not as they were at the tap: the
    // window takes seconds to lay, and anything changed meanwhile
    // would be saved back over.
    await SettingsService.update(
        SettingsService.state.value.copyWith(streakReminderOn: on));
    // Switching on may have just granted the permission, which retires
    // the banner.
    await _refreshPermission();
  }

  Future<void> _togglePersonal(
      BuildContext context, AppSettings s, bool on) async {
    HapticFeedback.selectionClick();
    if (!on) {
      await ReminderService.cancelPersonalReminder();
      await SettingsService.update(
          SettingsService.state.value.copyWith(personalReminderOn: false));
      return;
    }
    // Turning on: choose the time first, then arm it.
    await _pickTime(context, s, enabling: true);
  }

  Future<void> _pickTime(BuildContext context, AppSettings s,
      {bool enabling = false}) async {
    final picked = await pickReminderTime(
      context,
      initial: TimeOfDay(hour: s.personalHour, minute: s.personalMinute),
    );
    if (picked == null) return; // dismissed: nothing changes
    final ok =
        await ReminderService.setPersonalReminder(picked.hour, picked.minute);
    if (!ok) {
      if (context.mounted) _permissionSnack(context);
      return;
    }
    await SettingsService.update(SettingsService.state.value.copyWith(
      personalReminderOn: true,
      personalHour: picked.hour,
      personalMinute: picked.minute,
    ));
    await _refreshPermission();
    if (enabling && context.mounted) {
      final when = MaterialLocalizations.of(context).formatTimeOfDay(picked);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(toast(
          L10n.of(context).reminderSetSnack(when),
          tone: ToastTone.done,
        ));
    }
  }

  /// Opens in the real browser, not a web view — a legal document the
  /// stores check must be verifiably the hosted page. `canLaunchUrl` is
  /// skipped deliberately: on Android 11+ it needs a `<queries>` manifest
  /// entry to answer truthfully, and launching an https URL never needs one.
  Future<void> _openUrl(BuildContext context, String url) async {
    HapticFeedback.selectionClick();
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (e) {
      rlog('open url failed: $url $e');
    }
    if (!ok && context.mounted) {
      _snack(context, L10n.of(context).linkOpenFailed);
    }
  }

  void _snack(BuildContext context, String message,
      [ToastTone tone = ToastTone.problem]) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(toast(message, tone: tone));
  }

  Future<void> _openSystemSettings() async {
    HapticFeedback.selectionClick();
    await ReminderService.openSystemSettings();
    // Belt and braces: the lifecycle observer normally catches the
    // return, but a settings screen that opens as a separate task can
    // come back without one.
    await _refreshPermission();
  }

  void _permissionSnack(BuildContext context) {
    final l = L10n.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(toast(
        l.notificationsBlockedSnack,
        tone: ToastTone.problem,
        duration: const Duration(seconds: 6),
        actionLabel: l.openSettings,
        onAction: _openSystemSettings,
      ));
    // The switch snapped back, so the banner belongs on screen now.
    _refreshPermission();
  }
}

/// The one loud thing allowed on this screen, and only when the app is
/// silently failing to keep a promise the user made with a switch.
class _BlockedBanner extends StatelessWidget {
  final VoidCallback onOpen;
  const _BlockedBanner({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_off_rounded,
              size: 18, color: AppColors.goldBright),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.blockedBannerTitle,
                    style: t.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  l.blockedBannerBody,
                  style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.45),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: onOpen,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.goldBright,
                      side: BorderSide(
                          color: AppColors.gold.withValues(alpha: 0.55)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(l.openPhoneSettings),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  static const _radius = BorderRadius.all(Radius.circular(22));

  @override
  Widget build(BuildContext context) {
    // Translucent, not filled: the shell paints one living sky behind
    // all three tabs, and an opaque slab laid on it would make this
    // tab the one place in the app the night stops.
    //
    // Translucent but *not* blurred. The card used to sit on a
    // BackdropFilter, and the sky under it never stops moving, so a
    // blur here was a full backdrop re-read on every frame the tab was
    // up. A slightly denser tint keeps the night showing through as
    // colour.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.84),
        borderRadius: _radius,
        border: Border.all(color: AppColors.stroke.withValues(alpha: 0.9)),
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// The shape every row shares: an icon, a word, and whatever sits at
/// the end of the line. Nothing under the word — a row's name is the
/// whole of it.
class _RowLine extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool dot;
  final List<Widget> trailing;

  const _RowLine({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.dot,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 13),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      height: 1.2,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                NudgeDot(on: dot, size: 6.5),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onTap;

  /// A small value at the end of the line, before the switch — the
  /// time a reminder is set for.
  final String? trailing;

  /// What a screen reader says a double tap on the row does.
  final String? hint;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.onTap,
    this.trailing,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    // Two shapes to a screen reader. When the row itself is the
    // toggle, the whole row is one switch — title, value, on or off —
    // and the small drawn switch adds nothing. When the row opens the
    // time picker instead, it is a button, and the switch beside it
    // stays its own control, named after the row so it is never a
    // bare "switch, on" with nothing to say what it switches.
    final rowToggles = onTap == null;
    return Semantics(
      container: true,
      button: rowToggles ? null : true,
      toggled: rowToggles ? value : null,
      hint: hint,
      child: InkWell(
      onTap: onTap ?? () => onChanged(!value),
      child: _RowLine(
        icon: icon,
        // Gold whether the switch is on or off — dimmer when off,
        // never grey. A row of grey glyphs was the one place in the
        // app the accent colour went missing.
        iconColor: value
            ? AppColors.goldBright
            : AppColors.gold.withValues(alpha: 0.62),
        title: title,
        dot: false,
        trailing: [
          if (trailing != null) ...[
            _Trailing(trailing!),
            const SizedBox(width: 10),
          ],
          // Drawn here rather than borrowed: Material's switch is a
          // 52x32 control with a 48px tap slug, and at full size it
          // alone set the height of every row it sat in. This one is
          // half that, and the InkWell across the row is the real
          // target anyway.
          rowToggles
              ? ExcludeSemantics(
                  child: _MiniSwitch(value: value, onChanged: onChanged))
              : _MiniSwitch(
                  value: value, onChanged: onChanged, label: title),
        ],
      ),
      ),
    );
  }
}

/// The small dim value at the end of a row: a name, a time.
class _Trailing extends StatelessWidget {
  final String text;
  const _Trailing(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// A gold dot after the title, while the row is one a new install is
  /// being pointed at. Always in the tree so that going out is a fade
  /// rather than the title jumping sideways.
  final bool dot;

  /// A small value at the end of the line — the name the user gave —
  /// or a glyph there — the check on a widget that is placed. No
  /// chevron: every row here opens something, so a chevron on each
  /// would say nothing.
  final String? trailing;
  final IconData? trailingIcon;

  /// What a double tap will do, for a screen reader — same contract as
  /// the one on [_SwitchRow]. Most rows here need none: "Your name"
  /// opening the name dialog is not worth saying aloud. The two
  /// language rows do, because "App language · English" alone does not
  /// say that tapping it offers the others.
  final String? hint;

  const _NavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.dot = false,
    this.trailing,
    this.trailingIcon,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    // One button: the title, the value after it, and "new" while the
    // dot is lit. The check on a placed widget is read as done.
    return Semantics(
      container: true,
      button: true,
      hint: hint,
      child: InkWell(
      onTap: onTap,
      child: _RowLine(
        icon: icon,
        iconColor: AppColors.gold,
        title: title,
        dot: dot,
        trailing: [
          if (trailing != null && trailing!.isNotEmpty)
            Flexible(child: _Trailing(trailing!)),
          if (trailingIcon != null)
            Icon(trailingIcon,
                size: 16,
                color: AppColors.goldBright,
                semanticLabel: trailingIcon == Icons.check_rounded
                    ? L10n.of(context).a11yWidgetPlaced
                    : null),
        ],
      ),
      ),
    );
  }
}

/// A toggle at half the size of the stock one: a pill and a thumb,
/// gold when on, nothing else. The whole row is tappable, so this only
/// has to be readable.
class _MiniSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// What the switch switches, for a screen reader; only needed when
  /// it stands as its own control beside a row that does something
  /// else on a tap.
  final String? label;

  const _MiniSwitch(
      {required this.value, required this.onChanged, this.label});

  static const _w = 30.0;
  static const _h = 16.0;
  static const _thumb = 11.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      toggled: value,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: _w,
          height: _h,
          padding: const EdgeInsets.all((_h - _thumb) / 2),
          decoration: BoxDecoration(
            color: value ? AppColors.gold : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(_h / 2),
            border: Border.all(
              color: value ? AppColors.gold : AppColors.stroke,
              width: 0.8,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Container(
              width: _thumb,
              height: _thumb,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value
                    ? const Color(0xFF14100A)
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

