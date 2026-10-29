import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/home_widget_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'illumination.dart';

/// The sheet that walks through putting the widget on the home screen.
///
/// Always the steps, whichever phone: neither OS lets an app place a
/// widget by itself, and even Android's pin request only opens the
/// launcher's own confirmation, which some launchers do not have. So
/// the steps are the promise, and on Android "Add it now" sits above
/// them as the shortcut for the launchers that take it.
Future<void> showWidgetSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const WidgetSheet(),
  );
}

class WidgetSheet extends StatefulWidget {
  /// Overridable for tests: which phone's steps to show, and whether
  /// the launcher can be asked to place the widget.
  final bool? android;
  final Future<bool> Function()? canRequestPin;
  final Future<bool> Function()? isInstalled;

  const WidgetSheet({
    super.key,
    this.android,
    this.canRequestPin,
    this.isInstalled,
  });

  @override
  State<WidgetSheet> createState() => _WidgetSheetState();
}

class _WidgetSheetState extends State<WidgetSheet> {
  bool _pinnable = false;
  bool _installed = false;

  bool get _android => widget.android ?? (!kIsWeb && Platform.isAndroid);

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final pin =
        await (widget.canRequestPin ?? HomeWidgetService.canRequestPin)();
    final installed =
        await (widget.isInstalled ?? HomeWidgetService.isInstalled)();
    if (!mounted) return;
    setState(() {
      _pinnable = pin;
      _installed = installed;
    });
  }

  Future<void> _addNow() async {
    HapticFeedback.mediumImpact();
    final asked = await HomeWidgetService.requestPin();
    // The launcher's own dialog is now up; the sheet has done its job.
    if (asked && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final steps = _android ? l.widgetStepsAndroid : l.widgetStepsIos;
    // Scrolls when it has to — a small phone in a large font — and is
    // no taller than it needs to be otherwise.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(Icons.widgets_outlined,
                      size: 20, color: AppColors.goldBright),
                  const SizedBox(width: 10),
                  Expanded(
                    child: A11yHeader(
                      child: Text(l.widgetSheetTitle,
                          style: t.titleMedium?.copyWith(fontSize: 18)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                l.widgetSheetBody,
                style: t.bodySmall?.copyWith(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              const _WidgetPreview(),
              if (_pinnable) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _addNow,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: const Color(0xFF14100A),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(l.widgetAddNow,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  A11yHeader(
                    child: Text(
                      l.widgetHowToAdd,
                      style: t.bodySmall?.copyWith(
                        color: AppColors.gold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: OrnamentHairline(towardsEnd: true)),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < steps.length; i++) ...[
                _Step(number: i + 1, text: steps[i]),
                if (i < steps.length - 1) const SizedBox(height: 8),
              ],
              if (_installed) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 15, color: AppColors.goldBright),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        l.widgetAlreadyAdded,
                        style: t.bodySmall?.copyWith(
                            color: AppColors.goldBright, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(
                        color: AppColors.gold.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(l.tourDone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One numbered line of the instructions.
class _Step extends StatelessWidget {
  final int number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // One line per step: "1. Touch and hold…", not a number and then
    // a sentence as two things.
    return MergeSemantics(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold.withValues(alpha: 0.14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
          ),
          child: Text(
            '$number',
            style: t.bodySmall?.copyWith(
              color: AppColors.goldBright,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: t.bodyMedium?.copyWith(
                  color: AppColors.textPrimary, fontSize: 13.5, height: 1.4),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

/// A small picture of what they are adding: the widget's shape, its
/// label, and a line of the script — so the steps are for something
/// they have already seen.
class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    // A picture of the widget, described as one rather than read as
    // a label, a verse and a reference that belong to nothing.
    return Semantics(
      image: true,
      label: l.a11yWidgetPreview,
      excludeSemantics: true,
      child: AspectRatio(
      aspectRatio: 2.15,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2340), Color(0xFF12101C)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            // Stretched, so the verse's centring is across the card and
            // not within a one-line verse's own shrink-wrapped width.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SealGlyph(size: 7),
                  const SizedBox(width: 6),
                  Text(
                    l.verseFromTheQuran,
                    style: t.bodySmall?.copyWith(
                      color: AppColors.gold,
                      fontSize: 9.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'فَٱذْكُرُونِىٓ أَذْكُرْكُمْ وَٱشْكُرُوا لِى وَلَا تَكْفُرُونِ',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.quran(size: 15, color: AppColors.goldBright)
                    .copyWith(height: 1.5),
              ),
              const Spacer(),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  l.verseReference('Al-Baqarah', 152, 152),
                  style: t.bodySmall
                      ?.copyWith(color: AppColors.textSecondary, fontSize: 9.5),
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
