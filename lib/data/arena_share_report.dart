import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';
import 'arena_engine.dart';
import 'arena_service.dart';
import 'debug_log.dart';
import 'feedback_service.dart';
import 'install_date.dart';
import 'reel_library.dart';
import 'rewards_service.dart';
import 'settings_service.dart';
import 'whole_file.dart';

/// The door a Tanafus result went out through.
enum ArenaShareDoor {
  /// "Send to Instagram story".
  instagramStory,

  /// "Share the card": the system share sheet.
  shareCard,

  /// "Share to": straight into one app, named in [ArenaShareFacts.via].
  shareTo,
}

/// What the result screen knows about the round being shared, at the
/// moment of the tap.
@immutable
class ArenaShareFacts {
  final ArenaShareDoor door;
  final ArenaResult result;
  final ArenaMode mode;

  /// Where the round was played, in English: the inbox's language.
  final String scope;

  /// The score of the code it was played against, if it was.
  final int? rivalScore;

  /// What the card carries as it goes: the score, the player's name
  /// and the surah or juz, as the card's menu has them.
  final bool cardScore;
  final bool cardScope;
  final bool cardName;

  /// Whether the player has a name to put on the card at all: a name
  /// left off and a name never given read differently in the inbox.
  final bool nameSet;

  /// Set when the round was opened from the history rather than just
  /// played.
  final DateTime? playedAt;

  /// The app a [ArenaShareDoor.shareTo] tap went to, in English.
  final String? via;

  const ArenaShareFacts({
    required this.door,
    required this.result,
    required this.mode,
    required this.scope,
    required this.rivalScore,
    required this.cardScore,
    required this.cardScope,
    this.cardName = true,
    this.nameSet = true,
    this.playedAt,
    this.via,
  });
}

/// A note to the inbox for every tap on a Tanafus result's two share
/// buttons — the story and the card — through the channel the feedback
/// uses ([FeedbackService.post]).
///
/// **What it says.** Whether the sharer is new to the app, and since
/// when ([InstallDate]); how many reels they have made; the round —
/// where it was played, how many right and how many wrong, each answer,
/// the score and its word, solo or against a code; what the card shows;
/// and whether they have shared a round before, how many times, and
/// through which door. The report goes on the tap, before the share
/// sheet has answered, so a share the user then backs out of still
/// counts as the click it was.
///
/// **What it does not.** No name — not the one typed for Tanafus, not
/// a rival's — no identifier, no code, no address. The report says
/// what kind of user shared what kind of round; it cannot say who.
///
/// **It does not get lost.** A report that does not go (no network,
/// a refusal) is kept on the disk and sent before the next one, or a
/// little after the next launch — up to [_keep] of them, oldest
/// dropped first.
///
/// Never throws, never holds up a share: everything here runs behind
/// the tap.
abstract final class ArenaShareReport {
  /// Off under `flutter test`: nothing there should post anywhere.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// How long a user counts as new, from the first open.
  static const newForDays = 7;

  /// Reports kept for a later try, at most.
  static const _keep = 20;

  static bool _loaded = false;

  /// Share taps counted on this phone, since [_firstTap]: all of them,
  /// and by door.
  static int _taps = 0;
  static int _story = 0;
  static int _card = 0;
  static DateTime? _firstTap;

  /// Reports waiting for a network.
  static final _outbox = <Map<String, String>>[];

  /// One report at a time, in the order of the taps.
  static Future<void> _queue = Future.value();

  /// The tap. Fire and forget.
  static Future<void> tapped(ArenaShareFacts facts) {
    if (!enabled) return Future.value();
    final run = _queue.then((_) => _report(facts));
    _queue = run.catchError((Object _) {});
    return run;
  }

  /// Sends whatever an earlier launch could not. For the boot.
  static Future<void> flush() {
    if (!enabled) return Future.value();
    final run = _queue.then((_) async {
      await _init();
      await _flush();
    });
    _queue = run.catchError((Object _) {});
    return run;
  }

