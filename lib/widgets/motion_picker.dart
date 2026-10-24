import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/verse_ink.dart';
import '../data/verse_motion.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart' show accentOnDark, accentOnLight;
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'ink_swatch.dart';

/// How the verse moves, in one place: the designed looks, each a card
/// that plays what it does, side by side and all in view.
///
/// Only the cards. The parts of a look (its arrival, the thread, the
/// light, the trail, the unveil) used to sit under them as switches of
/// their own, which made two controls for every choice; and two of the
/// looks (a plain fade, and a fade that rose a few pixels) did too little
/// to see. What is left is five looks that each visibly do something.
///
/// The style step shows it in a panel under its frame, with the motion's
/// colour under it ([MotionColourRow]); the reel screen in a sheet under
/// the playing reel.
class MotionPicker extends StatefulWidget {
  final VerseMotion motion;

  /// Whether the voice has word timing in the reel's surah, without
  /// which the trail and the unveil have nothing to follow.
  final bool hasWords;
  final ValueChanged<VerseMotion> onChanged;

  /// Leaves the heading off, for a caller that has its own.
  final bool heading;

  /// The colour the cards play in: the reel's accent.
  final Color tint;

  /// What stands between the cards and the note: the colour row, on the
  /// style step.
  final Widget? below;

  const MotionPicker({
    super.key,
    required this.motion,
    required this.hasWords,
    required this.onChanged,
    this.heading = true,
    this.tint = AppColors.goldBright,
    this.below,
  });

  @override
  State<MotionPicker> createState() => _MotionPickerState();
}

class _MotionPickerState extends State<MotionPicker> {
  /// A look tapped that this voice can't play: the note under the cards
  /// says so for a moment, in place of the usual line, and the card
  /// shakes its head. Counted, so a second tap shakes it again.
  MotionPreset? _refused;
  int _refusals = 0;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  void _set(VerseMotion m) {
    HapticFeedback.selectionClick();
    widget.onChanged(m);
  }

  void _refuse(MotionPreset p) {
    HapticFeedback.lightImpact();
    _clear?.cancel();
    setState(() {
      _refused = p;
      _refusals++;
    });
    _clear = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _refused = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final chosen = MotionPreset.of(widget.motion);
    final refused = _refused;
    final note = refused != null
        ? l.motionNotForVoice(l.motionPresetName(refused.name))
        : widget.hasWords
            ? l.motionFollowsWords
            : l.motionNeedsWords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.heading)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
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
        LayoutBuilder(
          builder: (context, box) {
            const pad = 16.0, gap = 8.0;
            final n = MotionPreset.values.length;
            // Every look in view at once, on the narrowest phone too:
            // the cards narrow rather than scroll.
            final w = ((box.maxWidth - 2 * pad - gap * (n - 1)) / n)
                .clamp(52.0, 88.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: pad),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    () {
                      final p = MotionPreset.values[i];
                      final usable = !p.needsWords || widget.hasWords;
                      // A look this voice can't play still answers a
                      // tap: with a word on why, rather than nothing.
                      return _Shake(
                        trigger: p == refused ? _refusals : 0,
                        child: MotionPresetCard(
                          preset: p,
                          width: w,
                          tint: widget.tint,
                          selected: chosen == p,
                          enabled: usable,
                          onTap: usable
                              ? () => _set(p.motion)
                              : () => _refuse(p),
                        ),
                      );
                    }(),
                  ],
                ],
              ),
            );
          },
        ),
        if (widget.below != null) widget.below!,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              note,
              key: ValueKey(note),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.3,
                fontWeight:
                    refused != null ? FontWeight.w600 : FontWeight.w400,
                color: refused != null
                    ? AppColors.goldBright
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A card shaking its head: a few quick swings either side, dying away,
/// each time [trigger] changes to something other than zero.
class _Shake extends StatefulWidget {
  final int trigger;
  final Widget child;

  const _Shake({required this.trigger, required this.child});

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant _Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && widget.trigger != 0) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value;
        final dx = math.sin(v * math.pi * 6) * (1 - v) * 5;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// The motion's colour: the light passing through the words, the thread
/// under them, the recited word and the words the trail leaves lit. One
/// colour, the reel's accent, gold until another is chosen — offered here
/// because this is where what it colours can be seen moving.
///
/// Light is never a flat colour, so neither is this: the house gold
/// first, then every luminous ink in one line that scrolls sideways, the
/// inks drawn for the ground the verse is on leading.
class MotionColourRow extends StatelessWidget {
  final int accentArgb;
  final VerseInk accentInk;

  /// Whether the verse sits on a pale band, where the house gold is the
  /// deeper one.
  final bool onLight;
  final ValueChanged<VerseInk> onInk;

  /// Back to the house gold, free to follow the ground again.
  final VoidCallback onGold;

  /// Stands at the end of the heading's line: the style step's switch
  /// for the recited word, which costs the panel no line of its own.
  final Widget? trailing;

