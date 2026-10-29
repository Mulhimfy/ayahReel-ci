import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../screens/arena_screen.dart' show openArena;
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'arena_fx.dart';
import 'illumination.dart';
import 'night_sky.dart';
import 'ambient_pace.dart';

/// The Cards tab's door into the arena: it opens the lobby, exactly as
/// the roundel at the top of every tab does, where the round is chosen
/// and begun.
///
/// A pane of the arena's own weather — the mesh moving under dark
/// glass, a few stars, a faint lattice — with the crown leaning at its
/// head, a still gold rim, and a glint now and then: the
/// most alive thing on the tab, because it is the thing the tab most
/// wants tapped. All of it stands still under reduced motion.
class ArenaPortal extends StatefulWidget {
  const ArenaPortal({super.key});

  static const height = 86.0;
  static const radius = 24.0;

  @override
  State<ArenaPortal> createState() => _ArenaPortalState();
}

class _ArenaPortalState extends State<ArenaPortal>
    with AmbientTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: ambient,
    duration: const Duration(seconds: 6),
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

  void _go() {
    HapticFeedback.mediumImpact();
    _glint.fire();
    unawaited(openArena(context));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const r = ArenaPortal.radius;
    return A11yTap(
          label: l.arenaEnter,
          hint: l.a11yOpensArena,
          onTap: _go,
          child: Pressable(
            onTap: _go,
            scale: 0.975,
            child: AnimatedBuilder(
              animation: _turn,
              builder: (context, child) {
                final breath = _still
                    ? 1.0
                    : 1 + 0.012 * math.sin(_turn.value * 2 * math.pi);
                return Transform.scale(scale: breath, child: child);
              },
              child: Container(
                height: ArenaPortal.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(r),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.22),
                      blurRadius: 30,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // The arena's colours, plainly, under the weather:
                      // the mesh alone is too soft to read as colour on
                      // a pane this small.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF2B3399),
                              Color(0xFF5E2C9C),
                              Color(0xFF1A6F86),
                              Color(0xFF8A2B5C),
                            ],
                            stops: [0, 0.38, 0.72, 1],
                          ),
                        ),
                      ),
                      const MeshBackdrop(alpha: 1, speed: 1.4, seed: 5),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF0B0F18).withValues(alpha: 0.10),
                              AppColors.bg.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                      const IgnorePointer(
                          child: Starfield(count: 26, seed: 4, fade: false)),
                      const IgnorePointer(
                          child: CustomPaint(painter: _LatticePainter())),
                      TouchLight(
                        radius: BorderRadius.circular(r),
                        child: Glint(
                          controller: _glint,
                          every: const Duration(milliseconds: 4600),
                          strength: 0.8,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16, 0, 14, 0),
                            child: Row(
                              children: [
                                // The crown, in a small glass roundel.
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.bg.withValues(alpha: 0.55),
                                    border: Border.all(
                                        color: AppColors.gold
                                            .withValues(alpha: 0.45)),
                                  ),
                                  child: Center(
                                    child: AnimatedBuilder(
                                      animation: _turn,
                                      builder: (context, _) => TanafusMark(
                                        size: 30,
                                        phase: _still ? 0 : _turn.value,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      GildedText(
                                        l.arenaEnter,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        l.arenaEnterHint,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            height: 1.25,
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // The rim: a still gold line (its two chasing
                      // lights went, 2026-10-26, the owner's call).
                      const IgnorePointer(
                        child: CustomPaint(painter: _RimPainter(r)),
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

/// A faint khatam lattice over the weather: the illuminated page under
/// the glass.
class _LatticePainter extends CustomPainter {
  const _LatticePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Khatam.lattice(size, 26, bleed: 6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = AppColors.gold.withValues(alpha: 0.07),
    );
  }

  @override
  bool shouldRepaint(covariant _LatticePainter old) => false;
}

/// The pane's gold rim.
class _RimPainter extends CustomPainter {
  final double radius;
  const _RimPainter(this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.8);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.gold.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) => old.radius != radius;
}
