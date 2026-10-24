/// A challenge: one round, and the score to beat, as twelve letters.
///
/// Instagram cannot carry a link out of a story and WhatsApp strips
/// the parameters off most of them, so a score travels the one way
/// that survives every app between two phones: a short code the
/// friend types into the arena. It names the round exactly — scope,
/// games, seed — and the score and count it was played to, so
/// the friend plays the very same ten questions and the app can say
/// who won. See `ArenaRound.generate` for why the seed is enough.
///
/// The alphabet is Crockford's base32: no I, L, O or U, so a code read
/// off a story and typed in cannot be misread, and lowercase or a
/// stray dash is forgiven. Eight bits of checksum at the end catch a
/// typo before it becomes a round nobody sent.
library;

import 'arena_engine.dart';

class ArenaChallenge {
  final ArenaSetup setup;
  final int seed;

  /// The score the sender made, and how many they had right.
  final int score;
  final int correct;

  const ArenaChallenge({
    required this.setup,
    required this.seed,
    required this.score,
    required this.correct,
  });

  /// Codes are cut for a round of this many questions.
  static const questions = 10;

  /// What a code says in the two bits that were the round's clock
  /// before rounds lost theirs (2026-10-24): 3, the longest of 10, 15,
  /// 20 and 30 seconds, for a friend whose app still has a clock. This
  /// app reads the bits and lets them go.
  static const _oldClock = 3;

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// The code, grouped for the eye: `K7X2-9QPM-4R2A`.
  String get code {
    final w = _Bits();
    var mask = 0;
    for (final g in setup.games) {
      mask |= 1 << g.index;
    }
    w.put(mask, 6);
    w.put(setup.scope.kind.index, 2);
    w.put(setup.scope.value, 7);
    w.put(_oldClock, 2);
    w.put(setup.askMeanings ? 1 : 0, 1);
    w.put(seed, ArenaRound.seedBits);
    w.put(score.clamp(0, 4095), 12);
    w.put(correct.clamp(0, 15), 4);
    // 54 bits so far; pad to 55 so the checksum lands on a group.
    w.put(0, 1);
    final groups = w.groups();
    w.put(_check(groups), 5);
    final chars = [for (final g in w.groups()) _alphabet[g]].join();
    return '${chars.substring(0, 4)}-${chars.substring(4, 8)}-'
        '${chars.substring(8, 12)}';
  }

  /// The challenge a code names, or null for anything that is not
  /// one. Never throws: this is what gets pasted into a text field.
  static ArenaChallenge? parse(String? raw) {
    if (raw == null) return null;
    final chars = clean(raw);
    if (chars.length != 12) return null;
    final groups = <int>[];
    for (final c in chars.runes) {
      final i = _alphabet.indexOf(String.fromCharCode(c));
      if (i < 0) return null;
      groups.add(i);
    }
    if (_check(groups.sublist(0, 11)) != groups[11]) return null;
    final r = _Bits.from(groups);
    final mask = r.take(6);
    final kind = r.take(2);
    final value = r.take(7);
    r.take(2); // the old clock, see [_oldClock]
    final meanings = r.take(1);
    final seed = r.take(ArenaRound.seedBits);
    final score = r.take(12);
    final correct = r.take(4);
    if (kind >= ArenaScopeKind.values.length) return null;
    final scope = switch (ArenaScopeKind.values[kind]) {
      ArenaScopeKind.quran => const ArenaScope.quran(),
      ArenaScopeKind.juz => value >= 1 && value <= 30
          ? ArenaScope.juz(value)
          : null,
      ArenaScopeKind.surah => value >= 1 && value <= 114
          ? ArenaScope.surah(value)
          : null,
    };
    if (scope == null) return null;
    final games = {
      for (final g in ArenaGame.values)
        if (mask & (1 << g.index) != 0) g,
    };
    if (games.isEmpty) return null;
    return ArenaChallenge(
      setup: ArenaSetup(
        scope: scope,
        games: games,
        count: questions,
        askMeanings: meanings == 1,
      ),
      seed: seed,
      score: score,
      correct: correct,
    );
  }

  /// [raw] as the twelve letters alone: uppercased, dashes and spaces
  /// dropped, the letters the alphabet has no place for read as what
  /// they were probably meant to be.
  static String clean(String raw) {
    final b = StringBuffer();
    for (final c in raw.toUpperCase().runes) {
      final ch = String.fromCharCode(c);
      switch (ch) {
        case 'I' || 'L':
          b.write('1');
        case 'O':
          b.write('0');
        case '-' || ' ' || '_' || '.':
          break;
        default:
          b.write(ch);
      }
    }
    return b.toString();
  }

  /// A code somewhere in [text] — a pasted message, a story caption.
  static String? find(String text) {
    final m = RegExp(r'[0-9A-Za-z]{4}[-\s]?[0-9A-Za-z]{4}[-\s]?[0-9A-Za-z]{4}')
        .allMatches(text);
    for (final x in m) {
      if (parse(x.group(0)) != null) return x.group(0);
    }
    return null;
  }

  /// `ayahreel://arena/<code>` — what a link to a challenge looks like.
  String link({String by = ''}) {
    final base = 'ayahreel://arena/$code';
    if (by.trim().isEmpty) return base;
    return '$base?by=${Uri.encodeQueryComponent(by.trim())}';
  }

  /// The code in a link, or null for any other link.
  static String? codeInLink(String? link) {
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'ayahreel' || uri.host != 'arena') {
      return null;
    }
    // Decoding throws on an escape that isn't UTF-8 (`%FF`), and any
    // page can open a link like that: it is not a challenge.
    final List<String> segments;
    try {
      segments = uri.pathSegments;
    } on FormatException {
      return null;
    }
    if (segments.isEmpty) return null;
    return parse(segments.first) == null ? null : segments.first;
  }

  /// Who sent a link, when it says.
  static String senderInLink(String? link) {
    final uri = link == null ? null : Uri.tryParse(link);
    try {
      return uri?.queryParameters['by']?.trim() ?? '';
    } on FormatException {
      // `?by=%FF`: no name in it, and the challenge stands without one.
      return '';
    }
  }

  static int _check(List<int> groups) {
    var h = 7;
    for (final g in groups) {
      h = (h * 31 + g + 1) & 0xFF;
    }
    return h & 0x1F;
  }
}

/// Bits, five at a time.
class _Bits {
  final List<int> _bits = [];
  int _at = 0;

  _Bits();

  _Bits.from(List<int> groups) {
    for (final g in groups) {
      for (var i = 4; i >= 0; i--) {
        _bits.add((g >> i) & 1);
      }
    }
  }

  void put(int value, int width) {
    for (var i = width - 1; i >= 0; i--) {
      _bits.add((value >> i) & 1);
    }
  }

  int take(int width) {
    var v = 0;
    for (var i = 0; i < width; i++) {
      v = (v << 1) | _bits[_at++];
    }
    return v;
  }

  /// The bits so far as five-bit groups; the count must divide.
  List<int> groups() {
    assert(_bits.length % 5 == 0);
    final out = <int>[];
    for (var i = 0; i < _bits.length; i += 5) {
      var g = 0;
      for (var j = 0; j < 5; j++) {
        g = (g << 1) | _bits[i + j];
      }
      out.add(g);
    }
    return out;
  }
}
