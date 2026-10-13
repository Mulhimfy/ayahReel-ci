import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/arena_service.dart';
import 'data/export_budget.dart';
import 'data/ffmpeg_setup.dart';
import 'data/home_widget_service.dart';
import 'data/quran_verses.dart';
import 'data/reminder_service.dart';
import 'data/rewards_service.dart';
import 'data/scene_catalog.dart';
import 'data/settings_service.dart';
import 'l10n/l10n.dart';
import 'render/on_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/cinematic_hero.dart';

/// The app's one navigator, for the places that open a screen without
/// a widget of their own to open it from: a tap on the home-screen
/// widget arrives over a channel, not from a button.
final appNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything draws a picture off-screen: a frame drawn since
  // the launch, or since the app came back, is what says the surface
  // those pictures borrow is there.
  OnScreen.watch();
  // Before anything can run an encode: FFmpeg's plugin starts out
  // posting every log line and progress report to the main thread.
  unawaited(configureFfmpeg());
  // And before the first export: whether one died with the app last
  // time decides how small this phone's exports are planned.
  unawaited(PhoneBudget.load().then((_) {
    // A phone short of memory keeps fewer decoded pictures about. The
    // cache holds a hundred megabytes by default, and a scenery still
    // decoded is eight of them: a few sceneries looked at in the picker
    // were memory a save on a 3 GB phone then went without.
    if (PhoneBudget.now != ExportBudget.roomy) {
      PaintingBinding.instance.imageCache.maximumSizeBytes = 48 << 20;
    }
  }));
  // Edge to edge, and asked for rather than assumed: from Android 15
  // the system draws behind the bars whatever the app says, and the
  // window colour setters that used to arrange it are dead calls.
  // Naming a statusBarColor is one of them — Play reads it as an app
  // that still expects the old behaviour ("edge-to-edge may not
  // display for all users"), and on the phone it does nothing at all.
  // Every screen already sits inside a SafeArea, so the bars are
  // transparent and the content stays clear of them.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const AyahReelsApp());
}

