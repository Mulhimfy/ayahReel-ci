import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/debug_log.dart';
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
    this.launches = 0,
    this.snoozes = 0,
    this.nextAt,
  });

  /// Good moments since this code first ran.
  final int moments;
  final int shows;
  final DateTime? firstShown;
  final DateTime? lastShown;

  /// Joined, "Already joined" or "Don't ask again": never again.
  final bool joined;

  /// Times the app was opened since this code first ran.
  final int launches;

  /// Times "Not now" was answered (or the invitation waved away).
  final int snoozes;

  /// Not before this, after a "Not now".
  final DateTime? nextAt;

  TelegramInviteRecord copyWith({
    int? moments,
    int? shows,
    DateTime? firstShown,
    DateTime? lastShown,
    bool? joined,
    int? launches,
    int? snoozes,
    DateTime? nextAt,
  }) =>
      TelegramInviteRecord(
        moments: moments ?? this.moments,
        shows: shows ?? this.shows,
        firstShown: firstShown ?? this.firstShown,
        lastShown: lastShown ?? this.lastShown,
        joined: joined ?? this.joined,
        launches: launches ?? this.launches,
        snoozes: snoozes ?? this.snoozes,
        nextAt: nextAt ?? this.nextAt,
      );

  Map<String, dynamic> toJson() => {
        'moments': moments,
        'shows': shows,
        if (firstShown != null) 'first': firstShown!.millisecondsSinceEpoch,
        if (lastShown != null) 'last': lastShown!.millisecondsSinceEpoch,
        if (joined) 'joined': true,
        'launches': launches,
        'snoozes': snoozes,
        if (nextAt != null) 'next': nextAt!.millisecondsSinceEpoch,
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
      launches: (j['launches'] as int?) ?? 0,
      snoozes: (j['snoozes'] as int?) ?? 0,
      nextAt: at(j['next']),
    );
  }
}

/// What the invitation was answered with.
@visibleForTesting
enum TelegramAnswer {
  /// Join: the channel opens, and it is never asked again.
  join,

  /// Already a member: never asked again.
  joined,

  /// Don't ask again: never asked again.
  never,

  /// Not now — or the invitation waved away: asked again later.
  notNow,
}

/// The invitation to the app's Telegram channel.
///
/// Early, because the people most worth reaching are the ones who have
/// just found the app: it comes a few seconds after the first good
/// moment ([TelegramMoment]: a saved reel, a card, a quiz, a badge), or
/// half a minute into the second time the app is opened if nothing good
/// has happened yet — never on a first open with nothing done, never
/// over another dialog or sheet, never in the middle of making
/// something, and never with the app away.
///
/// Answered "Not now", it comes back later, every time: [snoozeSteps]
/// after the first "Not now", then longer, and then every
/// [snoozeSteps.last] for as long as it is put off. Join, "Already
/// joined" or "Don't ask again" end it for good, and so does the
/// channel already opened from Settings.
abstract final class TelegramInvite {
  static const url = 'https://t.me/AyahReel';

  /// How long a "Not now" holds it off: the first, the second, the
  /// third, and every one after that.
  static const snoozeSteps = [
    Duration(days: 2),
    Duration(days: 4),
    Duration(days: 7),
    Duration(days: 10),
  ];

  /// Into a launch, before a launch alone may bring it: time to land
  /// on Home and see what is new before anything asks for anything.
  static const launchDelay = Duration(seconds: 30);

  static const fileName = 'telegram_invite.json';

  /// The invitation itself, for a test to open and answer.
  @visibleForTesting
  static Widget dialog() => const _InviteDialog();

  static GlobalKey<NavigatorState>? _navigator;
  static TelegramInviteRecord? _record;
  static Timer? _pending;
  static int _badges = 0;

  /// How long the [snoozes]th "Not now" holds the invitation off.
  @visibleForTesting
  static Duration snoozeAfter(int snoozes) =>
      snoozeSteps[(snoozes - 1).clamp(0, snoozeSteps.length - 1)];

  /// At boot: where to show it, the badges to follow, every new one of
  /// which is an achievement moment — and this launch, counted, which
  /// may bring the invitation by itself once the app is settled.
  static Future<void> start(GlobalKey<NavigatorState> navigator) async {
    _navigator = navigator;
    await RewardsService.init();
    _badges = RewardsService.state.value.badges.length;
    RewardsService.state.addListener(() {
      final n = RewardsService.state.value.badges.length;
      if (n > _badges) unawaited(after(TelegramMoment.achievement));
      _badges = n;
    });
    try {
      final r = await _load();
      if (r.joined) return;
      final next = r.copyWith(launches: r.launches + 1);
      await _save(next);
      if (_pending == null && _dueNow(next)) {
        _pending = Timer(launchDelay, () {
          _pending = null;
          // A launch is not a moment: only on Home with nothing open,
          // never over a reel being made.
          unawaited(_show(atRest: true));
        });
      }
    } catch (e) {
      rlog('telegram invite: $e');
    }
  }

