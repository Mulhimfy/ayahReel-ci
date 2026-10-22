import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/scene_catalog.dart';
import '../theme/app_theme.dart';
import 'ambient_motion.dart';

/// The full-bleed opening of the app: a real place, lit, breathing,
/// with the greeting standing in it.
///
/// Everything here exists to make a still photograph stop being one:
///
///   the drift    a slow push in and across, on a minute-long loop
///   the parallax the picture holds back as the page scrolls off it
///   the haze     bands of mist crossing at three different speeds
///   the light    a fan of rays from off the top corner, turning
///   the grade    the whole frame pulled towards the app's own night
///   the scrim    the foot of the frame landed on the page's own colour
///
/// The scenery changes with every visit to Home — every launch, and
/// every return after a while away — and is drawn from the whole
/// library of places the app makes reels in: every still photograph on
/// the nature shelves that is dark enough at the top for the headline.
/// So the first thing a user sees on opening is a frame of the thing
/// they are here to make, and it is a new one each time. It never waits
/// on the network: the next picture already on the phone is the one
/// shown, and the two after it are fetched while it is looked at.
class CinematicHero extends StatefulWidget {
  /// The page this hero sits at the top of. Scrolling it pushes the
  /// picture back and dims it.
  final ScrollController page;

  final AmbientMotion? motion;

  /// The hero is as tall as what stands in it, and never shorter than
  /// this. Sizing to the content rather than to a fraction of the
  /// screen is what keeps it whole at a large system text scale — a
  /// fixed-height hero is a hero that overflows on somebody's phone.
  final double minHeight;

  final Widget child;

  /// How far the picture may slide against the page, and — because it
  /// is hung with exactly this much spare at the top and bottom — how
  /// far it can slide before it would show an edge.
  ///
  /// A picture pinned to the frame and then translated leaves a band of
  /// nothing behind it that grows with every pixel of scroll. That band
  /// was the "gap" at the top of the hero. Hanging it long and moving
  /// it inside its own slack cannot produce one.
  static const _slack = 120.0;

  const CinematicHero({
    super.key,
    required this.page,
    required this.child,
    this.minHeight = 470,
    this.motion,
  });

  /// The pictures the opening frame wears when the library is not at
  /// hand — before the catalog has loaded, and when the day's picture
  /// is neither bundled nor fetched yet. Every one is bundled, dark at
  /// the top where the headline sits, and empty of people. Two shelves,
  /// one for the day and one for the night.
  static const daytimeScenes = [
    'assets/backgrounds/mountains_pexels_01.jpg',
    'assets/backgrounds/sacred_pexels_03.jpg',
    'assets/backgrounds/mountains_pexels_02.jpg',
    'assets/backgrounds/road_openverse_01.jpg',
    'assets/backgrounds/forest_wallhaven_01.jpg',
    'assets/backgrounds/desert_pexels_02.jpg',
  ];
  static const nightScenes = [
    'assets/backgrounds/aurora_pexels_01.jpg',
    'assets/backgrounds/forest_pixabay_02.jpg',
    'assets/backgrounds/ocean_pixabay_01.jpg',
    'assets/backgrounds/aurora_pexels_02.jpg',
    'assets/backgrounds/road_pexels_01.jpg',
    'assets/backgrounds/ocean_pixabay_02.jpg',
  ];

  /// How a picture not on the phone is fetched. Null until the app sets
  /// it at startup (to [SceneCatalog.download]), so the frame reaches
  /// for the network only inside the running app — never from a widget
  /// under test, where the catalog is real but the network is a stub
  /// that falls over mid-stream.
  static Future<File?> Function(Scene)? fetch;

  /// The shelves of the library the frame draws on: places, not
  /// textures, and upright, so a phone-shaped window shows the picture
  /// and not a slice of it.
  static const heroTabs = {
    'sky', 'mountains', 'desert', 'water', 'forest', 'road', 'sacred',
  };

  /// How bright the top of a picture may be, as the catalog measured
  /// it, for the headline to stay readable on it. Every picture on the
  /// bundled shelves is under it.
  static const topLuminanceLimit = 0.5;

  /// Every still in the library the frame may wear, in one fixed
  /// shuffled order, so the walk through them never runs shelf by
  /// shelf and is the same on every phone.
  static List<Scene> library(Iterable<Scene> all) {
    final out = [
      for (final s in all)
        if (!s.isVideo &&
            !s.wide &&
            heroTabs.contains(s.tab) &&
            s.gradientArgb.isNotEmpty &&
            _luminance(s.gradientArgb.first) < topLuminanceLimit)
          s,
    ]..sort((a, b) => a.id.compareTo(b.id));
    out.shuffle(math.Random(2026));
    return out;
  }

