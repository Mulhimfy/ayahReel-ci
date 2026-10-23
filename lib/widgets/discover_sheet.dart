import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'illumination.dart';

/// Things the app does that nobody would guess.
///
/// Every one of these is a real affordance that is already on screen
/// and carries no label: a long press, a drag, a tap on something that
/// did not look tappable. An app can either put a hint next to each of
/// them — which is thirteen more words on thirteen screens, and a
/// worse app — or collect them somewhere a curious person will look.
/// This is that place.
///
/// The rule for what belongs here: it has to be *true on this build*,
/// reachable without turning anything on, and not already labelled
/// where it lives. When an affordance gets a visible label of its own,
/// its entry comes out of this list.
///
/// Each in plain words, as short as it can be and still say where the
/// thing is and what it does: a title that is the thing itself, and one
/// line under it.
///
/// And it has to be worth a scroll. The list reached sixteen entries —
/// six of them about cards — and a list that long is not a sheet
/// somebody reads, it is one they close: the two or three gestures
/// that actually change how the app is used were buried among a dozen
/// conveniences nobody needed told. So this is the short list, kept
/// short on purpose. Every entry here changes what a person can make;
/// an entry that only saves them a tap belongs in the app, unlabelled,
/// where they will find it on their own. The wording for the ones that
/// came out is still in [L10n.discovery], so putting one back is one
/// line.
const discoveries = <({String id, IconData icon})>[
  (id: 'luminous', icon: Icons.auto_awesome_rounded),
  (id: 'size-on-reel', icon: Icons.swipe_vertical_rounded),
  (id: 'scene-match', icon: Icons.auto_awesome_outlined),
  (id: 'verse-to-reel', icon: Icons.auto_stories_outlined),
  (id: 'hold-to-extend', icon: Icons.touch_app_outlined),
  (id: 'reel-edit', icon: Icons.edit_note_rounded),
  (id: 'offline', icon: Icons.download_rounded),
  (id: 'living-home', icon: Icons.landscape_outlined),
  (id: 'card-carry', icon: Icons.style_outlined),
];

/// Opens the list as the app's standard bottom sheet.
Future<void> showDiscoverSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const DiscoverSheet(),
  );
}

class DiscoverSheet extends StatelessWidget {
  const DiscoverSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Tall, but never the whole screen: a sheet that reaches the
        // status bar reads as a screen that cannot be dismissed.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.stroke,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  A11yHeader(
                    child: Text(l.discoverTitle, style: t.titleMedium),
                  ),
                  const SizedBox(height: 6),
                  Text(l.discoverBlurb,
                      style: t.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.5)),
                  const SizedBox(height: 10),
                  const OrnamentHairline(towardsEnd: true),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
                itemCount: discoveries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, i) {
                  final (title, body) = l.discovery(discoveries[i].id);
                  return _Row(
                    icon: discoveries[i].icon,
                    title: title,
                    body: body,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One discovery: a glyph, a line, and the sentence that says where to
/// find it. No button — everything here is somewhere else in the app,
/// and a shortcut would teach the shortcut instead of the gesture.
class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Row({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.30)),
            ),
            child: Icon(icon, size: 16, color: AppColors.goldBright),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: t.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3)),
                const SizedBox(height: 4),
                Text(body,
                    style: t.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