class AyahReelsApp extends StatelessWidget {
  const AyahReelsApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The MaterialApp rebuilds when the *language* changes, and only
    // then; the locale change flows down through Localizations, so
    // every screen re-reads its strings and the whole tree mirrors to
    // RTL in place — navigation state and playback survive the switch.
    //
    // Deliberately not a ValueListenableBuilder over the whole of
    // [AppSettings]: every setting lives in one notifier, so a nudge
    // dot going out or a verse edition changing was rebuilding the
    // entire application from the root — and somebody flicking through
    // the translations half a dozen times felt every one of those.
    // Nothing below here reads any other setting through this builder.
    return _WhenLanguageChanges(
      builder: (context, lang) => MaterialApp(
        navigatorKey: appNavigatorKey,
        title: 'AyahReel',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(lang: lang),
        locale: Locale(lang.code),
        supportedLocales: [
          for (final l in AppLang.values) Locale(l.code),
        ],
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

/// Rebuilds its child when the app's language changes, and at no other
/// time.
///
/// [SettingsService.state] is one notifier for every setting there is,
/// which is right for a settings file and wrong for the root of an
/// application: a listener there is a listener to everything. This
/// narrows it to the one field the root actually reads.
class _WhenLanguageChanges extends StatefulWidget {
  final Widget Function(BuildContext, AppLang) builder;
  const _WhenLanguageChanges({required this.builder});

  @override
  State<_WhenLanguageChanges> createState() => _WhenLanguageChangesState();
}

class _WhenLanguageChangesState extends State<_WhenLanguageChanges> {
  late AppLang _lang = SettingsService.state.value.lang;

  @override
  void initState() {
    super.initState();
    SettingsService.state.addListener(_onSettings);
  }

  @override
  void dispose() {
    SettingsService.state.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    final lang = SettingsService.state.value.lang;
    if (lang == _lang || !mounted) return;
    setState(() => _lang = lang);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _lang);
}

/// Decides which screen the app opens on, which needs settings off disk
/// first. That read is a few milliseconds — the app shows its own
/// background rather than a white flash while it happens.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

/// TEMPORARY (testing): forces onboarding on every launch, whatever the
/// stored flag says. Set back to false before shipping.
const _forceOnboarding = false;

class _RootState extends State<_Root> {
  /// Null until settings have loaded.
  bool? _onboarded;

  StreamSubscription<QuranVerse>? _widgetTaps;
  StreamSubscription<String>? _notificationTaps;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _widgetTaps?.cancel();
    _notificationTaps?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await SettingsService.init();
    if (mounted) {
      setState(() => _onboarded = _forceOnboarding
          ? false
          : SettingsService.state.value.onboardingDone);
    }
    // Streak/points and the reminder re-arm can finish after the first
    // frame; neither gates what the user sees, and neither prompts.
    RewardsService.init();
    // Laying a reminder window down is a platform call per day, on the
    // main thread — the thread the first frame also needs. Started
    // here, it held the launch screen for as long as it ran; a few
    // seconds later costs nothing, the window is weeks deep either way.
    unawaited(Future<void>.delayed(
        const Duration(seconds: 3), ReminderService.scheduleIfPermitted));
    // The scenery catalog, read once for the whole process. It is a
    // lazy singleton and the reel flow used to be the only thing that
    // warmed it, so a card made before any reel had a cold one:
    // [CardCompose.sceneFor] is synchronous and came back with nothing,
    // and a template naming a scenery family opened on bare paper.
    // Here rather than in the Cards tab because it is the app's, not a
    // screen's — and because a tab is entered often and this reads a
    // 376-entry file.
    unawaited(SceneCatalog.load());
    // The opening frame may fetch its picture only in the running app.
    CinematicHero.fetch = SceneCatalog.download;
    // A tap on the home-screen widget: the one that launched the app,
    // if that is what did, and any that arrive while it is open.
    HomeWidgetService.init();
    _widgetTaps = HomeWidgetService.taps.listen(_goHome);
    // The arena's lamps and bests, so the door at the top of the
    // shell shows the right count on its first frame.
    unawaited(ArenaService.init());
    final link = await HomeWidgetService.launchLink();
    // A challenge link opens the arena once the shell is up; a widget
    // link brings the home tab forward.
    ArenaService.takeLink(link);
    final launch = HomeWidgetService.parseLink(link);
    if (launch != null) _goHome(launch);
    // A tap on the day's notification: the one that launched the app,
    // if that is what did, and any that arrive while it is open.
    _notificationTaps = ReminderService.taps.listen(_openFromNotification);
    final tap = await ReminderService.launchTap();
    if (tap != null) _openFromNotification(tap);
  }

  /// Hands a tapped notification to the shell, which opens the quiz
  /// lobby or a new reel; whatever was open is unwound first, as for
  /// the widget. Mid-onboarding there is nowhere to go yet.
  void _openFromNotification(String open) {
    if (_onboarded != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = appNavigatorKey.currentState;
      if (!mounted || nav == null) return;
      nav.popUntil((r) => r.isFirst);
      HomeShell.notificationOpens.value = open;
    });
  }

  /// A tap on the widget brings the app to its home tab — where the
  /// same verse is on the card — and no further. The card's own tap
  /// is the door to the reel; the widget is a door to the app. Waits
  /// a frame so the shell exists first, and unwinds whatever was open
  /// so the home tab is what is actually on screen.
  void _goHome(QuranVerse _) {
    // Mid-onboarding there is nowhere to go yet; the widget can be
    // tapped again once the app is set up.
    if (_onboarded != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = appNavigatorKey.currentState;
      if (!mounted || nav == null) return;
      nav.popUntil((r) => r.isFirst);
      HomeShell.homeRequests.value++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = _onboarded;
    if (onboarded == null) {
      return const ColoredBox(color: AppColors.bg, child: SizedBox.expand());
    }
    if (onboarded) return const HomeShell();
    return OnboardingScreen(
      // The reminder time chosen during onboarding is stored but not
      // armed: ReminderService asks for the OS permission at the user's
      // first proud moment instead, then arms whatever was chosen here.
      onDone: () => setState(() => _onboarded = true),
    );
  }
}
