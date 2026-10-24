import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/home_widget_service.dart';
import '../data/settings_service.dart';
import '../data/verse_translation.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/quran_verses.dart';
import '../data/rewards_service.dart';
import '../l10n/l10n.dart';
import '../screens/reciter_screen.dart';
import '../screens/verses_screen.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'app_toast.dart';
import 'illumination.dart';
import 'make_sheet.dart';

/// Sets [v] up as the reel to make and goes to the voice first, then to
/// the verses, already selected — so the user can hear the reel before
/// they see it and still change the verse if they want to. The scenery
/// and the preview follow as they always do.
///
/// Only the card's tap lands here. A tap on the home-screen widget
/// brings the app to the home tab, where this card is, and stops.
/// Straight to the reel wizard with [v] already chosen.
///
/// The card's own tap now asks which of the two things to make first —
/// see [makeFromVerse] — and this is what it calls when the answer is
/// a reel. Still public and still called directly by everything that
/// knows it wants a reel: the moments rail, the series, the widget.
void startVerseReel(BuildContext context, QuranVerse v) {
  HapticFeedback.selectionClick();
  creationState
    ..startNewReel()
    ..selectSurah(v.surah)
    ..selectRange(v.startAyah, v.endAyah);
  // The verse picker will want the surah's text the moment it
  // opens; start it travelling now, while the voice is chosen.
  QuranRepository.ayahsOf(v.surah).catchError((_) => <Ayah>[]);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReciterScreen(
        surah: v.surah,
        onContinue: (ctx, r) {
          QuranRepository.prefetchRecitation(r, v.surah,
              startAyah: v.startAyah, endAyah: v.endAyah);
          Navigator.of(ctx).push(
            MaterialPageRoute(
                builder: (_) => const VersesScreen(preselect: true)),
          );
        },
      ),
    ),
  );
}

/// The verse the home screen carries right now.
///
/// Six days a week it is one short verse, set like a line from a
/// manuscript: a cartouche naming what it is, the verse in gold, its
/// reference — no button for the reel, because the whole card is the
/// button. It turns
/// twice a day, at midnight and at noon, in step with the widget. On
/// Friday it changes its dress: the whole verse of Salawat under a lamp
/// that turns slowly, the day itself named where the label was, and one
/// small gold door to the reel.
class DayVerseCard extends StatefulWidget {
  /// Overridable for tests and previews; the app passes nothing.
  final DateTime? date;

  /// Whether the home-screen widget is placed; injectable for tests.
  /// Asked so the first sighting of the widget can be the badge it is.
  final Future<bool> Function() isInstalled;

  const DayVerseCard({
    super.key,
    this.date,
    this.isInstalled = HomeWidgetService.isInstalled,
  });

  static const radius = BorderRadius.all(Radius.circular(26));

  /// The script's size for [shown]: a line of nine words sets large,
  /// and the longest verses in the rotation step down so the card
  /// stays three lines of Arabic at most on a narrow phone. The widget
  /// does the same on its own side.
  static double arabicSize(String shown) {
    final words = shown.split(' ').where((w) => w.length > 1).length;
    if (words <= 9) return 18;
    if (words <= 12) return 16.5;
    return 15;
  }

  @override
  State<DayVerseCard> createState() => _DayVerseCardState();
}

