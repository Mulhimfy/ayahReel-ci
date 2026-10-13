import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_lang.dart';
import 'verse_numbering.dart';
import 'verse_translation.dart';
import 'whole_file.dart';

/// Everything the Settings tab controls, in one immutable snapshot.
class AppSettings {
  /// The gentle streak nudge that offerAfterExport sets up.
  final bool streakReminderOn;

  /// The user's own fixed-time reminder — independent of the streak
  /// nudge, armed only when they switch it on in Settings.
  final bool personalReminderOn;
  final int personalHour; // 0–23
  final int personalMinute; // 0–59

  /// Adds a "Send to WhatsApp" action next to the normal share, which
  /// hands the reel straight to WhatsApp instead of the share sheet.
  /// On by default — WhatsApp is where these reels go — and only off if
  /// the user turns it off. Android only; the toggle is hidden
  /// elsewhere. Costs nothing when WhatsApp is absent: the button falls
  /// back to the share sheet.
  final bool whatsappDirectShare;

  /// Adds a "Make an Instagram Reel" action next to the normal share,
  /// which opens Instagram's reel composer with the finished reel
  /// already loaded — the editor a reel is published from, not Stories.
  /// On by default, for the same reason [whatsappDirectShare] is.
  /// The button only appears where the handoff can actually work; see
  /// InstagramShare.supported, which wants a Meta App ID compiled in.
  final bool instagramDirectShare;

  /// False until the user has been through onboarding once. Kept here
  /// rather than in its own file so a single read at launch decides
  /// which screen the app opens on.
  final bool onboardingDone;

  /// The language the app's own chrome is shown in. Arabic and Urdu
  /// mirror the whole tree to RTL; see [AppLang].
  final AppLang lang;

  /// The edition printed under each verse. Independent of [lang] on
  /// purpose — the person reading the buttons is often not the person
  /// the reel is being made for.
  final VerseTranslation translation;

  /// Kept so the many typographic call sites that only ever meant
  /// "is this Arabic" keep reading the way they did.
  bool get arabic => lang == AppLang.ar;

  /// False until the scenery screen has walked the user through its
  /// controls once. Lives here rather than in its own file for the
  /// same reason [onboardingDone] does: one read at launch.
  final bool sceneryTourDone;

  /// The scenery tab the picker opens on. Empty means the user has
  /// never chosen one and the picker opens on its own first tab. Kept
  /// here rather than in creation state because it outlives a reel:
  /// somebody who films skies wants skies again tomorrow.
  final String sceneTab;

  /// What the home screen calls the user — "Good evening, Yusuf".
  /// Empty means they have not given one, and the greeting stays bare.
  final String name;

  /// When the home-screen widget nudge was last dismissed, as epoch
  /// milliseconds. Zero means never, which is what makes it show the
  /// first time. It comes back two days after each dismissal until the
  /// widget is actually on the home screen — the app can see that —
  /// and then not at all.
  final int widgetNudgeDismissedAt;

  /// The two rows a new install is pointed at: a dot sits on the
  /// Settings tab, and on each of these rows, until the row has been
  /// opened once. Each is its own flag so the dot on one row does not
  /// go out because the other was tapped.
  final bool rateNudgeSeen;
  final bool widgetNudgeSeen;

  /// Whether anything is still left to point at — what decides the dot
  /// on the tab.
  bool get nudgesPending => !rateNudgeSeen || !widgetNudgeSeen;

  /// False until the Cards tab has been opened once.
  ///
  /// A tab that appears in an update is a tab nobody is looking for,
  /// so the glyph carries a dot until it has been visited — the same
  /// quiet nudge the two Settings rows use, and it goes out for good
  /// the first time somebody looks.
  final bool cardsSeen;

  /// False until Tanafus has been opened once. The roundel on the shell
  /// carries a dot until then — the same quiet nudge the Cards tab and
  /// the two Settings rows use.
  final bool arenaSeen;

  /// The look and the shape a new card starts on, by the name of the
  /// [CardTemplate] and the [CardFormat]. Empty means nobody has
  /// chosen, and the composer opens on its own defaults.
  ///
  /// Remembered for the same reason [sceneTab] is: these outlive a
  /// card. Somebody who makes ivory squares makes another one
  /// tomorrow, and being asked again every time is not a choice, it
  /// is an obstacle.
  final String cardTemplate;
  final String cardFormat;

  /// The last verse the user opened in the card finder — the surah,
  /// and the ayah inside it. 0 means nobody has opened one yet and the
  /// finder opens on Al-Fatiha.
  ///
  /// The same argument as [cardTemplate]: somebody working through a
  /// surah comes back to it, and a reader that reopens on verse one of
  /// chapter one every time makes them find their place again by hand.
  /// It is where they *were*, not a bookmark they set, so nothing in
  /// the app says it is being kept and nothing asks.
  final int lastSurah;
  final int lastAyah;

