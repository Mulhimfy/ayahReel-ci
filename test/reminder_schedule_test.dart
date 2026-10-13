import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/reminder_copy.dart';
import 'package:ayah_reels/data/reminder_service.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/app_lang.dart';

/// The real scheduler, on Android, with the plugin's channel recorded
/// rather than answered by a phone: one notification a day and never
/// two, at the time the user chose or at the end of the day, never
/// ending in the same words two days running, three quizzes to two
/// reels, each with its picture and its door.
void main() {
  late Directory tmp;
  late List<Map<Object?, Object?>> scheduled;
  late List<int> cancelled;
  late List<int> pendingIds;

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('reminders');
    PathProviderPlatform.instance = _Dirs(tmp.path);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    scheduled = [];
    cancelled = [];
    pendingIds = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
        case 'areNotificationsEnabled':
        case 'requestPermissions':
          return true;
        case 'checkPermissions':
          return {'isEnabled': true, 'isAlertEnabled': true};
        case 'zonedSchedule':
          scheduled.add(call.arguments as Map<Object?, Object?>);
          pendingIds.add((call.arguments as Map)['id'] as int);
          return null;
        case 'cancel':
          final id = call.arguments is Map
              ? (call.arguments as Map)['id'] as int
              : call.arguments as int;
          cancelled.add(id);
          pendingIds.remove(id);
          return null;
        case 'pendingNotificationRequests':
          return [
            for (final id in pendingIds)
              {'id': id, 'title': '', 'body': '', 'payload': ''},
          ];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    SettingsService.state.value = AppSettings.defaults;
    tmp.deleteSync(recursive: true);
  });

  /// When each scheduled notification fires, as the plugin was told.
  DateTime at(Map<Object?, Object?> m) =>
      DateTime.parse(m['scheduledDateTime']! as String);

  Map<Object?, Object?> android(Map<Object?, Object?> m) =>
      m['platformSpecifics']! as Map<Object?, Object?>;

  /// Runs [body] as an Android phone would. The override has to be
  /// undone inside the test itself, before the binding checks for it.
  Future<void> onAndroid(WidgetTester t, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await t.runAsync(body);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('the nudge alone: one a day, at nine in the evening',
      (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));

    expect(scheduled, hasLength(30));
    final days = {
      for (final m in scheduled)
        DateTime(at(m).year, at(m).month, at(m).day),
    };
    expect(days, hasLength(30), reason: 'never two on one day');
    final nights = ReminderCopy.timePhrases[AppLang.en]![DayPart.night]!;
    final endings = <String>[];
    for (final m in scheduled) {
      expect((at(m).hour, at(m).minute), (21, 0));
      expect(android(m)['channelId'], 'daily_reel');
      // Said for the night, in one of its ways of saying it.
      final said = '${m['title']} ${m['body']}';
      final ending = nights.where(said.contains).toList();
      expect(ending, hasLength(1), reason: said);
      endings.add(ending.single);
    }
    // Not the same words two nights running, and every one in turn.
    for (var i = 1; i < endings.length; i++) {
      expect(endings[i], isNot(endings[i - 1]), reason: 'night $i');
    }
    expect(endings.toSet(), nights.toSet());
  });

  testWidgets('three quizzes to two reels, each with its picture and door',
      (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));

    final quizzes =
        scheduled.where((m) => m['payload'] == ReminderService.openQuiz);
    final reels =
        scheduled.where((m) => m['payload'] == ReminderService.openReel);
    expect(quizzes, hasLength(18));
    expect(reels, hasLength(12));
    for (final m in scheduled) {
      final day = at(m);
      expect(
          m['payload'],
          ReminderCopy.kindOn(day) == NudgeKind.quiz
              ? ReminderService.openQuiz
              : ReminderService.openReel);
      final style = android(m)['styleInformation']! as Map<Object?, Object?>;
      final picture = style['bigPicture']! as String;
      expect(File(picture).existsSync(), isTrue, reason: picture);
      expect(File(picture).readAsBytesSync().sublist(1, 4),
          'PNG'.codeUnits, reason: 'a picture the phone can open');
      // Opened, the line is still there under the picture.
      expect(style['summaryText'], m['body']);
    }
    // The six of each kind, taken in turn.
    final pictures = {
      for (final m in scheduled)
        ((android(m)['styleInformation']! as Map)['bigPicture']! as String),
    };
    expect(pictures, hasLength(12));
  });

  testWidgets('my reminder, with the nudge on too: still one a day, at '
      'my time, said for the morning', (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setPersonalReminder(7, 30));

    expect(scheduled, hasLength(30));
    final mornings = ReminderCopy.timePhrases[AppLang.en]![DayPart.morning]!;
    for (final m in scheduled) {
      expect((at(m).hour, at(m).minute), (7, 30));
      expect(android(m)['channelId'], 'personal_reminder');
      final said = '${m['title']} ${m['body']}';
      expect(mornings.where(said.contains), hasLength(1), reason: said);
    }
  });

  testWidgets('my reminder off: the nudge takes the day back to the '
      'evening', (t) async {
    SettingsService.state.value = AppSettings.defaults.copyWith(
        streakReminderOn: true,
        personalReminderOn: true,
        personalHour: 8,
        personalMinute: 0);
    await onAndroid(t, () => ReminderService.cancelPersonalReminder());

    expect(scheduled, hasLength(30));
    expect(scheduled.map((m) => at(m).hour).toSet(), {21});
  });

  testWidgets('two writes of the window at once are taken in turn',
      (t) async {
    // The switch flipped on and straight back off, while the first
    // window is still being laid. Side by side, the off's cancel
    // landed in the middle of the on's schedules, and the days after
    // it were left queued for a reminder the user had turned off.
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: false, personalReminderOn: false);
    await onAndroid(t, () async {
      await Future.wait([
        ReminderService.setStreakReminder(true),
        ReminderService.setStreakReminder(false),
      ]);
    });
    expect(scheduled, hasLength(30), reason: 'the on was laid whole');
    expect(pendingIds, isEmpty, reason: 'and the off, after it, took it up');
  });

  testWidgets('both off: nothing is left queued', (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));
    expect(pendingIds, hasLength(30));
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(false));
    expect(pendingIds, isEmpty);
  });

  testWidgets('the two old windows, which could mean two a day, are '
      'cancelled', (t) async {
    // What an older build left queued: a nudge window, a reminder
    // window, and the repeating schedules before them.
    pendingIds.addAll([1100, 1101, 1150, 1200, 1201, 1289, 1001, 1002]);
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));

    expect(cancelled,
        containsAll([1100, 1101, 1150, 1200, 1201, 1289, 1001, 1002]));
    expect(pendingIds.where((id) => id < 1300), isEmpty);
  });

  testWidgets('a window laid in older words is laid again at the next '
      'launch, and after that left alone', (t) async {
    // What the build before left queued: a healthy window, but in the
    // words that build had.
    pendingIds.addAll([for (var i = 0; i < 90; i++) 1300 + i]);
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, hasLength(30));
    expect(pendingIds, hasLength(30));

    scheduled.clear();
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, isEmpty, reason: 'already in these words');
  });

  testWidgets('on Android a window is laid again once it is a week old, '
      'and the 90 days earlier patches laid come back as 30', (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, hasLength(30));

    final prefsFile = File('${tmp.path}/reminder_prefs.json');
    Map<String, dynamic> prefs() =>
        jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;
    void edit(Map<String, dynamic> Function(Map<String, dynamic>) f) =>
        prefsFile.writeAsStringSync(jsonEncode(f(prefs())));
    expect(prefs()['horizon'], 30);

    // Six days on: still trusted.
    edit((p) => p
      ..['laidOn'] = DateTime.now()
          .subtract(const Duration(days: 6))
          .toIso8601String());
    scheduled.clear();
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, isEmpty);

    // A week: the plugin's list may hold alarms the system dropped, so
    // the window is laid again, whole.
    edit((p) => p
      ..['laidOn'] = DateTime.now()
          .subtract(const Duration(days: 7, minutes: 1))
          .toIso8601String());
    scheduled.clear();
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, hasLength(30));
    expect(pendingIds, hasLength(30));

    // A 90-day window, as earlier patches laid it: healthy by count,
    // laid yesterday, but at the old length.
    pendingIds
      ..clear()
      ..addAll([for (var i = 0; i < 90; i++) 1300 + i]);
    edit((p) => p..remove('horizon'));
    scheduled.clear();
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, hasLength(30));
    expect(pendingIds, hasLength(30), reason: 'the other sixty cancelled');
  });

  testWidgets('on iOS: thirty days, each with a picture file of its own',
      (t) async {
    IOSFlutterLocalNotificationsPlugin.registerWith();
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await t.runAsync(() => ReminderService.setStreakReminder(true));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    // iOS keeps sixty-four pending notifications, and moves an
    // attachment's file into its own store when it schedules it: a
    // window of thirty, each with its own copy of the picture.
    expect(scheduled, hasLength(30));
    final files = <String>{};
    for (final m in scheduled) {
      final ios = m['platformSpecifics']! as Map<Object?, Object?>;
      final attachments = ios['attachments']! as List<Object?>;
      expect(attachments, hasLength(1));
      final path = (attachments.single! as Map)['filePath']! as String;
      expect(File(path).existsSync(), isTrue);
      files.add(path);
    }
    expect(files, hasLength(30), reason: 'one file per notification');
  });
}

class _Dirs extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Dirs(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}