class _DayVerseCardState extends State<DayVerseCard>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  Timer? _turn;

  /// The card's slow clock: the light drifting in its ground, the motes
  /// rising through it, the medallion turning, and the two points of
  /// light running round its rim. One turn every fourteen seconds;
  /// everything on it goes round a whole number of times per turn, so
  /// nothing jumps when it wraps.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  /// The verse being written in as the card arrives: a short wait for
  /// the card's own entrance, then the gold flowing in from the right.
  late final AnimationController _write = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  )..forward();

  /// The meaning, coming up under the verse as the writing ends.
  late final Animation<double> _meaning = _write.drive(
      CurveTween(curve: const Interval(0.6, 1, curve: Curves.easeOut)));

  bool _still = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armTurn();
    _refreshInstalled();
  }

  /// Less motion asked for: the clock stops and the verse is simply
  /// there.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _clock.stop();
      _write.value = 1;
    } else {
      _clock.repeat();
    }
  }

  @override
  void didUpdateWidget(DayVerseCard old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) _armTurn();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshInstalled();
    // A timer does not reliably fire across a phone's sleep, so the
    // morning's first look could still show last night's verse. Coming
    // back is the moment to re-read the day and re-arm the turn.
    if (mounted) setState(_armTurn);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _turn?.cancel();
    _clock.dispose();
    _write.dispose();
    super.dispose();
  }

  /// Asked on the way in and every time the app comes back to the
  /// front — which is when the user has just been out on the home
  /// screen placing the widget. The first time it is found there is a
  /// badge, and this card is where the user lands to be told.
  Future<void> _refreshInstalled() async {
    if (!await widget.isInstalled()) return;
    final first = await RewardsService.recordWidgetPlaced();
    if (!first || !mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(
      L10n.of(context)
          .widgetBadgeEarned(RewardsService.pointsForWidget),
      tone: ToastTone.done,
    ));
  }

  /// A card left on screen across noon or midnight turns over on its
  /// own, at the same moment the widget does. A pinned date (tests,
  /// previews) never turns.
  void _armTurn() {
    _turn?.cancel();
    if (widget.date != null) return;
    final now = DateTime.now();
    final wait = QuranVerses.nextChange(now).difference(now);
    _turn = Timer(wait + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(_armTurn);
      // A new verse is written in like the first.
      if (!_still) _write.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.date ?? DateTime.now();
    final v = QuranVerses.at(now);
    final jumuah = QuranVerses.isJumuah(now);
    final l = L10n.of(context);
    // The whole card is the button, so the whole card is one thing to
    // a screen reader: what it is, the verse, its meaning, and what a
    // double tap does. On Friday the day comes first, as it does on
    // the card; its inner door does the same as the card itself, so
    // nothing is lost by folding it in.
    final reference =
        l.verseReference(v.surahName, v.startAyah, v.endAyah);
    // The reader's edition, as the card shows it — not always English.
    final meaning = v.translationIn(_edition);
    final spoken = jumuah
        ? '${l.jumuahToday}. ${l.jumuahCardBody}, $reference. '
            '${v.arabic}${l.ar ? '' : '. $meaning'}'
        : l.a11yVerseCard(reference, v.shown, meaning);
    return A11yTap(
      label: spoken,
      hint: l.a11yMakesVerseReel,
      onTap: () => makeFromVerse(context, v),
      child: _Lean(
      child: Pressable(
      onTap: () => makeFromVerse(context, v),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: DayVerseCard.radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: AppColors.gold.withValues(alpha: jumuah ? 0.16 : 0.10),
              blurRadius: 46,
              spreadRadius: -8,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: DayVerseCard.radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        // Friday sits in a deeper night of the same
                        // colour the other six days are cut from — a
                        // richer plum under the same gold, so the day
                        // reads as different without the card leaving
                        // the app's own palette for one day a week.
                        colors: jumuah
                            ? const [Color(0xFF322546), Color(0xFF191228)]
                            : const [Color(0xFF251E32), Color(0xFF15121F)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(child: _Bloom(strong: jumuah)),
              ),
              // Light drifting in the ground, gold motes rising through
              // it, and (six days a week) a medallion turning behind the
              // verse: all on the one slow clock, behind its own repaint
              // boundary so the page never repaints with it.
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _GroundPainter(_clock, friday: jumuah),
                    ),
                  ),
                ),
              ),
              if (jumuah)
                const PositionedDirectional(
                  top: -34,
                  end: -34,
                  child: IgnorePointer(child: _Lamp(size: 150)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: jumuah
                    ? _JumuahBody(
                        verse: v,
                        onMake: () => startVerseReel(context, v),
                        write: _write,
                        meaning: _meaning,
                      )
                    : _DailyBody(verse: v, write: _write, meaning: _meaning),
              ),
              Positioned.fill(
                child: IlluminatedBorder(
                  radius: DayVerseCard.radius,
                  sealSize: 0,
                  color: jumuah ? AppColors.goldBright : AppColors.gold,
                ),
              ),
              // Two points of light running round the rim, opposite
              // each other, once a turn.
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _RimLightPainter(
                        _clock,
                        radius: DayVerseCard.radius,
                        colour: AppColors.goldBright,
                      ),
                    ),
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

/// Six days out of seven: the verse, and the least around it that
/// still says what it is. The way to the widget is in Settings and
/// the nudge under the card, not on the card.
/// The edition the card's translation line is in. Read at build time
/// rather than passed down: both bodies want it, and the card rebuilds
/// with the rest of the tree when Settings changes.
VerseTranslation get _edition => SettingsService.state.value.translation;

class _DailyBody extends StatelessWidget {
  final QuranVerse verse;

  /// The writing-in, and the meaning's fade under it: see the card.
  final Animation<double> write;
  final Animation<double> meaning;

  const _DailyBody(
      {required this.verse, required this.write, required this.meaning});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // The reference rides in the cartouche with the label — one line
    // says what this is and where it is from — so the card is the
    // verse, its meaning, and nothing under them.
    final reference =
        l.verseReference(verse.surahName, verse.startAyah, verse.endAyah);
    return Column(
      children: [
        Row(
          children: [
            // Expanded, not Flexible plus a Spacer: the two split the
            // row in half, cutting a long reference off with room to
            // spare beside it.
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child:
                    _Cartouche(label: '${l.verseFromTheQuran} · $reference'),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
        const SizedBox(height: 10),
        _WrittenIn(
          progress: write,
          child: Sheen(
            period: const Duration(milliseconds: 6400),
            strength: 0.30,
            phase: 0.3,
            child: Text(
              verse.shown,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: AppTheme.quran(
                size: DayVerseCard.arabicSize(verse.shown),
                color: AppColors.goldBright,
              ).copyWith(height: 1.5),
            ),
          ),
        ),
        if (!l.ar) ...[
          const SizedBox(height: 7),
          FadeTransition(opacity: meaning, child: const _Rule()),
          const SizedBox(height: 7),
          // Whole, never cut: a translation that ends in three dots is
          // a promise the card did not keep. The few long verses in
          // the rotation — Ayat al-Kursi, the last of Al-Baqarah —
          // step the type down a size rather than lose their ending.
          FadeTransition(
            opacity: meaning,
            child: Text(
              verse.translationIn(_edition),
              textAlign: TextAlign.center,
              textDirection: _edition.direction,
              style: AppTheme.translation(
                size:
                    verse.translationIn(_edition).length > 200 ? 10.5 : 11.5,
                arabic: _edition.arabicScript,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Friday: the day and the door on one line, the whole verse of
/// Salawat, its meaning, and one line saying what it is.
///
/// The verse is set whole here — not the opening clause the rotation's
/// long verses are cut to — because this one verse is the card's whole
/// reason for changing its dress, and half a salawat is not one.
class _JumuahBody extends StatelessWidget {
  final QuranVerse verse;
  final VoidCallback onMake;
  final Animation<double> write;
  final Animation<double> meaning;

  const _JumuahBody({
    required this.verse,
    required this.onMake,
    required this.write,
    required this.meaning,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SealGlyph(size: 10, color: AppColors.goldBright),
            const SizedBox(width: 8),
            Flexible(
              child: GildedText(
                l.jumuahToday,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.titleMedium!.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: l.arabicScript ? 0 : 0.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _MinimalButton(label: l.makeSalawatReel, onTap: onMake),
          ],
        ),
        const SizedBox(height: 10),
        // The row above is start-aligned, so the verse and its meaning
        // are given the card's whole width by hand — a shrink-wrapped
        // block would centre its lines inside itself and still sit
        // against the left edge.
        SizedBox(
          width: double.infinity,
          child: _WrittenIn(
            progress: write,
            child: Sheen(
              period: const Duration(milliseconds: 5200),
              strength: 0.38,
              phase: 0.15,
              child: Text(
                verse.arabic,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: AppTheme.quran(
                  size: DayVerseCard.arabicSize(verse.arabic),
                  color: AppColors.goldBright,
                ).copyWith(height: 1.5),
              ),
            ),
          ),
        ),
        if (!l.ar) ...[
          const SizedBox(height: 7),
          FadeTransition(
              opacity: meaning, child: const Center(child: _Rule())),
          const SizedBox(height: 7),
          // Whole, never cut, exactly as the daily card sets its own:
          // the Salawat is long, so it takes the smaller size rather
          // than lose its ending.
          FadeTransition(
            opacity: meaning,
            child: SizedBox(
              width: double.infinity,
              child: Text(
                verse.translationIn(_edition),
                textAlign: TextAlign.center,
                textDirection: _edition.direction,
                style: AppTheme.translation(
                  size: verse.translationIn(_edition).length > 200
                      ? 10.5
                      : 11.5,
                  arabic: _edition.arabicScript,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${l.verseReference(verse.surahName, verse.startAyah, verse.endAyah)} · '
          '${l.jumuahCardBody}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.bodySmall?.copyWith(
            fontSize: 11,
            letterSpacing: 0.2,
            color: AppColors.gold.withValues(alpha: 0.75),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The one door on the Friday card: a gold-rimmed pill, lit from
/// inside, with a breath in its glow slow enough to be felt rather
/// than watched.
class _MinimalButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _MinimalButton({required this.label, required this.onTap});

  @override
  State<_MinimalButton> createState() => _MinimalButtonState();
}

class _MinimalButtonState extends State<_MinimalButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  bool _still = false;

  /// Reduce motion stops the clock, as the bloom's does; drawing the
  /// glow still at its middle while it ticks on is a repaint a frame
  /// for nothing.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    still ? _c.stop() : _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      // The glow breathes every frame; the card, and the page under it,
      // must not repaint with it.
      child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final v = still ? 0.5 : Curves.easeInOut.transform(_c.value);
          return Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  AppColors.gold.withValues(alpha: 0.22 + 0.08 * v),
                  AppColors.gold.withValues(alpha: 0.10),
                ],
              ),
              border: Border.all(
                color: AppColors.goldBright.withValues(alpha: 0.55 + 0.3 * v),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.12 + 0.16 * v),
                  blurRadius: 12 + 8 * v,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.goldBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_rounded,
                size: 14, color: AppColors.goldBright),
          ],
        ),
      ),
      ),
    );
  }
}

/// The label over the daily verse, cut as a cartouche.
class _Cartouche extends StatelessWidget {
  final String label;
  const _Cartouche({required this.label});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _CartouchePainter(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SealGlyph(size: 8),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.goldBright,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
              ),
            ),
          ],
        ),
      ),
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
        path, Paint()..color = AppColors.gold.withValues(alpha: 0.13));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = AppColors.gold.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _CartouchePainter old) => false;
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 8,
        width: 108,
        child: Row(
          children: [
            Expanded(child: OrnamentHairline(towardsEnd: false)),
            SizedBox(width: 7),
            SealGlyph(size: 6),
            SizedBox(width: 7),
            Expanded(child: OrnamentHairline(towardsEnd: true)),
          ],
        ),
      );
}

