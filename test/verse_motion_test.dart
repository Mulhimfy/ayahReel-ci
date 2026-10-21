import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/models.dart';
import 'package:ayah_reels/data/verse_follow.dart';
import 'package:ayah_reels/data/verse_lines.dart';
import 'package:ayah_reels/data/verse_motion.dart';

/// Evaluates the slice of FFmpeg's expression language the motion
/// writes — numbers, `t`, + - * /, and if/lt/gt/pow/min/max — so the
/// expressions the export runs can be checked against the curves the
/// preview draws.
double ffEval(String expr, double t) {
  var i = 0;
  String peek() => i < expr.length ? expr[i] : '';
  void skip() {
    while (peek() == ' ') {
      i++;
    }
  }

  late double Function() sum;
  double atom() {
    skip();
    if (peek() == '(') {
      i++;
      final v = sum();
      skip();
      i++; // ')'
      return v;
    }
    if (peek() == '-') {
      i++;
      return -atom();
    }
    final start = i;
    while (i < expr.length && RegExp(r'[0-9.]').hasMatch(expr[i])) {
      i++;
    }
    if (i > start) return double.parse(expr.substring(start, i));
    while (i < expr.length && RegExp(r'[a-z]').hasMatch(expr[i])) {
      i++;
    }
    final name = expr.substring(start, i);
    if (name == 't') return t;
    i++; // '('
    final args = <double>[];
    while (true) {
      args.add(sum());
      skip();
      if (peek() == ',') {
        i++;
        continue;
      }
      i++; // ')'
      break;
    }
    return switch (name) {
      'if' => args[0] != 0 ? args[1] : args[2],
      'lt' => args[0] < args[1] ? 1 : 0,
      'gt' => args[0] > args[1] ? 1 : 0,
      'pow' => _pow(args[0], args[1]),
      'min' => args[0] < args[1] ? args[0] : args[1],
      'max' => args[0] > args[1] ? args[0] : args[1],
      _ => throw ArgumentError('unknown $name'),
    };
  }

  double product() {
    var v = atom();
    while (true) {
      skip();
      if (peek() == '*') {
        i++;
        v *= atom();
      } else if (peek() == '/') {
        i++;
        v /= atom();
      } else {
        return v;
      }
    }
  }

  sum = () {
    var v = product();
    while (true) {
      skip();
      if (peek() == '+') {
        i++;
        v += product();
      } else if (peek() == '-') {
        i++;
        v -= product();
      } else {
        return v;
      }
    }
  };
  return sum();
}

double _pow(double a, double b) {
  var r = 1.0;
  for (var k = 0; k < b.round(); k++) {
    r *= a;
  }
  return r;
}

