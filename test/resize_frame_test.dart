import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/verse_translation.dart';
import 'package:ayah_reels/widgets/resize_frame.dart';
import 'package:ayah_reels/widgets/surah_title.dart';

/// The handles on the surah's name and the verse: a corner sizes it with
/// one finger, anywhere else moves it, two fingers pinch it, and crop
/// marks frame it while it is touched.
void main() {
  late double scale;
  late List<double> sizes;
  late Offset moved;
  late int ends;

  setUp(() {
    scale = 1;
    sizes = [];
    moved = Offset.zero;
    ends = 0;
  });

  Future<void> host(WidgetTester t) => t.pumpWidget(
        MaterialApp(
          home: Center(
            child: StatefulBuilder(
              builder: (context, setState) => ResizableBox(
                key: const Key('box'),
                scale: scale,
                pad: 20,
                inset: 4,
                onResize: (v) => setState(() {
                  scale = v;
                  sizes.add(v);
                }),
                onMove: (d) => moved += d,
                onEnd: () => ends++,
                child: const SizedBox(width: 200, height: 60),
              ),
            ),
          ),
        ),
      );

  Rect box(WidgetTester t) => t.getRect(find.byKey(const Key('box')));

  double marks(WidgetTester t) => t
      .widget<AnimatedOpacity>(find.descendant(
          of: find.byKey(const Key('box')),
          matching: find.byType(AnimatedOpacity)))
      .opacity;

  testWidgets('a corner sizes it with one finger, out to grow, in to shrink',
      (t) async {
    await host(t);
    final r = box(t);
    final g = await t.startGesture(r.bottomRight - const Offset(8, 8));
    await t.pump();
    expect(marks(t), 1, reason: 'the marks come with the touch');
    await g.moveBy(const Offset(30, 10));
    await g.moveBy(const Offset(30, 10));
    await t.pump();
    expect(scale, greaterThan(1.2));
    expect(moved, Offset.zero, reason: 'a corner sizes; it does not move');
    await g.moveBy(const Offset(-120, -40));
    await t.pump();
    expect(scale, lessThan(1));
    await g.up();
    await t.pump();
    expect(ends, 1);
    // They linger a moment, then go.
    expect(marks(t), 1);
    await t.pump(ResizableBox.linger + const Duration(milliseconds: 50));
    expect(marks(t), 0);
    await t.pumpAndSettle();
  });

  testWidgets('anywhere else, one finger moves it', (t) async {
    await host(t);
    final c = box(t).center;
    await t.dragFrom(c, const Offset(0, 40));
    await t.pump();
    expect(moved.dy, greaterThan(20));
    expect(sizes, isEmpty);
    await t.pumpAndSettle();
  });

  testWidgets('two fingers pinch it', (t) async {
    await host(t);
    final c = box(t).center;
    final a = await t.startGesture(c - const Offset(30, 0), pointer: 1);
    final b = await t.startGesture(c + const Offset(30, 0), pointer: 2);
    await t.pump();
    await a.moveBy(const Offset(-30, 0));
    await b.moveBy(const Offset(30, 0));
    await t.pump();
    expect(scale, greaterThan(1.5));
    await a.up();
    await b.up();
    await t.pumpAndSettle();
  });

  testWidgets('the marks frame what is inside the padding', (t) async {
    await host(t);
    final g = await t.startGesture(box(t).center);
    await t.pump();
    final paint = t.widget<CustomPaint>(find.descendant(
        of: find.byKey(const Key('box')), matching: find.byType(CustomPaint)));
    expect(paint.painter, isA<CropMarks>());
    expect((paint.painter! as CropMarks).resizable, isTrue);
    await g.up();
    await t.pumpAndSettle();
  });

  testWidgets('the surah name takes a corner too, and keeps its pinch',
      (t) async {
    var titleScale = 1.0;
    await t.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 390,
        height: 694,
        child: StatefulBuilder(
          builder: (context, setState) => ReelSurahTitle(
            width: 390,
            surah: 2,
            edition: VerseTranslation.english,
            scale: titleScale,
            onDrag: (_) {},
            onResize: (v) => setState(() => titleScale = v),
          ),
        ),
      ),
    ));
    final r = t.getRect(find.byType(ResizableBox));
    final g = await t.startGesture(r.topRight + const Offset(-6, 6));
    await g.moveBy(const Offset(40, -10));
    await g.moveBy(const Offset(40, -10));
    await t.pump();
    expect(titleScale, greaterThan(1.1));
    await g.up();
    await t.pumpAndSettle();
  });
}
