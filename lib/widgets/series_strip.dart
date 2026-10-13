import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/series_library.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'illumination.dart';

/// The days of a series, in a row, lit as far as they are done.
///
/// Every day is a small lamp: unlit it is an outline with its number
/// in it, lit it fills with gold and glows. A gold thread runs through
/// the row and is lit up to the last finished day, so the streak reads
/// as one line being drawn rather than as a set of ticks. The day the
/// user is on carries a slow ring of light, so the next thing to do is
/// never in doubt.
///
/// Days light up on their own as their reels are exported, and a long
/// press lights one by hand — the same gesture takes a hand-lit one
/// back off. Both are the series' own bookkeeping; this only draws it.
class SeriesStrip extends StatefulWidget {
  final ReelSeries series;

  /// The day whose reels are open below, if the strip is on the series
  /// screen; the home screen has no such day.
  final int? selectedDay;
  final ValueChanged<int>? onTapDay;
  final ValueChanged<int>? onLongPressDay;

  /// The home strip, which has less room: smaller lamps, no labels
  /// beyond the number, and its own padding.
  final bool compact;

  const SeriesStrip({
    super.key,
    required this.series,
    this.selectedDay,
    this.onTapDay,
    this.onLongPressDay,
    this.compact = false,
  });

  @override
  State<SeriesStrip> createState() => _SeriesStripState();
}