/// A slow swell of warm light behind the verse. Stronger on Friday.
class _Bloom extends StatefulWidget {
  final bool strong;
  const _Bloom({required this.strong});

  @override
  State<_Bloom> createState() => _BloomState();
}

class _BloomState extends State<_Bloom> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat(reverse: true);

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    still ? _c.stop() : _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _BloomPainter(_c, widget.strong ? 1.6 : 1.0),
          size: Size.infinite,
        ),
      );
}

class _BloomPainter extends CustomPainter {
  final Animation<double> breath;
  final double gain;
  _BloomPainter(this.breath, this.gain) : super(repaint: breath);

  @override
  void paint(Canvas canvas, Size size) {
    final v = Curves.easeInOut.transform(breath.value);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            AppColors.gold.withValues(alpha: (0.10 + 0.05 * v) * gain),
            AppColors.gold.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCenter(
          center: Offset(size.width * 0.5, size.height * 0.46),
          width: size.width * (1.45 + 0.12 * v),
          height: size.height * (1.9 + 0.2 * v),
        )),
    );
  }

  @override
  bool shouldRepaint(covariant _BloomPainter old) => old.gain != gain;
}

/// The Friday lamp: a khatam star inside two rings, rays of light
/// turning behind it on a cycle too slow to count. Tucked into the
/// card's corner and half off it, so it reads as light falling into
/// the frame rather than an icon placed on it.
class _Lamp extends StatefulWidget {
  final double size;
  const _Lamp({required this.size});

