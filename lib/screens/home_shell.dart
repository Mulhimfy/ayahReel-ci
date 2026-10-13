import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/arena_service.dart';
import '../data/export_budget.dart';
import '../data/feedback_service.dart';
import '../data/reminder_service.dart';
import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_motion.dart';
import '../widgets/feedback_sheet.dart';
import '../widgets/illumination.dart';
import '../widgets/invite_sheet.dart';
import '../widgets/living_sky.dart';
import '../widgets/nudge_dot.dart';
import '../widgets/tanafus_button.dart';
import '../widgets/update_dialog.dart';
import 'arena_screen.dart';
import 'cards_screen.dart';
import 'home_screen.dart';
import 'my_reels_screen.dart';
import 'reciter_screen.dart';
import 'settings_screen.dart';

/// The app's four destinations: Home, Cards, My Reels, Settings.
/// Creation is deliberately NOT a tab — it's a focused full-screen
/// wizard pushed on top, so nobody tabs away from a half-made reel.
///
/// One sky is painted here, once, behind all four. The tabs are
/// transparent and float on it, so switching tabs is moving around
/// inside one place rather than cutting between four screens — and
/// the switch itself pushes the sky sideways, so the room turns with
/// you.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Asks the shell, wherever it is, to show its home tab: what a tap
  /// on the home-screen widget does. Bumped rather than set, so two
  /// taps in a row both land.
  static final ValueNotifier<int> homeRequests = ValueNotifier(0);

  /// What a tapped notification asked the shell to open —
  /// [ReminderService.openQuiz] or [ReminderService.openReel] — until
  /// the shell has opened it. A value rather than a bump: the tap that
  /// launched the app lands before there is a shell to hear it.
  static final ValueNotifier<String?> notificationOpens = ValueNotifier(null);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// Shared by the sky and every scrollable under it. Owned here so
  /// there is one clock for the whole shell, whichever tab is up.
  final _motion = AmbientMotion();

  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: 1,
  );

  /// Which way the last switch went, so the incoming tab enters from
  /// the side it came from.
  double _from = 0;

  /// Tabs that have been opened at least once. An IndexedStack builds
  /// every child up front, so My Reels was reading the library and
  /// pulling a poster frame out of every reel with FFmpeg, and Settings
  /// was asking the OS about notifications, before Home had drawn its
  /// first frame. A tab is built the first time it is looked at and
  /// kept alive from then on — its scroll position and loaded reels
  /// survive exactly as before.
  ///
  /// Cards is the same bargain and the biggest one: its library reads
  /// off disk and its composer decodes a photograph, and a user who
  /// never opens the tab pays for none of it.
  final Set<int> _visited = {0};

  @override
  void initState() {
    super.initState();
    // After the first frame: the app the user opened is on screen
    // before it asks them for anything, and a launch with no network
    // never waits on this at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptUpdate(context);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tellLostExport());
    HomeShell.homeRequests.addListener(_goHome);
    // A challenge arriving through a link opens the arena on its
    // own; the lobby takes the code from there.
    ArenaService.pendingCode.addListener(_onChallenge);
    // A link the app was *launched* with may have been taken before
    // this shell existed to hear about it.
    _onChallenge();
    // So may a notification's tap.
    HomeShell.notificationOpens.addListener(_onNotification);
    _onNotification();
    unawaited(ArenaService.init());
  }

  void _goHome() {
    if (mounted) _select(0);
  }

  /// Says what happened when the app closed in the middle of a save
  /// last time, and offers to send it to us.
  ///
  /// On a phone short of memory that is the system killing the app: no
  /// error, no message, the app is just gone, and it used to open again
  /// as if nothing had happened — leaving someone who never finished a
  /// reel to write "it refuses to download", if they wrote at all. Once
  /// per lost save; the next saves on this phone are already planned
  /// smaller (see [PhoneBudget]).
  Future<void> _tellLostExport() async {
    await PhoneBudget.load();
    if (!mounted || !PhoneBudget.takeLostExport()) return;
    FeedbackService.noteExportTrouble(
        'lost',
        'the app closed while a reel was saving'
        '${PhoneBudget.lostDetail}');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(L10n.current.exportLostNotice),
      duration: const Duration(seconds: 12),
      action: SnackBarAction(
        label: L10n.current.reportProblem,
        onPressed: () {
          if (mounted) {
            showFeedbackSheet(context, source: FeedbackSource.exportTrouble);
          }
        },
      ),
    ));
  }

  /// The day's notification, tapped: a quiz opens the quiz lobby, a
  /// reel the first step of a new one — straight there, which is the
  /// whole of what the notification asked for.
  void _onNotification() {
    final open = HomeShell.notificationOpens.value;
    if (open == null || !mounted) return;
    HomeShell.notificationOpens.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (open == ReminderService.openQuiz) {
        _openArena();
      } else if (open == ReminderService.openReel) {
        creationState.startNewReel();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReciterScreen()),
        );
      }
    });
  }

  void _onChallenge() {
    if (ArenaService.pendingCode.value == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // An open lobby may have taken the code in the meantime; it shows
      // it itself, and a second lobby would only cover it.
      if (mounted && ArenaService.pendingCode.value != null) _openArena();
    });
  }

  /// [openArena] keeps a second lobby from opening over the first.
  Future<void> _openArena() => openArena(context);

  @override
  void dispose() {
    ArenaService.pendingCode.removeListener(_onChallenge);
    HomeShell.notificationOpens.removeListener(_onNotification);
    HomeShell.homeRequests.removeListener(_goHome);
    _arrive.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    _from = (i - _index).sign.toDouble();
    // The sky is told about the switch in the same units it hears
    // about a scroll, so a tab change reads as the same kind of
    // movement as a flick — the room turning, not a screen replacing
    // another.
    _motion.pushLateral(_from * 120);
    setState(() {
      _index = i;
      _visited.add(i);
    });
    _arrive
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return AmbientScope(
      motion: _motion,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Content scrolls underneath the translucent bar — each tab
        // leaves enough bottom padding to clear it.
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: IgnorePointer(child: LivingSky(motion: _motion)),
              ),
            ),
            Positioned.fill(child: _arriving(_tabs())),
            // The door to the arena, fixed at the top corner of every
            // tab — the end corner, so it reads as a mark and not as a
            // title, and the home header lays its first line out to it.
            PositionedDirectional(
              top: 0,
              end: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(top: 8, end: 16),
                  child: TanafusButton(onTap: _openArena),
                ),
              ),
            ),
          ],
        ),
        // Present on every tab: the invitation should never be somewhere
        // the user has to go looking for it. The arena keeps its door in
        // the top corner. Scaffold floats this clear of the nav bar.
        floatingActionButton: const InviteFab(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _LampBar(index: _index, onSelect: _select),
      ),
    );
  }

  /// Only the tab you are looking at gets to animate. The others stay
  /// alive in the stack — their scroll positions and their loaded
  /// reels are exactly where they were left — but every shimmer, glow
  /// and turning seal on them is parked until you come back, which is
  /// the difference between four tabs and four tabs' worth of tickers
  /// running at once.
  Widget _tabs() {
    Widget tab(int i, Widget child) => _visited.contains(i)
        ? TickerMode(enabled: _index == i, child: child)
        : const SizedBox.shrink();
    return IndexedStack(
      index: _index,
      children: [
        tab(0, HomeScreen(onSeeAllReels: () => _select(2))),
        tab(1, const CardsScreen()),
        tab(2, const MyReelsScreen()),
        tab(3, const SettingsScreen()),
      ],
    );
  }

  /// The incoming tab rises out of the sky rather than appearing on
  /// it: a short lift from the side it came from, a fade, and a hair
  /// of scale. Half a beat, no more — this is a tab, not a journey.
  Widget _arriving(Widget child) {
    return AnimatedBuilder(
      animation: _arrive,
      builder: (context, c) {
        final v = Curves.easeOutCubic.transform(_arrive.value);
        final sign =
            Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
        return Opacity(
          opacity: (0.15 + 0.85 * v).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(sign * _from * 26 * (1 - v), 0),
            child: Transform.scale(scale: 0.985 + 0.015 * v, child: c),
          ),
        );
      },
      child: child,
    );
  }
}

