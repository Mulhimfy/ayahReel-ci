import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/arena_challenge.dart';
import 'package:ayah_reels/data/arena_engine.dart';
import 'package:ayah_reels/data/arena_service.dart';
import 'package:ayah_reels/data/quran_search.dart';

/// The bests and the history — kept whole enough to draw a round
/// again, and surviving a restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  var clock = DateTime(2026, 9, 22, 10);

  const setup = ArenaSetup(
    scope: ArenaScope.juz(30),
    games: {ArenaGame.missingWord, ArenaGame.orderWords},
    askMeanings: false,
  );

  ArenaResult result(int score, {int right = 5, int seed = 1}) => ArenaResult(
        setup: setup,
        seed: seed,
        answers: [
          for (var i = 0; i < 10; i++)
            ArenaAnswer(
                chosen: i,
                correct: i < right,
                points: i < right ? score ~/ right : 0),
        ],
      );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('arena_service');
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    ArenaService.now = () => clock;
  });

  tearDown(() {
    ArenaService.fileOverride = null;
    ArenaService.now = DateTime.now;
    ArenaService.reset();
    tmp.deleteSync(recursive: true);
  });

  test('a round is filed whole, and the best is the best', () async {
    expect(await ArenaService.record(result(900), mode: ArenaMode.solo),
        isTrue);
    clock = clock.add(const Duration(minutes: 1));
    expect(await ArenaService.record(result(600), mode: ArenaMode.solo),
        isFalse);
    clock = clock.add(const Duration(minutes: 1));
    expect(
        await ArenaService.record(result(1200, right: 8, seed: 77),
            mode: ArenaMode.challenge,
            me: 'Yusuf',
            rival: 'Amina',
            rivalScore: 1100,
            rivalCorrect: 7,
            code: 'ABCD-EFGH-JKMN'),
        isTrue);
    final s = ArenaService.state.value;
    expect(s.bestFor(setup), 1200);
    expect(s.played, 3);
    expect(s.answered, 1);
    expect(s.history, hasLength(3));
    final top = s.history.first;
    expect(top.rival, 'Amina');
    expect(top.me, 'Yusuf');
    expect(top.won, isTrue);
    expect(top.code, 'ABCD-EFGH-JKMN');
    expect(top.seed, 77);
    expect(top.correct, 8);
    expect(top.asked, 10);
    // The round can be rebuilt from what was kept.
    expect(top.setup.scope, const ArenaScope.juz(30));
    expect(top.setup.games, setup.games);
    expect(top.setup.askMeanings, isFalse);
    expect(top.result.score, top.score);
    expect(top.challenge?.score, 1100);
    expect(top.challenge?.correct, 7);
    expect(s.history.last.score, 900);
    expect(s.history.last.won, isFalse);
    expect(s.history.last.challenge, isNull);
    // Ids are distinct.
    expect(s.history.map((r) => r.id).toSet(), hasLength(3));
  });

  test('survives a restart', () async {
    await ArenaService.record(result(700), mode: ArenaMode.solo);
    await ArenaService.remember({'scope': 'j30', 'intro': '1'});
    final onDisk = jsonDecode(ArenaService.fileOverride!.readAsStringSync())
        as Map<String, dynamic>;
    expect(onDisk['played'], 1);
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    await ArenaService.init();
    final s = ArenaService.state.value;
    expect(s.bestFor(setup), 700);
    expect(s.history, hasLength(1));
    expect(s.history.single.answers, hasLength(10));
    expect(s.history.single.answers[3].chosen, 3);
    expect(s.prefs['scope'], 'j30');
    expect(s.prefs['intro'], '1');
  });

  test('a round can be taken out of the history', () async {
    for (var i = 0; i < 3; i++) {
      await ArenaService.record(result(100 + i), mode: ArenaMode.solo);
      clock = clock.add(const Duration(seconds: 1));
    }
    final middle = ArenaService.state.value.history[1];
    await ArenaService.remove(middle.id);
    final h = ArenaService.state.value.history;
    expect(h, hasLength(2));
    expect(h.map((r) => r.id), isNot(contains(middle.id)));
    // Gone from disk too.
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    await ArenaService.init();
    expect(ArenaService.state.value.history, hasLength(2));
  });

  test('keeps only the last thirty rounds', () async {
    for (var i = 0; i < 40; i++) {
      await ArenaService.record(result(100 + i), mode: ArenaMode.solo);
      clock = clock.add(const Duration(seconds: 1));
    }
    final h = ArenaService.state.value.history;
    expect(h, hasLength(ArenaService.historyLength));
    expect(h.first.score, result(139).score);
    expect(h.last.score, result(110).score);
    expect(ArenaService.state.value.played, 40);
  });

  test('reads a file from before rounds were kept whole', () async {
    ArenaService.fileOverride!.writeAsStringSync(jsonEncode({
      'lamps': 2,
      'day': '2026-9-22',
      'best': {'j30:seeker': 800},
      'played': 1,
      'history': [
        {
          'mode': 'duel',
          'scope': 'j30',
          'level': 'seeker',
          'score': 800,
          'correct': 6,
          'asked': 10,
          'at': '2026-09-22T10:00:00.000',
        }
      ],
    }));
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    await ArenaService.init();
    final s = ArenaService.state.value;
    expect(s.played, 1);
    // An old round has no answers to draw, and a mode that no longer
    // exists reads as a round of one's own.
    final old = s.history.single;
    expect(old.mode, ArenaMode.solo);
    expect(old.answers, isEmpty);
    expect(old.seed, 0);
  });

  test('a round keeps the verses it asked, through a restart', () async {
    await ArenaService.record(result(700),
        mode: ArenaMode.solo, verses: [(78, 1), (78, 2), (112, 4)]);
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    await ArenaService.init();
    expect(ArenaService.state.value.history.single.verses,
        [(78, 1), (78, 2), (112, 4)]);
  });

  test('a round filed before rounds kept their verses gets them from its '
      'seed', () async {
    QuranSearch.loadFrom(await rootBundle.loadString(QuranSearch.asset));
    await ArenaService.record(result(700, seed: 4242), mode: ArenaMode.solo);
    final old = ArenaService.state.value.history.single;
    expect(old.verses, isNull);

    await ArenaService.fillVerses();
    final corpus = await ArenaCorpus.load();
    final named = ArenaService.state.value.history.single.verses;
    expect(named, isNotEmpty);
    expect(
        named,
        ArenaRecord.versesOf(
            ArenaRound.generate(corpus, old.setup, 4242), old.asked));
    // Juz 30's verses, every one of them.
    expect(named!.every((v) => v.$1 >= 78), isTrue);
    // And kept.
    ArenaService.reset();
    ArenaService.fileOverride = File('${tmp.path}/arena.json');
    await ArenaService.init();
    expect(ArenaService.state.value.history.single.verses, named);
  });

  test('takes a challenge link and nothing else', () {
    const c = ArenaChallenge(setup: setup, seed: 5, score: 1000, correct: 7);
    ArenaService.takeLink('ayahreel://verse/2/152');
    expect(ArenaService.pendingCode.value, isNull);
    ArenaService.takeLink(c.link(by: 'Yusuf'));
    expect(ArenaService.pendingCode.value, c.code);
    expect(ArenaService.pendingSender, 'Yusuf');
  });
}
