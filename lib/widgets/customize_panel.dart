import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings_service.dart';
import '../data/verse_lines.dart';
import '../data/verse_numbering.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

/// Settings' Customize row, and the panel it opens in place.
///
/// The set-once choices about the reels themselves: how long verses
/// appear, whether the scenery follows their lines, the surah's name,
/// the verse numbers, the video's quality. They used to drop from the
/// row as a menu, which held two of them and crowded those; a panel
/// opening under the row has room to show what each choice does — the
/// long verses are drawn, not described — and stays open while the
/// choices are tried in turn.
class CustomizeRow extends StatefulWidget {
  final AppSettings settings;

  const CustomizeRow({super.key, required this.settings});

  @override
  State<CustomizeRow> createState() => _CustomizeRowState();
}

class _CustomizeRowState extends State<CustomizeRow> {
  bool _open = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
  }

  /// Read fresh at every change: the panel stays open across them, and
  /// [widget.settings] is the state it was last built with.
  static void _update(AppSettings Function(AppSettings s) change) {
    HapticFeedback.selectionClick();
    SettingsService.update(change(SettingsService.state.value));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final s = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        A11yTap(
          label: l.customizeTitle,
          hint: l.a11yCustomizeHint,
          expanded: _open,
          onTap: _toggle,
          child: InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      size: 18, color: AppColors.gold),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      l.customizeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        height: 1.2,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.expand_more_rounded,
                        size: 18, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                  child: _Panel(settings: s, update: _update),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final AppSettings settings;
  final void Function(AppSettings Function(AppSettings s)) update;

  const _Panel({required this.settings, required this.update});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = settings;
    final lines = s.verseLines > VerseLines.whole;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(l.longVersesTitle, note: l.longVersesNote),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ChoiceTile(
                    title: l.versesWhole,
                    note: l.versesWholeNote,
                    chosen: !lines,
                    art: const _LinesArt(byLine: false),
                    onTap: () => update((x) => x.copyWith(verseLines: 0)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ChoiceTile(
                    title: l.versesLines,
                    note: l.versesLinesNote,
                    chosen: lines,
                    art: _LinesArt(byLine: true, animate: lines),
                    onTap: () => update((x) => x.copyWith(
                        verseLines: x.verseLines > 0
                            ? x.verseLines
                            : VerseLines.preferred)),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !lines
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.linesAtOnce,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              for (final n in VerseLines.choices) ...[
                                const SizedBox(width: 6),
                                _CountChip(
                                  n: n,
                                  label: l.linesCount(n),
                                  chosen: s.verseLines == n,
                                  onTap: () => update(
                                      (x) => x.copyWith(verseLines: n)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.linesTimingNote,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const _Rule(),
                          _Heading(l.scenesChangeTitle,
                              note: l.scenesChangeNote),
                          const SizedBox(height: 8),
                          _Segmented(
                            options: [l.scenesEveryLine, l.scenesEveryVerse],
                            chosen: s.scenesFollowLines ? 0 : 1,
                            onPick: (i) => update((x) =>
                                x.copyWith(scenesFollowLines: i == 0)),
                          ),
                        ],
                      ),
                    ),
            ),
            const _Rule(),
            _SwitchLine(
              icon: Icons.menu_book_rounded,
              title: l.surahNameTitle,
              note: l.surahNameNote,
              value: s.surahTitle,
              onChanged: (on) => update((x) => x.copyWith(surahTitle: on)),
            ),
            const _Rule(),
            _Heading(l.verseNumbersTitle, note: l.verseNumbersNote),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in VerseNumbering.values)
                  _WordChip(
                    label: l.verseNumberingLabel(v),
                    chosen: s.verseNumbering == v,
                    onTap: () =>
                        update((x) => x.copyWith(verseNumbering: v)),
                  ),
              ],
            ),
            const _Rule(),
            _SwitchLine(
              icon: Icons.videocam_outlined,
              title: l.highQualityVideo,
              note: l.highQualityNote,
              value: s.highQualityVideo,
              onChanged: (on) =>
                  update((x) => x.copyWith(highQualityVideo: on)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section's name in small gold capitals, with a line under it.
class _Heading extends StatelessWidget {
  final String text;
  final String? note;

  const _Heading(this.text, {this.note});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.gold,
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            style: const TextStyle(
                fontSize: 11, height: 1.35, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// A hairline between sections.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppColors.stroke.withValues(alpha: 0),
              AppColors.stroke,
              AppColors.stroke.withValues(alpha: 0),
            ]),
          ),
        ),
      );
}

