import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Prefixed: the plugin exports an `AppSettings` too, and ours — the
// user's own settings model — is the one that should keep the name.
import 'package:app_settings/app_settings.dart' as os_settings;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'arena_service.dart';
import 'debug_log.dart';
import 'notification_art.dart';
import 'reel_library.dart';
import 'reminder_copy.dart';
import 'rewards_service.dart';
import 'settings_service.dart';
import 'verse_light.dart';
import 'whole_file.dart';

/// One notification a day — two on a Friday — whichever of the two
/// switches in Settings put it there:
///
/// * **My reminder** — a clock time the user picked ("every day at
///   8:00 PM"). When it is on, the day's notification comes then.
/// * **The daily nudge** — when only it is on, the notification comes
///   in the morning most days and at two in the afternoon on some
///   ([ReminderCopy.weekSlots]): the hours a phone is opened for
///   something new.
///
/// Both on used to mean two notifications a day. It is one now, at the
/// time the user chose — and Friday's second, after the Friday prayer.
///
/// Each day is a Quran quiz round or a reel, three to two (see
/// [ReminderCopy]); says so for the part of the day it lands in; and
/// opens into a picture drawn for it ([NotificationArt]) — the big
/// picture on Android, the attachment on iOS. A tap on a quiz opens the
/// quiz lobby, a tap on a reel the first step of a new one: see [taps].
///
/// **Two a week, at most, ask for a share** — Tuesday's notification
/// and Friday's second, and only when there is something of the user's
/// own to send: the "Your verses" card once a reel is made, a round of
/// the quiz once one is played. Those carry the user's own card, or
/// their best round, as their picture, and open straight onto it.
/// They take a slot rather than add one, so the count never grows.
///
/// The OS permission ask happens at the moment of highest willingness:
/// after a proud export, or when the user flips a switch in Settings.
abstract final class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _tzReady = false;

  /// The last of the jobs that lay or clear the day's window, queued.
  static Future<void> _queue = Future<void>.value();

  /// Runs [job] once every job queued before it has finished.
  ///
  /// The window is written from five places — the launch, a language
  /// switch, either switch in Settings, onboarding — and each write is a
  /// cancel and up to ninety schedules. Two at once interleaved: one's
  /// cancel landed in the middle of the other's schedules, and the
  /// window came out half in one language, or still holding the
  /// reminders the user had just turned off. One at a time, each job
  /// reads the settings as they are when its turn comes.
  ///
  /// A job must never queue another and wait for it: it would be
  /// waiting on itself.
  static Future<T> _inTurn<T>(Future<T> Function() job) {
    final run = _queue.then((_) => job());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// A notification's text is fixed the moment it's scheduled, so one
  /// repeating schedule can only ever say one thing. Both reminders are
  /// therefore laid down as a rolling window of dated one-shots — one
  /// per day, each with its own wording from [ReminderCopy].
  ///
  /// The day the window runs out is the day the reminders stop, so it
  /// is as long as each platform can carry: thirty days on both.
  ///
  /// * iOS keeps at most 64 pending local notifications per app and
  ///   silently discards the rest, so two reminders get 30 days each
  ///   with room to spare for anything else the app ever schedules.
  /// * On Android the plugin keeps every pending one in a list that it
  ///   reads and rewrites whole on the main thread, for each one laid
  ///   or cancelled and each that fires, and a broadcast isn't done
  ///   until that write is on disk. The quarter Android used to get,
  ///   103 alarms with Friday's seconds, made it ~150 KB: Play, 1.0.8,
  ///   ANRs in its ScheduledNotificationReceiver (realme C63, Android
  ///   16), and its boot receiver re-arming more alarms than an Infinix
  ///   would hold. Thirty days is a third of the list and a ninth of
  ///   the work of laying it. Laid again each week the app is opened
  ///   ([_relayAfter]), the reminders still run a month past the last
  ///   visit.
  ///
  /// A truly endless schedule is not reachable this way — the plugin
  /// recomputes a repeating notification's first fire from today, so a
  /// repeating tail cannot be parked beyond the window without also
  /// firing inside it. Endless *and* varied needs a push server.
  static int get _horizonDays => 30;

  /// How long Android trusts a laid window before laying it again.
  ///
  /// `pendingNotificationRequests` there reads the plugin's own list,
  /// not the alarms the system holds. An alarm the system dropped (a
  /// force stop, a cleaner) stays listed: its day never comes, and at
  /// the next boot the plugin re-arms it, past, so it fires at once
  /// with every other one like it. Laid again weekly, the list holds
  /// at most a week of those.
  static const _relayAfter = Duration(days: 7);

  /// True when [laidOn], as [_scheduleDaily] saved it, is less than
  /// [age] ago. A time in the future (the clock was set back) is not.
  static bool _laidWithin(Object? laidOn, Duration age) {
    final at = DateTime.tryParse('${laidOn ?? ''}');
    if (at == null) return false;
    final since = DateTime.now().difference(at);
    return !since.isNegative && since < age;
  }

  /// The window's length on a phone that once refused an alarm after
  /// [cap] of them; [_horizonDays] on every other phone.
  ///
  /// Android caps the alarms one app may hold at 500, and some phones
  /// cap them far lower: on Infinix HOT 50i (Android 14) the plugin's
  /// boot receiver crashed the app re-arming the 90-day window (Play,
  /// 1.0.8, IllegalStateException from `setAndAllowWhileIdle`). A third
  /// of the ceiling stays free for the widget's alarm and for the
  /// re-arming at boot; a week of the window is eight alarms, a day
  /// each and Friday's second.
  static int _horizonFor(Object? cap) {
    if (_iOS || cap is! int) return _horizonDays;
    return (cap * 2 ~/ 3 * 7 ~/ 8).clamp(1, _horizonDays);
  }

  /// Android's answer to one alarm too many: "Maximum limit of
  /// concurrent alarms 500 reached for uid …", an IllegalStateException
  /// that arrives here as a PlatformException.
  static bool _isAlarmCeiling(Object e) =>
      !_iOS && '$e'.toLowerCase().contains('alarms');

  /// The platform as Flutter sees it — the same as dart:io's on a phone,
  /// and one a test can set.
  static bool get _iOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// Ids reserved per window, at the largest horizon any platform uses,
  /// so a window laid down by one build stays fully cancellable by the
  /// next even if that build shortens the horizon.
  static const _maxWindow = 90;

  /// The one notification a day: 1300–1389.
  static const _dailyBase = 1300;

  /// Friday's second, by the same day index: 1400–1489.
  static const _fridayBase = 1400;

  /// The two windows it replaced — one per switch, which could mean two
  /// notifications a day. Kept only so they can be cancelled on devices
  /// that still have them laid down.
  static const _streakBase = 1100; // 1100–1189
  static const _personalBase = 1200; // 1200–1289

  /// The single repeating schedules these replaced. Kept only so they
  /// can be cancelled on devices that still have one armed.
  static const _streakId = 1001;
  static const _personalId = 1002;

  /// What a tap on each kind of notification asks for. See [taps].
  static const openQuiz = 'quiz';
  static const openReel = 'reel';

  /// A share notification: the "Your verses" card, or a round of the
  /// quiz, the round's id after the prefix.
  static const openVerses = 'verses';
  static const openRoundPrefix = 'round:';

  static final _taps = StreamController<String>.broadcast();

  /// Taps on a notification while the app is running, as [openQuiz] or
  /// [openReel]. The one that launched the app comes from [launchTap].
  static Stream<String> get taps => _taps.stream;

  static Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(
        // The launcher icon's monochrome layer, not the launcher icon:
        // that one is adaptive on Android 8 and up, and Android 8.0
        // refuses an adaptive small icon by crashing the app that
        // posted it ("Bad notification posted … Couldn't create
        // icon") — every day, from the alarm, for every user on 8.0.
        // Later versions draw it as a white blob, since the status bar
        // reads only a small icon's alpha and the adaptive one is
        // opaque all over.
        android: AndroidInitializationSettings('@mipmap/ic_launcher_monochrome'),
        iOS: DarwinInitializationSettings(
          // No prompt at init: the ask is deferred to the peak moment.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.isNotEmpty) _taps.add(p);
      },
    );
    _ready = true;
  }

  /// The payload of the notification whose tap launched the app, or
  /// null. Call once, at start-up; it also readies [taps].
  static Future<String?> launchTap() async {
    try {
      await _init();
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d == null || !d.didNotificationLaunchApp) return null;
      final p = d.notificationResponse?.payload;
      return p == null || p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  /// Timezone database + device zone, needed only for the fixed-time
  /// personal reminder. If the device zone can't be resolved the
  /// schedule still fires — the first instance is an absolute instant —
  /// it just won't track future DST changes.
  static Future<void> _initTz() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {/* fall back to the package default */}
    _tzReady = true;
  }

  /// Call on launch: silently (re)arm whatever the user has already
  /// opted into. Never prompts.
  static Future<void> scheduleIfPermitted() async {
    try {
      await _init();
      await SettingsService.init();
      if (!await _permitted()) return;
      await _armAll();
    } catch (_) {/* reminders are an invitation, never a requirement */}
  }

  /// (Re)arm the day's notification as the settings — or the change
  /// being made to them, which Settings saves only once this has
  /// succeeded — say the user wants it. Assumes permission is granted.
  static Future<void> _armAll({
    bool force = false,
    bool? streakOn,
    bool? personalOn,
    int? hour,
    int? minute,
  }) =>
      _inTurn(() => _armAllNow(
            force: force,
            streakOn: streakOn,
            personalOn: personalOn,
            hour: hour,
            minute: minute,
          ));

  /// [_armAll], for a job that already has its turn.
  static Future<void> _armAllNow({
    bool force = false,
    bool? streakOn,
    bool? personalOn,
    int? hour,
    int? minute,
  }) async {
    final s = SettingsService.state.value;
    final personal = personalOn ?? s.personalReminderOn;
    final streak = streakOn ?? s.streakReminderOn;
    if (!personal && !streak) {
      await _cancelWindow(_dailyBase);
      await _cancelWindow(_fridayBase);
      await _retireOldWindows();
      return;
    }
    await _scheduleDaily(
      time: personal
          ? (hour: hour ?? s.personalHour, minute: minute ?? s.personalMinute)
          : null,
      personal: personal,
      force: force,
    );
  }

  /// Re-lays every armed window in the current app language. Called
  /// when the language setting flips: a healthy window full of
  /// English one-shots is exactly what must not survive the switch
  /// to Arabic (and vice versa). Never prompts.
  static Future<void> relayForLanguageChange() async {
    try {
      await _init();
      await SettingsService.init();
      if (!await _permitted()) return;
      // Everything queued is ours, and every line of it is in the
      // language just left, so one call clears the lot. Cancelling id
      // by id was a platform call per day per window — a hundred and
      // eighty on Android, each rewriting the plugin's whole store —
      // before a single new line was laid.
      await _inTurn(() async {
        await _plugin.cancelAll();
        await _armAllNow(force: true);
      });
    } catch (_) {/* reminders are an invitation, never a requirement */}
  }

  /// Call right after a successful save/share — the peak moment.
  /// Shows the in-app invitation when appropriate; requests the OS
  /// permission only on an explicit yes.
  ///
  /// Returns whether it put a dialog on screen. That moment is shared
  /// with the store's rating sheet now, and only one of them may have
  /// it: two modals stacked on one export is how a peak moment turns
  /// into an obstacle course. This one goes first because it is the
  /// one that can still be repeated later.
  static Future<bool> offerAfterExport(BuildContext context) async {
    try {
      await _init();
      await SettingsService.init();
      final s = SettingsService.state.value;
      // Both switches off means the user has explicitly declined in
      // Settings — re-offering after every export would ignore that.
      if (!s.streakReminderOn && !s.personalReminderOn) return false;
      if (await _permitted()) {
        await _armAll(); // permission exists: just re-arm
        return false;
      }
      // No cap and no snooze: while the OS is set to deliver nothing,
      // the reminder the user asked for silently does not exist, so the
      // offer is repeated after every export until it is either granted
      // or switched off in Settings — which remains the way out.
      final prefs = await _loadPrefs();
      final asked = prefs['asked'] as int? ?? 0;
      if (!context.mounted) return false;

      // If they named a time during onboarding, say it back to them.
      // The ask then reads as keeping a promise rather than making a
      // new request.
      final chosen = s.personalReminderOn
          ? MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay(hour: s.personalHour, minute: s.personalMinute))
          : null;

      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final l = L10n.of(ctx);
          return AlertDialog(
            backgroundColor: AppColors.surfaceRaised,
            title: Text(l.proudExportTitle),
            content: Text(
              chosen == null
                  ? l.proudExportBodyNoTime
                  : l.proudExportBodyWithTime(chosen),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.notNow,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(chosen == null ? l.remindMeDaily : l.yesRemindMe,
                    style: const TextStyle(color: AppColors.goldBright)),
              ),
            ],
          );
        },
      );
      // Spread, or this write drops the wording the window was laid in,
      // and the next launch lays the whole window again for nothing.
      await _savePrefs({
        ...prefs,
        'asked': asked + 1,
        'last': DateTime.now().toIso8601String(),
      });
      // Everything from here on returns true: the dialog has been on
      // screen, so this export's one interruption is spent whatever
      // the user answered.
      if (yes != true) return true;
      if (await requestPermission()) {
        await _armAll();
        return true;
      }
      // The OS shows its dialog once per install. After that the request
      // returns false with nothing on screen, so a user who said yes
      // here would watch their tap do absolutely nothing. Ours is the
      // only ask left, and it points at the one place that still works.
      if (await _permitted()) {
        await _armAll();
        return true;
      }
      if (!context.mounted) return true;
      await _offerSystemSettings(context);
      return true;
    } catch (_) {/* never let the ask break the share flow */}
    return false;
  }

  /// Shown when the user has agreed but the OS will no longer ask on our
  /// behalf. Deliberately not styled as an error: from their side they
  /// just said yes, and the app is telling them where the switch is.
  static Future<void> _offerSystemSettings(BuildContext context) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = L10n.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text(l.oneSwitchAway),
          content: Text(l.oneSwitchAwayBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.later,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.openSettings,
                  style: const TextStyle(color: AppColors.goldBright)),
            ),
          ],
        );
      },
    );
    if (open == true) {
      await openSystemSettings();
      _armOnReturn();
    }
  }

  static AppLifecycleListener? _returnWatch;

  /// Arms whatever the user chose the moment they come back from the OS
  /// settings screen. Without this the switch they just flipped would do
  /// nothing until the next cold start.
  static void _armOnReturn() {
    _returnWatch?.dispose();
    _returnWatch = AppLifecycleListener(onResume: () async {
      _returnWatch?.dispose();
      _returnWatch = null;
      try {
        if (await _permitted()) await _armAll();
      } catch (_) {}
    });
  }

  // ---- Settings tab API -------------------------------------------

  /// Flip the daily streak nudge. Returns false if the OS permission
  /// was needed and denied (the switch should snap back).
  static Future<bool> setStreakReminder(bool on) async {
    try {
      await _init();
      if (!on) {
        // My reminder, if it's on, still brings the day's notification.
        if (await _permitted()) await _armAll(force: true, streakOn: false);
        await _retireOldWindows();
        return true;
      }
      if (!await _ensurePermission()) return false;
      await _armAll(force: true, streakOn: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Arm (or re-arm at a new time) the personal fixed-time reminder.
  /// Returns false if the OS permission was denied.
  static Future<bool> setPersonalReminder(int hour, int minute) async {
    try {
      await _init();
      if (!await _ensurePermission()) return false;
      // Forced: the time itself may have moved, and a healthy window at
      // the old time is exactly what must not survive.
      await _armAll(
          force: true, personalOn: true, hour: hour, minute: minute);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Switches My reminder off. The daily nudge, if it's on, takes the
  /// day's notification back to the week's own times.
  static Future<void> cancelPersonalReminder() async {
    try {
      await _init();
      if (await _permitted()) {
        await _armAll(force: true, personalOn: false);
      } else {
        await _inTurn(() async {
          await _cancelWindow(_dailyBase);
          await _cancelWindow(_fridayBase);
        });
      }
      await _retireOldWindows();
    } catch (_) {}
  }

  /// Onboarding's ask: request the OS permission and, if it's granted,
  /// arm everything the user chose on the way through. Returns whether
  /// permission ended up granted.
  ///
  /// The caller must have persisted the user's choices first — this
  /// arms from settings, not from arguments.
  ///
  /// A denial is spent from the same budget as the after-export ask, so
  /// between them the app can only ever raise the subject twice.
  static Future<bool> requestAndArm() async {
    try {
      await _init();
      await SettingsService.init();
      if (await _permitted() || await requestPermission()) {
        // Laid behind the user rather than in front of them: a month
        // of days with their pictures is seconds of platform calls on a
        // slow phone, and onboarding's last button used to wait for
        // every one of them, looking frozen.
        unawaited(_armAll().catchError((_) {}));
        return true;
      }
      final prefs = await _loadPrefs();
      await _savePrefs({
        ...prefs,
        'asked': (prefs['asked'] as int? ?? 0) + 1,
        'last': DateTime.now().toIso8601String(),
      });
      return false;
    } catch (_) {
      return false;
    }
  }

  /// True when notifications are already allowed by the OS.
  static Future<bool> permitted() async {
    try {
      await _init();
      return await _permitted();
    } catch (_) {
      return false;
    }
  }

  /// Ask the OS for notification permission (no-op if already granted).
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return android != null
        ? (await android.requestNotificationsPermission() ?? false)
        : ios != null
            ? (await ios.requestPermissions(
                    alert: true, badge: true, sound: true) ??
                false)
            : true;
  }

  /// Hand the user to the OS screen where notifications can be switched
  /// back on. Once a permission has been permanently denied, asking
  /// again is a silent no-op on both platforms, so this is the only
  /// route back.
  static Future<void> openSystemSettings() async {
    try {
      await os_settings.AppSettings.openAppSettings(
          type: os_settings.AppSettingsType.notification);
    } catch (_) {/* nothing useful to say if the OS refuses */}
  }

  static Future<bool> _ensurePermission() async =>
      await _permitted() || await requestPermission();

  // ---- internals ---------------------------------------------------

  /// Whether the OS will actually deliver anything we schedule.
  ///
  /// Asked of the system on both platforms rather than assumed: the
  /// Settings banner is driven off this, and a banner that kept nagging
  /// someone who had already said yes would be worse than no banner.
  static Future<bool> _permitted() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      // Provisional counts: those are delivered, quietly.
      final options = await ios.checkPermissions();
      return options?.isEnabled ?? false;
    }
    return false;
  }

  /// Lay down the next [_horizonDays] days as separate one-shots — at
  /// [time] when the user chose one, at the week's own times when not —
  /// each with its own kind, line and picture, replacing whatever was
  /// queued before; and each Friday's second beside them.
  ///
  /// [force] skips the coverage check, for when the schedule itself has
  /// changed rather than merely aged — a new reminder time, say.
  static Future<void> _scheduleDaily({
    required DayTime? time,
    required bool personal,
    bool force = false,
  }) async {
    await _initTz();
    // A window laid in other words is laid again however healthy it
    // is, or the old wording would run on for weeks after an update.
    final l = L10n.current;
    // What there is of the user's own to share, read once: the share
    // notifications are written from it weeks ahead, so a window laid
    // before the first reel or the tenth is laid again.
    final shares = await _Shareables.read();
    // The same goes for a window laid in another language (changed
    // while notifications were off), or in another time zone: its
    // instants are absolute, and "8 PM" laid in London rings at 3 AM
    // in Jakarta.
    final prefs = await _loadPrefs();
    final horizon = _horizonFor(prefs['alarmCap']);
    // And one laid at another length — the 90 days builds before
    // 2026-10-13 laid on Android — or, there, a week ago or more.
    if (!force &&
        prefs['copy'] == ReminderCopy.version &&
        prefs['lang'] == l.lang.code &&
        prefs['zone'] == tz.local.name &&
        prefs['shares'] == shares.signature &&
        prefs['horizon'] == horizon &&
        (_iOS || _laidWithin(prefs['laidOn'], _relayAfter)) &&
        await _coverageIsHealthy(_dailyBase, horizon)) {
      await _retireOldWindows();
      return;
    }
    await _cancelWindow(_dailyBase);
    await _cancelWindow(_fridayBase);
    await _retireOldWindows();
    // The channel follows the switch that put the notification there,
    // so a user who silenced one in the phone's settings keeps it
    // silenced.
    final channel = personal
        ? ('personal_reminder', l.channelPersonalName,
            l.channelPersonalDescription)
        : ('daily_reel', l.channelDailyName, l.channelDailyDescription);
    DayTime slotOn(DateTime d) => time ?? ReminderCopy.slotOn(d);
    final now = DateTime.now();
    // Start today if today's time hasn't passed yet, otherwise tomorrow.
    var day = DateTime(now.year, now.month, now.day);
    final first = slotOn(day);
    if (!DateTime(day.year, day.month, day.day, first.hour, first.minute)
        .isAfter(now)) {
      day = DateTime(day.year, day.month, day.day + 1);
    }
    // The user's own pictures, drawn once for the whole window.
    final versesArt = shares.verses
        ? await NotificationArt.versesPath(shares.light, shares.versesKey)
        : null;
    final best = shares.round;
    final roundArt = best == null
        ? null
        : await NotificationArt.roundPath(best.id, best.result.score,
            [for (final a in best.answers) a.correct]);
    Object? lastError;
    var laid = 0;
    // The alarms laid, and how many there were when the phone refused
    // one (see [_isAlarmCeiling]).
    final armed = <int>[];
    int? ceiling;

    Future<void> lay(int id, DateTime when, ReminderLine line, String payload,
        String? art) async {
      // A time that passes while the pictures are drawn (a second or so
      // at 8:29:59), or Friday's second already gone, is skipped: the
      // plugin refuses a time in the past.
      if (!when.isAfter(DateTime.now().add(const Duration(seconds: 5)))) {
        return;
      }
      Future<void> schedule(NotificationDetails details) =>
          _plugin.zonedSchedule(
            id,
            line.title,
            line.body,
            tz.TZDateTime.from(when, tz.local),
            details,
            payload: payload,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
      try {
        try {
          await schedule(await _details(channel, line, art, id));
        } catch (e, st) {
          // A picture refused — iOS checks every attachment before it
          // will schedule — must not cost the day its notification.
          if (art == null) rethrow;
          rlogError('reminder: $id with its picture', e, st);
          await schedule(await _details(channel, line, null, id));
        }
        laid++;
        armed.add(id);
      } catch (e, st) {
        // One day refused must not cost the other eighty-nine.
        rlogError('reminder: $id', e, st);
        lastError = e;
        if (ceiling == null && laid > 0 && _isAlarmCeiling(e)) {
          ceiling = laid;
        }
      }
    }

    Future<void> layShare(int id, DateTime when, ShareKind kind) => lay(
          id,
          when,
          shares.line(kind, when, l),
          shares.payload(kind),
          kind == ShareKind.verses ? versesArt : roundArt,
        );

    // Every day after the phone's ceiling would be refused too, one
    // platform call each.
    for (var i = 0; i < horizon && ceiling == null; i++) {
      // Rebuilt from date parts rather than added as a Duration, so a
      // clock change mid-window doesn't drag the whole tail an hour.
      final d = DateTime(day.year, day.month, day.day + i);
      final slot = slotOn(d);
      final when = DateTime(d.year, d.month, d.day, slot.hour, slot.minute);
      final share = d.weekday == ReminderCopy.shareWeekday
          ? ReminderCopy.shareFor(d,
              verses: shares.verses, round: best != null, friday: false)
          : null;
      if (share != null) {
        await layShare(_dailyBase + i, when, share);
      } else {
        final kind = ReminderCopy.kindOn(when);
        await lay(
          _dailyBase + i,
          when,
          ReminderCopy.forDay(when, lang: l.lang),
          kind == NudgeKind.quiz ? openQuiz : openReel,
          await NotificationArt.path(kind, ReminderCopy.ordinalOn(when)),
        );
      }
      if (d.weekday != DateTime.friday) continue;
      // Friday's second: a share if there is one, the day's greeting
      // and a verse to send on if not.
      final s2 = ReminderCopy.fridaySecond(slot.hour);
      final when2 = DateTime(d.year, d.month, d.day, s2.hour, s2.minute);
      final share2 = ReminderCopy.shareFor(d,
          verses: shares.verses, round: best != null, friday: true);
      if (share2 != null) {
        await layShare(_fridayBase + i, when2, share2);
      } else {
        await lay(
          _fridayBase + i,
          when2,
          ReminderCopy.jumuahLine(when2, lang: l.lang),
          openReel,
          await NotificationArt.path(
              NudgeKind.reel, ReminderCopy.dayNumber(d) ~/ 7),
        );
      }
    }
    // Nothing laid at all is a refusal (no permission, say), and the
    // caller has to hear it.
    final error = lastError;
    if (laid == 0 && error != null) throw error;
    final cap = ceiling;
    if (cap != null) {
      // A window that fills the phone to its last alarm may not fit
      // again at boot, where any other alarm of the app's can come
      // first: the plugin's boot receiver throws on the first refusal
      // and takes the app down. Only the days a smaller window keeps
      // stay laid.
      final keep = _horizonFor(cap);
      rlog('reminder: the phone took $cap alarms and refused the next; '
          'keeping $keep days');
      for (final id in armed) {
        final day = id >= _fridayBase ? id - _fridayBase : id - _dailyBase;
        if (day >= keep) await _plugin.cancel(id);
      }
    }
    await _savePrefs({
      ...await _loadPrefs(),
      if (cap != null) 'alarmCap': cap,
      'copy': ReminderCopy.version,
      'lang': l.lang.code,
      'zone': tz.local.name,
      'shares': shares.signature,
      // What the next launch will ask for: the shorter window, when the
      // phone refused an alarm of this one.
      'horizon': cap != null ? _horizonFor(cap) : horizon,
      'laidOn': DateTime.now().toIso8601String(),
    });
  }

  /// How the day's notification looks: its channel, and — when there is
  /// one — its picture, big on Android and attached on iOS.
  static Future<NotificationDetails> _details(
    (String, String, String) channel,
    ReminderLine line,
    String? art,
    int id,
  ) async {
    final (channelId, name, description) = channel;
    String? attachment;
    if (art != null && _iOS) attachment = await _iosCopy(art, id);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        name,
        channelDescription: description,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        largeIcon: art == null ? null : FilePathAndroidBitmap(art),
        styleInformation: art == null
            ? null
            : BigPictureStyleInformation(
                FilePathAndroidBitmap(art),
                contentTitle: line.title,
                // Opened, the big picture replaces the body; this is
                // where the line goes then.
                summaryText: line.body,
                hideExpandedLargeIcon: true,
              ),
      ),
      iOS: DarwinNotificationDetails(
        attachments: [
          if (attachment != null)
            DarwinNotificationAttachment(attachment, identifier: 'art'),
        ],
      ),
    );
  }

  /// A copy of [art] for one iOS notification. iOS moves an attachment
  /// into its own store when the notification is scheduled, so each day
  /// needs a file of its own; the picture itself stays where it is for
  /// the next window.
  static Future<String?> _iosCopy(String art, int id) async {
    try {
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/notification_art/ios')
        ..createSync(recursive: true);
      return (await File(art).copy('${dir.path}/$id.png')).path;
    } catch (_) {
      return null;
    }
  }

  /// Cancels what the two old per-switch windows still hold, and the
  /// repeating schedules before them. Asks the OS first, so once they
  /// are gone this costs one call.
  static Future<void> _retireOldWindows() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        final old = (p.id >= _streakBase && p.id < _streakBase + _maxWindow) ||
            (p.id >= _personalBase && p.id < _personalBase + _maxWindow) ||
            p.id == _streakId ||
            p.id == _personalId;
        if (old) await _plugin.cancel(p.id);
      }
    } catch (_) {}
  }

  /// True while the window still has more than half its days ahead of
  /// it.
  ///
  /// Laying a window down costs one platform call per day, so doing it
  /// at every cold launch would be wasteful; doing it only when the
  /// window is half spent keeps that to roughly every two weeks, and
  /// still leaves weeks of slack.
  ///
  /// Counted from what the plugin still lists. On iOS that is what the
  /// OS holds, so it self-corrects if the system drops one. On Android
  /// it is the plugin's own list, which keeps an alarm the system
  /// dropped; there the window is also laid again weekly
  /// ([_relayAfter]).
  static Future<bool> _coverageIsHealthy(int baseId, int horizon) async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      final ours = pending
          .where((p) => p.id >= baseId && p.id < baseId + _maxWindow)
          .length;
      return ours > horizon ~/ 2;
    } catch (_) {
      return false; // can't tell — lay it down again
    }
  }

  /// Cancels whatever the window still holds — and asks the OS what
  /// that is first. A cancel is a platform call, and ninety of them
  /// aimed at ids that were never armed cost more than laying the
  /// window itself.
  static Future<void> _cancelWindow(int baseId) async {
    List<int> ids;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      ids = [
        for (final p in pending)
          if (p.id >= baseId && p.id < baseId + _maxWindow) p.id,
      ];
    } catch (_) {
      ids = [for (var i = 0; i < _maxWindow; i++) baseId + i];
    }
    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }

  static Future<File> _prefsFile() async => File(
      '${(await getApplicationSupportDirectory()).path}/reminder_prefs.json');

  static Future<Map<String, dynamic>> _loadPrefs() async {
    try {
      final f = await _prefsFile();
      if (!f.existsSync()) return {};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _savePrefs(Map<String, dynamic> prefs) async {
    try {
      await writeWhole(await _prefsFile(), jsonEncode(prefs));
    } catch (_) {}
  }
}

/// What the user has made that a notification can offer to share, read
/// once for a whole window: the "Your verses" card (the library's
/// reels, lit on the Quran), how many reels have been made, the best
/// round still in the quiz's history, and how many have been played.
class _Shareables {
  _Shareables({
    required this.light,
    required this.reels,
    required this.round,
    required this.rounds,
  });

  final VerseLight light;
  final int reels;
  final ArenaRecord? round;
  final int rounds;

  bool get verses => !light.isEmpty;

  static Future<_Shareables> read() async {
    var light = VerseLight.of(const []);
    var reels = 0;
    ArenaRecord? round;
    var rounds = 0;
    try {
      final library = await ReelLibrary.load();
      // The card's whole light — the cards' verses and the quiz's too —
      // as the tab shows it.
      light = await VerseLight.gather(reels: library);
      await RewardsService.init();
      final made = RewardsService.state.value.reelsMade;
      reels = made > library.length ? made : library.length;
    } catch (_) {}
    try {
      await ArenaService.init();
      final a = ArenaService.state.value;
      rounds = a.played;
      // Newest first, so a tie keeps the newer.
      for (final r in a.history) {
        if (round == null || r.result.score > round.result.score) round = r;
      }
      if (rounds < a.history.length) rounds = a.history.length;
    } catch (_) {}
    return _Shareables(light: light, reels: reels, round: round, rounds: rounds);
  }

  /// Moves when what a share notification would say or show does: the
  /// window is laid again then, however healthy it is.
  String get signature => '${verses ? versesKey : '-'}|'
      '${round == null ? '-' : 'r${ReminderCopy.roundDown(rounds)}:${round!.id}'}';

  /// The picture's name: it changes when the count in its words does,
  /// and when the sun on it has gained verses.
  String get versesKey =>
      'v${ReminderCopy.roundDown(reels)}-${light.verses}';

  ReminderLine line(ShareKind kind, DateTime when, L10n l) =>
      ReminderCopy.shareLine(
        kind,
        when,
        lang: l.lang,
        reels: l.reelsCount(ReminderCopy.roundDown(reels).clamp(1, 1 << 30)),
        rounds: l.roundsCount(ReminderCopy.roundDown(rounds).clamp(1, 1 << 30)),
        score: round?.result.score ?? 0,
      );

  String payload(ShareKind kind) => kind == ShareKind.verses
      ? ReminderService.openVerses
      : '${ReminderService.openRoundPrefix}${round!.id}';
}
