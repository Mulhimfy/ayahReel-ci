import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/home_widget_service.dart';
import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'widget_sheet.dart';

/// The home tab's invitation to add the widget.
///
/// It comes back every other day after being dismissed, and stops for
/// good once the widget is actually on the home screen — the one thing
/// the app can check, so it never nags for something already done.
/// Nothing is shown until both answers are in; a banner that flashes
/// and vanishes is worse than none.
class WidgetNudge extends StatefulWidget {
  /// Overridable for tests.
  final Future<bool> Function() isInstalled;
  final DateTime Function() now;

  const WidgetNudge({
    super.key,
    this.isInstalled = HomeWidgetService.isInstalled,
    this.now = DateTime.now,
  });

  /// How long a dismissal holds it off.
  static const holdOff = Duration(days: 2);

  /// Whether the nudge is due, given when it was last dismissed.
  static bool due(AppSettings s, DateTime now) =>
      now.millisecondsSinceEpoch - s.widgetNudgeDismissedAt >=
      holdOff.inMilliseconds;

  @override
  State<WidgetNudge> createState() => _WidgetNudgeState();
}

class _WidgetNudgeState extends State<WidgetNudge> with WidgetsBindingObserver {
  /// Null until the widget has been looked for.
  bool? _installed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Adding a widget happens outside the app; look again on the way
  /// back in so the banner goes the moment it is no longer needed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final installed = await widget.isInstalled();
    if (mounted && installed != _installed) {
      setState(() => _installed = installed);
    }
  }

  void _dismiss() {
    HapticFeedback.selectionClick();
    SettingsService.update(SettingsService.state.value
        .copyWith(widgetNudgeDismissedAt: widget.now().millisecondsSinceEpoch));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) {
        final show = _installed == false && WidgetNudge.due(s, widget.now());
        // Animated out rather than cut, so dismissing it reads as the
        // page closing over the gap instead of a jump.
        return AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: show
              ? _Banner(
                  onHow: () => showWidgetSheet(context), onClose: _dismiss)
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final VoidCallback onHow;
  final VoidCallback onClose;
  const _Banner({required this.onHow, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    // One block to a screen reader — its two lines, then its two
    // buttons — read in its own place on the page rather than hoisted
    // above the verse card it sits under.
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Semantics(
        container: true,
        child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.36)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.widgets_outlined,
                  size: 18, color: AppColors.goldBright),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.widgetNudgeTitle,
                      style: t.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    l.widgetNudgeBody,
                    style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.45),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: onHow,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.goldBright,
                            side: BorderSide(
                                color: AppColors.gold.withValues(alpha: 0.55)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11)),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 15),
                          label: Text(l.widgetShowMeHow),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: onClose,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                        child: Text(l.notNow),
                      ),
                    ],
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
