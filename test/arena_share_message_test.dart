import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/l10n/l10n.dart';

/// The message a challenge travels in: the code, what to do with it,
/// and the stores, in every language.
void main() {
  test('says copy this code, names the road to paste it, and links the '
      'stores', () {
    for (final lang in AppLang.values) {
      final l = L10n(lang);
      final m = l.arenaShareMessage(
        name: 'Yusuf',
        score: 1480,
        correct: 8,
        asked: 10,
        scope: 'Juz Amma',
        code: 'ZT3C-0GJ9-98G0',
      );
      expect(m, startsWith('🏆'), reason: lang.code);
      expect(m, contains('Yusuf'));
      expect(m, contains('1480'));
      expect(m, contains('🔑'));
      expect(m, contains('ZT3C-0GJ9-98G0'));
      // The three steps: copy, open, paste — the mode's own name in it.
      expect(m, contains('📲'));
      expect(m, contains(l.arenaChallenge), reason: lang.code);
      expect(m, contains('apps.apple.com'));
      expect(m, contains('play.google.com'));
      // The code sits on a line of its own, where a thumb can select it.
      final line = m.split('\n').firstWhere((s) => s.contains('ZT3C'));
      expect(line.startsWith('🔑'), isTrue, reason: line);
    }
  });

  test('a nameless player still speaks in the first person', () {
    final m = L10n.en.arenaShareMessage(
        name: '', score: 900, correct: 6, asked: 10, scope: 'Al-Kahf',
        code: 'AAAA-BBBB-CCCC');
    expect(m, startsWith('🏆 I scored 900'));
  });

  test('with the score off the card, the message names no number either',
      () {
    for (final lang in AppLang.values) {
      final l = L10n(lang);
      final m = l.arenaShareMessage(
        name: 'Yusuf',
        score: 1480,
        correct: 8,
        asked: 10,
        scope: 'Juz Amma',
        code: 'ZT3C-0GJ9-98G0',
        showScore: false,
      );
      expect(m, startsWith('🏆'), reason: lang.code);
      expect(m, contains('Yusuf'), reason: lang.code);
      expect(m, isNot(contains('1480')), reason: lang.code);
      // Still the whole dare: the code on its own line, and the road.
      expect(m, contains('🔑'));
      expect(m, contains('ZT3C-0GJ9-98G0'));
      expect(m, contains(l.arenaChallenge), reason: lang.code);
    }
    expect(
        L10n.en.arenaShareMessage(
            name: '', score: 900, correct: 6, asked: 10, scope: 'Al-Kahf',
            code: 'AAAA-BBBB-CCCC', showScore: false),
        startsWith('🏆 Can you beat my round?'));
  });
}