void main() {
  group('VerseMotion', () {
    const fade = VerseMotion(arrival: VerseArrival.fade);
    const rise = VerseMotion(arrival: VerseArrival.rise);

    test('none is none, and keys only what is on', () {
      expect(VerseMotion.none.isNone, isTrue);
      expect(VerseMotion.none.key, '');
      expect(fade.key, isNot(''));
      expect(const VerseMotion(thread: true).key,
          isNot(const VerseMotion(light: true).key));
      expect(fade.moves, isTrue);
      expect(const VerseMotion(thread: true).moves, isFalse);
    });

    test('round-trips through JSON', () {
      const m = VerseMotion(
          arrival: VerseArrival.rise,
          thread: true,
          light: true,
          trail: true,
          unveil: true);
      expect(VerseMotion.fromJson(m.toJson()), m);
      expect(VerseMotion.fromJson(null), VerseMotion.none);
      expect(VerseMotion.fromJson(const {'arrival': 'warp'}), VerseMotion.none);
    });

    test('a voice without word timing drops what follows the words', () {
      const m = VerseMotion(
          arrival: VerseArrival.fade, thread: true, trail: true, unveil: true);
      final run = m.forVoice(hasWords: false);
      expect(run.trail, isFalse);
      expect(run.unveil, isFalse);
      expect(run.thread, isTrue);
      expect(m.forVoice(hasWords: true), m);
    });

    test('fades in, holds, fades out — linearly, as FFmpeg does', () {
      const unit = 3000;
      final w = fade.windowsFor(unit);
      expect(w.inMs, VerseMotion.fadeInMs);
      expect(w.outMs, VerseMotion.outMs);
      expect(fade.alphaAt(0, unit), 0);
      expect(fade.alphaAt(w.inMs ~/ 2, unit), closeTo(0.5, 0.01));
      expect(fade.alphaAt(1500, unit), 1);
      expect(fade.alphaAt(unit - w.outMs ~/ 2, unit), closeTo(0.5, 0.01));
      expect(fade.alphaAt(unit, unit), 0);
      expect(VerseMotion.none.alphaAt(0, unit), 1);
    });

    test('a short unit is never all fade', () {
      final w = fade.windowsFor(600);
      expect(w.inMs, lessThanOrEqualTo(200));
      expect(w.outMs, lessThanOrEqualTo(150));
    });

    test("the rise's FFmpeg expression is the preview's curve", () {
      const unit = 2800;
      for (var ms = 0; ms <= unit; ms += 20) {
        final expr = rise.offsetExpr('t', unit);
        expect(ffEval(expr, ms / 1000), closeTo(rise.offsetAt(ms, unit), 0.05),
            reason: 'at $ms ms: $expr');
      }
      expect(rise.offsetAt(0, unit), VerseMotion.risePx);
      expect(rise.offsetAt(1400, unit), 0);
      expect(fade.offsetExpr('t', unit), '0');
    });

    test('presets are what they say', () {
      expect(MotionPreset.still.motion, VerseMotion.none);
      expect(MotionPreset.of(const VerseMotion(arrival: VerseArrival.fade)),
          MotionPreset.breathe);
      expect(MotionPreset.unveil.needsWords, isTrue);
      expect(MotionPreset.thread.needsWords, isFalse);
      expect(MotionPreset.of(const VerseMotion(light: true)), isNull);
    });
  });

  group('RowProgress', () {
    test('reaches each word as the reciter does', () {
      // A 300-pixel line of three words, right to left.
      final p = RowProgress.words(const [
        (startMs: 100, endMs: 500, from: 0, to: 90),
        (startMs: 700, endMs: 1200, from: 100, to: 200),
        (startMs: 1300, endMs: 1800, from: 210, to: 300),
      ], 300);
      expect(p.at(0), 0);
      expect(p.at(100), 0);
      expect(p.at(500), 90);
      expect(p.at(300), closeTo(45, 0.01));
      // Across the breath it glides to the next word's edge.
      expect(p.at(600), closeTo(95, 0.01));
      expect(p.at(1200), 200);
      expect(p.at(1800), 300);
      expect(p.at(5000), 300);
    });

    test('never goes back, whatever the timing says', () {
      final p = RowProgress.words(const [
        (startMs: 100, endMs: 600, from: 0, to: 120),
        (startMs: 400, endMs: 900, from: 100, to: 200),
      ], 200);
      var last = -1.0;
      for (var ms = 0; ms < 1200; ms += 10) {
        final v = p.at(ms);
        expect(v, greaterThanOrEqualTo(last));
        last = v;
      }
    });

    test("its FFmpeg expression is the preview's function", () {
      final p = RowProgress.words(const [
        (startMs: 100, endMs: 500, from: 0, to: 90),
        (startMs: 700, endMs: 1200, from: 100, to: 200),
        (startMs: 1300, endMs: 1800, from: 210, to: 300),
      ], 300);
      final expr = p.expr('t');
      for (var ms = 0; ms <= 2000; ms += 25) {
        expect(ffEval(expr, ms / 1000), closeTo(p.at(ms), 0.2),
            reason: 'at $ms ms');
      }
      // In another clock: the pass's, with the unit 1.5 s in.
      final shifted = p.expr('(t-1.500)');
      expect(ffEval(shifted, 1.5 + 0.3), closeTo(p.at(300), 0.2));
    });

    test('an even line is crossed at an even pace', () {
      final p = RowProgress.even(1000, 3000, 400);
      expect(p.at(1000), 0);
      expect(p.at(2000), 200);
      expect(p.at(3000), 400);
    });
  });

  group('VerseFollow', () {
    const unit = VerseUnit(1, null, 1000, 5000);
    // Gap-filled, relative to the verse's start (1000): four words.
    const spans = [
      HighlightSpan(200, 1000, 0, 1),
      HighlightSpan(1000, 2000, 1, 3),
      HighlightSpan(2000, 3000, 3, 4),
      HighlightSpan(3000, 4000, 4, 5),
    ];

    test('nothing asked of the words is one plain card', () {
      final w = VerseFollow.of(
          unit: unit,
          verseStartMs: 1000,
          spans: spans,
          highlight: false,
          trail: false,
          unveil: false);
      expect(w, [const FollowWindow(1000, 5000, null, null)]);
      expect(w.single.isBase, isTrue);
    });

    test('the highlight lights each word in turn, gapless', () {
      final w = VerseFollow.of(
          unit: unit,
          verseStartMs: 1000,
          spans: spans,
          highlight: true,
          trail: false,
          unveil: false);
      expect(w.first, const FollowWindow(1000, 1200, null, null));
      expect(w[1].lit, (start: 0, end: 1));
      expect(w[2].lit, (start: 1, end: 3));
      expect(w.last.endMs, 5000);
      for (var i = 1; i < w.length; i++) {
        expect(w[i].startMs, w[i - 1].endMs);
      }
    });

    test('the trail keeps every recited word lit', () {
      final w = VerseFollow.of(
          unit: unit,
          verseStartMs: 1000,
          spans: spans,
          highlight: true,
          trail: true,
          unveil: false);
      expect([for (final x in w.skip(1)) x.lit?.end], [1, 3, 4, 5]);
      expect([for (final x in w.skip(1)) x.lit?.start], [0, 0, 0, 0]);
    });

    test('the unveil leaves the words ahead faint', () {
      final w = VerseFollow.of(
          unit: unit,
          verseStartMs: 1000,
          spans: spans,
          highlight: false,
          trail: false,
          unveil: true);
      expect(w.first.dimFrom, 0);
      expect([for (final x in w.skip(1)) x.dimFrom], [1, 3, 4, 5]);
      expect(VerseFollow.at(w, 2500).dimFrom, 3);
    });

    test("a part follows only its own words, in its own tokens", () {
      const part = VersePart(
        ayah: 1,
        index: 1,
        count: 2,
        tokenStart: 3,
        tokenEnd: 5,
        startMs: 3600,
        endMs: 5000,
        arabic: 'c d',
        translation: '',
        fit: 1,
      );
      const u = VerseUnit(1, part, 3600, 5000);
      final w = VerseFollow.of(
          unit: u,
          verseStartMs: 1000,
          spans: spans,
          highlight: true,
          trail: false,
          unveil: false);
      // Its first word starts as it does: no plain lead-in.
      expect(w.first.startMs, 3600);
      expect(w.last.endMs, 5000);
      expect([for (final x in w) x.lit],
          [(start: 0, end: 1), (start: 1, end: 2)]);
    });
  });

  test('a long reel goes without the light, and keeps the rest', () {
    const m = VerseMotion.standard;
    expect(m.forUnits(VerseMotion.lightMostUnits), m);
    final long = m.forUnits(VerseMotion.lightMostUnits + 1);
    expect(long.light, isFalse);
    expect(long.arrival, m.arrival);
    // Nothing to take off a motion without it.
    const thread = VerseMotion(arrival: VerseArrival.rise, thread: true);
    expect(thread.forUnits(1000), thread);
  });
}
