import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/share_origin.dart';

/// iOS will not open the share sheet at all without an anchor rect, and
/// it validates that rect on the way in:
///
///     PlatformException(error, sharePositionOrigin: argument must be
///     set, {{0, 0}, {0, 0}} must be non-zero and within coordinate
///     space of source view: {{0, 0}, {414, 896}})
///
/// Every share in the app went out with the zero rect once, so both
/// halves of that contract — non-empty, and inside the view — are
/// pinned here rather than left to each call site.
void main() {
  /// The rect iOS is handed for a button laid out per [align].
  Future<Rect> originOf(WidgetTester t, Alignment align) async {
    late Rect origin;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: align,
          child: Builder(
            builder: (c) => SizedBox(
              width: 120,
              height: 44,
              child: GestureDetector(onTap: () => origin = shareOriginOf(c)),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.byType(GestureDetector), warnIfMissed: false);
    return origin;
  }

  const view = Rect.fromLTWH(0, 0, 800, 600); // the test view's size

  testWidgets('anchors on the tapped widget', (t) async {
    final origin = await originOf(t, Alignment.center);
    expect(origin.width, 120);
    expect(origin.height, 44);
    expect(origin.center, const Offset(400, 300));
  });

  for (final (name, align) in [
    ('top-left', Alignment.topLeft),
    ('bottom-right', Alignment.bottomRight),
  ]) {
    testWidgets('a $name button still lands inside the view', (t) async {
      final origin = await originOf(t, align);
      expect(origin.isEmpty, isFalse);
      expect(view.contains(origin.topLeft), isTrue);
      expect(view.contains(origin.bottomRight - const Offset(0.01, 0.01)),
          isTrue);
    });
  }

  testWidgets('an unmeasurable widget falls back, never to the zero rect',
      (t) async {
    late Rect origin;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        // A context whose element carries no render object of its own
        // and is measured before its subtree lays out.
        origin = shareOriginOf(c);
        return const SizedBox.shrink();
      }),
    ));
    expect(origin.isEmpty, isFalse);
    expect(view.overlaps(origin), isTrue);
  });
}