  static Future<void> _report(ArenaShareFacts facts) async {
    try {
      await _init();
      final now = DateTime.now();
      final before = _taps;
      _taps++;
      if (facts.door == ArenaShareDoor.instagramStory) {
        _story++;
      } else {
        _card++;
      }
      _firstTap ??= now;
      await _persist();

      await FeedbackService.init();
      await InstallDate.init();
      await RewardsService.init();
      final reels = await ReelLibrary.load();
      final arena = ArenaService.state.value;
      // The earliest trace of the user on this phone: a saved reel or a
      // played round. What narrows down a "here before" join date.
      DateTime? first;
      for (final d in [
        for (final r in reels) r.createdAt,
        for (final h in arena.history) h.at,
      ]) {
        if (first == null || d.isBefore(first)) first = d;
      }
      final fields = payload(
        facts: facts,
        now: now,
        since: InstallDate.since,
        before: InstallDate.before,
        firstTrace: first,
        reelsMade: RewardsService.state.value.reelsMade,
        reelsKept: FeedbackService.renders,
        reelsSaved: reels.length,
        roundsPlayed: arena.played,
        sharesDone: arena.sent,
        tap: _taps,
        tapsBefore: before,
        storyTaps: _story,
        cardTaps: _card,
        firstTap: _firstTap,
      );
      // Older ones first, so the inbox reads in the order things happened.
      await _flush();
      if (!await FeedbackService.post(fields, what: 'tanafus share')) {
        _outbox.add(fields);
        while (_outbox.length > _keep) {
          _outbox.removeAt(0);
        }
        await _persist();
      } else {
        rlog('tanafus share: reported tap $_taps');
      }
    } catch (e, s) {
      rlogError('tanafus share report', e, s);
    }
  }

  static Future<void> _flush() async {
    if (_outbox.isEmpty) return;
    final waiting = List.of(_outbox);
    var sent = 0;
    for (final f in waiting) {
      if (!await FeedbackService.post(f, what: 'tanafus share (kept)')) break;
      sent++;
    }
    if (sent == 0) return;
    _outbox.removeRange(0, sent);
    await _persist();
  }

