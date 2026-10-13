import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../data/arena_service.dart';
import '../data/quran_repository.dart';
import '../data/reel_library.dart';
import '../data/rewards_service.dart';
import '../data/series_library.dart';
import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/ambient_motion.dart';
import '../widgets/arena_history.dart';
import '../widgets/badges_sheet.dart';
import '../widgets/cinematic_hero.dart';
import '../widgets/day_verse_card.dart';
import '../widgets/glow_button.dart';
import '../widgets/illumination.dart';
import '../widgets/night_sky.dart';
import '../widgets/reel_thumb.dart';
import '../widgets/series_strip.dart';
import '../widgets/shimmer_text.dart';
import '../widgets/tanafus_button.dart' show TanafusButton;
import '../widgets/widget_nudge.dart';
import 'arena_screen.dart' show openArena;
import 'reciter_screen.dart';
import 'reel_player_screen.dart';
import 'series_intro_screen.dart';
import 'series_screen.dart';

/// The landing tab.
///
/// It opens on a place. A full-bleed scenery chosen by the hour, drift
/// and haze and light moving in it, the salutation and the one thing
/// worth doing standing in the middle of it — and then the picture
/// dissolving into the night the rest of the page is made of, with the
/// verse card riding up over the join.
///
/// Below the fold it becomes a manuscript again: rules, seals, and two
/// rows that run off both edges of the screen.
///
/// The sky under all of it belongs to the shell, not to this screen,
/// and every scrollable here reports into it. That is the trick that
/// ties the two halves together: the page moves, the rows move, and
/// the night behind them moves too — slower, and at three different
/// rates, so the screen has a depth it cannot have standing still.
class HomeScreen extends StatefulWidget {
  /// Jumps the shell to the My Reels tab.
  final VoidCallback onSeeAllReels;

  const HomeScreen({super.key, required this.onSeeAllReels});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _page = ScrollController();
  List<SavedReel> _recent = const [];

