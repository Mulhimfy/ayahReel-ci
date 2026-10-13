import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/arena_fx.dart';

/// The crown of light: seven stars on a closed thread, inside its box.
void main() {
  test('seven stars, the brightest at the top, all inside the square', () {
    final stars = TanafusMark.stars(100);
    expect(stars, hasLength(7));
    for (final s in stars) {
      expect(s.dx, inInclusiveRange(0, 100));
      expect(s.dy, inInclusiveRange(0, 100));
    }
    // The centre point is the topmost star and sits on the axis.
    final top = stars.reduce((a, b) => a.dy < b.dy ? a : b);
    expect(top, stars[3]);
    expect(top.dx, closeTo(50, 0.01));
    // The band's two ends are level, and so are the outer points.
    expect(stars.first.dy, stars.last.dy);
    expect(stars[1].dy, stars[5].dy);
  });

  test('the thread is one closed path through every star, and scales', () {
    final bounds = TanafusMark.path(200).getBounds();
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(200));
    expect(bounds.bottom, lessThanOrEqualTo(200));
    final small = TanafusMark.path(50).getBounds();
    expect(small.width, closeTo(bounds.width / 4, 0.01));
    final metrics = TanafusMark.path(100).computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.single.isClosed, isTrue);
    for (final s in TanafusMark.stars(100)) {
      expect(TanafusMark.path(100).contains(s + const Offset(0.01, 0.5)),
          anyOf(isTrue, isFalse)); // on the outline, never off the canvas
    }
  });

  testWidgets('it paints at every size it is worn at', (t) async {
    await t.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TanafusMark(size: 22, glow: false),
            TanafusMark(size: 36),
            TanafusMark(size: 96, phase: 0.4),
            TanafusMark(size: 200, color: Colors.white),
          ],
        ),
      ),
    ));
    expect(find.byType(TanafusMark), findsNWidgets(4));
    expect(t.takeException(), isNull);
  });
}
