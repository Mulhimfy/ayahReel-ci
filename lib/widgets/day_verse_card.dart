import 'dart:async';
import 'dart:math' as math;

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
    with WidgetsBindingObserver {
  Timer? _turn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armTurn();
    _refreshInstalled();
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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(L10n.of(context)
          .widgetBadgeEarned(RewardsService.pointsForWidget)),
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
      if (mounted) setState(_armTurn);
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
                        verse: v, onMake: () => startVerseReel(context, v))
                    : _DailyBody(verse: v),
              ),
              Positioned.fill(
                child: IlluminatedBorder(
                  radius: DayVerseCard.radius,
                  sealSize: 0,
                  color: jumuah ? AppColors.goldBright : AppColors.gold,
                ),
              ),
            ],
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
  const _DailyBody({required this.verse});

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
        Sheen(
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
        if (!l.ar) ...[
          const SizedBox(height: 7),
          const _Rule(),
          const SizedBox(height: 7),
          // Whole, never cut: a translation that ends in three dots is
          // a promise the card did not keep. The few long verses in
          // the rotation — Ayat al-Kursi, the last of Al-Baqarah —
          // step the type down a size rather than lose their ending.
          Text(
            verse.translationIn(_edition),
            textAlign: TextAlign.center,
            textDirection: _edition.direction,
            style: AppTheme.translation(
              size: verse.translationIn(_edition).length > 200 ? 10.5 : 11.5,
              arabic: _edition.arabicScript,
              color: AppColors.textSecondary,
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
  const _JumuahBody({required this.verse, required this.onMake});

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
        if (!l.ar) ...[
          const SizedBox(height: 7),
          const Center(child: _Rule()),
          const SizedBox(height: 7),
          // Whole, never cut, exactly as the daily card sets its own:
          // the Salawat is long, so it takes the smaller size rather
          // than lose its ending.
          SizedBox(
            width: double.infinity,
            child: Text(
              verse.translationIn(_edition),
              textAlign: TextAlign.center,
              textDirection: _edition.direction,
              style: AppTheme.translation(
                size: verse.translationIn(_edition).length > 200 ? 10.5 : 11.5,
                arabic: _edition.arabicScript,
                color: AppColors.textSecondary,
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
