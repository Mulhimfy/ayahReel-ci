import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'ambient_pace.dart';

/// Text whose words light up one after another in an endless, unhurried
/// wave — the first word, then the second, then the third, and around
/// again with a short breath in between.
///
/// The light is a smooth swell rather than a hard on/off, so at any
/// instant two or three neighbouring words share it and the line reads
/// as breathing, not blinking. Deliberately slow: this sits under
/// recitation, never over it.
///
/// Reserved for the two lines that carry the app's promise — the Create
/// card headline and the line the user reads while their reel encodes.
/// Used anywhere else it stops meaning anything.
class ShimmerText extends StatefulWidget {
  final String text;

  /// The resting style. Its colour is the colour a word returns to;
  /// if it has none, the ambient text colour is used.
  final TextStyle style;

  /// The colour a word reaches at the peak of the wave.
  final Color highlight;

  final TextAlign textAlign;

  /// Time between one word's peak and the next word's peak.
  final Duration perWord;

  /// The quiet beat after the last word, before the wave starts over.
  /// Kept at or above the swell width so the loop has no visible seam.
  final Duration restBetweenPasses;

  /// Strength of the soft halo at a word's peak, 0–1.
  final double glow;

  const ShimmerText({
    super.key,
    required this.text,
    required this.style,
    this.highlight = AppColors.goldBright,
    this.textAlign = TextAlign.center,
    this.perWord = const Duration(milliseconds: 260),
    this.restBetweenPasses = const Duration(milliseconds: 1200),
    this.glow = 0.55,
  });

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with AmbientTickerProviderStateMixin {
  late List<String> _words = _split(widget.text);
  late final AnimationController _c =
      AnimationController(vsync: ambient, duration: _cycle())..repeat();

  /// True when the platform asks for reduced motion: the line is then
  /// shown at rest, fully legible, and the ticker is parked.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still == _still) return;
    _still = still;
    if (still) {
      _c.stop();
    } else {
      _c.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ShimmerText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text &&
        old.perWord == widget.perWord &&
        old.restBetweenPasses == widget.restBetweenPasses) {
      return;
    }
    _words = _split(widget.text);
    _c.duration = _cycle();
    if (!_still) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static List<String> _split(String s) =>
      s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  Duration _cycle() => Duration(
        milliseconds: _words.length * widget.perWord.inMilliseconds +
            widget.restBetweenPasses.inMilliseconds,
      );

  @override
  Widget build(BuildContext context) {
    if (_still || _words.isEmpty) {
      return Text(widget.text,
          textAlign: widget.textAlign, style: widget.style);
    }

    final base = widget.style.color ??
        DefaultTextStyle.of(context).style.color ??
        AppColors.textPrimary;
    final step = widget.perWord.inMilliseconds.toDouble();
    // Wider than one step, so neighbours overlap and the light travels
    // as a swell instead of hopping between words.
    final spread = step * 1.6;
    final total = _c.duration!.inMilliseconds.toDouble();

    // The wave repaints every frame; the rest of the card must not.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final phase = _c.value * total;
          return Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < _words.length; i++)
                  TextSpan(
                    // The trailing space belongs to the span so the
                    // line still wraps exactly where a plain Text would.
                    text: i == _words.length - 1
                        ? _words[i]
                        : '${_words[i]} ',
                    style: _styleAt(phase - i * step, spread, base),
                  ),
              ],
            ),
            textAlign: widget.textAlign,
            style: widget.style,
          );
        },
      ),
    );
  }

  /// [delta] is milliseconds since this word's own peak — negative
  /// before it, positive after.
  TextStyle _styleAt(double delta, double spread, Color base) {
    final t = (1 - delta.abs() / spread).clamp(0.0, 1.0);
    if (t == 0) return widget.style;
    final heat = Curves.easeInOut.transform(t);
    return widget.style.copyWith(
      color: Color.lerp(base, widget.highlight, heat),
      shadows: [
        Shadow(
          color: widget.highlight.withValues(alpha: widget.glow * heat),
          blurRadius: 16 * heat,
        ),
      ],
    );
  }
}
