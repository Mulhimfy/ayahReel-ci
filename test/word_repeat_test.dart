import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/word_align_service.dart';
import 'package:ayah_reels/widgets/verse_geometry.dart';

/// A reciter who stops on a word and takes the words before it again (a
/// waqf, then ibtida'): the light and the thread go back with him to the
/// word he takes again, on whichever line it is, instead of waiting
/// where he first got to.
void main() {
  // Words a hundred wide, right to left as Arabic runs: word 0 rightmost.
  VerseRow row(List<int> tokens) => VerseRow(
        tokens: tokens,
        boxes: {
          for (final k in tokens)
            k: Rect.fromLTRB(300.0 - 100 * k, 0, 400.0 - 100 * k, 10),
        },
        left: 400.0 - 100 * (tokens.last + 1),
        right: 400.0 - 100 * tokens.first,
        top: 0,
        bottom: 10,
      );

  test('the recitation is kept in its order where it goes back', () {
    const arabic = 'قُلْ هُوَ ٱللَّهُ أَحَدٌ';
    const spans = [
      WordSpan(0, 1, 0, 400),
      WordSpan(1, 2, 400, 800),
      WordSpan(2, 3, 800, 1200),
      // A breath, then the second word again.
      WordSpan(1, 2, 1600, 2000),
      WordSpan(2, 3, 2000, 2400),
      WordSpan(3, 4, 2400, 2900),
    ];
    final t = WordAlignService.tokenWindows(arabic, spans).times;
    // Each word's first time is what a line changes by, as before.
    expect(t[1], (400, 800));
    expect(t, isA<TokenTimes>());
    final recited = (t as TokenTimes).recited!;
    expect(recited, hasLength(6));
    expect(recited[3], (1, 2, 1600, 2000));
    // Straight through, nothing more is kept.
    final plain =
        WordAlignService.tokenWindows(arabic, spans.take(3).toList()).times;
    expect((plain as TokenTimes).recited, isNull);
  });

  test('the light goes back along the line with the reciter', () {
    final times = TokenTimes(
      [(0, 400), (400, 800), (800, 1200), (2400, 2900)],
      [
        (0, 1, 0, 400),
        (1, 2, 400, 800),
        (2, 3, 800, 1200),
        (1, 2, 1600, 2000),
        (2, 3, 2000, 2400),
        (3, 4, 2400, 2900),
      ],
    );
    final p = row([0, 1, 2, 3]).progressFromWords(times, 0);
    // The voice never leaves the line: one stretch of light.
    expect(p.visits, [(0, 2900)]);
    final reached = p.at(1190);
    // It waits through the breath where it was, then goes back.
    expect(p.at(1500), closeTo(reached, 15));
    expect(p.at(1700), lessThan(reached - 100));
    // And on to the line's end with the words.
    expect(p.at(2900), 400);
  });

  test('a line the voice comes back to lights again; the next waits', () {
    final times = TokenTimes(
      [(0, 400), (400, 800), (800, 1200), (2400, 2900)],
      [
        (0, 1, 0, 400),
        (1, 2, 400, 800),
        (2, 3, 800, 1200),
        // Back over the wrap to the first line's last word.
        (1, 2, 1600, 2000),
        (2, 3, 2000, 2400),
        (3, 4, 2400, 2900),
      ],
    );
    final first = row([0, 1]).progressFromWords(times, 0);
    final second = row([2, 3]).progressFromWords(times, 0);
    // The first line is done while the voice is on the second, and
    // lights again, going back with it, when it comes back.
    expect(first.visits, [(0, 800), (1600, 2000)]);
    expect(first.at(1200), first.width);
    expect(first.at(1800), 150);
    expect(first.visitAt(1200, 220), isNull);
    // The second is back at its start meanwhile, its light off.
    expect(second.visits, [(800, 1200), (2000, 2900)]);
    expect(second.at(1800), 0);
    expect(second.visitAt(1800, 220), isNull);
    expect(second.at(2900), second.width);
  });

  test('a unit cut from the verse keeps the order, the rest off the card',
      () {
    final verse = TokenTimes(
      [(0, 400), (400, 800), (800, 1200), (2400, 2900)],
      [(0, 1, 0, 400), (2, 3, 800, 1200), (0, 1, 1600, 2000)],
    );
    // The verse's second line: its tokens 2..3, starting at 800 ms.
    const unit = VerseUnit(
      1,
      VersePart(
        ayah: 1,
        index: 1,
        count: 2,
        tokenStart: 2,
        tokenEnd: 4,
        startMs: 800,
        endMs: 3000,
        arabic: 'ٱللَّهُ أَحَدٌ',
        translation: '',
        fit: 1,
      ),
      800,
      3000,
    );
    final own = unit.timesIn(verse, 0)! as TokenTimes;
    expect(own.recited,
        [(-1, 0, -800, -400), (0, 1, 0, 400), (-1, 0, 800, 1200)]);
    // Its own first windows, as before.
    expect(own.toList(), [(0, 400), (1600, 2100)]);
  });
}