  @override
  State<_Lamp> createState() => _LampState();
}

class _LampState extends State<_Lamp> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    still ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(painter: _LampPainter(_c)),
        ),
      );
}

class _LampPainter extends CustomPainter {
  final Animation<double> turn;
  _LampPainter(this.turn) : super(repaint: turn);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final a = turn.value * 2 * math.pi;

    // Rays: twelve soft wedges, alternating in strength, turning.
    for (var i = 0; i < 12; i++) {
      final from = a + i * math.pi / 6;
      final strength = i.isEven ? 0.10 : 0.05;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..arcTo(Rect.fromCircle(center: c, radius: r), from, math.pi / 14,
              false)
          ..close(),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              AppColors.goldBright.withValues(alpha: strength),
              AppColors.gold.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // Two rings, the inner one turning against the rays.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = AppColors.gold.withValues(alpha: 0.35);
    canvas.drawCircle(c, r * 0.42, ring);
    canvas.drawPath(
      Khatam.seal(c, r * 0.34, rotation: -a * 0.5),
      ring..color = AppColors.gold.withValues(alpha: 0.5),
    );
    canvas.drawPath(
      Khatam.star(c, r * 0.16, rotation: a * 0.5),
      Paint()..color = AppColors.goldBright.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _LampPainter old) => false;
}

// ---------------------------------------------------------------------
// The card alive
// ---------------------------------------------------------------------

/// The verse written in: the letters are there from the first frame,
/// faint, and the gold flows in behind a soft front that runs the way
/// Arabic is written — from the right, and a little ahead on the upper
/// lines — with a glow riding the front while the pen is moving. Once
/// written it is the plain text again, with nothing laid over it.
class _WrittenIn extends StatelessWidget {
  final Animation<double> progress;
  final Widget child;