  const MotionColourRow({
    super.key,
    required this.accentArgb,
    required this.accentInk,
    required this.onLight,
    required this.onInk,
    required this.onGold,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final gold = onLight ? accentOnLight : accentOnDark;
    final isGold = accentInk.isNone;
    final named = isGold ? l.colourName(gold) : l.inkName(accentInk);
    final name = named.isEmpty
        ? named
        : named[0].toUpperCase() + named.substring(1);
    final section = l.motionColour;
    final heading = ExcludeSemantics(
      child: Text(
        '${section.toUpperCase()} · $name',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing == null)
            heading
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ),
            ),
          const SizedBox(height: 4),
          InkStrip(
            inks: VerseInk.ordered(onLight: onLight),
            selected: isGold ? null : accentInk,
            onPick: onInk,
            labelOf: (ink) => '$section${l.comma} ${l.a11yInkSwatch(ink)}',
            leading: [
              _Disc(
                label: '$section${l.comma} ${l.colourName(gold)}',
                selected: isGold,
                onTap: onGold,
                child: _goldDisc(gold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The house gold, as a disc with its own light: the default, set
  /// apart from the inks by its shape.
  static Widget _goldDisc(int argb) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.45),
            radius: 0.95,
            colors: [
              Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.3), Color(argb)),
              Color(argb),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
                color: Color(argb).withValues(alpha: 0.35), blurRadius: 8),
          ],
        ),
      );
}

/// A colour in [MotionColourRow], ringed in gold when it is the one.
class _Disc extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _Disc({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.gold : Colors.transparent,
              width: 1.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One designed look, as a small frame playing what it does.
class MotionPresetCard extends StatelessWidget {
  final MotionPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  /// How wide the card is; its frame keeps the reel's proportions.
  final double width;

  /// The colour it plays in: the reel's accent.
  final Color tint;

  const MotionPresetCard({
    super.key,
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.width = 84,
    this.tint = AppColors.goldBright,
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
          // Sized outright, the look alone animated: a width that eased
          // to a new screen's share ran the row off its edge meanwhile.
          child: SizedBox(
            width: width,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.stroke,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: (width - 10) * 1.12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: MotionDemo(motion: preset.motion, tint: tint),
                  ),
                ),
                const SizedBox(height: 4),
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
      ),
    );
  }
}

/// A motion, played in shapes: two lines of a verse as bars of words on
/// a night ground, coming on, being recited right to left, and going.
/// Loops; holds still when the platform asks for less motion.
class MotionDemo extends StatefulWidget {
  final VerseMotion motion;

  /// The colour the light, the thread and the lit words play in.
  final Color tint;

  const MotionDemo(
      {super.key, required this.motion, this.tint = AppColors.goldBright});

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
          painter: _DemoPainter(_c, widget.motion, widget.tint),
          size: Size.infinite,
        ),
      );
}

class _DemoPainter extends CustomPainter {
  final Animation<double> t;
  final VerseMotion motion;
  final Color tint;

  _DemoPainter(this.t, this.motion, this.tint) : super(repaint: t);

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
    final gold = tint;
    final core = Color.lerp(tint, Colors.white, 0.8)!;
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
                core.withValues(alpha: alpha),
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
                ..color = core.withValues(alpha: alpha)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.02),
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DemoPainter old) =>
      old.motion != motion || old.tint != tint;
}

/// How a reel shows its long verses: whole, or one, two or three lines
/// at a time — one row of choices, the way the reel screen's sheet
/// offers it.
class LinesChooser extends StatelessWidget {
  final int lines;
  final ValueChanged<int> onPick;

  /// How this reel's long verses came out, as (shown whole, cut): what
  /// the note under the choice says, when some of them could not be cut.
  /// Null for a chooser with no reel under it.
  final ValueNotifier<(int, int)>? planned;

  const LinesChooser(
      {super.key, required this.lines, required this.onPick, this.planned});

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
          if (lines == 0 || planned == null)
            _note(lines == 0 ? l.versesWholeNote : l.linesTimingNote)
          else
            ValueListenableBuilder<(int, int)>(
              valueListenable: planned!,
              builder: (_, p, __) => _note(
                p.$1 == 0
                    ? l.linesTimingNote
                    : p.$2 == 0
                        ? l.linesAllWhole
                        : l.linesSomeWhole,
                warn: p.$1 > 0,
              ),
            ),
        ],
      ),
    );
  }
}

Widget _note(String text, {bool warn = false}) => Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        height: 1.3,
        fontWeight: warn ? FontWeight.w600 : FontWeight.w400,
        color: warn ? AppColors.goldBright : AppColors.textSecondary,
      ),
    );

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
  ValueNotifier<(int, int)>? planned,
  Color tint = AppColors.goldBright,
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
                  planned: planned,
                  onPick: (n) {
                    HapticFeedback.selectionClick();
                    set(() => currentLines = n);
                    onLines(n);
                  },
                ),
              MotionPicker(
                motion: current,
                hasWords: hasWords,
                tint: tint,
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
