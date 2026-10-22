import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// The one glowing CTA per screen. Gold, breathing glow, full-width.
/// Everything else on a screen must be visually quieter than this.
class GlowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  /// 0..1 while [busy], when the wait has a measurable end. Null keeps
  /// the indeterminate spinner — which, on a wait long enough to doubt,
  /// is indistinguishable from a button that has stopped responding.
  final double? busyProgress;

  /// Adds a scale pop in step with the glow — reserved for the one
  /// hero CTA of a screen (Home's Create, Preview's Share). Every other
  /// button stays still.
  final bool breathe;

  /// Multiplier on how fast the glow breathes. 1.0 is the house rate;
  /// above it the button is a little more insistent, for the CTA a
  /// screen exists to get tapped.
  final double pulseSpeed;

  /// Overall height. The default is the full-weight CTA; a screen
  /// already carrying its own controls runs a shorter one.
  final double height;

  /// Tighter padding, a smaller glyph and a smaller label, for a button
  /// sharing its row with another. The full-width one keeps M3's
  /// generous sides; at half a phone's width those alone would eat the
  /// label.
  final bool dense;

  const GlowButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.busyProgress,
    this.breathe = false,
    this.pulseSpeed = 1.0,
    this.height = 58,
    this.dense = false,
  });

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton>
    with SingleTickerProviderStateMixin {
  static const _basePulseMs = 1800;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration:
        Duration(milliseconds: (_basePulseMs / widget.pulseSpeed).round()),
  )..repeat(reverse: true);

  bool _still = false;

  /// Reduce motion holds the glow steady at half strength instead of
  /// breathing.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _pulse.value = 0.5; // setting the value stops the controller
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant GlowButton old) {
    super.didUpdateWidget(old);
    if (old.pulseSpeed == widget.pulseSpeed) return;
    _pulse.duration =
        Duration(milliseconds: (_basePulseMs / widget.pulseSpeed).round());
    if (!_still) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    // The glow repaints every frame; nothing else on the screen should
    // be re-rastered with it. Without this boundary the pulse was
    // repainting the whole page under it — the preview's scenery, a
    // list of verses, the scenery grid — sixty times a second.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          // Eased rather than linear: the swell holds at the top and at
          // the bottom, which is what makes it read as a pop instead of
          // a sine wave.
          final eased = Curves.easeInOut.transform(_pulse.value);
          final glow =
              enabled ? 0.25 + (widget.breathe ? 0.30 : 0.20) * eased : 0.0;
          final scale = enabled && widget.breathe ? 1.0 + 0.032 * eased : 1.0;
          // A plain DecoratedBox, not an AnimatedContainer: this builder
          // runs once a frame, and an implicit animation restarted every
          // frame never finishes and costs a tween per tick for nothing.
          return Transform.scale(
            scale: scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  if (enabled)
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: glow),
                      blurRadius: 28,
                      spreadRadius: 1,
                    ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: _button(context),
      ),
    );
  }

  /// The button itself, built once per rebuild rather than once per
  /// frame of the glow.
  Widget _button(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: FilledButton(
          onPressed: enabled ? widget.onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            disabledBackgroundColor: AppColors.surfaceRaised,
            foregroundColor: const Color(0xFF14100A),
            padding: widget.dense
                ? const EdgeInsets.symmetric(horizontal: 10)
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: widget.busy
              // The spinner replaces the words, so a screen reader
              // would otherwise find a dimmed button with no name.
              // It keeps the name, and says how far along it is when
              // that is known.
              ? Semantics(
                  label: L10n.of(context).a11yBusy(widget.label),
                  value: widget.busyProgress == null
                      ? null
                      : '${(widget.busyProgress! * 100).round()}%',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      value: widget.busyProgress,
                      color: const Color(0xFF14100A),
                      // Only under a determinate value: an unfilled
                      // track behind the sweep is what makes the fill
                      // legible.
                      backgroundColor: widget.busyProgress == null
                          ? null
                          : const Color(0x3314100A),
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: widget.dense ? 18 : 22),
                      SizedBox(width: widget.dense ? 7 : 10),
                    ],
                    // Flexible so a long label or a large accessibility
                    // text scale clips instead of bursting the button.
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontSize: widget.dense ? 14 : null,
                            ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

/// The deliberately quiet secondary action that sits beside/below the
/// glowing one.
class QuietButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// Tighter, on a screen already carrying more controls than it wants
  /// to. The touch target is untouched — only the paint shrinks.
  final bool dense;

  const QuietButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return TextButton.icon(
      onPressed: onPressed,
      style: dense
          ? TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              visualDensity: VisualDensity.compact,
            )
          : null,
      icon: icon != null
          ? Icon(icon, size: dense ? 15 : 18, color: AppColors.textSecondary)
          : const SizedBox.shrink(),
      label: Text(
        label,
        style: (dense ? t.bodySmall : t.bodyMedium)
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