  const _WrittenIn({required this.progress, required this.child});

  /// The front's softness, as a share of the sweep.
  static const _soft = 0.24;

  /// The wait at the start, for the card's own entrance.
  static const _wait = Interval(0.18, 1);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final raw = progress.value;
        if (raw >= 1) return child!;
        final p = Curves.easeInOutSine.transform(_wait.transform(raw));
        final front = -_soft + p * (1 + 2 * _soft);
        final a = (front - _soft).clamp(0.0, 1.0);
        final b = front.clamp(0.0, 1.0);
        final heat = math.sin(p * math.pi);
        return Stack(
          children: [
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                begin: const Alignment(1, -0.8),
                end: const Alignment(-1, 0.8),
                colors: const [
                  Colors.white,
                  Colors.white,
                  Color(0x26FFFFFF),
                  Color(0x26FFFFFF),
                ],
                stops: [0, a, b, 1],
              ).createShader(rect),
              child: child,
            ),
            if (heat > 0.02)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _PenGlowPainter(front: b, heat: heat),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The glow riding the writing's front.
class _PenGlowPainter extends CustomPainter {
  final double front;
  final double heat;

  const _PenGlowPainter({required this.front, required this.heat});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final lo = (front - 0.07).clamp(0.0, 1.0);
    final hi = (front + 0.03).clamp(0.0, 1.0);
    if (hi <= lo) return;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: const Alignment(1, -0.8),
          end: const Alignment(-1, 0.8),
          colors: [
            AppColors.goldBright.withValues(alpha: 0),
            AppColors.goldBright.withValues(alpha: 0.30 * heat),
            AppColors.goldBright.withValues(alpha: 0),
          ],
          stops: [lo, (lo + hi) / 2, hi],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _PenGlowPainter old) =>
      old.front != front || old.heat != heat;
}

/// What lives in the card's ground: three soft lights drifting (violet,
/// sea-green and gold, low enough that the night stays night), gold
/// motes rising and twinkling, and — six days a week — an eight-pointed
/// medallion turning slowly behind the verse, half off the card's corner.
class _GroundPainter extends CustomPainter {
  final Animation<double> clock;
  final bool friday;

