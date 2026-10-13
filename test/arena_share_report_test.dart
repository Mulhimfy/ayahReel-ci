import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/arena_engine.dart';
import 'package:ayah_reels/data/arena_service.dart';
import 'package:ayah_reels/data/arena_share_report.dart';

/// Every tap on a Tanafus result's share buttons sends the inbox a
/// note: who shared (new or old, how many reels), the round (where,
/// how many right and wrong, each answer), what the card shows, and
/// the shares before it. This pins what the note says.
void main() {
  const setup = ArenaSetup(
    scope: ArenaScope.juz(30),
    games: {ArenaGame.completeVerse, ArenaGame.whichSurah},
  );
  ArenaAnswer ans(bool ok) =>
      ArenaAnswer(chosen: 0, correct: ok, timeLeft: 0.5, points: ok ? 150 : 0);
  // Seven right of ten: ✓ ✓ ✗ ✓ ✓ ✓ ✗ ✓ ✓ ✗
  final result = ArenaResult(setup: setup, seed: 1, answers: [
    for (final ok in [true, true, false, true, true, true, false, true, true, false])
      ans(ok),
  ]);
  final now = DateTime(2026, 10, 10, 12);

  ArenaShareFacts facts({
    ArenaShareDoor door = ArenaShareDoor.instagramStory,
    ArenaResult? r,
    ArenaMode mode = ArenaMode.solo,
    int? rival,
    bool score = true,
    bool scope = true,
    bool name = true,
    bool nameSet = true,
  }) =>
      ArenaShareFacts(
        door: door,
        result: r ?? result,
        mode: mode,
        scope: 'Juz Amma',
        rivalScore: rival,
        cardScore: score,
        cardScope: scope,
        cardName: name,
        nameSet: nameSet,
      );

  Map<String, String> note(
    ArenaShareFacts f, {
    DateTime? since,
    bool before = false,
    DateTime? firstTrace,
    int sharesDone = 0,
    int tap = 1,
    int tapsBefore = 0,
  }) =>
      ArenaShareReport.payload(
        facts: f,
        now: now,
        since: since,
        before: before,
        firstTrace: firstTrace,
        reelsMade: 3,
        reelsKept: 12,
        reelsSaved: 5,
        roundsPlayed: 9,
        sharesDone: sharesDone,
        tap: tap,
        tapsBefore: tapsBefore,
        storyTaps: 1,
        cardTaps: tap - 1,
        firstTap: now,
      );

  test('a first share by a new user: who, the round, and no shares before',
      () {
    final n = note(facts(), since: DateTime(2026, 10, 8));
    expect(n['user'], 'NEW');
    expect(n['joined'], contains('2 days ago'));
    expect(n['joined'], contains('2026-10-08'));
    expect(n['door'], 'Instagram story');
    expect(n['reels_made'], '3');
    expect(n['quiz_scope'], 'Juz Amma');
    expect(n['quiz_questions'], '10');
    expect(n['quiz_right'], '7');
    expect(n['quiz_wrong'], '3');
    expect(n['quiz_outcome'], '7 right, 3 wrong');
    expect(n['quiz_answers'], '✓ ✓ ✗ ✓ ✓ ✓ ✗ ✓ ✓ ✗');
    expect(n['quiz_score'], '1050');
    expect(n['quiz_mode'], 'solo');
    expect(n['card_shows'], 'score + name + surah/juz');
    expect(n['card_score'], 'on');
    expect(n['card_name'], 'on');
    expect(n['card_scope'], 'on');
    expect(n['message'],
        contains('CARD MENU: score on · name on · surah/juz on'));
    expect(n['shared_before'], 'no');
    expect(n['shares_completed_before'], '0');
    expect(n['share_tap_number'], '1');
    // The subject says the gist; the message says all of it.
    expect(n['_subject'], contains('NEW user'));
    expect(n['_subject'], contains('Juz Amma 7/10'));
    expect(n['message'], contains('USER: NEW'));
    expect(n['message'], contains('SHARED BEFORE: no'));
    // The inbox's own fields, as the feedback sends them.
    expect(n['_captcha'], 'false');
    expect(n['_honey'], '');
  });

  test('an old user sharing again, through the card', () {
    final n = note(facts(door: ArenaShareDoor.shareCard),
        since: DateTime(2026, 8, 1), sharesDone: 4, tap: 6, tapsBefore: 5);
    expect(n['user'], 'OLD');
    expect(n['door'], 'Share card');
    expect(n['shared_before'], 'yes');
    expect(n['shares_completed_before'], '4');
    expect(n['share_tap_number'], '6');
    expect(n['message'], contains('this is share tap #6'));
  });

  test('somebody here before the date was kept is old, unless their first '
      'reel or round is recent', () {
    final old = note(facts(),
        before: true, firstTrace: DateTime(2026, 7, 14));
    expect(old['user'], 'OLD');
    expect(old['joined'], contains('since before'));
    expect(old['joined'], contains('2026-07-14'));
    final recent =
        note(facts(), before: true, firstTrace: DateTime(2026, 10, 9));
    expect(recent['user'], 'NEW');
    final blank = note(facts(), before: true);
    expect(blank['user'], 'OLD');
  });

  test('all right, all wrong, a challenge, and a card with nothing on it',
      () {
    final perfect = ArenaResult(
        setup: setup, seed: 1, answers: [for (var i = 0; i < 10; i++) ans(true)]);
    final none = ArenaResult(
        setup: setup, seed: 1, answers: [for (var i = 0; i < 10; i++) ans(false)]);
    expect(note(facts(r: perfect))['quiz_outcome'], 'all right');
    expect(note(facts(r: perfect))['quiz_tier'], 'Flawless');
    expect(note(facts(r: none))['quiz_outcome'], 'all wrong');
    final vs = note(facts(mode: ArenaMode.challenge, rival: 900));
    expect(vs['quiz_mode'], contains('900'));
    expect(vs['quiz_mode'], contains('beat it'));
    final bare = note(facts(score: false, scope: false, name: false));
    expect(bare['card_shows'], 'the round alone');
    expect(bare['card_score'], 'off');
    expect(bare['card_name'], 'off');
    expect(bare['card_scope'], 'off');
    expect(note(facts(name: false))['card_shows'], 'score + surah/juz');
    // A name left off, and a name never given, read differently.
    expect(note(facts(name: false, nameSet: false))['card_name'],
        'off (no name set)');
  });

  test('the note carries no name and no code', () {
    final n = note(facts());
    for (final v in n.values) {
      expect(v, isNot(contains('Yusuf')));
    }
    expect(n.keys, isNot(contains('name')));
    expect(n.keys, isNot(contains('code_value')));
  });
}