// ---------------------------------------------------------------------
// The bar
// ---------------------------------------------------------------------

/// Four glyphs standing under a lamp.
///
/// The bar itself is glass with a single gold hairline across the top,
/// and the hairline is brightest directly above whichever destination
/// you are in. The lamp — a pool of warm light rising off the floor
/// and a tapered gold rule under the glyph — slides between them on a
/// spring, so the light travels to the new tab instead of being
/// switched off in one place and on in another.
class _LampBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _LampBar({required this.index, required this.onSelect});

  @override
  State<_LampBar> createState() => _LampBarState();
}

class _LampBarState extends State<_LampBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );
  late double _from = widget.index.toDouble();
  late double _to = widget.index.toDouble();

  @override
  void didUpdateWidget(covariant _LampBar old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    // Resume from wherever the light actually is, not from the last
    // destination: tapping three tabs quickly must not make the lamp
    // jump backwards to restart its travel.
    _from = _position;
    _to = widget.index.toDouble();
    _c
      ..value = 0
      ..forward();
  }

  double get _position {
    final v = Curves.easeOutCubic.transform(_c.value);
    return _from + (_to - _from) * v;
  }

  /// A touch of overshoot on the settle, and none on the way out — the
  /// lamp swings under the new glyph and comes back to rest.
  double get _overshoot {
    final v = _c.value;
    if (v >= 1) return 0;
    return math.sin(v * math.pi) * (_to - _from) * 0.055;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final items = <(NavGlyph, String)>[
      (NavGlyph.mihrab, l.navHome),
      (NavGlyph.card, l.navCards),
      (NavGlyph.reel, l.navMyReels),
      (NavGlyph.seal, l.navSettings),
    ];
    return ClipRect(
      child: BackdropFilter(
        // Kept low on purpose: a backdrop blur re-reads and
        // re-filters everything behind it every frame, and what is
        // behind this one is a sky that never stops moving. The
        // cost scales with the radius.
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.bg.withValues(alpha: 0.58),
                AppColors.bg.withValues(alpha: 0.90),
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 66,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) => CustomPaint(
                  painter: _LampPainter(
                    slot: _position + _overshoot,
                    slots: items.length,
                    rtl: Directionality.of(context) == TextDirection.rtl,
                  ),
                  child: child,
                ),
                // The dot on the seal: lit until both rows a new
                // install is pointed at have been opened. Listened to
                // here so it goes out the moment the second one is.
                child: ValueListenableBuilder<AppSettings>(
                  valueListenable: SettingsService.state,
                  builder: (context, s, _) => Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavStop(
                            glyph: items[i].$1,
                            label: items[i].$2,
                            selected: i == widget.index,
                            dot: (i == items.length - 1 && s.nudgesPending)
                                || (i == 1 && !s.cardsSeen),
                            onTap: () => widget.onSelect(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LampPainter extends CustomPainter {
  final double slot;
  final int slots;
  final bool rtl;
  const _LampPainter(
      {required this.slot, required this.slots, required this.rtl});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / slots;
    final i = rtl ? (slots - 1 - slot) : slot;
    final cx = w * (i + 0.5);

    // The floor light: warm, wide, rising out of the bottom edge.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.13),
            AppColors.gold.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCenter(
          center: Offset(cx, size.height * 0.96),
          width: w * 2.1,
          height: size.height * 2.5,
        )),
    );

    // The rule under the glyph: a cartouche flattened almost to a
    // line, so even the indicator is a piece of the same alphabet.
    final rule = Rect.fromCenter(
      center: Offset(cx, 5.5),
      width: w * 0.46,
      height: 3.2,
    );
    canvas.drawPath(
      Khatam.cartouche(rule),
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.0),
            AppColors.goldBright.withValues(alpha: 0.95),
            AppColors.gold.withValues(alpha: 0.0),
          ],
        ).createShader(rule),
    );

    // The hairline across the whole bar, brightest where the lamp is.
    final top = Rect.fromLTWH(0, 0, size.width, 0.9);
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.stroke.withValues(alpha: 0.55),
            AppColors.gold.withValues(alpha: 0.55),
            AppColors.stroke.withValues(alpha: 0.55),
          ],
          stops: [
            math.max(0.0, cx / size.width - 0.26),
            (cx / size.width).clamp(0.0, 1.0),
            math.min(1.0, cx / size.width + 0.26),
          ],
        ).createShader(top),
    );
  }

  @override
  bool shouldRepaint(covariant _LampPainter old) =>
      old.slot != slot || old.slots != slots || old.rtl != rtl;
}