  _GroundPainter(this.clock, {required this.friday}) : super(repaint: clock);

  static const _lights = [
    Color(0xFF7A5CFF),
    Color(0xFF2FB6A0),
    Color(0xFFE0A93A),
  ];

  /// Sixteen motes, the same every time: where across the card each
  /// rises, how many times a turn, how big, and its place in the cycle.
  static final _motes = [
    for (var i = 0; i < 16; i++)
      () {
        final r = math.Random(i * 7919 + 13);
        return (
          x: 0.04 + r.nextDouble() * 0.92,
          laps: 1 + i % 3,
          size: 0.6 + r.nextDouble() * 1.3,
          phase: r.nextDouble(),
          sway: r.nextDouble() * 2 * math.pi,
        );
      }(),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = clock.value;
    final turn = t * 2 * math.pi;

    for (var i = 0; i < _lights.length; i++) {
      final ph = i * 2 * math.pi / _lights.length;
      final c = Offset(
        size.width * (0.5 + 0.45 * math.sin(turn + ph)),
        size.height * (0.5 + 0.5 * math.cos(turn + ph * 1.7)),
      );
      final r = size.longestSide * 0.55;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.radial(c, r, [
            _lights[i].withValues(alpha: 0.17),
            _lights[i].withValues(alpha: 0),
          ]),
      );
    }

    if (!friday) {
      final at = Offset(size.width * 0.93, size.height * 0.16);
      final r = size.height * 0.62;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = AppColors.gold.withValues(alpha: 0.075);
      canvas.drawPath(Khatam.seal(at, r, rotation: turn / 8), ring);
      canvas.drawPath(Khatam.star(at, r * 0.55, rotation: -turn / 8), ring);
      canvas.drawCircle(at, r * 0.28, ring);
    }

    for (final m in _motes) {
      final cycle = (t * m.laps + m.phase) % 1;
      final y = (1 - cycle) * (size.height + 16) - 8;
      final x = (m.x + 0.025 * math.sin(turn * 2 + m.sway)) * size.width;
      final twinkle = 0.5 + 0.5 * math.sin(turn * (3 + m.laps) + m.sway);
      // Fading in off the foot of the card and out before its top.
      final edge = math.min(1.0, math.min(cycle / 0.15, (1 - cycle) / 0.25));
      final alpha = (0.12 + 0.5 * twinkle) * edge.clamp(0.0, 1.0);
      final p = Offset(x, y);
      canvas.drawCircle(
        p,
        m.size * 3.2,
        Paint()..color = AppColors.goldBright.withValues(alpha: 0.10 * alpha),
      );
      canvas.drawCircle(
        p,
        m.size,
        Paint()
          ..color = Color.lerp(AppColors.goldBright, Colors.white, 0.35)!
              .withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GroundPainter old) =>
      old.clock != clock || old.friday != friday;
}

/// Two points of light running round the card's rim, opposite each
/// other, each trailing a fading tail: the frame lit as if a lamp were
/// carried round it.
class _RimLightPainter extends CustomPainter {
  final Animation<double> clock;
  final BorderRadius radius;
  final Color colour;