  /// Whether Home shows its Moments row and its Reel series section.
  /// On unless turned off in Settings.
  final bool showMoments;
  final bool showSeries;
  /// Whether a reel's verse card carries the verse's number, and how —
  /// see [VerseNumbering]. Off until the user turns it on.
  final VerseNumbering verseNumbering;

  /// Whether a reel's verse card leaves the translation out, and
  /// carries the Arabic alone: "None" in the translation picker. The
  /// edition stays chosen underneath, so picking one again brings back
  /// the one the user had.
  final bool verseTranslationOff;

  /// Whether reels are encoded at the higher bitrate — sharper moving
  /// scenery and smoother skies, at about twice the file size. Off
  /// until the user turns it on: a reel that doubled in size after an
  /// update would fill somebody's phone without their asking.
  final bool highQualityVideo;

  const AppSettings({
    required this.streakReminderOn,
    required this.personalReminderOn,
    required this.personalHour,
    required this.personalMinute,
    required this.whatsappDirectShare,
    required this.instagramDirectShare,
    required this.onboardingDone,
    required this.lang,
    required this.translation,
    required this.name,
    required this.sceneryTourDone,
    required this.sceneTab,
    this.widgetNudgeDismissedAt = 0,
    this.rateNudgeSeen = false,
    this.widgetNudgeSeen = false,
    this.cardTemplate = '',
    this.cardFormat = '',
    this.lastSurah = 0,
    this.lastAyah = 0,
    this.cardsSeen = false,
    this.arenaSeen = false,
    this.showMoments = true,
    this.showSeries = true,
    this.verseNumbering = VerseNumbering.off,
    this.verseTranslationOff = false,
    this.highQualityVideo = false,
  });

  static const defaults = AppSettings(
    streakReminderOn: true,
    personalReminderOn: false,
    personalHour: 20,
    personalMinute: 0,
    whatsappDirectShare: true,
    instagramDirectShare: true,
    onboardingDone: false,
    lang: AppLang.en,
    translation: VerseTranslation.english,
    name: '',
    sceneryTourDone: false,
    sceneTab: '',
  );

  AppSettings copyWith({
    bool? streakReminderOn,
    bool? personalReminderOn,
    int? personalHour,
    int? personalMinute,
    bool? whatsappDirectShare,
    bool? instagramDirectShare,
    bool? onboardingDone,
    AppLang? lang,
    VerseTranslation? translation,
    String? name,
    bool? sceneryTourDone,
    String? sceneTab,
    int? widgetNudgeDismissedAt,
    bool? rateNudgeSeen,
    bool? widgetNudgeSeen,
    String? cardTemplate,
    String? cardFormat,
    int? lastSurah,
    int? lastAyah,
    bool? cardsSeen,
    bool? arenaSeen,
    bool? showMoments,
    bool? showSeries,
    VerseNumbering? verseNumbering,
    bool? verseTranslationOff,
    bool? highQualityVideo,
  }) {
    return AppSettings(
      streakReminderOn: streakReminderOn ?? this.streakReminderOn,
      personalReminderOn: personalReminderOn ?? this.personalReminderOn,
      personalHour: personalHour ?? this.personalHour,
      personalMinute: personalMinute ?? this.personalMinute,
      whatsappDirectShare: whatsappDirectShare ?? this.whatsappDirectShare,
      instagramDirectShare:
          instagramDirectShare ?? this.instagramDirectShare,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      lang: lang ?? this.lang,
      translation: translation ?? this.translation,
      name: name ?? this.name,
      sceneryTourDone: sceneryTourDone ?? this.sceneryTourDone,
      sceneTab: sceneTab ?? this.sceneTab,
      widgetNudgeDismissedAt:
          widgetNudgeDismissedAt ?? this.widgetNudgeDismissedAt,
      rateNudgeSeen: rateNudgeSeen ?? this.rateNudgeSeen,
      widgetNudgeSeen: widgetNudgeSeen ?? this.widgetNudgeSeen,
      cardTemplate: cardTemplate ?? this.cardTemplate,
      cardFormat: cardFormat ?? this.cardFormat,
      lastSurah: lastSurah ?? this.lastSurah,
      lastAyah: lastAyah ?? this.lastAyah,
      cardsSeen: cardsSeen ?? this.cardsSeen,
      arenaSeen: arenaSeen ?? this.arenaSeen,
      showMoments: showMoments ?? this.showMoments,
      showSeries: showSeries ?? this.showSeries,
      verseNumbering: verseNumbering ?? this.verseNumbering,
      verseTranslationOff: verseTranslationOff ?? this.verseTranslationOff,
      highQualityVideo: highQualityVideo ?? this.highQualityVideo,
    );
  }

