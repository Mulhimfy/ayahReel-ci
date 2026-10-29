import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_version.dart';
import '../data/debug_log.dart';
import '../data/fatiha_data.dart';
import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../render/on_screen.dart';
import '../theme/app_theme.dart';

/// What 1.0.10 brought, said once, to the people who had the app
/// before it.
///
/// Never to a new install, and never in any other version: the first
/// launch of this version decides, and the decision is kept. Somebody
/// who had finished onboarding by then was here before it; a phone
/// still to see onboarding is new, and is marked as told on that very
/// launch, so finishing onboarding later changes nothing. Shown on Home
/// with nothing over it, once; marked as shown before it is answered,
/// so an app closed with it open never brings it back.
abstract final class WhatsNew {
  /// The one version this note is about. Any other version never reads
  /// or writes the record.
  static const forVersion = '1.0.10';

  static const fileName = 'whats_new.json';

  /// Into a launch: long enough for Home to land first.
  static const delay = Duration(milliseconds: 1500);

  /// While Home is covered (a widget tap, a notification, a sheet), how
  /// often it looks again, and for how long before leaving it for the
  /// next launch.
  static const retry = Duration(seconds: 3);
  static const tries = 40;

  static bool _shownThisLaunch = false;

  /// It came up in this launch: the Telegram invitation keeps away
  /// until the next one, so two asks never follow each other.
  static bool get shownThisLaunch => _shownThisLaunch;

  /// The dialog itself, for a test to open.
  @visibleForTesting
  static Widget dialog() => const _WhatsNewDialog();

  /// Whether the note is still to show. [recorded] is what the record
  /// says — null on the first launch of this version, when it doesn't
  /// exist yet; [onboarded] is the settings' onboarding flag as this
  /// launch read it, before onboarding could change it.
  @visibleForTesting
  static bool pending({
    required String version,
    required bool? recorded,
    required bool onboarded,
  }) {
    if (version != forVersion) return false;
    return recorded ?? onboarded;
  }

  /// At boot, straight after [SettingsService.init].
  static Future<void> start(GlobalKey<NavigatorState> navigator) async {
    if (kAppVersion != forVersion) return;
    // Read before anything is awaited: a new install finishing
    // onboarding must never pass for an old one.
    final onboarded = SettingsService.state.value.onboardingDone;
    try {
      final f = await _file();
      bool? recorded;
      if (f.existsSync()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        recorded = j['for'] == forVersion && j['pending'] == true;
      }
      final show = pending(
          version: kAppVersion, recorded: recorded, onboarded: onboarded);
      if (recorded == null) await _save(show);
      if (show) _schedule(navigator, 0);
    } catch (e) {
      rlog('whats new: $e');
    }
  }

  static void _schedule(GlobalKey<NavigatorState> navigator, int tried) {
    Timer(tried == 0 ? delay : retry, () async {
      if (await _show(navigator)) return;
      if (tried + 1 < tries) _schedule(navigator, tried + 1);
    });
  }

  /// Shows it if Home is on screen with nothing over it. False when it
  /// couldn't, to be tried again.
  static Future<bool> _show(GlobalKey<NavigatorState> navigator) async {
    final nav = navigator.currentState;
    final context = navigator.currentContext;
    if (nav == null || context == null || !OnScreen.now) return false;
    if (nav.canPop()) return false;
    if (!SettingsService.state.value.onboardingDone) return false;
    _shownThisLaunch = true;
    await _save(false);
    rlog('whats new: shown');
    if (!context.mounted) return true;
    await showDialog<void>(
      context: context,
      builder: (_) => const _WhatsNewDialog(),
    );
    return true;
  }

  static Future<void> _save(bool pending) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      tmp.writeAsStringSync(
          jsonEncode({'for': forVersion, 'pending': pending}),
          flush: true);
      tmp.renameSync(f.path);
    } catch (e) {
      rlog('whats new: could not save: $e');
    }
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$fileName');
}

class _WhatsNewDialog extends StatelessWidget {
  const _WhatsNewDialog();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    String name(String id) {
      for (final r in reciters) {
        if (r.id == id) return l.reciterName(r);
      }
      return id;
    }

    final items = [
      l.whatsNewReciters(name('luhaidan'), name('sobhi')),
      l.whatsNewMotion,
      l.whatsNewShare,
      l.whatsNewBismillahSearch,
      l.whatsNewFaster,
    ];
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.gold, size: 30),
              const SizedBox(height: 12),
              Text(l.whatsNewTitle,
                  textAlign: TextAlign.center, style: text.titleLarge),
              const SizedBox(height: 4),
              Text(WhatsNew.forVersion,
                  textAlign: TextAlign.center,
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsetsDirectional.only(
                                    top: 7, end: 12),
                                child: SizedBox(
                                  width: 6,
                                  height: 6,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: AppColors.gold,
                                        shape: BoxShape.circle),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(item, style: text.bodyMedium),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.whatsNewDone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
