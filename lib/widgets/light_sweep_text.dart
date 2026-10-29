import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A line of text a band of light passes through every few seconds, in
/// reading order: the same light a reel's verse is crossed by, here to
/// draw the eye to one row (the Telegram row in Settings, the owner's
/// ask, 2026-10-27).
///
/// One pass, then a rest with nothing moving: between passes nothing
/// asks for a frame. Shown still where the platform asks for reduced
/// motion.
class LightSweepText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// The colour at the band's heart.
  final Color light;

  /// How long the band takes to cross, and the rest after it.
  final Duration pass;
  final Duration every;

  final int? maxLines;
  final TextOverflow? overflow;

  const LightSweepText({
    super.key,
    required this.text,
    required this.style,
    this.light = AppColors.goldBright,
    this.pass = const Duration(milliseconds: 1400),
    this.every = const Duration(milliseconds: 3200),
    this.maxLines,
    this.overflow,
  });

  @override
  State<LightSweepText> createState() => _LightSweepTextState();
}

class _LightSweepTextState extends State<LightSweepText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.pass);
  Timer? _next;
  bool _still = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_started && still == _still) return;
    _started = true;
    _still = still;
    _next?.cancel();
    if (still) {
      _c.stop();
      _c.value = 0;
    } else {
      // The first pass waits a moment, so the screen is in before it.
      _next = Timer(const Duration(milliseconds: 600), _run);
    }
  }

  void _run() {
    if (!mounted || _still) return;
    _c.duration = widget.pass;
    _c.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || _still) return;
      _next?.cancel();
      _next = Timer(widget.every, _run);
    });
  }

  @override
  void dispose() {
    _next?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style.color ??
        DefaultTextStyle.of(context).style.color ??
        AppColors.textPrimary;
    final text = Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
    );
    if (_still) return text;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: text,
        builder: (context, child) {
          final v = _c.value;
          // At rest (before a pass and after it) the band is off the
          // line, and the text is its own colour.
          if (v == 0 || v == 1) return child!;
          const half = 0.16;
          // From just before the line's start to just past its end.
          final at = -half + (1 + 2 * half) * Curves.easeInOut.transform(v);
          final p = rtl ? 1 - at : at;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => LinearGradient(
              colors: [base, base, widget.light, base, base],
              stops: [
                0,
                (p - half).clamp(0.0, 1.0),
                p.clamp(0.0, 1.0),
                (p + half).clamp(0.0, 1.0),
                1,
              ],
            ).createShader(rect),
            child: child,
          );
        },
      ),
    );
  }
}
