import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/arena_challenge.dart';
import 'package:ayah_reels/data/arena_engine.dart';

/// The twelve letters a score travels as.
void main() {
  const games = {
    ArenaGame.completeVerse,
    ArenaGame.missingWord,
    ArenaGame.whichSurah,
    ArenaGame.nextVerse,
    ArenaGame.orderWords,
    ArenaGame.surahFacts,
  };

  test('a code says exactly what it was cut from', () {
    const c = ArenaChallenge(
      setup: ArenaSetup(
        scope: ArenaScope.juz(30),
        games: {ArenaGame.completeVerse, ArenaGame.orderWords},
        seconds: 30,
        askMeanings: false,
      ),
      seed: 777777,
      score: 1480,
      correct: 8,
    );
    final code = c.code;
    expect(code, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$')));
    expect(code, isNot(contains(RegExp('[ILOU]'))));
    final back = ArenaChallenge.parse(code)!;
    expect(back.setup.scope, const ArenaScope.juz(30));
    expect(back.setup.games,
        {ArenaGame.completeVerse, ArenaGame.orderWords});
    expect(back.setup.seconds, 30);
    expect(back.setup.askMeanings, isFalse);
    expect(back.setup.count, ArenaChallenge.questions);
    expect(back.seed, 777777);
    expect(back.score, 1480);
    expect(back.correct, 8);
  });

  test('every corner of the space round-trips', () {
    final rnd = Random(3);
    for (var i = 0; i < 2000; i++) {
      final kind = ArenaScopeKind.values[rnd.nextInt(3)];
      final scope = switch (kind) {
        ArenaScopeKind.quran => const ArenaScope.quran(),
        ArenaScopeKind.juz => ArenaScope.juz(1 + rnd.nextInt(30)),
        ArenaScopeKind.surah => ArenaScope.surah(1 + rnd.nextInt(114)),
      };
      final picked = {
        for (final g in ArenaGame.values)
          if (rnd.nextBool()) g,
      };
      if (picked.isEmpty) picked.add(ArenaGame.missingWord);
      final c = ArenaChallenge(
        setup: ArenaSetup(
          scope: scope,
          games: picked,
          seconds: ArenaSetup.secondsOptions[rnd.nextInt(4)],
          askMeanings: rnd.nextBool(),
        ),
        seed: rnd.nextInt(ArenaRound.seedLimit),
        score: rnd.nextInt(4096),
        correct: rnd.nextInt(16),
      );
      final back = ArenaChallenge.parse(c.code);
      expect(back, isNotNull, reason: c.code);
      expect(back!.setup.scope, scope);
      expect(back.setup.games, picked);
      expect(back.setup.seconds, c.setup.seconds);
      expect(back.setup.askMeanings, c.setup.askMeanings);
      expect(back.seed, c.seed);
      expect(back.score, c.score);
      expect(back.correct, c.correct);
    }
  });

  test('forgives what a thumb does to a code', () {
    const c = ArenaChallenge(
      setup: ArenaSetup(scope: ArenaScope.quran(), games: games),
      seed: 4242,
      score: 900,
      correct: 6,
    );
    final code = c.code;
    final bare = code.replaceAll('-', '');
    expect(ArenaChallenge.parse(bare)?.seed, 4242);
    expect(ArenaChallenge.parse(bare.toLowerCase())?.seed, 4242);
    expect(ArenaChallenge.parse(' ${code.replaceAll('-', ' ')} ')?.seed, 4242);
    // I, L and O are not in the alphabet; read as the digits they
    // look like.
    final confused = code.replaceAll('1', 'l').replaceAll('0', 'O');
    expect(ArenaChallenge.parse(confused)?.seed, 4242);
  });

  test('refuses a typo, a truncation and a stranger', () {
    const c = ArenaChallenge(
      setup: ArenaSetup(scope: ArenaScope.surah(18), games: games),
      seed: 99,
      score: 1200,
      correct: 9,
    );
    final code = c.code;
    var caught = 0;
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final bare = code.replaceAll('-', '');
    for (var i = 0; i < bare.length; i++) {
      for (final ch in alphabet.runes) {
        final r = String.fromCharCode(ch);
        if (r == bare[i]) continue;
        final typo = bare.substring(0, i) + r + bare.substring(i + 1);
        if (ArenaChallenge.parse(typo) == null) caught++;
      }
    }
    // A five-bit check catches all but about one substitution in
    // thirty-two.
    expect(caught, greaterThan(bare.length * 31 * 0.9));
    expect(ArenaChallenge.parse(bare.substring(1)), isNull);
    expect(ArenaChallenge.parse(''), isNull);
    expect(ArenaChallenge.parse(null), isNull);
    expect(ArenaChallenge.parse('hello there friend'), isNull);
    expect(ArenaChallenge.parse('ZZZZ-ZZZZ-ZZZZ'), isNull);
  });

  test('finds itself in a message, and in a link', () {
    const c = ArenaChallenge(
      setup: ArenaSetup(scope: ArenaScope.juz(29), games: games),
      seed: 31337,
      score: 1750,
      correct: 10,
    );
    final code = c.code;
    expect(ArenaChallenge.find('Beat me: $code — in AyahReel'), code);
    expect(ArenaChallenge.find('nothing here'), isNull);
    expect(c.link(), 'ayahreel://arena/$code');
    expect(c.link(by: 'Yusuf Ali'), 'ayahreel://arena/$code?by=Yusuf+Ali');
    expect(ArenaChallenge.codeInLink(c.link(by: 'Yusuf')), code);
    expect(ArenaChallenge.senderInLink(c.link(by: 'Yusuf')), 'Yusuf');
    expect(ArenaChallenge.senderInLink(c.link()), '');
    expect(ArenaChallenge.codeInLink('ayahreel://verse/2/152'), isNull);
    expect(ArenaChallenge.codeInLink('ayahreel://arena/NOPE'), isNull);
    expect(ArenaChallenge.codeInLink(null), isNull);
  });

  test('a link with an escape that is not UTF-8 is read, not thrown', () {
    // Any web page can open one of these. Decoding `%FF` throws, and
    // the throw used to stop the app's start-up where it read the link.
    final code = const ArenaChallenge(
      setup: ArenaSetup(scope: ArenaScope.juz(29), games: games),
      seed: 31337,
      score: 1750,
      correct: 10,
    ).code;
    expect(ArenaChallenge.senderInLink('ayahreel://arena/$code?by=%FF'), '');
    expect(ArenaChallenge.codeInLink('ayahreel://arena/$code?by=%FF'), code);
    expect(ArenaChallenge.codeInLink('ayahreel://arena/%FF'), isNull);
  });
}
