import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/glow_button.dart';
import '../widgets/illumination.dart';
import '../widgets/night_sky.dart';
import '../widgets/shimmer_text.dart';
import 'series_setup_screen.dart';

/// The first page of a series: what it is, in one breath, before a
/// single choice is asked for.
///
/// A row of seven lamps lighting one after another does most of the
/// explaining — that is the whole idea, a surah becoming a day at a
/// time — and the headline says the rest. One door out, at the bottom.
class SeriesIntroScreen extends StatelessWidget {
  const SeriesIntroScreen({super.key});

  void _begin(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SeriesSetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
      ),
      body: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 340,
            child: ExcludeSemantics(
                child: IgnorePointer(child: Starfield(count: 40))),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  const Center(child: _StreakPreview()),
                  const Spacer(),
                  Text(
                    l.seriesIntroLabel,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.gold,
                      fontSize: 11,
                      letterSpacing: l.arabicScript ? 0 : 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  A11yHeader(
                    child: ShimmerText(
                      text: l.seriesIntroHeadline,
                      style: t.headlineMedium!.copyWith(
                        fontSize: 27,
                        height: 1.24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: l.arabicScript ? 0 : -0.7,
                      ),
                      textAlign: TextAlign.start,
                      perWord: const Duration(milliseconds: 260),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(
                    width: 120,
                    child: OrnamentHairline(towardsEnd: true),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.seriesIntroBody,
                    style: t.bodyMedium?.copyWith(height: 1.55),
                  ),
                  const Spacer(flex: 2),
                  GlowButton(
                    label: l.seriesIntroBegin,
                    icon: Icons.calendar_month_rounded,
                    breathe: true,
                    onPressed: () => _begin(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven lamps in a row, lighting one after another and then resting
/// dark for a beat before starting again: a series, watched happen.
class _StreakPreview extends StatefulWidget {
  const _StreakPreview();

  @override
  State<_StreakPreview> createState() => _StreakPreviewState();
}

class _StreakPreviewState extends State<_StreakPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7200),
  )..repeat();

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _c.stop();
      _c.value = 0.8; // all lit, at rest
    } else {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A picture of the idea, so it is described as one.
    return Semantics(
      image: true,
      label: L10n.of(context).a11ySeriesPreview,
      child: RepaintBoundary(
        child: SizedBox(
          width: 300,
          height: 92,
          child: CustomPaint(painter: _StreakPainter(_c)),
        ),
      ),
    );
  }
}

class _StreakPainter extends CustomPainter {
  final Animation<double> t;
  _StreakPainter(this.t) : super(repaint: t);

  static const _days = 7;

  /// The day numbers, shaped once each. A TextPainter laid out per lamp
  /// per frame was seven text layouts sixty times a second for glyphs
  /// that never change; the painter lives as long as the widget, so
  /// the layouts do too.
  final Map<int, TextPainter> _labels = {};

  TextPainter _label(int day, bool lit) =>
      _labels.putIfAbsent(day * 2 + (lit ? 1 : 0), () {
        return TextPainter(
          text: TextSpan(
            text: '$day',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: lit ? const Color(0xFF14100A) : AppColors.textSecondary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });

  @override
  void paint(Canvas canvas, Size size) {
    // The first 80% lights the lamps in turn; the last 20% holds them
    // lit, then everything goes dark and starts over.
    final v = t.value;
    final lit = v < 0.8 ? (v / 0.8 * _days) : _days.toDouble();
    final gap = size.width / _days;
    final r = gap * 0.30;
    final cy = size.height * 0.46;

    // The thread first, under the lamps.
    for (var i = 0; i < _days - 1; i++) {
      final from = Offset(gap * (i + 0.5) + r, cy);
      final to = Offset(gap * (i + 1.5) - r, cy);
      final on = lit >= i + 1.5;
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = 1
          ..color = on
              ? AppColors.gold.withValues(alpha: 0.9)
              : AppColors.stroke,
      );
    }

    for (var i = 0; i < _days; i++) {
      final c = Offset(gap * (i + 0.5), cy);
      final seal = Khatam.seal(c, r);
      // How lit this lamp is: 0 dark, 1 full, with a short swell as it
      // arrives.
      final k = (lit - i).clamp(0.0, 1.0);
      if (k > 0) {
        final swell = k < 1 ? 1 + 0.18 * (1 - (k * 2 - 1).abs()) : 1.0;
        canvas.drawPath(
          Khatam.seal(c, r * swell),
          Paint()
            ..color = AppColors.gold.withValues(alpha: 0.35 * k)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
        );
        canvas.drawPath(
          Khatam.seal(c, r * swell),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(AppColors.surface, AppColors.goldBright, k)!,
                Color.lerp(AppColors.surface, AppColors.gold, k)!,
              ],
            ).createShader(Rect.fromCircle(center: c, radius: r)),
        );
      } else {
        canvas.drawPath(seal, Paint()..color = AppColors.surface);
      }
      canvas.drawPath(
        seal,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = k > 0
              ? AppColors.goldBright.withValues(alpha: 0.6)
              : AppColors.stroke,
      );
      // The day's number.
      final tp = _label(i + 1, k > 0.5);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _StreakPainter old) => false;
}
