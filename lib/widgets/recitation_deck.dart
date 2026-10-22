import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/live_recitation.dart';
import '../data/models.dart';
import '../data/surah_index.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// `m:ss`, or `h:mm:ss` past the hour — the long surahs run that long.
String liveClock(int ms) {
  final s = (ms / 1000).floor().clamp(0, 1 << 30);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// The head of the verse picker: the surah being cut from, playing.
///
/// One slim bar. A gold coin plays and pauses; beside it the surah's
/// name, which opens the full picker as it always did, and whose voice
/// it is in; at its end the time. Under them a thin line of light that
/// flows while the voice recites — bright where the surah has been,
/// quiet where it is still to come, a bead at each ayah's start and the
/// voice itself a lamp on it.
///
/// The line is also a handle. Pulled right it goes forward, left it goes
/// back, ten seconds a notch, each notch felt and the ayah it lands on
/// lit in the list before the finger lifts ([onPreviewAyah]). A tap on
/// it goes straight to that point of the surah. A flick is one notch.
/// And at its two ends, the same notch as a button: ten seconds back,
/// ten on — the move a thumb looks for first.
///
/// The line runs left-to-right in every language, as a player's does:
/// a right-to-left page still reads time running to the right.
class RecitationDeck extends StatefulWidget {
  final LiveRecitation live;
  final SurahInfo info;
  final Reciter? reciter;

  /// Opens the full surah picker.
  final VoidCallback onOpenSurah;

  /// The ayah a pull of the line would land on, while it is being
  /// pulled; null once it is let go.
  final ValueChanged<int?> onPreviewAyah;

  /// The listener moved the recitation themselves: a skip, a pull, a
  /// tap on the line. The list then follows it whatever it was doing.
  final VoidCallback onUserMove;

  const RecitationDeck({
    super.key,
    required this.live,
    required this.info,
    required this.reciter,
    required this.onOpenSurah,
    required this.onPreviewAyah,
    required this.onUserMove,
  });

  @override
  State<RecitationDeck> createState() => _RecitationDeckState();
}

class _RecitationDeckState extends State<RecitationDeck>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Repaints the line without rebuilding anything else.
  final _frame = _Frame();

  /// The clock under the line, by the second.
  final _clock = ValueNotifier<int>(0);

  Duration _last = Duration.zero;
  double _time = 0;

  /// How alive the line is: 1 while the voice recites, settling to a
  /// breath when it stops.
  double _energy = 0.12;

  /// A pull in progress: where it started on the timeline, how far the
  /// finger has gone, and how many ten-second notches that makes.
  int? _pullFrom;
  double _pullDx = 0;
  int _notches = 0;

  static const _notchPx = 30.0;
  static const _stepMs = 10000;

  /// How far in from the bar's edges the line starts and ends.
  static const _linePad = 8.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.live.addListener(_onLive);
    _clock.value = widget.live.positionMs ~/ 1000;
    _wake();
  }

  @override
  void didUpdateWidget(RecitationDeck old) {
    super.didUpdateWidget(old);
    if (!identical(old.live, widget.live)) {
      old.live.removeListener(_onLive);
      widget.live.addListener(_onLive);
      _onLive();
    }
  }

  @override
  void dispose() {
    widget.live.removeListener(_onLive);
    _ticker.dispose();
    _frame.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _onLive() {
    if (!mounted) return;
    setState(() {});
    _wake();
    _clock.value = widget.live.positionMs ~/ 1000;
  }

  /// Keeps the line moving while there is anything to move it.
  void _wake() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final live = widget.live;
    final on = live.status == LiveStatus.playing;
    final target = on ? 1.0 : (live.busy ? 0.32 : 0.12);
    _energy += (target - _energy) * (1 - math.exp(-dt * 5));
    // The flow slows with the energy rather than stopping dead.
    _time += dt * (0.35 + 0.65 * _energy);
    _frame.tick();
    final sec = live.positionMs ~/ 1000;
    if (sec != _clock.value) _clock.value = sec;
    // At rest and settled: stop asking for frames.
    if (!on && !live.busy && _pullFrom == null &&
        (_energy - target).abs() < 0.004) {
      _ticker.stop();
    }
  }

  // ---- the pull ------------------------------------------------------

  int get _pullTarget {
    final live = widget.live;
    final from = _pullFrom ?? live.positionMs;
    final int last = math.max(0, live.totalMs - 1);
    return (from + _notches * _stepMs).clamp(0, last);
  }

  void _pullStart(DragStartDetails d) {
    _pullFrom = widget.live.positionMs;
    _pullDx = 0;
    _notches = 0;
    _wake();
    setState(() {});
  }

  void _pullUpdate(DragUpdateDetails d) {
    if (_pullFrom == null) return;
    _pullDx += d.primaryDelta ?? d.delta.dx;
    final n = (_pullDx / _notchPx).truncate();
    if (n != _notches) {
      final before = _pullTarget;
      _notches = n;
      // A notch past either end of the surah is no notch.
      if (_pullTarget != before) HapticFeedback.selectionClick();
      widget.onPreviewAyah(widget.live.ayahAt(_pullTarget));
      setState(() {});
    }
  }

  void _pullEnd(DragEndDetails d) {
    if (_pullFrom == null) return;
    // A flick too short for a notch is still one, in its direction.
    final v = d.primaryVelocity ?? 0;
    if (_notches == 0 && v.abs() > 500) {
      _notches = v > 0 ? 1 : -1;
      HapticFeedback.selectionClick();
    }
    final target = _pullTarget;
    final moved = _notches != 0;
    _pullFrom = null;
    _pullDx = 0;
    _notches = 0;
    widget.onPreviewAyah(null);
    setState(() {});
    if (moved) {
      widget.onUserMove();
      widget.live.seekTo(target);
    }
  }

  void _pullCancel() {
    if (_pullFrom == null) return;
    _pullFrom = null;
    _pullDx = 0;
    _notches = 0;
    widget.onPreviewAyah(null);
    setState(() {});
  }

  /// [width] is the line's own, inside its inset either side.
  void _tapLine(TapUpDetails d, double width) {
    final live = widget.live;
    if (live.totalMs <= 0 || width <= 0) return;
    HapticFeedback.selectionClick();
    widget.onUserMove();
    final f = ((d.localPosition.dx - _linePad) / width).clamp(0.0, 1.0);
    live.seekTo((f * live.totalMs).round());
  }

  void _skip(int ms) {
    HapticFeedback.selectionClick();
    widget.onUserMove();
    widget.live.skip(ms);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final live = widget.live;
    final playing = live.status == LiveStatus.playing;
    final failed = live.status == LiveStatus.failed;
    final can = live.totalMs > 0;
    final info = widget.info;
    final r = widget.reciter;
    final under = failed
        ? l.liveFailed
        : r == null
            ? l.versesCount(info.ayahCount)
            : '${l.versesCount(info.ayahCount)} · ${l.reciterName(r)}';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: playing
              ? AppColors.gold.withValues(alpha: 0.34)
              : AppColors.stroke,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _PlayButton(
                playing: live.wantsPlay,
                busy: live.busy,
                failed: failed,
                label: live.busy
                    ? l.liveLoading
                    : (live.wantsPlay ? l.pause : l.play),
                onTap: () {
                  HapticFeedback.selectionClick();
                  live.toggle();
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SurahTitleButton(
                  info: info,
                  subtitle: under,
                  alert: failed,
                  onTap: widget.onOpenSurah,
                ),
              ),
              const SizedBox(width: 6),
              _clockText(),
              const SizedBox(width: 8),
            ],
          ),
          // Time runs left to right whatever the language: ten seconds
          // back at the start of the line, ten on at its end.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                _SkipButton(
                  forward: false,
                  label: l.liveBack10,
                  onTap: can ? () => _skip(-_stepMs) : null,
                ),
                Expanded(child: _line(l)),
                _SkipButton(
                  forward: true,
                  label: l.liveForward10,
                  onTap: can ? () => _skip(_stepMs) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(L10n l) {
    final live = widget.live;
    final pulling = _pullFrom != null;
    final target = pulling ? _pullTarget : null;
    // Said as the ayah and the time, now and a step either way.
    String said(int ms) {
      final int last = math.max(0, live.totalMs - 1);
      final int at = ms.clamp(0, last);
      final a = live.ayahAt(at);
      return '${l.ayahRange(a, a)}, ${liveClock(at)}';
    }

    final now = live.positionMs;
    return A11yAdjustable(
      label: l.a11yLiveLine,
      value: said(now),
      increasedValue: said(now + _stepMs),
      decreasedValue: said(now - _stepMs),
      onIncrease: live.totalMs <= 0 ? null : () => _skip(_stepMs),
      onDecrease: live.totalMs <= 0 ? null : () => _skip(-_stepMs),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tapLine(d, w - 2 * _linePad),
            onHorizontalDragStart: _pullStart,
            onHorizontalDragUpdate: _pullUpdate,
            onHorizontalDragEnd: _pullEnd,
            onHorizontalDragCancel: _pullCancel,
            child: SizedBox(
              height: 30,
              width: w,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: _linePad),
                      child: CustomPaint(
                        painter: _FlowPainter(
                          live: live,
                          frame: _frame,
                          time: () => _time,
                          energy: () => _energy,
                          pull: () => _pullDx,
                          target: target,
                        ),
                      ),
                    ),
                  ),
                  if (target != null)
                    _PullTag(
                      text: _pullLabel(l, target),
                      x: _linePad +
                          (live.totalMs <= 0
                                  ? 0.0
                                  : target / live.totalMs) *
                              (w - 2 * _linePad),
                      width: w,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _pullLabel(L10n l, int target) {
    final secs = (_notches * _stepMs) ~/ 1000;
    final sign = secs > 0 ? '+' : (secs < 0 ? '−' : '');
    final a = widget.live.ayahAt(target);
    return '$sign${secs.abs()}s · ${l.ayahRange(a, a)}';
  }

  /// Where the voice is and how long the surah runs — the place in gold
  /// while a pull is choosing it. A tilde while the length is still an
  /// estimate.
  Widget _clockText() {
    final live = widget.live;
    return ValueListenableBuilder<int>(
      valueListenable: _clock,
      builder: (_, s, __) {
        final pulling = _pullFrom != null;
        return Text.rich(
          TextSpan(children: [
            TextSpan(
              text: liveClock(pulling ? _pullTarget : s * 1000),
              style: TextStyle(
                color:
                    pulling ? AppColors.goldBright : AppColors.textPrimary,
              ),
            ),
            TextSpan(
              text: ' / ${live.timelineExact ? '' : '~'}'
                  '${liveClock(live.totalMs)}',
            ),
          ]),
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

/// A listenable that only ever says "paint again".
class _Frame extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// The surah's name, a quiet line under it, and the way into the full
/// surah picker: the head of the verse picker, playing or not.
class SurahTitleButton extends StatelessWidget {
  final SurahInfo info;

  /// How many verses, and in whose voice — or what went wrong.
  final String subtitle;

  /// The line under the name is a problem to read: it goes gold.
  final bool alert;

  final VoidCallback onTap;

  const SurahTitleButton({
    super.key,
    required this.info,
    required this.subtitle,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Semantics(
      container: true,
      button: true,
      hint: l.a11yOpensSurahPicker,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        l.surahTitle(info),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium
                            ?.copyWith(fontSize: 15.5, height: 1.2),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.unfold_more_rounded,
                        size: 16, color: AppColors.textSecondary),
                  ],
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(
                    fontSize: 12,
                    height: 1.25,
                    color: alert ? AppColors.goldBright : null,
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

/// Where a pull will land: seconds and the ayah, over the line.
class _PullTag extends StatelessWidget {
  final String text;
  final double x;
  final double width;
  const _PullTag({required this.text, required this.x, required this.width});

  @override
  Widget build(BuildContext context) {
    const tagWidth = 132.0;
    final double right = math.max(4.0, width - tagWidth - 4);
    final double left = (x - tagWidth / 2).clamp(4.0, right);
    return Positioned(
      left: left,
      top: -16,
      width: tagWidth,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 10),
              ],
            ),
            child: Text(
              text,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.goldBright,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line itself.
///
/// Three threads of one wave, summed sines drifting at their own rates,
/// swelling around the voice and lying almost flat far from it, pinned
/// to the line at both ends. Gold and glowing behind the voice, a quiet
/// grey ahead of it. A bead at every ayah's start, the ayah sounding
/// marked by a faint band, the voice a lamp; a pull shows its landing
/// as a ring.
class _FlowPainter extends CustomPainter {
  final LiveRecitation live;
  final double Function() time;
  final double Function() energy;
  final double Function() pull;
  final int? target;

  _FlowPainter({
    required this.live,
    required Listenable frame,
    required this.time,
    required this.energy,
    required this.pull,
    required this.target,
  }) : super(repaint: frame);

  static const _threads = [
    // frequency (waves across the line), amplitude, drift speed, phase
    [(1.6, 0.62, 1.9, 0.0), (3.1, 0.38, -2.7, 1.3)],
    [(2.3, 0.55, -1.4, 2.1), (4.7, 0.45, 3.3, 0.4)],
    [(0.9, 0.5, 1.1, 4.0), (5.6, 0.5, -3.9, 2.6)],
  ];
  static const _gain = [1.0, 0.62, 0.38];
  static const _alpha = [1.0, 0.42, 0.22];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0) return;
    final mid = h / 2 + 2;
    final total = live.totalMs;
    final p = total <= 0 ? 0.0 : (live.positionMs / total).clamp(0.0, 1.0);
    final xp = p * w;
    final t = time();
    final e = energy();
    final drag = pull();

    // The ayah sounding: a faint band under its stretch of the line.
    final starts = live.ayahStarts;
    if (total > 0 && starts.isNotEmpty) {
      final a = live.ayah;
      final x0 = starts[a - 1] / total * w;
      final x1 = (a < starts.length ? starts[a] : total) / total * w;
      if (x1 - x0 >= 2) {
        canvas.drawRRect(
          RRect.fromLTRBR(x0, mid - h * 0.36, x1, mid + h * 0.36,
              const Radius.circular(6)),
          Paint()..color = AppColors.gold.withValues(alpha: 0.07),
        );
      }
    }

    double y(int thread, double x) {
      // Strongest at the voice, a ripple elsewhere, nothing at the ends.
      final d = (x - xp) / (w * 0.24);
      final swell = 0.16 + 0.84 * math.exp(-d * d);
      final ends = _smooth(x / 18) * _smooth((w - x) / 18);
      var v = 0.0;
      for (final (f, a, speed, phase) in _threads[thread]) {
        v += a * math.sin(2 * math.pi * f * (x + drag * 0.6) / w +
            phase +
            speed * t);
      }
      return mid + v * h * 0.30 * e * _gain[thread] * swell * ends;
    }

    Path trace(int thread, double from, double to) {
      final path = Path()..moveTo(from, y(thread, from));
      for (var x = from + 3; x < to; x += 3) {
        path.lineTo(x, y(thread, x));
      }
      path.lineTo(to, y(thread, to));
      return path;
    }

    // Ahead of the voice: quiet.
    if (xp < w) {
      for (var k = _threads.length - 1; k >= 0; k--) {
        canvas.drawPath(
          trace(k, xp, w),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = k == 0 ? 1.4 : 1
            ..strokeCap = StrokeCap.round
            ..color = AppColors.textSecondary
                .withValues(alpha: (k == 0 ? 0.34 : 0.16) * _alpha[k] + 0.04),
        );
      }
    }
    // Behind it: gold, and a glow under the main thread.
    if (xp > 0) {
      final shader = const LinearGradient(
        colors: [
          AppColors.goldDeep,
          AppColors.gold,
          AppColors.goldBright,
        ],
        stops: [0.0, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, math.max(xp, 1), h));
      final main = trace(0, 0, xp);
      canvas.drawPath(
        main,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = AppColors.gold.withValues(alpha: 0.18 + 0.14 * e)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      for (var k = _threads.length - 1; k >= 1; k--) {
        canvas.drawPath(
          trace(k, 0, xp),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..strokeCap = StrokeCap.round
            ..color = AppColors.gold.withValues(alpha: 0.55 * _alpha[k]),
        );
      }
      canvas.drawPath(
        main,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
    }

    // A bead at each ayah's start, where there is room for them.
    if (total > 0 && starts.length > 1 && w / starts.length >= 5) {
      final past = Paint()..color = AppColors.goldBright.withValues(alpha: 0.8);
      final ahead = Paint()
        ..color = AppColors.textSecondary.withValues(alpha: 0.45);
      for (var i = 1; i < starts.length; i++) {
        final x = starts[i] / total * w;
        canvas.drawCircle(
            Offset(x, mid), x <= xp ? 1.5 : 1.2, x <= xp ? past : ahead);
      }
    }

    // Where a pull would land.
    final tg = target;
    if (tg != null && total > 0) {
      final xt = tg / total * w;
      final dash = Paint()
        ..color = AppColors.goldBright.withValues(alpha: 0.5)
        ..strokeWidth = 1.2;
      final dir = xt >= xp ? 1.0 : -1.0;
      for (var x = xp; (xt - x) * dir > 0; x += 6 * dir) {
        final to = x + 3 * dir;
        final end = (to - xt) * dir > 0 ? xt : to;
        canvas.drawLine(Offset(x, mid), Offset(end, mid), dash);
      }
      canvas.drawCircle(
        Offset(xt, mid),
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = AppColors.goldBright,
      );
      canvas.drawCircle(Offset(xt, mid), 2.2,
          Paint()..color = AppColors.goldBright);
    }

    // The voice: a lamp on the line.
    final at = Offset(xp, y(0, xp.clamp(0.0, w)));
    final breath = 1 + 0.08 * math.sin(t * 3.2) * e;
    canvas.drawCircle(
      at,
      11 * breath,
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.goldBright.withValues(alpha: 0.42 + 0.2 * e),
          AppColors.goldBright.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: at, radius: 11 * breath)),
    );
    canvas.drawCircle(at, 3.8, Paint()..color = AppColors.goldBright);
    canvas.drawCircle(at, 1.4, Paint()..color = Colors.white);
  }

  static double _smooth(double v) {
    final c = v.clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.target != target || !identical(old.live, live);
}

/// Ten seconds back or on: a ring open at the top, the arrow arriving
/// there, the 10 inside it. Sized to the line it stands at the end of.
class _SkipButton extends StatelessWidget {
  final bool forward;
  final String label;
  final VoidCallback? onTap;
  const _SkipButton({
    required this.forward,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return A11yTap(
      label: label,
      enabled: on,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 34,
          height: 30,
          child: CustomPaint(
            painter: _SkipGlyph(
              forward: forward,
              color: AppColors.textPrimary.withValues(alpha: on ? 0.86 : 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipGlyph extends CustomPainter {
  final bool forward;
  final Color color;
  const _SkipGlyph({required this.forward, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 9.0;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    // Open at the top, the arrow arriving there: clockwise for on,
    // the other way for back.
    const top = -math.pi / 2;
    const sweep = math.pi * 5 / 3;
    final start = forward ? top - sweep : top + sweep;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start,
        forward ? sweep : -sweep, false, stroke);
    final tip = Offset(c.dx, c.dy - r);
    final d = forward ? 1.0 : -1.0;
    final head = Path()
      ..moveTo(tip.dx + 3.2 * d, tip.dy)
      ..lineTo(tip.dx - 1.2 * d, tip.dy - 2.9)
      ..lineTo(tip.dx - 1.2 * d, tip.dy + 2.9)
      ..close();
    canvas.drawPath(head, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: '10',
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2 - 0.5));
  }

  @override
  bool shouldRepaint(_SkipGlyph old) =>
      old.forward != forward || old.color != color;
}

/// Play and pause, in a gold coin; a ring runs round it while the ayah
/// is fetched, and it offers a retry when the fetch failed.
class _PlayButton extends StatelessWidget {
  final bool playing;
  final bool busy;
  final bool failed;
  final String label;
  final VoidCallback onTap;

  const _PlayButton({
    required this.playing,
    required this.busy,
    required this.failed,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = failed
        ? Icons.refresh_rounded
        : playing
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded;
    return A11yTap(
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: busy ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppColors.goldBright,
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.goldBright, AppColors.gold],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: Tween(begin: 0.6, end: 1.0).animate(a),
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: Icon(
                    icon,
                    key: ValueKey(icon),
                    size: 21,
                    color: const Color(0xFF14100A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