  static double _luminance(int argb) {
    final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  }

  /// Which twelve-hour slot [now] falls in, counted from the start of
  /// 2026: the morning of a day is one slot, its afternoon and night
  /// the next.
  static int slotOf(DateTime now) {
    final day = DateTime(now.year, now.month, now.day)
        .difference(DateTime(2026, 1, 1))
        .inDays;
    return (day * 2 + (now.hour >= 12 ? 1 : 0)).abs();
  }

  /// The bundled picture for [now], for when the library's is not at
  /// hand: a new one every twelve hours, the day's from one shelf and
  /// the night's from the other, each shelf walked in turn.
  static String sceneFor(DateTime now) {
    final night = now.hour >= 19 || now.hour < 5;
    final day = DateTime(now.year, now.month, now.day)
        .difference(DateTime(2026, 1, 1))
        .inDays;
    final shelf = night ? nightScenes : daytimeScenes;
    return shelf[day.abs() % shelf.length];
  }

  /// The picture for [turn] in [library]'s walk: the first at or after
  /// that place that is already on the phone — bundled, or fetched
  /// before — and its place, so the walk goes on from there; null when
  /// none is. Never waits on the network: the frame changes at once,
  /// and [CinematicHero.fetch] brings the pictures after it in for the
  /// turns to come.
  static Future<({int at, ImageProvider picture})?> onPhoneFrom(
      int turn, List<Scene> library) async {
    if (library.isEmpty) return null;
    final from = turn % library.length;
    for (var k = 0; k < library.length; k++) {
      final at = (from + k) % library.length;
      final s = library[at];
      if (s.bundled) return (at: at, picture: AssetImage(s.bundledAsset));
      final f = await SceneCatalog.cachedFile(s);
      if (f != null) return (at: at, picture: FileImage(f));
    }
    return null;
  }

  /// Where the walk through the library stands, kept between launches
  /// in a file of its own, so every open of the app shows the next
  /// picture rather than the last one again.
  static const turnFile = 'home_picture_turn.txt';

  /// Away at least this long, and coming back is a new visit to Home,
  /// with a new picture.
  static const awayForNew = Duration(minutes: 20);

  /// [sceneFor] by the hour alone, for callers that only have one.
  static String sceneForHour(int hour) {
    final now = DateTime.now();
    return sceneFor(DateTime(now.year, now.month, now.day, hour));
  }

  @override
  State<CinematicHero> createState() => _CinematicHeroState();
}