  /// A good moment has passed: counted, and followed by the invitation
  /// after [TelegramMoment.delay] when it is due. One at a time: a
  /// moment while one waits only counts. Nothing before [start], which
  /// the app calls at boot and a widget test never does.
  static Future<void> after(TelegramMoment moment) async {
    if (_navigator == null) return;
    try {
      final r = await _load();
      if (r.joined) return;
      final next = r.copyWith(moments: r.moments + 1);
      await _save(next);
      if (!_dueNow(next)) return;
      // A moment outranks a launch's wait: it is the better time.
      _pending?.cancel();
      _pending = Timer(moment.delay, () {
        _pending = null;
        unawaited(_show());
      });
    } catch (e) {
      rlog('telegram invite: $e');
    }
  }

  /// Whether the invitation is due at [now]. [opened]: the channel was
  /// opened from Settings.
  ///
  /// The first time, after the first good moment or from the second
  /// launch on; after a "Not now", once its hold has run out.
  @visibleForTesting
  static bool due(
    TelegramInviteRecord r,
    DateTime now, {
    required bool opened,
    int reelsMade = 0,
  }) {
    if (r.joined || opened) return false;
    if (r.shows == 0) {
      return r.moments >= 1 || reelsMade >= 1 || r.launches >= 2;
    }
    // Records from before "Not now" came back have no hold written:
    // theirs runs from the last time it was shown.
    final last = r.lastShown ?? r.firstShown;
    final next = r.nextAt ?? last?.add(snoozeAfter(r.snoozes.clamp(1, 99)));
    return next == null || !now.isBefore(next);
  }

  /// The record after the invitation shown at [now] is answered.
  @visibleForTesting
  static TelegramInviteRecord answered(
      TelegramInviteRecord r, TelegramAnswer a, DateTime now) {
    if (a != TelegramAnswer.notNow) return r.copyWith(joined: true);
    final snoozes = r.snoozes + 1;
    return r.copyWith(snoozes: snoozes, nextAt: now.add(snoozeAfter(snoozes)));
  }

  static bool _dueNow(TelegramInviteRecord r) => due(
        r,
        DateTime.now(),
        opened: SettingsService.state.value.telegramNudgeSeen,
        reelsMade: RewardsService.state.value.reelsMade,
      );

  /// [atRest]: only on the screen the app opens on, with nothing pushed
  /// over it — what a launch asks for, where a moment is its own time.
  static Future<void> _show({bool atRest = false}) async {
    final nav = _navigator?.currentState;
    final context = _navigator?.currentContext;
    if (nav == null || context == null || !OnScreen.now) return;
    if (atRest && nav.canPop()) return;
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
    final shown = r.copyWith(
      shows: r.shows + 1,
      firstShown: r.firstShown ?? now,
      lastShown: now,
    );
    // Written before it is answered, with the hold a "Not now" would
    // give: an app killed with the invitation up must not show it again
    // on the very next open.
    await _save(answered(shown, TelegramAnswer.notNow, now)
        .copyWith(snoozes: shown.snoozes));
    rlog('telegram invite: shown (${shown.shows})');
    if (!context.mounted) return;
    final choice = await showDialog<TelegramAnswer>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    final answer = choice ?? TelegramAnswer.notNow;
    await _save(answered(shown, answer, DateTime.now()));
    rlog('telegram invite: ${answer.name}');
    if (answer == TelegramAnswer.notNow) return;
    final s = SettingsService.state.value;
    if (!s.telegramNudgeSeen) {
      unawaited(SettingsService.update(s.copyWith(telegramNudgeSeen: true)));
    }
    if (answer != TelegramAnswer.join) return;
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

class _InviteDialog extends StatelessWidget {
  const _InviteDialog();

  /// Telegram's own blue.
  static const _blue = Color(0xFF229ED9);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final text = Theme.of(context).textTheme;
    void answer(TelegramAnswer a) => Navigator.of(context).pop(a);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
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
                onPressed: () => answer(TelegramAnswer.join),
                child: Text(l.telegramJoin),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => answer(TelegramAnswer.notNow),
                    child: Text(l.notNow, textAlign: TextAlign.center),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => answer(TelegramAnswer.joined),
                    child: Text(l.telegramJoined, textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
            // The way out for good, quieter than the rest: a choice to
            // honour, not to invite.
            TextButton(
              onPressed: () => answer(TelegramAnswer.never),
              style: TextButton.styleFrom(
                foregroundColor:
                    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                textStyle: text.labelLarge?.copyWith(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(l.telegramNever, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
