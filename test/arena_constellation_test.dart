import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/arena_constellation.dart';

/// The round as a constellation: where the stars stand and how the
/// thread walks them.
void main() {
  const side = 1000.0;
  const c = Offset(side / 2, side / 2);

  test('ten stars scattered over the disc, the same every time for a seed',
      () {
    final p = ConstellationPainter.positions(10, 4242, side);
    expect(p, hasLength(10));
    for (final s in p) {
      expect((s - c).distance, lessThanOrEqualTo(side * 0.37 + 0.001));
    }
    expect(ConstellationPainter.positions(10, 4242, side), p);
    expect(ConstellationPainter.positions(10, 4243, side), isNot(p));
    // Scaled, not re-rolled.
    final half = ConstellationPainter.positions(10, 4242, side / 2);
    for (var i = 0; i < 10; i++) {
      expect(half[i].dx, closeTo(p[i].dx / 2, 0.001));
      expect(half[i].dy, closeTo(p[i].dy / 2, 0.001));
    }
  });

  test('no two stars crowd each other', () {
    for (final seed in [1, 7, 99, 12345, 777777]) {
      final p = ConstellationPainter.positions(10, seed, side);
      var nearest = double.infinity;
      for (var i = 0; i < p.length; i++) {
        for (var j = i + 1; j < p.length; j++) {
          nearest = math.min(nearest, (p[i] - p[j]).distance);
        }
      }
      // A tenth of the side, at least: room for a star and its glow.
      expect(nearest, greaterThan(side * 0.1), reason: 'seed $seed');
    }
  });

  test('the thread starts at the top and always steps to the nearest '
      'star not yet visited', () {
    for (final seed in [3, 21, 4242, 31337]) {
      final p = ConstellationPainter.positions(10, seed, side);
      expect(p.first.dy, p.map((s) => s.dy).reduce(math.min));
      for (var i = 0; i < p.length - 1; i++) {
        final step = (p[i + 1] - p[i]).distance;
        for (var j = i + 1; j < p.length; j++) {
          expect(step, lessThanOrEqualTo((p[j] - p[i]).distance + 1e-9),
              reason: 'seed $seed, step $i');
        }
      }
    }
  });

  test('the net joins every star to at least two others, once each', () {
    final p = ConstellationPainter.positions(10, 8, side);
    final web = ConstellationPainter.web(p);
    expect(web.toSet(), hasLength(web.length));
    for (var i = 0; i < p.length; i++) {
      expect(web.where((e) => e.$1 == i || e.$2 == i).length,
          greaterThanOrEqualTo(2));
    }
  });

  testWidgets('it paints, with and without its words, and draws itself in',
      (t) async {
    final nodes = [
      for (var i = 0; i < 10; i++)
        ConstellationNode('كَلَّا لَوْ تَعْلَمُونَ', correct: i % 3 != 0),
    ];
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
                width: 108,
                height: 108,
                child: Constellation(nodes: nodes, seed: 5, labels: false)),
            SizedBox(
                width: 360,
                height: 360,
                child: ConstellationReveal(nodes: nodes, seed: 5)),
          ],
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 1200));
    await t.pump(const Duration(seconds: 2));
    expect(find.byType(Constellation), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
}