  /// The report itself, built where it can be read and tested.
  ///
  /// English throughout, whatever the app is set to: it is read in one
  /// inbox, by us. Every fact is its own field — FormSubmit lays them
  /// out as a table — and `message` says the lot in a few lines, for
  /// the notification preview and a phone screen.
  @visibleForTesting
  static Map<String, String> payload({
    required ArenaShareFacts facts,
    required DateTime now,
    required DateTime? since,
    required bool before,
    required DateTime? firstTrace,
    required int reelsMade,
    required int reelsKept,
    required int reelsSaved,
    required int roundsPlayed,
    required int sharesDone,
    required int tap,
    required int tapsBefore,
    required int storyTaps,
    required int cardTaps,
    required DateTime? firstTap,
  }) {
    final r = facts.result;
    final right = r.correct;
    final asked = r.asked;
    final wrong = asked - right;
    final door = switch (facts.door) {
      ArenaShareDoor.instagramStory => 'Instagram story',
      ArenaShareDoor.shareCard => 'Share card',
      ArenaShareDoor.shareTo => 'Share to ${facts.via ?? 'an app'}',
    };

    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    int daysTo(DateTime d) => now.difference(d).inDays;
    String ago(DateTime d) {
      final n = daysTo(d);
      return n <= 0 ? 'today' : (n == 1 ? '1 day ago' : '$n days ago');
    }

    // New or old, and since when.
    final String kind;
    final String joined;
    if (since != null) {
      kind = daysTo(since) < newForDays ? 'NEW' : 'OLD';
      joined = 'first opened the app ${ago(since)} (${day(since)})';
    } else if (before) {
      // Here before the date was kept: the earliest saved reel or played
      // round is the best word on it.
      final recent = firstTrace != null && daysTo(firstTrace) < newForDays;
      kind = recent ? 'NEW' : 'OLD';
      joined = 'using the app since before ${InstallDate.trackedFrom}'
          '${firstTrace == null ? '' : ', first reel or round ${ago(firstTrace)} (${day(firstTrace)})'}';
    } else {
      kind = 'UNKNOWN';
      joined = 'join date not recorded';
    }

    final outcome = asked == 0
        ? 'no questions'
        : right == asked
            ? 'all right'
            : right == 0
                ? 'all wrong'
                : '$right right, $wrong wrong';
    final marks = [for (final a in r.answers) a.correct ? '✓' : '✗'].join(' ');
    final rival = facts.rivalScore;
    final mode = facts.mode == ArenaMode.challenge
        ? (rival == null
            ? 'challenge (a rematch, nobody to beat yet)'
            : 'challenge against a code scoring $rival — '
                '${r.score > rival ? 'beat it' : r.score == rival ? 'level' : 'still behind'}')
        : 'solo';
    final shows = [
      if (facts.cardScore) 'score',
      if (facts.cardName) 'name',
      if (facts.cardScope) 'surah/juz',
    ];
    final card = shows.isEmpty ? 'the round alone' : shows.join(' + ');
    // Each of the card menu's three, on or off, so a card's look can be
    // read off the inbox whichever were picked.
    String on(bool v) => v ? 'on' : 'off';
    final nameState = facts.cardName
        ? 'on'
        : facts.nameSet
            ? 'off'
            : 'off (no name set)';
    final sharedBefore = tapsBefore > 0 || sharesDone > 0;
    final firstShare = firstTap == null ? '' : ', counted since ${day(firstTap)}';

    final lines = [
      'Tanafus result shared — $door',
      '',
      'USER: $kind — $joined',
      'REELS: $reelsMade made · $reelsKept rendered and kept · $reelsSaved in My Reels',
      'QUIZ: ${facts.scope} · $asked questions: $outcome · '
          'score ${r.score} · ${_tier(r.tier)} · best run ${r.bestRun}',
      'ANSWERS: $marks',
      'MODE: $mode',
      if (facts.playedAt != null)
        'ROUND: from the history, played ${day(facts.playedAt!)}',
      'CARD SHOWS: $card',
      'CARD MENU: score ${on(facts.cardScore)} · name $nameState · '
          'surah/juz ${on(facts.cardScope)}',
      'SHARED BEFORE: ${sharedBefore ? 'yes' : 'no'} — $sharesDone shares '
          'completed before this one; this is share tap #$tap '
          '(story $storyTaps · card $cardTaps$firstShare)',
      'ROUNDS PLAYED: $roundsPlayed',
    ];

    return {
      // The notification's own subject: the gist, for the inbox list.
      '_subject': 'AyahReel · Tanafus share · $kind user · '
          '${facts.scope} $right/$asked · $door',
      'subject': 'AyahReel tanafus share',
      'message': lines.join('\n'),
      // As FeedbackService.payload: nothing here can solve a captcha,
      // and an empty honeypot is what a person's post looks like.
      '_captcha': 'false',
      '_honey': '',
      '_template': 'table',
      'app': 'AyahReel',
      'event': 'tanafus share',
      'door': door,
      'user': kind,
      'joined': joined,
      'reels_made': '$reelsMade',
      'reels_kept': '$reelsKept',
      'reels_in_library': '$reelsSaved',
      'quiz_scope': facts.scope,
      'quiz_questions': '$asked',
      'quiz_right': '$right',
      'quiz_wrong': '$wrong',
      'quiz_outcome': outcome,
      'quiz_answers': marks,
      'quiz_score': '${r.score}',
      'quiz_tier': _tier(r.tier),
      'quiz_best_run': '${r.bestRun}',
      'quiz_mode': mode,
      if (facts.playedAt != null) 'quiz_played': day(facts.playedAt!),
      'card_shows': card,
      'card_score': on(facts.cardScore),
      'card_name': nameState,
      'card_scope': on(facts.cardScope),
      'shared_before': sharedBefore ? 'yes' : 'no',
      'shares_completed_before': '$sharesDone',
      'share_tap_number': '$tap',
      'share_taps_story': '$storyTaps',
      'share_taps_card': '$cardTaps',
      'rounds_played': '$roundsPlayed',
      'version': kAppVersion,
      'code': FeedbackService.codeDate,
      'platform': Platform.operatingSystem,
      'language': SettingsService.state.value.lang.code,
    };
  }

  /// The tier's word, as the English app says it.
  static String _tier(int tier) => switch (tier) {
        4 => 'Flawless',
        3 => 'Excellent',
        2 => 'Strong',
        1 => 'Decent',
        _ => 'Fair',
      };

  static Future<void> _init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _taps = j['taps'] as int? ?? 0;
      _story = j['story'] as int? ?? 0;
      _card = j['card'] as int? ?? 0;
      _firstTap = DateTime.tryParse(j['first'] as String? ?? '');
      for (final e in (j['outbox'] as List? ?? const [])) {
        if (e is Map) {
          _outbox.add({
            for (final kv in e.entries) '${kv.key}': '${kv.value}',
          });
        }
      }
    } catch (_) {/* an unreadable file starts the count again */}
  }

  static Future<void> _persist() async {
    try {
      await writeWhole(
          await _file(),
          jsonEncode({
            'taps': _taps,
            'story': _story,
            'card': _card,
            if (_firstTap != null) 'first': _firstTap!.toIso8601String(),
            'outbox': _outbox,
          }));
    } catch (_) {/* a count, best-effort */}
  }

  static Future<File> _file() async => File(
      '${(await getApplicationSupportDirectory()).path}/tanafus_shares.json');
}
