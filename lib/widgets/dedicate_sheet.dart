import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/dedication.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'reel_watermark.dart';

/// Asks who a reel or a card was made for.
///
/// One sheet for both, because it is one decision and one line of
/// wording — a second copy of it would be a second place for the
/// phrasing to drift, and this is the only text the app writes into
/// somebody else's hands.
///
/// Returns the dedication, an empty one if it was taken off, or null
/// if the sheet was dismissed without deciding.
///
/// [movable] says the line can be dragged where it lands, which a reel
/// allows and a card does not, and the sheet says so.
Future<Dedication?> showDedicateSheet(
  BuildContext context, {
  required Dedication dedication,
  bool movable = false,
}) {
  return showModalBottomSheet<Dedication>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _DedicateSheet(current: dedication, movable: movable),
  );
}

class _DedicateSheet extends StatefulWidget {
  final Dedication current;
  final bool movable;
  const _DedicateSheet({required this.current, required this.movable});

  @override
  State<_DedicateSheet> createState() => _DedicateSheetState();
}

class _DedicateSheetState extends State<_DedicateSheet> {
  /// A new dedication starts on sadaqah jariyah. One that already
  /// exists opens on the intention it was made with.
  late DedicationKind _kind = widget.current.isEmpty
      ? DedicationKind.sadaqah
      : widget.current.kind;
  late final _controller = TextEditingController(text: widget.current.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Dedication get _value =>
      Dedication(kind: _kind).copyWith(name: _controller.text);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    final value = _value;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        // Scrollable, so on a short phone the keyboard the field opens
        // with pushes the sheet up under it rather than covering Save.
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              A11yHeader(child: Text(l.dedicateTitle, style: t.titleMedium)),
              const SizedBox(height: 6),
              Text(l.dedicateBlurb,
                  style: t.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.5)),
              const SizedBox(height: 16),
              // Two intentions, and they are not the same act — so they
              // are two choices with a sentence each, rather than a
              // switch somebody has to guess the meaning of.
              _Kind(
                label: l.dedicateGift,
                hint: l.dedicateGiftHint,
                icon: Icons.card_giftcard_rounded,
                selected: _kind == DedicationKind.gift,
                onTap: () => setState(() => _kind = DedicationKind.gift),
              ),
              const SizedBox(height: 8),
              _Kind(
                label: l.dedicateSadaqah,
                hint: l.dedicateSadaqahHint,
                icon: Icons.all_inclusive_rounded,
                selected: _kind == DedicationKind.sadaqah,
                onTap: () => setState(() => _kind = DedicationKind.sadaqah),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: widget.current.isEmpty,
                textCapitalization: TextCapitalization.words,
                maxLength: Dedication.maxName,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _done(),
                style: t.bodyMedium?.copyWith(
                    color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: l.dedicateNameHint,
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.bg.withValues(alpha: 0.6),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.stroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.gold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // The line itself, drawn by the very widget that will
              // burn it into the reel — so what is promised here is
              // what is delivered there.
              _Preview(dedication: value),
              if (widget.movable) ...[
                const SizedBox(height: 8),
                Text(l.dedicateMoveHint,
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.4)),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 14),
              Row(
                children: [
                  if (widget.current.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(Dedication.none),
                      child: Text(l.remove,
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: value.isEmpty ? null : _done,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: const Color(0xFF14100A),
                      disabledBackgroundColor: AppColors.surfaceRaised,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      value.isEmpty ? l.dedicateNameMissing : l.save,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  void _done() {
    final value = _value;
    if (value.isEmpty) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(value);
  }
}

/// One of the two intentions: what it is called, and what it means.
class _Kind extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _Kind({
    required this.label,
    required this.hint,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: '$label. $hint',
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
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.55)
                  : AppColors.stroke,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? AppColors.goldBright
                      : AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                          color: AppColors.textPrimary,
                        )),
                    const SizedBox(height: 2),
                    Text(hint,
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: AppColors.textSecondary)),
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

/// The dedication as it will appear, on a strip of night.
class _Preview extends StatelessWidget {
  final Dedication dedication;
  const _Preview({required this.dedication});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final line =
        dedication.isEmpty ? '' : l.dedicationLine(dedication.kind, dedication.name);
    return Semantics(
      label: line.isEmpty ? null : l.a11yDedication(line),
      excludeSemantics: true,
      child: Container(
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF10151C), Color(0xFF05070A)],
          ),
          border: Border.all(color: AppColors.stroke),
        ),
        // Laid out at a third of export width, which is what the reel
        // is drawn at on a phone — every size inside it is a fraction
        // of this, so the strip is the bottom of the reel to scale:
        // the line on its own once there is one, and until then the
        // bare mark, which is what an undedicated reel signs off with.
        child: line.isEmpty
            ? const ReelWatermarkMark(width: 360)
            : ReelDedicationLine(width: 360, line: line),
      ),
    );
  }
}
