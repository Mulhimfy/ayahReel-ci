import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'glow_button.dart';

/// The colours the user has mixed and kept, newest first — one list for
/// the whole app, offered inside every custom colour picker.
///
/// However many: a kept colour stays until the user lets it go. It
/// used to stop at twelve, and the thirteenth pushed the oldest out —
/// somebody's house colour gone without a word.
abstract final class CustomColours {
  static List<int> get saved => SettingsService.state.value.customColours;

  /// Keeps [argb] at the front, without a duplicate.
  static Future<void> save(int argb) {
    final colour = 0xFF000000 | (argb & 0xFFFFFF);
    final next = [
      colour,
      for (final c in saved)
        if ((c & 0xFFFFFF) != (colour & 0xFFFFFF)) c,
    ];
    return SettingsService.update(
        SettingsService.state.value.copyWith(customColours: next));
  }

  static Future<void> remove(int argb) => SettingsService.update(
        SettingsService.state.value.copyWith(customColours: [
          for (final c in saved)
            if ((c & 0xFFFFFF) != (argb & 0xFFFFFF)) c,
        ]),
      );
}

/// `#A1B2C3`, for showing a colour and for reading one out.
String hexOf(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Every hue, once round — the custom circle's rim and the hue bar.
const _spectrum = [
  Color(0xFFFF4D4D),
  Color(0xFFFFB84D),
  Color(0xFFF8F05A),
  Color(0xFF63E07A),
  Color(0xFF4DD8E6),
  Color(0xFF5B7CFF),
  Color(0xFFC264F0),
  Color(0xFFFF4D9E),
  Color(0xFFFF4D4D),
];

/// The last swatch in any row of colours: a small ring of every hue
/// that opens [showCustomColourPicker]. When the colour in use is one
/// the row does not hold — a mixed one — the circle wears it and is
/// the one marked chosen, so the row still says what is in use.
class CustomColourCircle extends StatelessWidget {
  /// The colour in use now.
  final int current;

  /// Whether [current] is a mixed colour rather than one of the row's.
  final bool chosen;
  final ValueChanged<int> onPick;
  final double size;

  const CustomColourCircle({
    super.key,
    required this.current,
    required this.chosen,
    required this.onPick,
    this.size = 26,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showCustomColourPicker(context, initial: current);
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final rim = math.max(2.5, size * 0.12);
    return A11yTap(
      label: chosen ? l.customColourIs(hexOf(current)) : l.customColour,
      selected: chosen,
      onTap: () => _open(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _open(context);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size + (chosen ? 4 : 0),
          height: size + (chosen ? 4 : 0),
          padding: EdgeInsets.all(chosen ? 2 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: chosen
                ? Border.all(color: AppColors.goldBright, width: 2)
                : null,
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: _spectrum),
            ),
            child: Padding(
              padding: EdgeInsets.all(rim),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen ? Color(current) : AppColors.bg,
                ),
                child: chosen
                    ? null
                    : Icon(Icons.add_rounded,
                        size: size * 0.5, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mix a colour: a field of every shade of one hue, a bar of every hue,
/// and the colours already kept. Save keeps the mix and answers it;
/// a tap on a kept colour answers that one. Null when put away.
Future<int?> showCustomColourPicker(BuildContext context,
    {required int initial}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (_) => _PickerSheet(initial: initial),
  );
}

class _PickerSheet extends StatefulWidget {
  final int initial;
  const _PickerSheet({required this.initial});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(Color(0xFF000000 | widget.initial));

  int get _argb => _hsv.toColor().toARGB32();

  void _set(HSVColor next) {
    if (next == _hsv) return;
    setState(() => _hsv = next);
  }

  /// Keeps the mix and answers it at once: the list is in settings the
  /// moment [CustomColours.save] is called, and the file write behind
  /// it is no reason to hold the sheet open.
  void _save() {
    HapticFeedback.mediumImpact();
    final argb = _argb;
    unawaited(CustomColours.save(argb));
    Navigator.of(context).pop(argb);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final colour = _hsv.toColor();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D2537), Color(0xFF131A28)],
          ),
          border: Border(
              top: BorderSide(
                  color: AppColors.gold.withValues(alpha: 0.3), width: 0.9)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.stroke,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: A11yHeader(
                        child: Text(l.customColourTitle,
                            style: t.titleMedium?.copyWith(fontSize: 17)),
                      ),
                    ),
                    // What it is now, as a chip: the colour, lit, and
                    // its code.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsetsDirectional.fromSTEB(6, 5, 12, 5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.stroke),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: colour,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3)),
                              boxShadow: [
                                BoxShadow(
                                  color: colour.withValues(alpha: 0.6),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hexOf(_argb),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppColors.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AspectRatio(
                  aspectRatio: 1.7,
                  child: _Field(hsv: _hsv, onChanged: _set),
                ),
                const SizedBox(height: 14),
                _HueBar(hsv: _hsv, onChanged: _set),
                const SizedBox(height: 16),
                _Kept(
                  current: _argb,
                  onPick: (argb) {
                    HapticFeedback.selectionClick();
                    unawaited(CustomColours.save(argb));
                    Navigator.of(context).pop(argb);
                  },
                ),
                const SizedBox(height: 16),
                GlowButton(
                  label: l.customColourSave,
                  icon: Icons.check_rounded,
                  height: 52,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Saturation across, brightness down, for the hue on the bar. A drag
/// anywhere on it mixes; the ring follows the finger.
class _Field extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _Field({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      void at(Offset p) {
        final s = (p.dx / size.width).clamp(0.0, 1.0);
        final v = 1 - (p.dy / size.height).clamp(0.0, 1.0);
        onChanged(hsv.withSaturation(s).withValue(v));
      }

      final thumb = Offset(hsv.saturation * size.width,
          (1 - hsv.value) * size.height);
      return Semantics(
        label: l.customColourField,
        value: hexOf(hsv.toColor().toARGB32()),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) {
            HapticFeedback.selectionClick();
            at(d.localPosition);
          },
          onPanUpdate: (d) => at(d.localPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CustomPaint(painter: _FieldPainter(hsv.hue)),
                ),
              ),
              Positioned(
                left: thumb.dx - 14,
                top: thumb.dy - 14,
                child: IgnorePointer(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hsv.toColor(),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _FieldPainter extends CustomPainter {
  final double hue;
  const _FieldPainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white,
          HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
        ]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.hue != hue;
}

/// Every hue in one bar; the thumb wears the pure hue it stands on.
class _HueBar extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  const _HueBar({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      void at(double x) =>
          onChanged(hsv.withHue((x / w).clamp(0.0, 1.0) * 359.9));
      String hueAt(double h) => l.customColourHueValue(h.round() % 360);
      return A11yAdjustable(
        label: l.customColourHue,
        value: hueAt(hsv.hue),
        increasedValue: hueAt((hsv.hue + 15) % 360),
        decreasedValue: hueAt((hsv.hue - 15) % 360),
        onIncrease: () => onChanged(hsv.withHue((hsv.hue + 15) % 360)),
        onDecrease: () => onChanged(hsv.withHue((hsv.hue - 15) % 360)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => at(d.localPosition.dx),
          onPanUpdate: (d) => at(d.localPosition.dx),
          child: SizedBox(
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  top: 5,
                  bottom: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  left: (hsv.hue / 360 * w - 15).clamp(-6.0, w - 24),
                  child: IgnorePointer(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The colours already kept, every one of them: rows of them, three in
/// sight and the rest a scroll away. A tap uses one. The small "Remove"
/// beside the heading turns the taps into letting go — each colour
/// wears a cross until "Done" — and a long press lets one go any time.
class _Kept extends StatefulWidget {
  final int current;
  final ValueChanged<int> onPick;
  const _Kept({required this.current, required this.onPick});

  /// One kept colour, and the room between two.
  static const _cell = 30.0;
  static const _gap = 9.0;

  @override
  State<_Kept> createState() => _KeptState();
}

class _KeptState extends State<_Kept> {
  bool _removing = false;

  void _remove(int argb) {
    HapticFeedback.mediumImpact();
    unawaited(CustomColours.remove(argb));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) {
        final kept = s.customColours;
        // With nothing left to let go of, the switch is put back.
        final removing = _removing && kept.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.customColourKept,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (kept.isNotEmpty)
                  _RemoveSwitch(
                    on: removing,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _removing = !removing);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (kept.isEmpty)
              Text(
                l.customColourKeptEmpty,
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: AppColors.textSecondary),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(
                    maxHeight: 3 * _Kept._cell + 2 * _Kept._gap),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: _Kept._gap,
                    runSpacing: _Kept._gap,
                    children: [
                      for (final c in kept)
                        _KeptSwatch(
                          argb: c,
                          chosen: !removing &&
                              (c & 0xFFFFFF) == (widget.current & 0xFFFFFF),
                          removing: removing,
                          onTap: () => removing ? _remove(c) : widget.onPick(c),
                          onLongPress: () => _remove(c),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Remove", and "Done" while removing: small, beside the heading, out
/// of the way of the colours themselves.
class _RemoveSwitch extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const _RemoveSwitch({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final label = on ? l.customColourRemoveDone : l.customColourRemove;
    return A11yTap(
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 26,
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 10, 0),
          decoration: BoxDecoration(
            color: on
                ? AppColors.gold.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: on ? AppColors.gold.withValues(alpha: 0.7) : AppColors.stroke,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? Icons.check_rounded : Icons.remove_rounded,
                  size: 14,
                  color: on ? AppColors.goldBright : AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: on ? AppColors.goldBright : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One kept colour. While removing, a small cross on its corner says a
/// tap lets it go.
class _KeptSwatch extends StatelessWidget {
  final int argb;
  final bool chosen;
  final bool removing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _KeptSwatch({
    required this.argb,
    required this.chosen,
    required this.removing,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const size = _Kept._cell;
    return A11yTap(
      label: l.customColourIs(hexOf(argb)),
      hint: removing ? l.customColourTapToRemove : l.customColourKeptHint,
      selected: chosen,
      onTap: onTap,
      onLongPress: onLongPress,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: size,
                height: size,
                padding: EdgeInsets.all(removing ? 3 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: chosen
                        ? AppColors.goldBright
                        : Colors.white.withValues(alpha: removing ? 0 : 0.2),
                    width: chosen ? 2.5 : 1,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(argb),
                    shape: BoxShape.circle,
                    border: removing
                        ? Border.all(color: Colors.white.withValues(alpha: 0.2))
                        : null,
                  ),
                ),
              ),
              if (removing)
                const PositionedDirectional(
                  top: -3,
                  end: -3,
                  child: _Cross(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cross a kept colour wears while it can be let go.
class _Cross extends StatelessWidget {
  const _Cross();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2A3245),
        border: Border.all(color: AppColors.textSecondary, width: 0.8),
      ),
      child: const Icon(Icons.close_rounded,
          size: 10, color: AppColors.textPrimary),
    );
  }
}