  Map<String, dynamic> toJson() => {
        'streakReminderOn': streakReminderOn,
        'personalReminderOn': personalReminderOn,
        'personalHour': personalHour,
        'personalMinute': personalMinute,
        'whatsappDirectShare': whatsappDirectShare,
        'instagramDirectShare': instagramDirectShare,
        'onboardingDone': onboardingDone,
        'lang': lang.code,
        'translation': translation.code,
        'name': name,
        'sceneryTourDone': sceneryTourDone,
        'sceneTab': sceneTab,
        'widgetNudgeDismissedAt': widgetNudgeDismissedAt,
        'rateNudgeSeen': rateNudgeSeen,
        'widgetNudgeSeen': widgetNudgeSeen,
        'cardTemplate': cardTemplate,
        'cardFormat': cardFormat,
        'lastSurah': lastSurah,
        'lastAyah': lastAyah,
        'cardsSeen': cardsSeen,
        'arenaSeen': arenaSeen,
        'showMoments': showMoments,
        'showSeries': showSeries,
        'verseNumbering': verseNumbering.code,
        'verseTranslationOff': verseTranslationOff,
        'highQualityVideo': highQualityVideo,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        streakReminderOn: j['streakReminderOn'] as bool? ?? true,
        personalReminderOn: j['personalReminderOn'] as bool? ?? false,
        personalHour: j['personalHour'] as int? ?? 20,
        personalMinute: j['personalMinute'] as int? ?? 0,
        // Absent key = never touched it = on. An explicit false persists.
        whatsappDirectShare: j['whatsappDirectShare'] as bool? ?? true,
        instagramDirectShare: j['instagramDirectShare'] as bool? ?? true,
        // Absent on an install that predates onboarding: those users
        // have already seen the app, so don't send them through it.
        onboardingDone: j['onboardingDone'] as bool? ?? true,
        // 'lang' replaced the old 'arabic' boolean. A settings file
        // written before that has only the boolean, and somebody who
        // had chosen Arabic must not be dropped back into English by
        // an update — so the boolean is still read when the code is
        // absent, and only then.
        lang: j.containsKey('lang')
            ? AppLang.fromCode(j['lang'] as String?)
            : ((j['arabic'] as bool? ?? false) ? AppLang.ar : AppLang.en),
        // Absent on every install that predates the picker, and those
        // users have been reading Saheeh International all along.
        translation: VerseTranslation.fromCode(j['translation'] as String?),
        name: j['name'] as String? ?? '',
        // Absent on an install that predates the tour: those users know
        // this screen already, so don't stop them with coach marks.
        sceneryTourDone: j['sceneryTourDone'] as bool? ?? true,
        sceneTab: j['sceneTab'] as String? ?? '',
        widgetNudgeDismissedAt: j['widgetNudgeDismissedAt'] as int? ?? 0,
        // Absent = not yet seen, on purpose, unlike the tour flags: a
        // dot on two rows is a nudge and not a wall, and an install
        // that predates it has as much reason to rate the app and add
        // the widget as a new one.
        rateNudgeSeen: j['rateNudgeSeen'] as bool? ?? false,
        widgetNudgeSeen: j['widgetNudgeSeen'] as bool? ?? false,
        cardTemplate: j['cardTemplate'] as String? ?? '',
        cardFormat: j['cardFormat'] as String? ?? '',
        lastSurah: j['lastSurah'] as int? ?? 0,
        lastAyah: j['lastAyah'] as int? ?? 0,
        // Absent on every install that predates the tab, which is
        // exactly who the dot is for.
        cardsSeen: j['cardsSeen'] as bool? ?? false,
        arenaSeen: j['arenaSeen'] as bool? ?? false,
        showMoments: j['showMoments'] as bool? ?? true,
        showSeries: j['showSeries'] as bool? ?? true,
        // Absent on every install that predates it, and those reels
        // never carried numbers.
        verseNumbering:
            VerseNumbering.fromCode(j['verseNumbering'] as String?),
        // Absent on every install that predates "None": their reels
        // have always carried a translation.
        verseTranslationOff: j['verseTranslationOff'] as bool? ?? false,
        highQualityVideo: j['highQualityVideo'] as bool? ?? false,
      );
}

/// JSON-file settings store, same pattern as rewards/reminder prefs:
/// no plugin, no schema migration, survives reinstall-free updates.
abstract final class SettingsService {
  static final ValueNotifier<AppSettings> state =
      ValueNotifier(AppSettings.defaults);

  static Future<void>? _loading;

  /// Reads the file once. Every caller waits for that one read: a
  /// second caller that went ahead while it was still running got the
  /// defaults, and anything it saved from them overwrote the user's.
  static Future<void> init() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      state.value = AppSettings.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {/* defaults are fine */}
  }

  static Future<void> update(AppSettings next) async {
    state.value = next;
    try {
      await writeWhole(await _file(), jsonEncode(next.toJson()));
    } catch (_) {/* settings are best-effort */}
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/settings.json');
}
