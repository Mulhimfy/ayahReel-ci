import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/debug_log.dart';
import '../data/install_date.dart';
import '../data/rewards_service.dart';
import '../data/settings_service.dart';
import '../l10n/l10n.dart';
import '../render/on_screen.dart';

/// A good moment the Telegram invitation may follow, and how long
/// after: long enough for the moment's own word (a badge, a result, a
/// saved reel) to be read first, so the invitation never covers it.
enum TelegramMoment {
  achievement(Duration(seconds: 8)),
  quiz(Duration(seconds: 10)),
  card(Duration(seconds: 8)),
  reel(Duration(seconds: 15));

  const TelegramMoment(this.delay);
  final Duration delay;
}

/// What the invitation remembers between launches.
@visibleForTesting
class TelegramInviteRecord {
  const TelegramInviteRecord({
    this.moments = 0,
    this.shows = 0,
    this.firstShown,
    this.lastShown,
    this.joined = false,
  });

  /// Good moments since this code first ran.
  final int moments;
  final int shows;
  final DateTime? firstShown;
  final DateTime? lastShown;

  /// Tapped Join or "I've joined": never again.
  final bool joined;

  TelegramInviteRecord copyWith({
    int? moments,
    int? shows,
    DateTime? firstShown,
    DateTime? lastShown,
    bool? joined,
  }) =>
      TelegramInviteRecord(
        moments: moments ?? this.moments,
        shows: shows ?? this.shows,
        firstShown: firstShown ?? this.firstShown,
        lastShown: lastShown ?? this.lastShown,
        joined: joined ?? this.joined,
      );

  Map<String, dynamic> toJson() => {
        'moments': moments,
        'shows': shows,
        if (firstShown != null) 'first': firstShown!.millisecondsSinceEpoch,
        if (lastShown != null) 'last': lastShown!.millisecondsSinceEpoch,
        if (joined) 'joined': true,
      };

  factory TelegramInviteRecord.fromJson(Map<String, dynamic> j) {
    DateTime? at(Object? ms) =>
        ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    return TelegramInviteRecord(
      moments: (j['moments'] as int?) ?? 0,
      shows: (j['shows'] as int?) ?? 0,
      firstShown: at(j['first']),
      lastShown: at(j['last']),
      joined: j['joined'] == true,
    );
  }
}

/// The invitation to the app's Telegram channel, a few seconds after a
/// good moment ([TelegramMoment]).
///
/// Twice in a lifetime at most, both inside one week, and never to
/// someone new: not on the first open, not at a first badge, but once
/// the app has been on the phone for [minAge] and its owner has had
/// [minMoments] good moments in it. The second comes [secondAfter] or
/// more after the first, and only inside the first one's [window].
/// Join or "I've joined" ends it for good, and so does the channel
/// already opened from Settings. It never stacks on another dialog or
/// sheet, and never shows with the app away; a moment it skips for
/// that isn't one of its two.
abstract final class TelegramInvite {
  static const url = 'https://t.me/AyahReel';
  static const minAge = Duration(days: 3);
  static const minMoments = 3;
  static const secondAfter = Duration(days: 2);
  static const window = Duration(days: 7);
  static const maxShows = 2;

  static const fileName = 'telegram_invite.json';

  static GlobalKey<NavigatorState>? _navigator;
  static TelegramInviteRecord? _record;
  static Timer? _pending;
  static int _badges = 0;

  /// At boot: where to show it, and the badges to follow, every new
  /// one of which is an achievement moment.
  static Future<void> start(GlobalKey<NavigatorState> navigator) async {
    _navigator = navigator;
    await RewardsService.init();
    _badges = RewardsService.state.value.badges.length;
    RewardsService.state.addListener(() {
      final n = RewardsService.state.value.badges.length;
      if (n > _badges) unawaited(after(TelegramMoment.achievement));
      _badges = n;
    });
  }

  /// A good moment has passed: counted, and followed by the invitation
  /// after [TelegramMoment.delay] when it is due. One at a time: a
  /// moment while one waits only counts.
  static Future<void> after(TelegramMoment moment) async {
    try {
      final r = await _load();
      if (r.joined || r.shows >= maxShows) return;
      final next = r.copyWith(moments: r.moments + 1);
      await _save(next);
      if (_pending != null || !_dueNow(next)) return;
      _pending = Timer(moment.delay, () {
        _pending = null;
        unawaited(_show());
      });
    } catch (e) {
      rlog('telegram invite: $e');
    }
  }