/// One of two large choices, drawn rather than described.
class _ChoiceTile extends StatelessWidget {
  final String title;
  final String note;
  final bool chosen;
  final Widget art;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.title,
    required this.note,
    required this.chosen,
    required this.art,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(8, 9, 8, 9),
          decoration: BoxDecoration(
            color: chosen
                ? AppColors.gold.withValues(alpha: 0.12)
                : AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: chosen ? AppColors.gold : AppColors.stroke,
              width: chosen ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 26, height: 46, child: art),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                        color: chosen
                            ? AppColors.goldBright
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A phone's frame with a verse in it, in shapes: the whole verse small
/// and at once, or two lines of it large, the next two coming on after.
class _LinesArt extends StatefulWidget {
  final bool byLine;
  final bool animate;

  const _LinesArt({required this.byLine, this.animate = false});

  @override
  State<_LinesArt> createState() => _LinesArtState();
}

class _LinesArtState extends State<_LinesArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LinesArt old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.animate || still) {
      _c
        ..stop()
        ..value = 0.3;
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
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(painter: _LinesPainter(_c, widget.byLine)),
      );
}

class _LinesPainter extends CustomPainter {
  final Animation<double> t;
  final bool byLine;

  _LinesPainter(this.t, this.byLine) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.width * 0.2));
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF233046), Color(0xFF32261A)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.stroke);
    final w = size.width, h = size.height;
    void bar(double y, double share, double thick, double a) {
      final bw = w * share;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(w / 2, y), width: bw, height: thick),
            Radius.circular(thick / 2)),
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }

    if (!byLine) {
      // The whole verse at once, small.
      const shares = [0.7, 0.62, 0.7, 0.5, 0.58];
      for (var i = 0; i < shares.length; i++) {
        bar(h * (0.32 + i * 0.09), shares[i], h * 0.035, 0.8);
      }
      return;
    }
    // Two lines at a time, large, the pair after them coming on.
    final p = t.value;
    final second = p > 0.5;
    final local = second ? (p - 0.5) * 2 : p * 2;
    final fadeIn = (local / 0.18).clamp(0.0, 1.0);
    final fadeOut = ((1 - local) / 0.15).clamp(0.0, 1.0);
    final a = math.min(fadeIn, fadeOut) * 0.92;
    final pair = second ? const [0.66, 0.42] : const [0.74, 0.58];
    bar(h * 0.44, pair[0], h * 0.07, a);
    bar(h * 0.58, pair[1], h * 0.07, a);
    // A gold rule under them: the line being read.
    final ruleW = w * 0.3 * a;
    canvas.drawLine(
      Offset(w / 2 - ruleW / 2, h * 0.7),
      Offset(w / 2 + ruleW / 2, h * 0.7),
      Paint()
        ..color = AppColors.goldBright.withValues(alpha: a)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) => old.byLine != byLine;
}

/// "1 line", "2 lines", "3 lines".
class _CountChip extends StatelessWidget {
  final int n;
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  const _CountChip({
    required this.n,
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: chosen
                ? AppColors.gold.withValues(alpha: 0.18)
                : AppColors.surface,
            border: Border.all(
              color: chosen ? AppColors.gold : AppColors.stroke,
              width: chosen ? 1.4 : 1,
            ),
          ),
          child: Text(
            '$n',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: chosen ? AppColors.goldBright : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of choices that share one track.
class _Segmented extends StatelessWidget {
  final List<String> options;
  final int chosen;
  final ValueChanged<int> onPick;

  const _Segmented({
    required this.options,
    required this.chosen,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == chosen,
                inMutuallyExclusiveGroup: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == chosen
                          ? AppColors.gold.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      options[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            i == chosen ? FontWeight.w600 : FontWeight.w400,
                        color: i == chosen
                            ? AppColors.goldBright
                            : AppColors.textSecondary,
                      ),
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

/// A chip for one of several choices: the verse numbers.
class _WordChip extends StatelessWidget {
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  const _WordChip({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: chosen
                ? AppColors.gold.withValues(alpha: 0.16)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: chosen ? AppColors.gold : AppColors.stroke,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
              color: chosen ? AppColors.goldBright : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// An on/off choice with a line under its name saying what it does.
class _SwitchLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchLine({
    required this.icon,
    required this.title,
    required this.note,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      toggled: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon,
                  size: 17,
                  color: value
                      ? AppColors.goldBright
                      : AppColors.gold.withValues(alpha: 0.62)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ExcludeSemantics(
                child: _Pill(value: value, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small switch Settings draws everywhere: a pill and a thumb.
class _Pill extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Pill({required this.value, required this.onChanged});

  static const _w = 30.0;
  static const _h = 16.0;
  static const _thumb = 11.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: _w,
        height: _h,
        padding: const EdgeInsets.all((_h - _thumb) / 2),
        decoration: BoxDecoration(
          color: value ? AppColors.gold : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(_h / 2),
          border: Border.all(
            color: value ? AppColors.gold : AppColors.stroke,
            width: 0.8,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            width: _thumb,
            height: _thumb,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? const Color(0xFF14100A) : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
