import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/gilded_writing.dart';

/// The app's name, written in gold as Home opens. It must read from the
/// first frame, move nothing around it, be said once to a reader, and
/// end as the gilded name at the size the name always had.
void main() {
  Widget host({bool still = false}) => MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(
              body: Center(
                // As Home sets it: a stop of its own for a reader.
                child: Semantics(
                  container: true,
                  child: const GildedWriting(
                    'AyahReel',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// The travelling light: only there while the name is being written.
  final light = find.descendant(
      of: find.byType(GildedWriting), matching: find.byType(CustomPaint));

  /// Every label a reader is handed that carries the name.
  List<String> named(WidgetTester t) {
    final out = <String>[];
    void walk(SemanticsNode n) {
      final label = n.getSemanticsData().label;
      if (label.contains('AyahReel')) out.add(label);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(t.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
    return out;
  }

  testWidgets('written in under a second and a half, then the gilded name',
      (t) async {
    final h = t.ensureSemantics();
    // Gilded from the start: the size of the name's own text.
    await t.pumpWidget(host(still: true));
    final size = t.getSize(find.byType(GildedWriting));
    expect(size, t.getSize(find.text('AyahReel')));

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(host());
    // While it writes: the tooled letters and the leaf over them, the
    // light, and the name said once.
    expect(find.text('AyahReel'), findsNWidgets(2));
    expect(light, findsOneWidget);
    expect(named(t), ['AyahReel']);
    expect(t.getSize(find.byType(GildedWriting)), size);

    await t.pump(const Duration(milliseconds: 700));
    expect(named(t), ['AyahReel']);
    expect(t.getSize(find.byType(GildedWriting)), size,
        reason: 'the writing moved what is around it');

    await t.pump(const Duration(milliseconds: 800));
    await t.pump();
    expect(find.text('AyahReel'), findsOneWidget);
    expect(light, findsNothing);
    expect(named(t), ['AyahReel']);
    expect(t.getSize(find.byType(GildedWriting)), size);
    h.dispose();
  });

  testWidgets('with less motion asked for, it is gilded from the first frame',
      (t) async {
    await t.pumpWidget(host(still: true));
    expect(find.text('AyahReel'), findsOneWidget);
    expect(light, findsNothing);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('AyahReel'), findsOneWidget);
  });

  testWidgets('the leaf reaches into the tail of the y', (t) async {
    // Laid past the text's own box, so nothing that pokes out of a
    // tight line is left bare.
    await t.pumpWidget(host(still: true));
    final writing = t.getRect(find.byType(GildedWriting));
    final leaf = t.getRect(find
        .descendant(
            of: find.byType(GildedWriting), matching: find.byType(ShaderMask))
        .first);
    expect(leaf.top, lessThan(writing.top));
    expect(leaf.bottom, greaterThan(writing.bottom));
    expect(leaf.left, lessThan(writing.left));
    expect(leaf.right, greaterThan(writing.right));
  });
}