  _RimLightPainter(this.clock, {required this.radius, required this.colour})
      : super(repaint: clock);

  Size? _for;
  ui.PathMetric? _rim;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (_for != size) {
      _for = size;
      final metrics = (Path()
            ..addRRect(radius.toRRect((Offset.zero & size).deflate(0.9))))
          .computeMetrics()
          .toList();
      _rim = metrics.isEmpty ? null : metrics.first;
    }
    final rim = _rim;
    if (rim == null) return;
    final length = rim.length;
    final tail = length * 0.14;
    const steps = 7;
    for (final start in const [0.0, 0.5]) {
      final head = ((clock.value + start) % 1) * length;
      for (var j = 0; j < steps; j++) {
        final from = head - tail + tail * j / steps;
        final to = head - tail + tail * (j + 1) / steps;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = colour.withValues(alpha: 0.75 * (j + 1) / steps);
        _stroke(canvas, rim, from, to, length, paint);
      }
      final tip = rim.getTangentForOffset(head);
      if (tip != null) {
        canvas.drawCircle(tip.position, 5,
            Paint()..color = colour.withValues(alpha: 0.22));
        canvas.drawCircle(tip.position, 1.9,
            Paint()..color = Color.lerp(colour, Colors.white, 0.5)!);
      }
    }
  }

  /// A stretch of the rim from [from] to [to], either of which may have
  /// gone round past the start.
  static void _stroke(Canvas canvas, ui.PathMetric rim, double from, double to,
      double length, Paint paint) {
    if (from < 0 && to <= 0) {
      canvas.drawPath(rim.extractPath(from + length, to + length), paint);
    } else if (from < 0) {
      canvas.drawPath(rim.extractPath(from + length, length), paint);
      canvas.drawPath(rim.extractPath(0, to), paint);
    } else {
      canvas.drawPath(rim.extractPath(from, to), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RimLightPainter old) =>
      old.clock != clock || old.radius != radius || old.colour != colour;
}

/// The card leaning toward the finger that rests on it, a few degrees,
/// and swinging back when it lifts. A finger that moves off is starting
/// a scroll, and the card lets it go.
class _Lean extends StatefulWidget {
  final Widget child;
  const _Lean({required this.child});

  @override
  State<_Lean> createState() => _LeanState();
}

class _LeanState extends State<_Lean> {
  Offset? _down;

  /// Where the finger is, -1..1 each way across the card.
  Offset? _at;

  void _press(Offset p) {
    _down = p;
    _set(p);
  }

  void _move(Offset p) {
    final down = _down;
    if (down == null) return;
    if ((p - down).distance > 12) {
      _release();
      return;
    }
    _set(p);
  }

  void _set(Offset p) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    setState(() => _at = Offset(
          (p.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
          (p.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
        ));
  }

  void _release() {
    _down = null;
    if (_at != null) setState(() => _at = null);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final at = still ? Offset.zero : (_at ?? Offset.zero);
    return Listener(
      onPointerDown: (e) => _press(e.localPosition),
      onPointerMove: (e) => _move(e.localPosition),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween(end: at),
        duration: Duration(milliseconds: _at == null ? 560 : 160),
        curve: _at == null ? Curves.easeOutBack : Curves.easeOut,
        builder: (context, o, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0009)
            ..rotateX(-o.dy * 0.07)
            ..rotateY(o.dx * 0.09),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