class _NavStop extends StatelessWidget {
  final NavGlyph glyph;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A gold dot at the glyph's shoulder, the way an unread mark sits
  /// on an app icon.
  final bool dot;

  const _NavStop({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.goldBright : AppColors.textSecondary;
    // One node per destination: its name, whether it is the one open,
    // and "new" after it while the dot is lit. Said here rather than
    // gathered from the glyph and the word, so the name comes first.
    final l = L10n.of(context);
    return Semantics(
      container: true,
      selected: selected,
      button: true,
      label: dot ? '$label${l.comma} ${l.a11yNew}' : label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 48,
        highlightColor: AppColors.gold.withValues(alpha: 0.06),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The glyph lifts a little when it is the one lit, which is
            // most of what tells you the light belongs to it.
            TweenAnimationBuilder<double>(
              tween: Tween(end: selected ? 1 : 0),
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Transform.translate(
                offset: Offset(0, -2.5 * v),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: NavGlyphPainter(
                            glyph: glyph,
                            color: Color.lerp(AppColors.textSecondary,
                                AppColors.goldBright, v)!,
                            lit: v,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        top: -3,
                        end: -5,
                        child: NudgeDot(on: dot),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 10.5,
                height: 1.0,
                letterSpacing: selected ? 0.5 : 0.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four destinations, drawn rather than borrowed from an icon
/// set. A mihrab for the place you come back to, a ruled card for the
/// ones you write, a frame with a play in it for the reels you made,
/// and the khatam itself for the settings — the seal at the end of the
/// page.
enum NavGlyph { mihrab, card, reel, seal }

class NavGlyphPainter extends CustomPainter {
  final NavGlyph glyph;
  final Color color;

  /// 0..1. Lit glyphs gain a wash of gold inside the outline and a
  /// faint halo; unlit ones are the outline alone.
  final double lit;

  const NavGlyphPainter({
    required this.glyph,
    required this.color,
    required this.lit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final path = switch (glyph) {
      NavGlyph.mihrab => _mihrab(s),
      NavGlyph.card => _card(s),
      NavGlyph.reel => _reel(s),
      NavGlyph.seal => Khatam.star(Offset(s / 2, s / 2), s * 0.44),
    };

    if (lit > 0.02) {
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.16 * lit)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.30 * lit)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    // The lamp hanging in the mihrab: the one flourish, and the thing
    // that stops the arch reading as a plain doorway.
    if (glyph == NavGlyph.mihrab) {
      canvas.drawPath(
        Khatam.star(Offset(s / 2, s * 0.47), s * 0.10),
        Paint()..color = color.withValues(alpha: 0.55 + 0.45 * lit),
      );
    }
  }

  /// A pointed arch on two short piers, standing on a sill.
  Path _mihrab(double s) {
    final l = s * 0.20, r = s * 0.80, base = s * 0.86, spring = s * 0.46;
    return Path()
      ..moveTo(l, base)
      ..lineTo(l, spring)
      ..quadraticBezierTo(l, s * 0.14, s / 2, s * 0.10)
      ..quadraticBezierTo(r, s * 0.14, r, spring)
      ..lineTo(r, base)
      ..moveTo(s * 0.12, base)
      ..lineTo(s * 0.88, base);
  }

  /// A card standing upright with two lines of writing on it. Squarer
  /// than the reel glyph beside it, and ruled rather than played,
  /// which is the whole difference between the two things.
  Path _card(double s) {
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.17, s * 0.19, s * 0.83, s * 0.81),
        Radius.circular(s * 0.11),
      ))
      ..moveTo(s * 0.32, s * 0.42)
      ..lineTo(s * 0.68, s * 0.42)
      ..moveTo(s * 0.38, s * 0.58)
      ..lineTo(s * 0.62, s * 0.58);
  }

  /// An upright frame with a play mark in it, and a second frame
  /// standing behind — one reel, and the ones before it.
  Path _reel(double s) {
    final front = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.24, s * 0.14, s * 0.78, s * 0.90),
      Radius.circular(s * 0.13),
    );
    return Path()
      ..addRRect(front)
      // The one behind, showing only along its leading edge.
      ..moveTo(s * 0.16, s * 0.26)
      ..lineTo(s * 0.16, s * 0.78)
      ..moveTo(s * 0.44, s * 0.40)
      ..lineTo(s * 0.62, s * 0.52)
      ..lineTo(s * 0.44, s * 0.64)
      ..close();
  }

  @override
  bool shouldRepaint(covariant NavGlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.lit != lit;
}
