import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ayah_reels/data/arena_engine.dart';
import 'package:ayah_reels/data/arena_service.dart';
import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/data/reminder_copy.dart';
import 'package:ayah_reels/data/reminder_service.dart';
import 'package:ayah_reels/data/rewards_service.dart';
import 'package:ayah_reels/data/settings_service.dart';
import 'package:ayah_reels/l10n/app_lang.dart';

/// The real scheduler, on Android, with the plugin's channel recorded
/// rather than answered by a phone: one notification a day and a second
/// on Fridays, at the time the user chose or in the morning most days
/// and at two on some, three quizzes to two reels, each with its
/// picture and its door — and, once there is something of the user's
/// own to share, two a week asking for it.
void main() {
  late Directory tmp;
  late List<Map<Object?, Object?>> scheduled;
  late List<int> cancelled;
  late List<int> pendingIds;
  // How many alarms the phone holds before it refuses one; none = all.
  int? alarmCeiling;

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('reminders');
    PathProviderPlatform.instance = _Dirs(tmp.path);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    scheduled = [];
    cancelled = [];
    pendingIds = [];
    alarmCeiling = null;
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
          final most = alarmCeiling;
          if (most != null && pendingIds.length >= most) {
            throw PlatformException(
                code: 'error',
                message: 'Maximum limit of concurrent alarms $most reached '
                    'for uid: u0a321, callingPackage: com.ayahreel.app');
          }
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

  int idOf(Map<Object?, Object?> m) => m['id']! as int;

  /// The day's own notifications, and Friday's seconds beside them.
  List<Map<Object?, Object?>> daily() =>
      [for (final m in scheduled) if (idOf(m) < 1400) m];
  List<Map<Object?, Object?>> fridays() =>
      [for (final m in scheduled) if (idOf(m) >= 1400) m];
  int fridaysAmong(List<Map<Object?, Object?>> days) =>
      days.where((m) => at(m).weekday == DateTime.friday).length;

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

  testWidgets('the nudge alone: one a day and two on Fridays, mornings '
      'mostly and two in the afternoon', (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));

    final days = daily();
    expect(days, hasLength(30));
    expect({
      for (final m in days) DateTime(at(m).year, at(m).month, at(m).day),
    }, hasLength(30), reason: "never two of the day's own on one day");
    expect(fridays(), hasLength(fridaysAmong(days)),
        reason: 'and a second every Friday');
    for (final m in days) {
      final slot = ReminderCopy.slotOn(at(m));
      expect((at(m).hour, at(m).minute), (slot.hour, slot.minute));
      expect(android(m)['channelId'], 'daily_reel');
      // Said for its part of the day, in one of its ways of saying it.
      final phrases = ReminderCopy
          .timePhrases[AppLang.en]![ReminderCopy.partOf(at(m).hour)]!;
      final said = '${m['title']} ${m['body']}';
      expect(phrases.where(said.contains), hasLength(1), reason: said);
    }
    expect({for (final m in days) at(m).hour}, {8, 14});
    expect(days.where((m) => at(m).hour == 8).length,
        greaterThan(days.length * 2 ~/ 3),
        reason: 'mornings, mostly');
    for (final m in fridays()) {
      expect(at(m).weekday, DateTime.friday);
      expect((at(m).hour, at(m).minute), (14, 0),
          reason: 'after the Friday prayer');
      // Nothing of the user's own to share yet: the day's greeting.
      expect(m['payload'], ReminderService.openReel);
      expect(ReminderCopy.jumuahPools[AppLang.en]!.map((l) => l.title),
          contains(m['title']));
    }
  });

  testWidgets('three quizzes to two reels, each with its picture and door',
      (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));

    final days = daily();
    final quizzes =
        days.where((m) => m['payload'] == ReminderService.openQuiz);
    final reels = days.where((m) => m['payload'] == ReminderService.openReel);
    expect(quizzes, hasLength(18));
    expect(reels, hasLength(12));
    for (final m in days) {
      expect(
          m['payload'],
          ReminderCopy.kindOn(at(m)) == NudgeKind.quiz
              ? ReminderService.openQuiz
              : ReminderService.openReel);
    }
    for (final m in scheduled) {
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

    expect(daily(), hasLength(30));
    final mornings = ReminderCopy.timePhrases[AppLang.en]![DayPart.morning]!;
    for (final m in daily()) {
      expect((at(m).hour, at(m).minute), (7, 30));
      expect(android(m)['channelId'], 'personal_reminder');
      final said = '${m['title']} ${m['body']}';
      expect(mornings.where(said.contains), hasLength(1), reason: said);
    }
    // Friday's second comes after the prayer, on the same channel.
    expect(fridays(), hasLength(fridaysAmong(daily())));
    for (final m in fridays()) {
      expect((at(m).hour, at(m).minute), (14, 0));
      expect(android(m)['channelId'], 'personal_reminder');
    }
  });

  testWidgets("my reminder off: the nudge takes the day back to the week's "
      'own times', (t) async {
    SettingsService.state.value = AppSettings.defaults.copyWith(
        streakReminderOn: true,
        personalReminderOn: true,
        personalHour: 8,
        personalMinute: 0);
    await onAndroid(t, () => ReminderService.cancelPersonalReminder());

    expect(daily(), hasLength(30));
    expect(daily().map((m) => at(m).hour).toSet(), {8, 14});
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
    expect(daily(), hasLength(30), reason: 'the on was laid whole');
    expect(pendingIds, isEmpty, reason: 'and the off, after it, took it up');
  });

  testWidgets('a phone that refuses alarms early keeps a window it can '
      're-arm at boot, and lays only that from then on', (t) async {
    // Infinix HOT 50i, 1.0.8: the plugin's boot receiver crashed the app
    // re-arming the 90-day window, AlarmManager refusing one alarm too
    // many. A phone that holds fewer than the thirty days' alarms.
    alarmCeiling = 20;
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));
    expect(t.takeException(), isNotNull, reason: 'the refusal is logged');

    // Two thirds of the 20 it took, at eight alarms a week: 11 days.
    expect(pendingIds.where((id) => id < 1400).toList()..sort(),
        [for (var i = 0; i < 11; i++) 1300 + i]);
    expect(pendingIds.length, lessThanOrEqualTo(13),
        reason: 'a third of the ceiling left free');
    expect(pendingIds.where((id) => id >= 1400),
        everyElement(lessThan(1400 + 11)));

    // The next launch keeps the short window as it is.
    scheduled.clear();
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, isEmpty);

    // The window runs down; the next one is laid short from the start,
    // and the phone refuses none of it.
    scheduled.clear();
    pendingIds.clear();
    await onAndroid(t, () => ReminderService.setStreakReminder(true));
    expect(t.takeException(), isNull);
    expect(daily(), hasLength(11));
    expect(scheduled, hasLength(11 + fridaysAmong(daily())));
  });

  testWidgets('both off: nothing is left queued', (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));
    expect(pendingIds.where((id) => id < 1400), hasLength(30));
    expect(pendingIds.where((id) => id >= 1400), isNotEmpty);
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
    expect(daily(), hasLength(30));
    expect(pendingIds.where((id) => id < 1400), hasLength(30));

    scheduled.clear();
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(scheduled, isEmpty, reason: 'already in these words');
  });

  testWidgets('on Android a window is laid again once it is a week old, '
      'and the 90 days older builds laid come back as 30', (t) async {
    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(daily(), hasLength(30));

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
    expect(daily(), hasLength(30));
    expect(pendingIds.where((id) => id < 1400), hasLength(30));

    // A 90-day window, as builds before 2026-10-13 laid it: healthy by
    // count, laid yesterday, but at the old length.
    pendingIds
      ..clear()
      ..addAll([for (var i = 0; i < 90; i++) 1300 + i]);
    edit((p) => p..remove('horizon'));
    scheduled.clear();
    await onAndroid(t, ReminderService.scheduleIfPermitted);
    expect(daily(), hasLength(30));
    expect(pendingIds.where((id) => id < 1400), hasLength(30),
        reason: 'the other sixty cancelled');
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
    expect(daily(), hasLength(30));
    expect(fridays(), hasLength(fridaysAmong(daily())));
    final files = <String>{};
    for (final m in scheduled) {
      final ios = m['platformSpecifics']! as Map<Object?, Object?>;
      final attachments = ios['attachments']! as List<Object?>;
      expect(attachments, hasLength(1));
      final path = (attachments.single! as Map)['filePath']! as String;
      expect(File(path).existsSync(), isTrue);
      files.add(path);
    }
    expect(files, hasLength(scheduled.length),
        reason: 'one file per notification');
  });

  testWidgets('something of their own: Tuesdays and Friday seconds ask for '
      'it, with its own picture and its own door', (t) async {
    // A reel in the library and a round played.
    final reels = Directory('${tmp.path}/reels')..createSync(recursive: true);
    File('${reels.path}/reel_r1.mp4').writeAsBytesSync(const [0]);
    File('${reels.path}/library.json').writeAsStringSync(jsonEncode([
      SavedReel(
        id: 'r1',
        fileName: 'reel_r1.mp4',
        reciterName: 'Mishary Alafasy',
        surahName: 'Al-Mulk',
        startAyah: 1,
        endAyah: 5,
        gradientArgb: const [0xFF1B2433, 0xFF0B0F17],
        createdAt: DateTime(2026, 6, 1),
      ).toJson(),
    ]));
    const setup = ArenaSetup(
      scope: ArenaScope.juz(30),
      games: {ArenaGame.missingWord},
      askMeanings: false,
    );
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    RewardsService.resetForTest();
    RewardsService.fileOverride = File('${tmp.path}/rewards.json');
    addTearDown(() {
      ArenaService.fileOverride = null;
      ArenaService.reset();
      RewardsService.fileOverride = null;
      RewardsService.resetForTest();
    });
    await t.runAsync(() => ArenaService.record(
          ArenaResult(setup: setup, seed: 3, answers: [
            for (var i = 0; i < 10; i++)
              ArenaAnswer(
                  chosen: i, correct: i < 8, points: i < 8 ? 120 : 0),
          ]),
          mode: ArenaMode.solo,
        ));
    final round = ArenaService.state.value.history.single;

    SettingsService.state.value = AppSettings.defaults
        .copyWith(streakReminderOn: true, personalReminderOn: false);
    await onAndroid(t, () => ReminderService.setStreakReminder(true));

    final shares = [
      for (final m in scheduled)
        if (m['payload'] == ReminderService.openVerses ||
            '${m['payload']}'.startsWith(ReminderService.openRoundPrefix))
          m,
    ];
    // Every Tuesday and every Friday's second, and nothing else.
    for (final m in shares) {
      final friday = at(m).weekday == DateTime.friday;
      expect(friday || at(m).weekday == DateTime.tuesday, isTrue);
      expect(idOf(m) >= 1400, friday);
    }
    final tuesdays = daily().where((m) => at(m).weekday == DateTime.tuesday);
    expect(shares, hasLength(tuesdays.length + fridays().length));
    expect(daily(), hasLength(30), reason: 'a share takes a slot, never adds one');
    // Both kinds, taking turns, each with its door and its picture.
    final verses = shares.where((m) => m['payload'] == ReminderService.openVerses);
    final rounds = shares.where((m) => m['payload'] != ReminderService.openVerses);
    expect(verses, isNotEmpty);
    expect(rounds, isNotEmpty);
    for (final m in rounds) {
      expect(m['payload'], '${ReminderService.openRoundPrefix}${round.id}');
      expect('${m['title']} ${m['body']}', contains('960'),
          reason: "the best round's score, said");
    }
    for (final m in shares) {
      final style = android(m)['styleInformation']! as Map<Object?, Object?>;
      final picture = style['bigPicture']! as String;
      expect(File(picture).existsSync(), isTrue, reason: picture);
      expect(picture, contains('/own/'));
    }
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
