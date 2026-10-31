import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_theme.dart';
import 'glass_tile.dart' show paintSparkle;
import 'illumination.dart';

/// A name written in gold the first time it is shown.
///
/// The letters are on the page from the first frame — tooled into it
/// but not yet gilded, a dim gold that already reads — and a point of
/// light travels along them laying the gold in behind it: white-hot
/// where the light is, cooling to beaten gold a little way back. At
/// the end of the word the light lifts off the last letter's tip and
/// goes out in a glint. A gilder's order of work, in a second and a
/// half, once per showing.
///
/// After that it is the name in [GildedText.leaf], at exactly the size
/// it always had: nothing around it moves while it writes. With the
/// platform asking for less motion it is that from the start.
class GildedWriting extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;

  /// Before the light sets off.
  final Duration delay;

  /// The light's journey along the word.
  final Duration duration;

  const GildedWriting(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
    this.delay = const Duration(milliseconds: 140),
    this.duration = const Duration(milliseconds: 960),
  });

  @override
  State<GildedWriting> createState() => _GildedWritingState();
}

class _GildedWritingState extends State<GildedWriting>
    with SingleTickerProviderStateMixin {
  /// The glint at the end, after the journey.
  static const _glint = Duration(milliseconds: 380);

  /// How far past the text's own box the leaf is laid: a tight line
  /// (the wordmark is set at height 1.0) lets the tail of its "y" out
  /// of the box, and a mask the size of the box would leave it bare.
  static const _bleed = EdgeInsets.fromLTRB(4, 6, 4, 8);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration + _glint,
  )..addStatusListener(_status);

  bool _done = false;

  void _status(AnimationStatus s) {
    if (s == AnimationStatus.completed && mounted && !_done) {
      setState(() => _done = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
      _done = true;
    } else if (!_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// The letters in gold leaf, the leaf laid over the bleed as well.
  Widget _leaf() => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: GildedText.leaf.createShader,
        child: Padding(
          padding: _bleed,
          child: Text(
            widget.text,
            maxLines: widget.maxLines,
            style: widget.style.copyWith(color: Colors.white),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_done) return _Bleed(by: _bleed, child: _leaf());
    final leaf = _leaf();
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => _writing(leaf),
      ),
    );
  }

  Widget _writing(Widget leaf) {
    final total = _c.duration!.inMicroseconds.toDouble();
    final now = _c.value * total;
    final delay = widget.delay.inMicroseconds.toDouble();
    final journey = widget.duration.inMicroseconds.toDouble();
    final t = ((now - delay) / journey).clamp(0.0, 1.0);
    final e = Curves.easeInOutCubic.transform(t);
    // After the journey: the glint's own clock, 0..1.
    final g =
        ((now - delay - journey) / _glint.inMicroseconds).clamp(0.0, 1.0);
    // The last stretch lifts the light off the word and opens the
    // gilding the rest of the way.
    final lift =
        Curves.easeOutCubic.transform(((e - 0.85) / 0.15).clamp(0.0, 1.0));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The tooling: every letter already there, in a gold that
        // reads, waiting for its leaf. It is also what the name
        // measures, so the writing is exactly the size of the name.
        ExcludeSemantics(
          child: Text(
            widget.text,
            maxLines: widget.maxLines,
            style: widget.style.copyWith(
              color: AppColors.gold.withValues(alpha: 0.36),
            ),
          ),
        ),
        // The leaf, laid in behind the light, hot at the front.
        _Bleed(
          by: _bleed,
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => _heat(_inner(rect), e, lift, g),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => _laid(_inner(rect), e, lift),
              child: leaf,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PenPainter(
                travel: e,
                lift: lift,
                arrive: (t / 0.08).clamp(0.0, 1.0),
                glint: now < delay ? -1 : g,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The text's own box inside the bled one, which the masks measure
  /// the writing along.
  static Rect _inner(Rect bled) => _bleed.deflateRect(bled);

  /// Where the gold has been laid, as a fraction of the width: just
  /// ahead of the light (which runs from −3 % to the end of the last
  /// letter), with a soft edge behind it, and the rest of the way once
  /// the light lifts off.
  static double _front(double e, double lift) => 0.01 + 0.97 * e + 0.22 * lift;

  static Shader _laid(Rect rect, double e, double lift) {
    final f = _front(e, lift);
    final from = (f - 0.12).clamp(0.0, 1.0);
    final to = f.clamp(0.0, 1.0);
    return ui.Gradient.linear(
      rect.centerLeft,
      rect.centerRight,
      const [Colors.white, Colors.white, Colors.transparent, Colors.transparent],
      [0, from, math.max(from, to), 1],
    );
  }

  static Shader _heat(Rect rect, double e, double lift, double glint) {
    final f = _front(e, lift);
    // The heat goes out of the last letters as the glint goes off.
    final heat = 1 - Curves.easeOut.transform((glint / 0.6).clamp(0.0, 1.0));
    final peak = (f - 0.03).clamp(0.0, 1.0);
    final tail = (f - 0.26).clamp(0.0, peak);
    const hot = Color(0xFFFFF7E0);
    return ui.Gradient.linear(
      rect.centerLeft,
      rect.centerRight,
      [
        hot.withValues(alpha: 0),
        hot.withValues(alpha: 0),
        hot.withValues(alpha: 0.85 * heat),
        hot.withValues(alpha: 0),
      ],
      [0, tail, peak, math.max(peak, f.clamp(0.0, 1.0))],
    );
  }
}

/// Lays its child out [by] larger than itself and paints it that much
/// out past its own edges, so the box everyone else sees is the inner
/// one. What it is for: a mask over the child covers the bleed too.
class _Bleed extends SingleChildRenderObjectWidget {
  final EdgeInsets by;
  const _Bleed({required this.by, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBleed(by);

  @override
  void updateRenderObject(BuildContext context, _RenderBleed bleed) {
    bleed.by = by;
  }
}

class _RenderBleed extends RenderShiftedBox {
  _RenderBleed(this._by) : super(null);

  EdgeInsets _by;
  set by(EdgeInsets value) {
    if (value == _by) return;
    _by = value;
    markNeedsLayout();
  }

  BoxConstraints _outer(BoxConstraints c) => BoxConstraints(
        maxWidth: c.maxWidth + _by.horizontal,
        maxHeight: c.maxHeight + _by.vertical,
      );

  Size _inner(Size outer) => Size(
        math.max(0.0, outer.width - _by.horizontal),
        math.max(0.0, outer.height - _by.vertical),
      );

  @override
  double computeMinIntrinsicWidth(double height) => math.max(0.0,
      (child?.getMinIntrinsicWidth(height + _by.vertical) ?? 0.0) - _by.horizontal);

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(0.0,
      (child?.getMaxIntrinsicWidth(height + _by.vertical) ?? 0.0) - _by.horizontal);

  @override
  double computeMinIntrinsicHeight(double width) => math.max(0.0,
      (child?.getMinIntrinsicHeight(width + _by.horizontal) ?? 0.0) - _by.vertical);

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(0.0,
      (child?.getMaxIntrinsicHeight(width + _by.horizontal) ?? 0.0) - _by.vertical);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
        _inner(child.getDryLayout(_outer(constraints.loosen()))));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_outer(constraints.loosen()), parentUsesSize: true);
    size = constraints.constrain(_inner(child.size));
    (child.parentData! as BoxParentData).offset = Offset(-_by.left, -_by.top);
  }
}

/// The light itself: a soft glow with a small star at its heart, along
/// the middle of the letters, lifting at the end to the last one's tip
/// and going out there in a glint.
class _PenPainter extends CustomPainter {
  /// 0..1 along the word, eased.
  final double travel;

  /// 0..1, the rise off the end of the word.
  final double lift;

  /// 0..1, the light coming up as it sets off.
  final double arrive;

  /// 0..1 through the glint; negative before the light has set off.
  final double glint;

  const _PenPainter({
    required this.travel,
    required this.lift,
    required this.arrive,
    required this.glint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (glint < 0 || size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    // The end of the stroke: just in from the right edge (the width
    // carries the letter spacing after the last letter), at the top.
    final endX = w - 2.5;
    final x = -0.03 * w + (endX + 0.03 * w) * travel;
    final y = h * (0.56 - 0.44 * lift);
    final at = Offset(x, y);

    // Up as it sets off, out through the glint.
    final fade = glint > 0 ? 1 - Curves.easeIn.transform(glint) : 1.0;
    final alpha = arrive * fade;
    if (alpha <= 0.004) return;

    final r = h * 0.95;
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          at,
          r,
          [
            const Color(0xFFFFF2CE).withValues(alpha: 0.5 * alpha),
            AppColors.gold.withValues(alpha: 0.2 * alpha),
            AppColors.gold.withValues(alpha: 0),
          ],
          const [0, 0.4, 1],
        ),
    );
    // The star opens a little as it goes out.
    final flare = glint > 0 ? Curves.easeOutCubic.transform(glint) : 0.0;
    paintSparkle(
      canvas,
      at,
      opacity: alpha,
      scale: 0.62 + 0.45 * flare,
      rotation: 45 * travel + 60 * flare,
      color: const Color(0xFFFFF7E0),
      glow: 0.35,
    );
  }

  @override
  bool shouldRepaint(covariant _PenPainter old) =>
      old.travel != travel ||
      old.lift != lift ||
      old.arrive != arrive ||
      old.glint != glint;
}
