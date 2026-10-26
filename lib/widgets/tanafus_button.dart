import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'arena_fx.dart';
import 'illumination.dart';
import 'nudge_dot.dart';

/// The two doors to Tanafus that stand on the shell: a small roundel at
/// the top corner of every tab, and the floating button at the foot of
/// the three tabs that are not Settings.
///
/// Both are the same thing at two sizes — a disc of dark glass with the
/// crown of light leaning inside, a ring of the arena's light circling
/// the rim, a glint now and then — so the eye learns one shape. No words:
/// the mark is the name. A gold dot sits on the roundel's shoulder
/// until the arena has been opened once.
class TanafusButton extends StatelessWidget {
  final VoidCallback? onTap;
  const TanafusButton({super.key, this.onTap});

  /// The roundel's diameter; the home header is laid out to it.
  static const size = 36.0;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) => A11yTap(
        label: l.arenaTitle,
        hint: l.a11yOpensArena,
        value: s.arenaSeen ? null : l.a11yNew,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _Roundel(size: size, onTap: onTap),
            PositionedDirectional(
              top: -2,
              end: -2,
              child: NudgeDot(on: !s.arenaSeen, size: 8),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating door, where the invitation stands on Settings.
class TanafusFab extends StatelessWidget {
  final VoidCallback? onTap;
  const TanafusFab({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return A11yTap(
      label: l.arenaTitle,
      hint: l.a11yOpensArena,
      onTap: onTap,
      child: _Roundel(size: 48, onTap: onTap, breathe: true),
    );
  }
}

class _Roundel extends StatefulWidget {
  final double size;
  final VoidCallback? onTap;
  final bool breathe;
  const _Roundel({required this.size, this.onTap, this.breathe = false});

  @override
  State<_Roundel> createState() => _RoundelState();
}

class _RoundelState extends State<_Roundel>
    with SingleTickerProviderStateMixin {
  /// One clock: the ring's light makes a turn in seven seconds, and so
  /// does the light on the crown's thread.
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();
  final _glint = GlintController();
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reducedMotion(context);
    if (still == _still) return;
    _still = still;
    still ? _turn.stop() : _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    _glint.dispose();
    super.dispose();
  }

  void _tap() {
    HapticFeedback.mediumImpact();
    _glint.fire();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size;
    return Pressable(
      onTap: _tap,
      scale: 0.92,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, child) {
            final v = _turn.value;
            final breath = widget.breathe && !_still
                ? 1 + 0.035 * math.sin(v * 2 * math.pi)
                : 1.0;
            return Transform.scale(scale: breath, child: child);
          },
          child: SizedBox(
            width: d,
            height: d,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // The halo on the wall behind.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _HaloPainter(_turn)),
                  ),
                ),
                Glint(
                  controller: _glint,
                  every: const Duration(milliseconds: 5200),
                  strength: 0.7,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF1E2636).withValues(alpha: 0.72),
                              AppColors.bg.withValues(alpha: 0.9),
                            ],
                          ),
                        ),
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _turn,
                            // The crown leans a little as the light
                            // goes round it, so it stands in the glass
                            // rather than being printed on it.
                            builder: (context, _) {
                              final v = _turn.value * 2 * math.pi;
                              return Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.0022)
                                  ..rotateY(_still ? 0 : 0.26 * math.sin(v))
                                  ..rotateX(
                                      _still ? 0 : 0.12 * math.sin(v * 2 + 1)),
                                child: TanafusMark(
                                  size: d * 0.64,
                                  phase: _still ? 0 : _turn.value,
                                  glow: d >= 48,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The ring of light going round the rim.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _RimPainter(_turn)),
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

/// The glow the door throws on the wall behind it, breathing with the
/// ring.
class _HaloPainter extends CustomPainter {
  final Animation<double> turn;
  _HaloPainter(this.turn) : super(repaint: turn);

  @override
  void paint(Canvas canvas, Size size) {
    final b = 0.5 + 0.5 * math.sin(turn.value * 2 * math.pi);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      size.center(Offset.zero),
      r * 0.92,
      Paint()
        ..color = AppColors.gold.withValues(alpha: 0.24 + 0.14 * b)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, r * 0.5 + r * 0.2 * b),
    );
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) => false;
}

/// A quiet gold rim, and the arena's light going round it.
class _RimPainter extends CustomPainter {
  final Animation<double> turn;
  _RimPainter(this.turn) : super(repaint: turn);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 0.8;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.gold.withValues(alpha: 0.38),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = SweepGradient(
          colors: [
            Colors.transparent,
            ArenaPalette.teal.withValues(alpha: 0.55),
            AppColors.goldBright,
            ArenaPalette.rose.withValues(alpha: 0.55),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0, 0.08, 0.16, 0.24, 0.34, 1],
          transform: GradientRotation(turn.value * 2 * math.pi),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) => false;
}

/// Marks the arena as opened once, which puts the roundel's dot out.
Future<void> markArenaSeen() async {
  final s = SettingsService.state.value;
  if (s.arenaSeen) return;
  await SettingsService.update(s.copyWith(arenaSeen: true));
}
