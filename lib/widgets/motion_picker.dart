import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/verse_motion.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// Everything about how the verse moves, in one place: the designed
/// looks as cards that each play what they do, then the parts of a look
/// to mix by hand. The style step shows it in a panel under its frame;
/// the reel screen in a sheet under the playing reel.
class MotionPicker extends StatelessWidget {
  final VerseMotion motion;

  /// Whether the voice has word timing, without which the trail and
  /// the unveil have nothing to follow.
  final bool hasWords;
  final ValueChanged<VerseMotion> onChanged;

  /// Leaves the heading off, for a caller that has its own.
  final bool heading;

  const MotionPicker({
    super.key,
    required this.motion,
    required this.hasWords,
    required this.onChanged,
    this.heading = true,
  });

  void _set(VerseMotion m) {
    HapticFeedback.selectionClick();
    onChanged(m);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (heading)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                A11yHeader(
                  child: Text(
                    l.motionTitle.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l.motionBody,
                  style: t.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: MotionPreset.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = MotionPreset.values[i];
              final usable = !p.needsWords || hasWords;
              return MotionPresetCard(
                preset: p,
                selected: MotionPreset.of(motion) == p,
                enabled: usable,
                onTap: usable ? () => _set(p.motion) : null,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.motionArrival,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _Segments<VerseArrival>(
                values: VerseArrival.values,
                chosen: motion.arrival,
                label: (a) => switch (a) {
                  VerseArrival.none => l.arrivalCut,
                  VerseArrival.fade => l.arrivalFade,
                  VerseArrival.rise => l.arrivalRise,
                },
                onPick: (a) => _set(motion.copyWith(arrival: a)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        MotionSwitchRow(
          icon: Icons.gradient_rounded,
          label: l.motionThread,
          on: motion.thread,
          onToggle: (on) => _set(motion.copyWith(thread: on)),
        ),
        MotionSwitchRow(
          icon: Icons.wb_sunny_outlined,
          label: l.motionLight,
          on: motion.light,
          onToggle: (on) => _set(motion.copyWith(light: on)),
        ),
        MotionSwitchRow(
          icon: Icons.brush_rounded,
          label: l.motionTrail,
          on: motion.trail && hasWords,
          onToggle: hasWords ? (on) => _set(motion.copyWith(trail: on)) : null,
        ),
        MotionSwitchRow(
          icon: Icons.blur_on_rounded,
          label: l.motionUnveil,
          on: motion.unveil && hasWords,
          onToggle:
              hasWords ? (on) => _set(motion.copyWith(unveil: on)) : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: Text(
            hasWords ? l.motionFollowsWords : l.motionNeedsWords,
            style: const TextStyle(
                fontSize: 10.5, height: 1.3, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// One designed look, as a small frame playing what it does.
class MotionPresetCard extends StatelessWidget {
  final MotionPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const MotionPresetCard({
    super.key,
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final name = l.motionPresetName(preset.name);
    return A11yTap(
      label: '${l.motionTitle}${l.comma} $name',
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 84,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.stroke,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: MotionDemo(motion: preset.motion),
                  ),
                ),
                const SizedBox(height: 5),
                // Shrunk rather than cut: "Golden thread" in German or
                // Indonesian is longer than the card is wide.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.goldBright
                          : AppColors.textSecondary,
                    ),
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

/// A motion, played in shapes: two lines of a verse as bars of words on
/// a night ground, coming on, being recited right to left, and going.
/// Loops; holds still when the platform asks for less motion.
class MotionDemo extends StatefulWidget {
  final VerseMotion motion;

  const MotionDemo({super.key, required this.motion});

  /// One loop: on, recited, off.
  static const loop = Duration(milliseconds: 3400);

  @override
  State<MotionDemo> createState() => _MotionDemoState();
}

class _MotionDemoState extends State<MotionDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: MotionDemo.loop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c
        ..stop()
        ..value = 0.62;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _DemoPainter(_c, widget.motion),
          size: Size.infinite,
        ),
      );
}

class _DemoPainter extends CustomPainter {
  final Animation<double> t;
  final VerseMotion motion;

  _DemoPainter(this.t, this.motion) : super(repaint: t);

  /// The words of the two lines, as shares of the frame's width, right
  /// to left.
  static const _lines = [
    [0.22, 0.14, 0.18],
    [0.16, 0.24],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // The night the verse sits on.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2433), Color(0xFF2B2219)],
        ).createShader(Offset.zero & size),
    );

    // One unit: on at 6%, recited from 18% to 78%, off by 94%.
    const unitFrom = 0.06, unitTo = 0.94;
    final p = t.value;
    if (p < unitFrom || p > unitTo) return;
    const unitMs = 3000;
    final ms = ((p - unitFrom) / (unitTo - unitFrom) * unitMs).round();
    final alpha = motion.alphaAt(ms, unitMs);
    final dy = motion.offsetAt(ms, unitMs) / VerseMotion.risePx * h * 0.07;
    // Recitation progress over every word, 0..1.
    final words = _lines.expand((l) => l).length;
    final recited =
        ((ms / unitMs - 0.14) / 0.66).clamp(0.0, 1.0) * words;

    final barH = h * 0.085;
    final gap = w * 0.035;
    const gold = AppColors.goldBright;
    var index = 0;
    for (var li = 0; li < _lines.length; li++) {
      final line = _lines[li];
      final lineW = line.fold<double>(0, (a, b) => a + b) * w +
          gap * (line.length - 1);
      final right = (w + lineW) / 2;
      final y = h * (0.38 + li * 0.2) + dy;
      var x = right;
      final lineStart = index;
      for (final share in line) {
        final ww = share * w;
        final done = (recited - index).clamp(0.0, 1.0);
        final current = done > 0 && done < 1;
        var c = Colors.white;
        var a = 0.88;
        if (motion.trail && done > 0) c = gold;
        if (!motion.trail && current && motion.moves) c = gold;
        if (motion.unveil && done == 0) a = 0.25;
        final r = RRect.fromRectAndRadius(
            Rect.fromLTWH(x - ww, y - barH / 2, ww, barH),
            Radius.circular(barH / 2));
        canvas.drawRRect(
            r, Paint()..color = c.withValues(alpha: a * alpha));
        // The light, passing through the word being recited.
        if (motion.light && current) {
          final cx = x - ww * done;
          canvas.save();
          canvas.clipRRect(r);
          canvas.drawRect(
            Rect.fromLTWH(cx - w * 0.06, y - barH, w * 0.12, barH * 2),
            Paint()
              ..shader = LinearGradient(colors: [
                gold.withValues(alpha: 0),
                const Color(0xFFFFF6DC).withValues(alpha: alpha),
                gold.withValues(alpha: 0),
              ]).createShader(
                  Rect.fromLTWH(cx - w * 0.06, y, w * 0.12, 1)),
          );
          canvas.restore();
        }
        x -= ww + gap;
        index++;
      }
      // The thread under the line, drawn out word by word.
      if (motion.thread) {
        final drawn = (recited - lineStart).clamp(0.0, line.length.toDouble());
        var len = 0.0;
        var xx = right;
        for (var k = 0; k < line.length; k++) {
          final ww = line[k] * w;
          final f = (drawn - k).clamp(0.0, 1.0);
          len = (right - xx) + ww * f + (f >= 1 && k < line.length - 1 ? gap : 0);
          if (f < 1) break;
          xx -= ww + gap;
        }
        if (len > 0) {
          final ty = y + barH * 0.95;
          canvas.drawLine(
            Offset(right, ty),
            Offset(right - len, ty),
            Paint()
              ..color = gold.withValues(alpha: alpha)
              ..strokeWidth = math.max(1.2, h * 0.018)
              ..strokeCap = StrokeCap.round,
          );
          if (drawn < line.length && drawn > 0) {
            canvas.drawCircle(
              Offset(right - len, ty),
              h * 0.035,
              Paint()
                ..color = const Color(0xFFFFF6DC).withValues(alpha: alpha)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.02),
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DemoPainter old) => old.motion != motion;
}

/// An on/off part of a motion, in the style step's row shape: an icon,
/// a name, and a small switch, dimmed when it cannot be had.
class MotionSwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool on;

  /// Null when the row cannot be switched.
  final ValueChanged<bool>? onToggle;

  const MotionSwitchRow({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onToggle != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
      child: MergeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Row(
            children: [
              Icon(icon,
                  size: 17,
                  color: on ? AppColors.goldBright : AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: on ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.78,
                child: Switch(
                  value: on,
                  activeThumbColor: AppColors.gold,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: onToggle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How a reel shows its long verses: whole, or one, two or three lines
/// at a time — one row of choices, the way the reel screen's sheet
/// offers it.
class LinesChooser extends StatelessWidget {
  final int lines;
  final ValueChanged<int> onPick;

  const LinesChooser({super.key, required this.lines, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          A11yHeader(
            child: Text(
              l.longVersesTitle.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _Segments<int>(
              values: const [0, 1, 2, 3],
              chosen: lines,
              label: (n) => n == 0 ? l.versesWhole : l.linesCount(n),
              onPick: onPick,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            lines == 0 ? l.versesWholeNote : l.linesTimingNote,
            style: const TextStyle(
                fontSize: 10.5, height: 1.3, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A row of pill choices, one of them chosen.
class _Segments<T> extends StatelessWidget {
  final List<T> values;
  final T chosen;
  final String Function(T) label;
  final ValueChanged<T> onPick;

  const _Segments({
    required this.values,
    required this.chosen,
    required this.label,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            A11yTap(
              label: label(v),
              selected: v == chosen,
              onTap: () => onPick(v),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: v == chosen
                        ? AppColors.gold.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label(v),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          v == chosen ? FontWeight.w600 : FontWeight.w500,
                      color: v == chosen
                          ? AppColors.goldBright
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The motion as a sheet under the playing reel: every change shows on
/// the reel above it at once, through [onChanged].
///
/// With [onLines], the sheet also holds how this reel shows its long
/// verses — whole, or a number of lines at a time — since that, too, is
/// best chosen while the reel plays above it.
Future<void> showMotionSheet(
  BuildContext context, {
  required VerseMotion motion,
  required bool hasWords,
  required ValueChanged<VerseMotion> onChanged,
  int lines = 0,
  ValueChanged<int>? onLines,
}) {
  var current = motion;
  var currentLines = lines;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceRaised,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => StatefulBuilder(
      builder: (context, set) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onLines != null)
                LinesChooser(
                  lines: currentLines,
                  onPick: (n) {
                    HapticFeedback.selectionClick();
                    set(() => currentLines = n);
                    onLines(n);
                  },
                ),
              MotionPicker(
                motion: current,
                hasWords: hasWords,
                onChanged: (m) {
                  set(() => current = m);
                  onChanged(m);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
