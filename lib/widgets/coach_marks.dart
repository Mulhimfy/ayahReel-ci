import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// One stop on a coach-mark tour: a control to point at, and what to
/// say about it.
class CoachStep {
  /// The widget being pointed at. A step whose key is not on screen is
  /// skipped rather than pointing at nothing.
  final GlobalKey target;

  /// Pointed at instead when [target] is not mounted — how a step about
  /// controls that only appear in one mode still finds something to
  /// stand next to.
  final GlobalKey? fallback;

  final String title;
  final String body;

  const CoachStep({
    required this.target,
    required this.title,
    required this.body,
    this.fallback,
  });
}

/// A one-at-a-time walkthrough drawn over a screen: everything dims
/// except the control being explained, an arrow points at it, and a
/// numbered card says what it does.
///
/// Stack this over the screen it explains — it measures its targets
/// through their [GlobalKey]s, so it needs no knowledge of the layout
/// and holds no copy of its own.
///
/// There is no way out but forward, and only one way forward: the OK
/// on the card. Every other tap is swallowed — it neither reaches the
/// screen underneath nor moves the tour along. The tour is shown once
/// in the life of an install, so a stray tap must not be able to spend
/// the only chance these controls get to explain themselves, whether
/// by skipping a card or by skipping the lot.
class CoachMarks extends StatefulWidget {
  final List<CoachStep> steps;

  /// Called once, when the last step is acknowledged. Marking the tour
  /// as seen is the caller's job — nobody is shown this twice.
  final VoidCallback onFinished;

  const CoachMarks({
    super.key,
    required this.steps,
    required this.onFinished,
  });

  @override
  State<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<CoachMarks> {
  int _i = 0;

  /// Where the current step's control sits, in this widget's own
  /// coordinates. Null on the first frame — the targets have not been
  /// laid out yet — and re-measured after every frame, so a tab rail
  /// that grows or a panel that expands moves the spotlight with it.
  Rect? _hole;

  /// Set once the tour is over, so the per-frame re-measure stops and
  /// [CoachMarks.onFinished] can never fire twice.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// Measures the step in front, walking past any whose control is not
  /// on this screen. Re-armed after every frame the tour is up for.
  void _measure() {
    if (!mounted || _finished) return;
    var i = _i;
    Rect? rect;
    while (i < widget.steps.length) {
      final s = widget.steps[i];
      rect = _rectOf(s.target) ?? _rectOf(s.fallback);
      if (rect != null) break;
      i++;
    }
    if (i >= widget.steps.length) {
      _finish();
      return;
    }
    if (i != _i || rect != _hole) {
      setState(() {
        _i = i;
        _hole = rect;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  Rect? _rectOf(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    final self = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (self is! RenderBox || !self.attached || !self.hasSize) return null;
    // Both sides go through screen coordinates rather than asking for
    // a transform between them: the target lives under the screen this
    // is stacked over, not under the tour itself.
    final origin = box.localToGlobal(Offset.zero) -
        self.localToGlobal(Offset.zero);
    final rect = origin & box.size;
    // A control collapsed to nothing — a rail with no tabs in it yet —
    // is not something to point at either.
    return rect.isEmpty ? null : rect;
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_i + 1 >= widget.steps.length) {
      _finish();
      return;
    }
    setState(() {
      _i++;
      _hole = null; // re-measured before the next paint
    });
    _measure();
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    // Nothing measured yet: hold every tap, but show nothing rather
    // than flashing a card at the wrong place for one frame.
    if (hole == null) {
      return const AbsorbPointer(child: SizedBox.expand());
    }
    final step = widget.steps[_i];
    final size = MediaQuery.sizeOf(context);
    final spot = hole.inflate(7);
    // The card goes under the control when there is room beneath it,
    // and above it otherwise — the arrow flips with it.
    final below = spot.bottom < size.height * 0.55;
    // The screen under the tour is sealed for a screen reader exactly
    // as it is for a finger: nothing behind the dim can be reached
    // until the last card is acknowledged.
    return BlockSemantics(
      child: Material(
      color: Colors.transparent,
      child: GestureDetector(
        // Opaque with nothing behind it: taps on the dimmed screen are
        // caught and dropped. The card's own button sits deeper in this
        // tree and still wins the gesture, so OK is the one tap that
        // does anything at all.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        // A swallow, not a control: it must not read as a nameless
        // button over the whole screen.
        excludeFromSemantics: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SpotlightPainter(spot)),
              ),
            ),
            Positioned(
              left: spot.center.dx - 9,
              top: below ? spot.bottom + 4 : null,
              bottom: below ? null : size.height - spot.top + 4,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(18, 10),
                  painter: _ArrowPainter(up: below),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              top: below ? spot.bottom + 14 : null,
              bottom: below ? null : size.height - spot.top + 14,
              child: _Bubble(
                step: step,
                index: _i,
                total: widget.steps.length,
                onNext: _next,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Everything dims except the control in question, which keeps its own
/// pixels and takes a gold ring.
class _SpotlightPainter extends CustomPainter {
  final Rect spot;
  const _SpotlightPainter(this.spot);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(spot, const Radius.circular(14));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rrect),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.78),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AppColors.gold,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.spot != spot;
}

/// The little tail joining the card to the control.
class _ArrowPainter extends CustomPainter {
  final bool up;
  const _ArrowPainter({required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (up) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..lineTo(0, 0);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = AppColors.surfaceRaised);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppColors.gold.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.up != up;
}

class _Bubble extends StatelessWidget {
  final CoachStep step;
  final int index;
  final int total;
  final VoidCallback onNext;

  const _Bubble({
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final last = index + 1 >= total;
    // Live, so each card is read out as it arrives — the tour moves on
    // its own button, and a reader parked on OK would otherwise hear
    // nothing change.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The number the user is on, so a four-step tour reads as
              // four steps and not as an app that keeps interrupting.
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: t.bodySmall?.copyWith(
                    color: const Color(0xFF14100A),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: A11yHeader(
                  child: Text(
                    step.title,
                    style: t.titleMedium?.copyWith(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l.tourStepOf(index + 1, total),
                style: t.bodySmall
                    ?.copyWith(color: AppColors.textSecondary, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(step.body, style: t.bodyMedium?.copyWith(height: 1.5)),
          Row(
            children: [
              // Forward is the only way out: see [CoachMarks].
              const Spacer(),
              TextButton(
                onPressed: onNext,
                child: Text(
                  last ? l.tourDone : l.tourNext,
                  style: t.bodyMedium?.copyWith(
                    color: AppColors.goldBright,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
