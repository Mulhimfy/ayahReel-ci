import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'illumination.dart' show SealGlyph;

/// What a toast is saying, which decides its mark: something finished
/// (a gold coin with a check), something to know (the app's seal), or
/// something that did not work (a warm warning).
enum ToastTone { info, done, problem }

/// The app's one notice at the foot of the screen — "Saved to your
/// gallery", "Code copied", "Couldn't open the store".
///
/// Every message the app used to put in a flat grey bar comes through
/// here. It is still a [SnackBar], so the messenger queues it, times it
/// and reads it out exactly as before; what changes is the thing that
/// arrives. A piece of dark glass that turns up off the bottom edge and
/// settles flat, a line of light run across it once as it lands, a mark
/// on its leading edge that says at a glance how the news is, and the
/// one action, when there is one, inside it.
SnackBar toast(
  String message, {
  ToastTone tone = ToastTone.info,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    clipBehavior: Clip.none,
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
    duration: duration,
    content: AppToast(
      message: message,
      tone: tone,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

/// The toast's body, public for the odd place that shows one outside a
/// messenger — and for tests.
class AppToast extends StatefulWidget {
  final String message;
  final ToastTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppToast({
    super.key,
    required this.message,
    this.tone = ToastTone.info,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  static const _land = Interval(0, 0.36);
  static const _coin = Interval(0.18, 0.52, curve: Curves.elasticOut);
  static const _glint = Interval(0.34, 0.86, curve: Curves.easeInOutSine);

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Color get _accent => switch (widget.tone) {
        ToastTone.done => AppColors.gold,
        ToastTone.info => const Color(0xFFB9C2CE),
        ToastTone.problem => const Color(0xFFF0906F),
      };

  void _act() {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.maybeOf(context)
        ?.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
    widget.onAction?.call();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(18);
    final hasAction = widget.actionLabel != null && widget.onAction != null;

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF28313F), Color(0xFF171D26)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: _accent.withValues(alpha: 0.16),
            blurRadius: 26,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                  12, 11, hasAction ? 8 : 18, 11),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _in,
                    builder: (context, child) => Transform.scale(
                      scale: still ? 1 : _coin.transform(_in.value),
                      child: child,
                    ),
                    child: _Mark(tone: widget.tone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.32,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (hasAction) ...[
                    const SizedBox(width: 8),
                    _Action(label: widget.actionLabel!, onTap: _act),
                  ],
                ],
              ),
            ),
            // The bevel: light along the top edge, so the glass has a
            // thickness rather than an outline.
            Positioned(
              top: 0,
              left: 20,
              right: 20,
              child: IgnorePointer(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
            ),
            // One run of light across it as it lands.
            if (!still)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _in,
                    builder: (context, _) {
                      final p = _glint.transform(_in.value);
                      if (p <= 0 || p >= 1) return const SizedBox.shrink();
                      final x = -1.8 + 3.6 * p;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(x - 0.5, -1),
                            end: Alignment(x + 0.5, 1),
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              _accent.withValues(alpha: 0.13),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (still) return card;
    // Turned up off the bottom edge and laid flat, with a little give
    // at the end — paper landing, not a panel sliding.
    return AnimatedBuilder(
      animation: _in,
      builder: (context, child) {
        final raw = _land.transform(_in.value);
        final t = Curves.easeOutBack.transform(raw);
        final lift = 1 - t;
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..translateByDouble(0, 26 * lift, 0, 1)
          ..rotateX(0.95 * lift)
          ..scaleByDouble(0.94 + 0.06 * t, 0.94 + 0.06 * t, 1, 1);
        return Opacity(
          opacity: Curves.easeOut.transform(raw),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: m,
            child: child,
          ),
        );
      },
      child: card,
    );
  }
}

/// The mark on the toast's leading edge.
class _Mark extends StatelessWidget {
  final ToastTone tone;
  const _Mark({required this.tone});

  @override
  Widget build(BuildContext context) {
    return switch (tone) {
      ToastTone.done => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFEDB8), AppColors.gold, Color(0xFFB0832F)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.5),
                blurRadius: 12,
              ),
            ],
          ),
          child: const Icon(Icons.check_rounded,
              size: 18, color: Color(0xFF14100A)),
        ),
      ToastTone.info => Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
          ),
          child: const SealGlyph(size: 12, color: AppColors.goldBright),
        ),
      ToastTone.problem => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFF0906F).withValues(alpha: 0.14),
            border: Border.all(
                color: const Color(0xFFF0906F).withValues(alpha: 0.55)),
          ),
          child: const Icon(Icons.error_outline_rounded,
              size: 17, color: Color(0xFFF6B39B)),
        ),
    };
  }
}

/// The toast's one action, set inside it as a small gold pill.
class _Action extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Action({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.gold.withValues(alpha: 0.12),
      shape: StadiumBorder(
          side: BorderSide(color: AppColors.gold.withValues(alpha: 0.4))),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.goldBright,
            ),
          ),
        ),
      ),
    );
  }
}