  /// Whether the invitation is due at [now]. [aged]: the app has been
  /// on the phone for [minAge]. [opened]: the channel was opened from
  /// Settings. [reelsMade] stands in for the moments of somebody who
  /// made reels before this code counted any.
  @visibleForTesting
  static bool due(
    TelegramInviteRecord r,
    DateTime now, {
    required bool aged,
    required bool opened,
    int reelsMade = 0,
  }) {
    if (r.joined || opened || r.shows >= maxShows) return false;
    final first = r.firstShown;
    if (r.shows == 0 || first == null) {
      return aged && (r.moments >= minMoments || reelsMade >= minMoments);
    }
    final last = r.lastShown ?? first;
    return now.difference(last) >= secondAfter &&
        now.difference(first) < window;
  }

  static bool _dueNow(TelegramInviteRecord r) {
    final now = DateTime.now();
    final since = InstallDate.since;
    return due(
      r,
      now,
      aged: InstallDate.before ||
          since == null ||
          now.difference(since) >= minAge,
      opened: SettingsService.state.value.telegramNudgeSeen,
      reelsMade: RewardsService.state.value.reelsMade,
    );
  }

  static Future<void> _show() async {
    final nav = _navigator?.currentState;
    final context = _navigator?.currentContext;
    if (nav == null || context == null || !OnScreen.now) return;
    // Something already asks for the user's attention: the rating ask,
    // a reminder invitation, a sheet they opened. Not over it.
    Route<dynamic>? top;
    nav.popUntil((route) {
      top = route;
      return true;
    });
    if (top is PopupRoute) return;
    final r = await _load();
    if (!_dueNow(r)) return;
    final now = DateTime.now();
    await _save(r.copyWith(
      shows: r.shows + 1,
      firstShown: r.firstShown ?? now,
      lastShown: now,
    ));
    rlog('telegram invite: shown (${r.shows + 1} of $maxShows)');
    if (!context.mounted) return;
    final choice = await showDialog<_Choice>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    if (choice == null) return;
    await _save((await _load()).copyWith(joined: true));
    final s = SettingsService.state.value;
    if (!s.telegramNudgeSeen) {
      unawaited(SettingsService.update(s.copyWith(telegramNudgeSeen: true)));
    }
    if (choice != _Choice.join) return;
    try {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) rlog('telegram invite: could not open $url');
    } catch (e) {
      rlog('telegram invite: could not open $url: $e');
    }
  }

  static Future<TelegramInviteRecord> _load() async {
    final known = _record;
    if (known != null) return known;
    try {
      final f = await _file();
      if (f.existsSync()) {
        return _record = TelegramInviteRecord.fromJson(
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      }
    } catch (e) {
      rlog('telegram invite: unreadable record: $e');
    }
    return _record = const TelegramInviteRecord();
  }

  static Future<void> _save(TelegramInviteRecord r) async {
    _record = r;
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(r.toJson()), flush: true);
      tmp.renameSync(f.path);
    } catch (e) {
      rlog('telegram invite: could not save: $e');
    }
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$fileName');
}

enum _Choice { join, joined }

class _InviteDialog extends StatelessWidget {
  const _InviteDialog();

  /// Telegram's own blue.
  static const _blue = Color(0xFF229ED9);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration:
                  const BoxDecoration(color: _blue, shape: BoxShape.circle),
              // The paper plane, pointing up and right as Telegram's
              // does in every language: the send icon mirrors itself
              // in Arabic and Urdu.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Transform.rotate(
                  angle: -0.45,
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 30),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(l.telegramInviteTitle,
                textAlign: TextAlign.center, style: text.titleLarge),
            const SizedBox(height: 8),
            Text(l.telegramInviteBody,
                textAlign: TextAlign.center, style: text.bodyMedium),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _blue, foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).pop(_Choice.join),
                child: Text(l.telegramJoin),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(_Choice.joined),
                    child: Text(l.telegramJoined, textAlign: TextAlign.center),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.notNow, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