class _CinematicHeroState extends State<CinematicHero>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Long enough that no one ever sees it turn around.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 54),
  )..repeat(reverse: true);

  bool _still = false;

  /// The library's picture for this visit, once it is at hand; until
  /// then the bundled shelf stands in.
  ImageProvider? _picture;

  /// When the app last went out of sight, for [CinematicHero.awayForNew].
  DateTime? _awayAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_look());
  }

  /// Every visit to Home wears the next picture: a launch, and a return
  /// after [CinematicHero.awayForNew] or more away. A glance at another
  /// app and back is the same visit, and keeps its picture.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _awayAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final away = _awayAt;
    _awayAt = null;
    if (away != null &&
        DateTime.now().difference(away) >= CinematicHero.awayForNew) {
      unawaited(_look());
    }
  }

  /// Turns to the next picture in the library's walk that is on the
  /// phone, at once, and fetches the two after it for the visits to
  /// come. It waits for the catalog the app reads at startup rather
  /// than reading it itself, so nothing is spawned on a screen's
  /// account. Nothing here can bring the screen down: a catalog that
  /// will not load, a file that cannot be written or a fetch that fails
  /// leaves a picture showing, which is a home screen either way.
  Future<void> _look() async {
    try {
      await SceneCatalog.ready;
      if (!mounted) return;
      final all = [
        for (final t in SceneCatalog.tabOrder) ...SceneCatalog.inTab(t),
      ];
      final library = CinematicHero.library(all);
      if (library.isEmpty) return;
      final turn = await _readTurn();
      final found = await CinematicHero.onPhoneFrom(turn, library);
      if (!mounted || found == null) return;
      setState(() => _picture = found.picture);
      // The walk goes on after what was shown, so the pictures skipped
      // for not being on the phone yet come round once they are.
      await _writeTurn(found.at + 1);
      final fetch = CinematicHero.fetch;
      if (fetch == null) return;
      for (var k = 1; k <= 2; k++) {
        final next = library[(found.at + k) % library.length];
        if (next.bundled || await SceneCatalog.cachedFile(next) != null) {
          continue;
        }
        unawaited(fetch(next));
      }
    } catch (_) {
      // A picture is already showing.
    }
  }

  /// Where the walk stands. A phone that has never kept it starts at
  /// the half-day's place, so two new phones do not open on the same
  /// picture the same morning.
  static Future<int> _readTurn() async {
    try {
      final f = await _turnFile();
      if (f.existsSync()) {
        final n = int.tryParse(f.readAsStringSync().trim());
        if (n != null && n >= 0) return n;
      }
    } catch (_) {}
    return CinematicHero.slotOf(DateTime.now());
  }

  static Future<void> _writeTurn(int n) async {
    try {
      final f = await _turnFile();
      f.writeAsStringSync('$n', flush: true);
    } catch (_) {/* the next visit starts from the half-day's place */}
  }

  static Future<File> _turnFile() async => File(
      '${(await getApplicationSupportDirectory()).path}/${CinematicHero.turnFile}');


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still != _still) {
      _still = still;
      still ? _drift.stop() : _drift.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final ImageProvider scene =
        _picture ?? AssetImage(CinematicHero.sceneFor(DateTime.now()));
    // Decoded no larger than it will ever be drawn, with a little in
    // hand for the push-in. A 1080-wide still decoded at full size on
    // a small phone is several megabytes of nothing.
    //
    // Never zero. A MediaQuery can hand back an empty size — between a
    // resize and the frame that answers it, and on the first frame of a
    // freshly attached view — and Image.asset asserts that a cacheWidth
    // it is given is greater than zero. One frame of a degenerate size
    // is not a reason to bring the screen down.
    final decodeWidth = math.max(
      1,
      (media.size.width * media.devicePixelRatio * 1.2).round(),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Stack(
        children: [
          // 1 · the picture, hung long and drifting inside its slack
          Positioned(
            top: -CinematicHero._slack,
            bottom: -CinematicHero._slack,
            left: 0,
            right: 0,
            child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_drift, widget.page]),
              builder: (context, child) {
                final raw = widget.page.hasClients &&
                        widget.page.position.hasContentDimensions
                    ? widget.page.offset
                    : 0.0;
                // Never past the slack the picture is hung with, so
                // there is no scroll position at which an edge can
                // come into view.
                final shift = (raw * 0.3)
                    .clamp(-CinematicHero._slack * 0.6,
                        CinematicHero._slack * 0.75)
                    .toDouble();
                // Nothing here answers an overscroll. The page it sits
                // in cannot go past its own top any more, and the
                // opening-up this used to do was only ever visible
                // alongside the edge that came with it.
                final k = Curves.easeInOut.transform(_drift.value);
                return Transform.scale(
                  scale: 1.02 + 0.06 * k,
                  child: Transform.translate(
                    // Held back to under a third of the page's travel:
                    // the whole reason the header feels like a window
                    // rather than a banner.
                    offset: Offset(-8.0 + 16.0 * k, shift),
                    child: child,
                  ),
                );
              },
              // The library's picture dissolves in over the bundled
              // one when it lands, rather than snapping.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, if (current != null) current],
                ),
                child: Image(
                  key: ValueKey(scene),
                  image: ResizeImage.resizeIfNeeded(decodeWidth, null, scene),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  // Scenery, not content: a reader lands on the greeting
                  // standing in it, not on an unnamed picture behind it.
                  excludeFromSemantics: true,
                  // A scenery that will not decode leaves the painted sky
                  // showing through rather than an error box: the screen
                  // is still the screen, one layer shallower.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  // A dark frame first, then the photograph fading up
                  // into it — never a white flash under gold text.
                  frameBuilder: (context, child, frame, wasSync) =>
                      AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOut,
                    child: child,
                  ),
                ),
              ),
            ),
            ),
          ),

          // 2 · the grade: every scenery pulled towards one night
          const Positioned.fill(child: IgnorePointer(child: _Grade())),

          // 3 · haze and light
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _AtmospherePainter(
                    drift: _drift,
                    motion: widget.motion,
                  ),
                ),
              ),
            ),
          ),

          // 4 · the scrim that lands the picture on the page
          const Positioned.fill(child: IgnorePointer(child: _Scrim())),

          // 5 · what stands in it
          widget.child,
        ],
      ),
    );
  }
}

/// One colour grade over whichever scenery is up, so a sunrise and a
/// moonlit dune arrive at the same temperature and the gold on top of
/// them stays the brightest thing in the frame.
class _Grade extends StatelessWidget {
  const _Grade();

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          // Cooled and darkened, hardest at the top where the status
          // bar has to stay legible.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF080C15).withValues(alpha: 0.48),
                  const Color(0xFF0B1220).withValues(alpha: 0.20),
                  const Color(0xFF0D1117).withValues(alpha: 0.36),
                ],
                stops: const [0.0, 0.40, 1.0],
              ),
            ),
          ),
          // …and then one warm breath put back, low and central, so
          // the frame is lit rather than merely dimmed.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.35),
                radius: 0.95,
                colors: [
                  AppColors.gold.withValues(alpha: 0.10),
                  AppColors.gold.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      );
}