  /// The series in progress, if there is one: its days ride above the
  /// recent reels so the next one to make is a glance away.
  ReelSeries? _series;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadSeries();
    ReelLibrary.revision.addListener(_loadRecent);
    SeriesLibrary.revision.addListener(_loadSeries);
    RewardsService.state.addListener(_rewardsChanged);
    SettingsService.state.addListener(_rewardsChanged);
    ArenaService.state.addListener(_rewardsChanged);
  }

  @override
  void dispose() {
    ReelLibrary.revision.removeListener(_loadRecent);
    SeriesLibrary.revision.removeListener(_loadSeries);
    RewardsService.state.removeListener(_rewardsChanged);
    SettingsService.state.removeListener(_rewardsChanged);
    ArenaService.state.removeListener(_rewardsChanged);
    _page.dispose();
    super.dispose();
  }

  void _rewardsChanged() {
    if (mounted) setState(() {});
  }

  /// Reels a user has to have made before the page offers them a
  /// series of reels. Two: the first is finding out what a reel is,
  /// the second is coming back for another — which is the habit a
  /// series is for. Until then the offer is a plan for something the
  /// user has not yet done once.
  static const _reelsBeforeSeries = 2;

  Future<void> _loadRecent() async {
    final reels = await ReelLibrary.load();
    if (mounted) setState(() => _recent = reels.take(8).toList());
  }

  /// Whether the quiz has rounds to shelve: the switch on the heading
  /// only exists once one has been played.
  bool get _hasRounds {
    final a = ArenaService.state.value;
    return a.played > 0 && a.history.any((r) => r.answers.isNotEmpty);
  }

  /// Rounds on the shelf: chosen — and kept, so the app opens on the
  /// same shelf — or all there is with no reels yet.
  bool get _showingRounds =>
      _hasRounds &&
      (SettingsService.state.value.homeRounds || _recent.isEmpty);

  /// The shelf's heading: a plain title with one kind of thing to show,
  /// and the two names as a switch with both.
  Widget _shelfRule(BuildContext context, L10n l) {
    final rounds = _showingRounds;
    final both = _hasRounds && _recent.isNotEmpty;
    return SectionRule(
      title: rounds ? l.arenaRecent : l.recentReels,
      titleWidget: both
          ? _ShelfSwitch(
              rounds: rounds,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                SettingsService.update(
                    SettingsService.state.value.copyWith(homeRounds: v));
              },
            )
          : null,
      subtitle: rounds ? null : l.recentReelsSubtitle,
      // Only the way to the rest of them.
      trailing: TextButton(
        onPressed: rounds ? () => openArena(context) : widget.onSeeAllReels,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          l.seeAll,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.goldBright, fontSize: 13),
        ),
      ),
    );
  }

  Future<void> _loadSeries() async {
    final s = await SeriesLibrary.active();
    if (mounted) setState(() => _series = s);
  }

  void _planSeries() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SeriesIntroScreen()),
    );
  }

  void _openSeries(ReelSeries s, [int? day]) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => SeriesScreen(seriesId: s.id, initialDay: day)),
    );
  }

  void _startCreate() {
    HapticFeedback.selectionClick();
    creationState.startNewReel();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReciterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // Read once: the series row's callbacks close over the value this
    // frame was built from, not over a field a library refresh can
    // null out between the frame and the tap.
    final series = _series;
    final settings = SettingsService.state.value;
    // No sky of its own: the shell paints one behind all three tabs.
    // Falling back to none keeps this screen usable on its own in a
    // test or a preview harness.
    final motion = AmbientScope.maybeOf(context);
    final content = ListView(
      controller: _page,
      // The page stops at its own beginning and its own end, and
      // nothing marks the attempt to go past either.
      //
      // Pulling down used to carry the whole page off the top of the
      // screen, which put the hero's own top edge against the shell's
      // sky as a hard horizontal line — the band reported at the top of
      // the screen. Nothing painted there could have hidden it: the
      // edge is the page leaving, not something drawn behind it. So the
      // page does not leave. The glow and the stretch go with it, for
      // the same reason — they are also something appearing when the
      // user asked for nothing.
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      // The hero runs under the status bar and off both edges, so the
      // page takes no padding of its own; everything below the fold
      // takes the margin by hand, and the two rows deliberately do not
      // — their cards slide away under the edge of the screen.
      padding: const EdgeInsets.only(bottom: 78),
      children: [
        CinematicHero(
          page: _page,
          motion: motion,
          minHeight: 508,
          child: SafeArea(
            bottom: false,
            child: Padding(
              // The bottom inset is room for the verse card, which
              // rides up out of the page and over the foot of the
              // picture.
              padding: const EdgeInsets.fromLTRB(
                  _HeroContent.margin, 4, _HeroContent.margin, 74),
              child: ValueListenableBuilder<AppSettings>(
                valueListenable: SettingsService.state,
                builder: (context, s, _) => _HeroContent(
                  greeting: l.greeting(DateTime.now().hour, name: s.name),
                  onCreate: _startCreate,
                ),
              ),
            ),
          ),
        ),
        // Everything under the picture, lifted so the first card
        // overlaps it. The lift does not change layout, so the page
        // simply ends 58px early — which is what the shortened bottom
        // padding above accounts for.
        //
        // Not Transform.translate: that moves the paint and the hit
        // test, but a box still only answers taps inside its own laid-
        // out bounds, so the 58px of the card lifted over the picture
        // — the label row, and the widget pill on it — took no taps at
        // all. See [_Lifted].
        _Lifted(
          by: 58,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
            // The hero ends on the page's own colour, and the sky
            // behind the shell does not: its washes and stars carry on
            // under it, so the line where the picture stops was the
            // line where they suddenly appeared — a tear across the
            // middle of the page.
            //
            // This is the hem. A band of that same colour, fading to
            // nothing over a hundred and fifty pixels, so the sky
            // arrives instead of starting. It is painted first and
            // everything on the page stands on top of it.
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 150,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.bg,
                        Color(0xE60D1117),
                        Color(0x000D1117),
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                // The verse — and on Friday, Jumu'ah's.
                const _Margin(
                  child: _Reveal(delayMs: 60, child: DayVerseCard()),
                ),
                const SizedBox(height: 24),
                // The invitation to put the verse on the home screen.
                // Nothing at all most of the time: it carries its own
                // spacing only while it is showing.
                const _Margin(
                  child: _Reveal(delayMs: 80, child: WidgetNudge()),
                ),
                // A surah over several days. Here once a series exists,
                // or once the user has made a couple of reels — see
                // [_reelsBeforeSeries] — and it holds the streak once a
                // series exists. Kept to a rule and one line under it
                // until then: the home page is for the verse and the
                // reels, and a plan that does not exist yet should take
                // no more room than a sentence.
                if (settings.showSeries &&
                    (series != null ||
                        RewardsService.state.value.reelsMade >=
                            _reelsBeforeSeries)) ...[
                  const SizedBox(height: 18),
                  _Margin(
                    child: _Reveal(
                      delayMs: 135,
                      // No button on the rule: before a series, the line
                      // under it is the way in; after, a new one is in
                      // the series' own menu.
                      child: SectionRule(title: l.seriesTitle),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _Reveal(
                    delayMs: 135,
                    child: series == null
                        ? _Margin(child: _SeriesInvite(onTap: _planSeries))
                        : _SeriesRow(
                            series: series,
                            onTapDay: (d) => _openSeries(series, d),
                            onLongPressDay: (d) =>
                                SeriesLibrary.toggleDay(series.id, d),
                            onOpen: () => _openSeries(series),
                          ),
                  ),
                ],
                // The shelf at the foot: the latest reels, or — once a
                // round of the quiz has been played — the rounds, by a
                // tap on the heading.
                if (_recent.isNotEmpty || _hasRounds) ...[
                  const SizedBox(height: 18),
                  _Margin(
                    child: _Reveal(
                      delayMs: 160,
                      child: _shelfRule(context, l),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Reveal(
                    delayMs: 160,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(a),
                          child: child,
                        ),
                      ),
                      child: _showingRounds
                          ? const ArenaHistoryStrip(
                              key: ValueKey('rounds'),
                              limit: 12,
                              padding: EdgeInsets.symmetric(horizontal: 22),
                            )
                          : _ReelsRail(
                              key: const ValueKey('reels'),
                              reels: _recent,
                              // The streak above takes some of this row's
                              // room: the cards stand a little shorter
                              // under it.
                              compact: series != null,
                              onOpen: (r) => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => ReelPlayerScreen(reel: r)),
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
            ],
          ),
        ),
      ],
    );

    // No glow, no stretch: the two things a Material list does when it
    // is pulled past its end are both "something appearing", which is
    // exactly what this page must not do.
    final still = ScrollConfiguration(
      behavior: const _NoOverscroll(),
      child: content,
    );
    if (motion == null) return still;
    return AmbientScrollSensor(motion: motion, child: still);
  }
}

/// A list that shows nothing at all when it is pulled past an end.
///
/// The default Material behaviour paints a glow there, and on Android
/// 12 and up it stretches the whole page instead. Both are answers to
/// "you have reached the end", and both are a thing appearing at the
/// top of the home screen — which is the one thing this page is not
/// allowed to do.
class _NoOverscroll extends MaterialScrollBehavior {
  const _NoOverscroll();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

// ---------------------------------------------------------------------
// What stands in the picture
// ---------------------------------------------------------------------

/// The whole argument of the app, on the opening frame: whose letter
/// this is, who is being greeted, what it is for, and the one door in.
///
/// Centred rather than ranged left. Over a photograph, a centred
/// column reads as composed into the frame; the same words ranged left
/// read as a header that has been laid on top of it.
class _HeroContent extends StatelessWidget {
  final String greeting;
  final VoidCallback onCreate;

  /// The frame's side margin. The greeting and the cartouche under it
  /// hang out past it by exactly this much — see [_HungToEdge].
  static const margin = 26.0;

  const _HeroContent({required this.greeting, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The salutation comes first and sits high, right under the
        // status bar — it is a greeting, and a greeting that arrives
        // halfway down a page has been kept waiting.
        // Each line of the opening frame is its own stop for a screen
        // reader, in the order it is laid out: the page's first item
        // would otherwise gather every loose line into one block and
        // read it before the headline.
        // The first line of the frame: the greeting at the start, hung
        // out to the screen's edge on the same line as the cartouche
        // under it, the name dead centre, and the corner at the end
        // left clear for the shell's door to the arena, which stands
        // on that line.
        _Reveal(
          delayMs: 0,
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Semantics(container: true, child: const _Wordmark()),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HungToEdge(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.40),
                      child: Semantics(
                        container: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Sheen(
                              period: const Duration(milliseconds: 7000),
                              strength: 0.42,
                              child: GildedText(
                                'السَّلَامُ عَلَيْكُمْ',
                                style: AppTheme.quran(size: 17)
                                    .copyWith(height: 1.4),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // A name typed in makes this line as long as
                            // the user likes; two lines then an ellipsis,
                            // so the name in the middle is never crowded.
                            Text(
                              greeting,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleMedium?.copyWith(
                                fontSize: 17,
                                height: 1.25,
                                color: const Color(0xFFCFC9BC),
                                fontWeight: FontWeight.w500,
                                shadows: const [
                                  Shadow(
                                      color: Color(0x99000000),
                                      blurRadius: 14),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: TanafusButton.size + 8),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // What was earned, under the line, on its own — hung out past
        // the frame's margin so it stands against the screen's edge,
        // square under the greeting.
        const _Reveal(
          delayMs: 40,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _HungToEdge(child: _StreakCartouche()),
          ),
        ),
        const SizedBox(height: 26),
        const _Reveal(delayMs: 70, child: BismillahOrnament(fontSize: 15)),
        const SizedBox(height: 22),
        // The promise, and now the headline of the screen.
        //
        // It used to sit under the greeting in body type, which made
        // the largest words on the app's opening frame "Good evening" —
        // a pleasantry where the argument should have been. The wave of
        // light walks it word by word so the eye reads it again on
        // every visit.
        _Reveal(
          delayMs: 130,
          child: A11yHeader(
            child: ShimmerText(
            text: l.beTheReason,
            style: t.headlineMedium!.copyWith(
              fontSize: 26,
              height: 1.26,
              fontWeight: FontWeight.w700,
              letterSpacing: l.arabicScript ? 0 : -0.8,
              shadows: const [
                // The photograph underneath is never flat black; this
                // is what keeps the line readable over the brightest
                // part of any of them.
                Shadow(color: Color(0xB3000000), blurRadius: 26),
              ],
            ),
            perWord: const Duration(milliseconds: 290),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _Reveal(delayMs: 170, child: _HeroRule()),
        const SizedBox(height: 13),
        _Reveal(
          delayMs: 200,
          child: Semantics(
            container: true,
            child: Text(
            l.createCardBody,
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.5,
              color: const Color(0xFFB9B3A6),
              shadows: const [
                Shadow(color: Color(0x99000000), blurRadius: 14),
              ],
            ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _Reveal(
          delayMs: 240,
          child: ConstrainedBox(
            // Narrower than the column it sits in. A gold bar running
            // the full width of a photograph is a banner; a gold bar
            // the width of the words above it is a door.
            constraints: const BoxConstraints(maxWidth: 278),
            child: GlowButton(
              label: l.createAReel,
              icon: Icons.add_rounded,
              breathe: true,
              pulseSpeed: 1.1,
              height: 54,
              onPressed: onCreate,
            ),
          ),
        ),
      ],
    );
  }
}

/// Moves [child] out past the frame's margin to the screen's start
/// edge — the right edge in Arabic and Urdu.
///
/// The greeting and the cartouche both hang from this one widget so
/// they stand on the same line; when the cartouche hung alone and the
/// greeting kept the margin, the two looked set by different hands.
class _HungToEdge extends StatelessWidget {
  final Widget child;
  const _HungToEdge({required this.child});

  @override
  Widget build(BuildContext context) {
    const m = _HeroContent.margin;
    return Transform.translate(
      offset: Offset(Directionality.of(context) == TextDirection.rtl ? m : -m, 0),
      child: child,
    );
  }
}

/// The app's name, at the head of the opening frame between the
/// greeting and the streak.
///
/// This is the one place the frame says whose it is, and it says it
/// the way a masthead does: on its own, in the same beaten gold as
/// the salutation beside it, with nothing ruled around it. It used to
/// be set small into the rule under the headline, where it read as
/// part of the ornament and was missed. The name is a name in both
/// languages — it is not translated, for the same reason a platform's
/// is not.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  static const wordmark = 'AyahReel';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Sheen(
      period: const Duration(milliseconds: 9000),
      strength: 0.34,
      phase: 0.5,
      child: GildedText(
        wordmark,
        maxLines: 1,
        style: t.labelSmall!.copyWith(
          fontSize: 15,
          height: 1.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

/// A hairline out to each margin, meeting at a single seal: the rule
/// under the headline, and nothing but a rule now that the name has
/// moved up to the head of the frame.
class _HeroRule extends StatelessWidget {
  const _HeroRule();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 236,
      child: Row(
        children: [
          Expanded(child: OrnamentHairline(towardsEnd: false)),
          SizedBox(width: 10),
          SealGlyph(size: 5),
          SizedBox(width: 10),
          Expanded(child: OrnamentHairline(towardsEnd: true)),
        ],
      ),
    );
  }
}

/// Streak + points, only shown once the user has earned something, and
/// set in a cartouche rather than a pill: on this page a number that
/// was earned should look awarded.
class _StreakCartouche extends StatelessWidget {
  const _StreakCartouche();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ValueListenableBuilder<RewardsState>(
      valueListenable: RewardsService.state,
      builder: (context, s, _) {
        if (s.points == 0) return const SizedBox.shrink();
        final style = t.bodySmall?.copyWith(
          color: AppColors.goldBright,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );
        final badges = s.badges.length;
        final l = L10n.of(context);
        // A tap opens the shelf of badges: the cartouche is the one
        // awarded thing on the page, so it is where the rest live.
        // Read as one sentence rather than three bare numbers.
        return A11yTap(
          label: l.a11yRewards(s.streakDays, s.points, badges),
          hint: l.a11yOpensBadges,
          onTap: () => showBadgesSheet(context),
          child: Pressable(
          onTap: () => showBadgesSheet(context),
          scale: 0.96,
          child: CustomPaint(
            painter: const _CartouchePainter(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 7, 18, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.streakDays > 0) ...[
                    const Icon(Icons.local_fire_department_rounded,
                        size: 13, color: AppColors.gold),
                    const SizedBox(width: 3),
                    Text('${s.streakDays}', style: style),
                    const SizedBox(width: 8),
                    const SealGlyph(size: 4, color: Color(0x66D4A947)),
                    const SizedBox(width: 8),
                  ],
                  const SealGlyph(size: 9),
                  const SizedBox(width: 4),
                  Text('${s.points}', style: style),
                  if (badges > 0) ...[
                    const SizedBox(width: 8),
                    const SealGlyph(size: 4, color: Color(0x66D4A947)),
                    const SizedBox(width: 8),
                    const Icon(Icons.workspace_premium_rounded,
                        size: 13, color: AppColors.gold),
                    const SizedBox(width: 3),
                    Text('$badges', style: style),
                  ],
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

class _CartouchePainter extends CustomPainter {
  const _CartouchePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Khatam.cartouche(rect.deflate(0.6));
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.gold.withValues(alpha: 0.20),
            AppColors.gold.withValues(alpha: 0.07),
          ],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.gold.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _CartouchePainter old) => false;
}

// ---------------------------------------------------------------------
// Rails
// ---------------------------------------------------------------------

/// A horizontal row whose items know where they are.
///
/// [builder] is handed `t` — where the item's centre sits across the
/// viewport, 0 at the leading edge and 1 at the trailing one — so a
/// card can lean, dim or lift according to its own position, and the
/// row gains the depth a flat strip of cards never has.
class _Rail extends StatefulWidget {
  final double height;
  final double itemWidth;
  final double gap;
  final int count;
  final EdgeInsets padding;
  final Widget Function(BuildContext context, int index, double t) builder;

  const _Rail({
    required this.height,
    required this.itemWidth,
    required this.gap,
    required this.count,
    required this.builder,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  final _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final view = box.maxWidth;
          return ListView.separated(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: widget.padding,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemCount: widget.count,
            separatorBuilder: (_, __) => SizedBox(width: widget.gap),
            itemBuilder: (context, i) {
              // Only the handful of items actually on screen exist, so
              // this listens per item rather than rebuilding the row.
              return AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final offset =
                      _ctrl.hasClients && _ctrl.position.hasContentDimensions
                          ? _ctrl.offset
                          : 0.0;
                  final centre = widget.padding.left +
                      i * (widget.itemWidth + widget.gap) +
                      widget.itemWidth / 2;
                  final t = view <= 0 ? 0.5 : (centre - offset) / view;
                  return widget.builder(context, i, t);
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// The reels already made, stood up in a row and turned to face the
/// middle of it — the nearest one square on, the ones to either side
/// falling away. Scrolling this row is also what pushes the sky
/// sideways behind the whole page.
class _ReelsRail extends StatelessWidget {
  final List<SavedReel> reels;
  final void Function(SavedReel) onOpen;

  /// Shorter cards, for when the series streak is on the page above.
  final bool compact;

  const _ReelsRail({
    super.key,
    required this.reels,
    required this.onOpen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final width = compact ? 88.0 : 108.0;
    return _Rail(
      height: compact ? 156 : 190,
      itemWidth: width,
      gap: 13,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      count: reels.length,
      builder: (context, i, t) {
        final d = (t - 0.5).clamp(-1.0, 1.0);
        final away = d.abs();
        return Transform.scale(
          scale: 1 - away * 0.09,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              // A shallow perspective: enough that a card turns, not so
              // much that the row starts looking like a screensaver.
              ..setEntry(3, 2, 0.0013)
              ..rotateY((rtl ? d : -d) * 0.46),
            child: _ReelCard(
              key: ValueKey(reels[i].id),
              reel: reels[i],
              width: width,
              lit: (1 - away * 1.7).clamp(0.0, 1.0),
              onTap: () => onOpen(reels[i]),
            ),
          ),
        );
      },
    );
  }
}

/// The heading of the shelf at the foot of the page, as a switch: the
/// recent reels, or the rounds of the quiz. The one showing is the
/// heading; the other waits beside it, quieter, a tap away.
class _ShelfSwitch extends StatelessWidget {
  final bool rounds;
  final ValueChanged<bool> onChanged;

  const _ShelfSwitch({required this.rounds, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _ShelfName(
            label: l.reelsTabReels,
            on: !rounds,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: _ShelfName(
            label: l.shelfRounds,
            on: rounds,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _ShelfName extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;

  const _ShelfName({
    required this.label,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return A11yTap(
      label: label,
      selected: on,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: t.titleMedium!.copyWith(
                  letterSpacing: 0.1,
                  fontSize: on ? 17 : 15,
                  color: on
                      ? AppColors.textPrimary
                      : AppColors.textSecondary.withValues(alpha: 0.75),
                ),
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 3),
              // The one showing carries a short gold underline.
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: 2,
                width: on ? 18 : 0,
                decoration: BoxDecoration(
                  color: AppColors.goldBright,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The active series on the home page: its days in a row, and the
/// surah's name above them as the way into the whole plan.
class _SeriesRow extends StatelessWidget {
  final ReelSeries series;
  final ValueChanged<int> onTapDay;
  final ValueChanged<int> onLongPressDay;
  final VoidCallback onOpen;

  const _SeriesRow({
    required this.series,
    required this.onTapDay,
    required this.onLongPressDay,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final surah = QuranRepository.surahInfo(series.surah);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Margin(
          child: A11yTap(
            hint: l.a11yOpensSeries,
            child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l.seriesHeading(surah.nameEnglish, series.days)} · '
                    '${l.seriesProgress(series.daysDone, series.days)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: AppColors.gold.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SeriesStrip(
          series: series,
          compact: true,
          onTapDay: onTapDay,
          onLongPressDay: onLongPressDay,
        ),
      ],
    );
  }
}

/// Before any series exists: one quiet line saying what the section is
/// for, and nothing else — no card, no seals, no border. The line is
/// the door.
class _SeriesInvite extends StatelessWidget {
  final VoidCallback onTap;
  const _SeriesInvite({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return A11yTap(
      hint: l.a11yPlansSeries,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l.seriesSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
      ),
    );
  }
}

class _ReelCard extends StatelessWidget {
  final SavedReel reel;
  final double width;
  final double lit;
  final VoidCallback onTap;

  const _ReelCard({
    super.key,
    required this.reel,
    required this.width,
    required this.lit,
    required this.onTap,
  });

  static const _radius = BorderRadius.all(Radius.circular(18));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final g = reel.gradientArgb;
    // The card shows the surah alone; the reader is told whose voice
    // and when, the way the My Reels card says it.
    return A11yTap(
      label: l.a11yReel(
          reel.surahName, reel.reciterName, l.formatDate(reel.createdAt)),
      hint: l.a11yPlaysReel,
      onTap: onTap,
      child: Pressable(
      onTap: onTap,
      scale: 0.96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45 * lit + 0.2),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _radius,
          child: SizedBox(
            width: width,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(g[0]), Color(g[1])],
                    ),
                  ),
                ),
                ReelThumb(reel: reel),
                // Nothing laid over the frame. A reel is a picture of
                // itself; a mark in the middle of it is a mark over the
                // one thing the card exists to show.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(9, 20, 9, 9),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 0.8,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.gold
                                    .withValues(alpha: 0.15 + 0.55 * lit),
                                AppColors.gold.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          L10n.of(context).localizedSurahName(reel.surahName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Motion helpers
// ---------------------------------------------------------------------

/// The page's margin. Everything that is not a rail sits inside it.
class _Margin extends StatelessWidget {
  final Widget child;
  const _Margin({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: child,
      );
}

/// Gentle staggered entrance: fade + a short rise. Runs once.
class _Reveal extends StatelessWidget {
  final int delayMs;
  final Widget child;
  const _Reveal({required this.delayMs, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 480 + delayMs),
      curve: Interval(
        delayMs / (480 + delayMs),
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - v)),
          child: Transform.scale(scale: 0.985 + 0.015 * v, child: child),
        ),
      ),
      child: child,
    );
  }
}

/// Paints its child [by] pixels higher than it is laid out, and takes
/// taps there too.
///
/// Transform.translate does the first half of that and not the
/// second: a render box answers a hit test only inside its own bounds,
/// and the translated part of the child is outside them. The verse
/// card's top strip — the label row and the widget pill — sat in that
/// dead zone for as long as the page was lifted with a transform, and
/// every tap on it fell through to the picture behind. This box
/// skips the bounds check and hands the child the tap at the offset
/// it was painted at.
class _Lifted extends SingleChildRenderObjectWidget {
  final double by;
  const _Lifted({required this.by, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLifted(by);

  @override
  void updateRenderObject(BuildContext context, _RenderLifted renderObject) {
    renderObject.by = by;
  }
}

class _RenderLifted extends RenderProxyBox {
  _RenderLifted(this._by);

  double _by;
  double get by => _by;
  set by(double v) {
    if (v == _by) return;
    _by = v;
    markNeedsPaint();
  }

  Offset get _shift => Offset(0, -_by);

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c != null) context.paintChild(c, offset + _shift);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // No bounds check: the lifted strip is above this box's own top.
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, transformed) =>
          c.hitTest(result, position: transformed),
    );
  }
}