class _SeriesStripState extends State<SeriesStrip> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Open on the day that matters — today's, or the first unfinished
    // — rather than on day one of a month-long series.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealFocus());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealFocus() {
    if (!mounted || !_scroll.hasClients) return;
    final s = widget.series;
    final focus = widget.selectedDay ?? s.nextDay ?? s.todayIndex(DateTime.now());
    final lamp = widget.compact ? _compactLamp : _lamp;
    final gap = widget.compact ? _compactGap : _gap;
    final x = (focus - 1) * (lamp + gap) - lamp * 1.5;
    _scroll.jumpTo(x.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  static const _lamp = 54.0;
  static const _gap = 14.0;
  static const _compactLamp = 40.0;
  static const _compactGap = 10.0;

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    final today = s.todayIndex(DateTime.now());
    final lamp = widget.compact ? _compactLamp : _lamp;
    final gap = widget.compact ? _compactGap : _gap;
    return SizedBox(
      height: widget.compact ? 58 : 84,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 22 : 24),
        physics: const BouncingScrollPhysics(),
        itemCount: s.days,
        itemBuilder: (context, i) {
          final day = i + 1;
          return SizedBox(
            width: lamp + (i == s.days - 1 ? 0 : gap),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The thread to the next lamp, lit when both its ends
                // are.
                if (i < s.days - 1)
                  Positioned(
                    left: lamp,
                    width: gap,
                    top: lamp / 2 - 0.5,
                    child: _Thread(
                        lit: s.isDayDone(day) && s.isDayDone(day + 1)),
                  ),
                _DayLamp(
                  day: day,
                  size: lamp,
                  done: s.isDayDone(day),
                  today: day == today && !s.finished,
                  selected: widget.selectedDay == day,
                  reels: s.reelsOn(day).length,
                  reelsDone: s.reelsOn(day).where((r) => r.done).length,
                  compact: widget.compact,
                  onTap: widget.onTapDay == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          widget.onTapDay!(day);
                        },
                  onLongPress: widget.onLongPressDay == null
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          widget.onLongPressDay!(day);
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Thread extends StatelessWidget {
  final bool lit;
  const _Thread({required this.lit});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: lit
              ? [
                  AppColors.gold.withValues(alpha: 0.9),
                  AppColors.goldBright.withValues(alpha: 0.9),
                ]
              : [
                  AppColors.stroke.withValues(alpha: 0.9),
                  AppColors.stroke.withValues(alpha: 0.9),
                ],
        ),
        boxShadow: lit
            ? [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
    );
  }
}

/// One day.
class _DayLamp extends StatefulWidget {
  final int day;
  final double size;
  final bool done;
  final bool today;
  final bool selected;
  final int reels;
  final int reelsDone;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DayLamp({
    required this.day,
    required this.size,
    required this.done,
    required this.today,
    required this.selected,
    required this.reels,
    required this.reelsDone,
    required this.compact,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_DayLamp> createState() => _DayLampState();
}

class _DayLampState extends State<_DayLamp>
    with SingleTickerProviderStateMixin {
  /// The ring of light on today's lamp, and the swell when a day
  /// lights up.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool _still = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant _DayLamp old) {
    super.didUpdateWidget(old);
    if (old.today != widget.today) _sync();
  }

  void _sync() {
    if (widget.today && !_still) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final size = widget.size;
    final done = widget.done;
    final partial = !done && widget.reelsDone > 0;
    // One node per day, said whole: which day, whether it is today,
    // how far it has got. The number painted in the lamp is not read
    // again after it, and the long press is spelled out, since it is
    // the one way a reader has to mark a day by hand.
    return Semantics(
      container: true,
      button: widget.onTap != null,
      selected: widget.selected ? true : null,
      label: l.a11yDayLamp(
        widget.day,
        done: done,
        today: widget.today,
        reelsDone: widget.reelsDone,
        reels: widget.reels,
      ),
      hint: widget.onLongPress == null ? null : l.a11yHoldToMarkDone,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Today's ring breathes every frame, with a blur on it;
              // the strip and the page around it stay put.
              RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final v = Curves.easeInOut.transform(_c.value);
                  return SizedBox(
                    width: size,
                    height: size,
                    child: CustomPaint(
                      painter: _LampPainter(
                        done: done,
                        today: widget.today,
                        selected: widget.selected,
                        ring: v,
                        partial: partial
                            ? widget.reelsDone / math.max(1, widget.reels)
                            : 0,
                      ),
                      child: child,
                    ),
                  );
                },
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 400),
                    style: t.titleMedium!.copyWith(
                      fontSize: widget.compact ? 14 : 17,
                      fontWeight: FontWeight.w700,
                      color: done
                          ? const Color(0xFF14100A)
                          : widget.today || widget.selected
                              ? AppColors.goldBright
                              : AppColors.textSecondary,
                    ),
                    child: Text('${widget.day}'),
                  ),
                ),
              ),
              ),
              if (!widget.compact) ...[
                const SizedBox(height: 6),
                Text(
                  widget.today ? l.today : l.dayN(widget.day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(
                    fontSize: 10.5,
                    letterSpacing: 0.2,
                    fontWeight:
                        widget.today ? FontWeight.w700 : FontWeight.w500,
                    color: done || widget.today
                        ? AppColors.gold
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LampPainter extends CustomPainter {
  final bool done;
  final bool today;
  final bool selected;

  /// 0..1 breath of today's ring.
  final double ring;

  /// Share of the day's reels done, when some but not all are.
  final double partial;

  const _LampPainter({
    required this.done,
    required this.today,
    required this.selected,
    required this.ring,
    required this.partial,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 3;
    final seal = Khatam.seal(c, r);

    if (done) {
      // Lit: the seal filled with gold, glowing.
      canvas.drawPath(
        seal,
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        seal,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.goldBright, AppColors.gold],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      return;
    }

    // Unlit: an outline, the inside barely there.
    canvas.drawPath(
      seal,
      Paint()
        ..color = (selected ? AppColors.gold : AppColors.surface)
            .withValues(alpha: selected ? 0.14 : 0.9),
    );
    if (partial > 0) {
      // Part of the day made: a wedge of gold, as far as it got.
      canvas.save();
      canvas.clipPath(seal);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 1.5),
        -math.pi / 2,
        2 * math.pi * partial,
        true,
        Paint()..color = AppColors.gold.withValues(alpha: 0.22),
      );
      canvas.restore();
    }
    canvas.drawPath(
      seal,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected || today ? 1.4 : 1
        ..color = selected || today
            ? AppColors.gold.withValues(alpha: 0.85)
            : AppColors.stroke,
    );
    if (today) {
      // The ring of light: a soft halo that breathes.
      canvas.drawPath(
        Khatam.seal(c, r + 1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 2 * ring
          ..color = AppColors.gold.withValues(alpha: 0.18 + 0.28 * ring)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 3 * ring),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LampPainter old) =>
      old.done != done ||
      old.today != today ||
      old.selected != selected ||
      old.ring != ring ||
      old.partial != partial;
}