/// Weight under the words, then the page's own colour.
///
/// This ends fully opaque on [AppColors.bg]. That is only safe because
/// the sky painted behind the whole shell is now flat [AppColors.bg]
/// across the top three-quarters of the screen — the two meet on the
/// same value, so there is no shade for the join to give itself away
/// with. Change one without the other and the seam comes back.
class _Scrim extends StatelessWidget {
  const _Scrim();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.22),
              AppColors.bg.withValues(alpha: 0.45),
              AppColors.bg.withValues(alpha: 0.92),
              AppColors.bg,
            ],
            stops: const [0.10, 0.42, 0.72, 0.90, 1.0],
          ),
        ),
      );
}

/// Mist and light: three bands of haze crossing at their own speeds,
/// and a fan of rays from off the top corner that turns about once
/// every couple of minutes.
///
/// Both brighten with [AmbientMotion.energy] — flick the page and the
/// air in the picture moves too.
class _AtmospherePainter extends CustomPainter {
  final Animation<double> drift;
  final AmbientMotion? motion;

  _AtmospherePainter({required this.drift, this.motion})
      : super(
          // The ambient clock alone when there is one: it is the time
          // the painter reads, and it repaints at half rate at rest.
          // Merging in the drift repainted every frame regardless.
          repaint: motion ?? drift,
        );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final t = motion?.time ?? drift.value * 54;
    final energy = motion?.energy ?? 0;
    canvas.clipRect(rect);

    _rays(canvas, rect, size, t, energy);
    _haze(canvas, rect, size, t, energy);
  }

  /// A fan out of the top corner. Each blade is a long thin triangle
  /// filled with a gradient that dies before its own tip, so none of
  /// them ever shows an edge.
  void _rays(Canvas canvas, Rect rect, Size size, double t, double energy) {
    final origin = Offset(size.width * 0.74, -size.height * 0.34);
    final reach = size.height * 2.6;
    final turn = math.sin(t * 0.021) * 0.09;
    canvas.save();
    for (var i = 0; i < 11; i++) {
      // Irregular spacing and width: an evenly-fanned set of rays
      // reads as a graphic, an uneven one reads as light. The spacing
      // is deliberately not a constant step — a fan whose blades you
      // can count has stopped being light and become a sunburst.
      final a = math.pi / 2 +
          turn +
          (i - 5) * 0.082 +
          math.sin(i * 2.7) * 0.045;
      final w = 0.013 + 0.014 * (1 + math.sin(i * 1.9 + t * 0.06));
      final alpha = (0.016 + 0.013 * math.sin(t * 0.09 + i * 1.3)) *
          (1 + 0.9 * energy);
      final p = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(origin.dx + reach * math.cos(a - w),
            origin.dy + reach * math.sin(a - w))
        ..lineTo(origin.dx + reach * math.cos(a + w),
            origin.dy + reach * math.sin(a + w))
        ..close();
      canvas.drawPath(
        p,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFE9B8).withValues(alpha: alpha.clamp(0.0, 1.0)),
              const Color(0xFFFFE9B8).withValues(alpha: 0.0),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  /// Three soft bands sliding across at different rates. Nothing in a
  /// still photograph moves; this is what persuades the eye that the
  /// air in it does.
  void _haze(Canvas canvas, Rect rect, Size size, double t, double energy) {
    const bands = [
      (y: 0.30, h: 0.20, speed: 0.016, alpha: 0.055),
      (y: 0.52, h: 0.26, speed: 0.026, alpha: 0.045),
      (y: 0.74, h: 0.22, speed: 0.011, alpha: 0.035),
    ];
    for (final b in bands) {
      final cy = size.height * (b.y + 0.012 * math.sin(t * b.speed * 3.1));
      final cx = size.width * (0.5 + 0.75 * math.sin(t * b.speed));
      final bounds = Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.width * 2.4,
        height: size.height * b.h * (1 + 0.25 * energy),
      );
      // The band's own footprint, not the frame: outside [bounds] the
      // gradient is its transparent end stop, so a full-height fill
      // was three whole hero frames a tick blending nothing. Same
      // pixels for a fifth of the work.
      canvas.drawRect(
        bounds.intersect(rect),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              Colors.white
                  .withValues(alpha: b.alpha * (1 + 0.7 * energy)),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(bounds),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter old) => false;
}
