import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/widgets/glass_tile.dart';

/// The glass over the scenery tiles: it leans to a finger, runs light
/// across itself, follows a held finger from tile to tile — and takes
/// nothing from the grid it sits in. A tap still taps, a drag still
/// scrolls, a reader still hears the tile, and nothing is left running
/// once the glass is home.
void main() {
  group('the motion, at the wallet card\'s rates', () {
    test('leans toward the finger and lifts a hair', () {
      // The top-right corner.
      final m = GlassMotion()..aim(1, -1);
      const dt = 1 / 60;
      var p = m.update(dt, dt);
      expect(p.yaw, closeTo(9 * (1 - math.exp(-8 * dt)), 1e-9));
      expect(p.pitch, closeTo(7 * (1 - math.exp(-8 * dt)), 1e-9));
      expect(p.scale, closeTo(1 + 0.01 * (1 - math.exp(-12 * dt)), 1e-12));
      for (var i = 2; i <= 120; i++) {
        p = m.update(i * dt, dt);
      }
      expect(p.yaw, closeTo(9, 0.01));
      expect(p.pitch, closeTo(7, 0.01));
      expect(p.scale, closeTo(1.01, 1e-4));
      // Held off-centre, the glass is still awake.
      expect(p.isActive, isTrue);
    });

    test('never turns further than 9° and 7°, wherever the finger goes', () {
      final m = GlassMotion()..aim(-3, 4);
      late GlassPose p;
      for (var i = 1; i <= 300; i++) {
        p = m.update(i / 60, 1 / 60);
      }
      expect(p.yaw, closeTo(-9, 0.01));
      expect(p.pitch, closeTo(-7, 0.01));
    });

    test('eases home once the finger lifts, and comes to rest', () {
      final m = GlassMotion()..aim(1, 1);
      var now = 0.0;
      for (var i = 0; i < 60; i++) {
        m.update(now += 1 / 60, 1 / 60);
      }
      m.release();
      final before = m.update(now += 1 / 60, 1 / 60);
      var p = before;
      for (var i = 0; i < 60 * 4; i++) {
        p = m.update(now += 1 / 60, 1 / 60);
      }
      expect(before.yaw, greaterThan(5));
      expect(p.yaw.abs(), lessThan(0.01));
      expect(p.pitch.abs(), lessThan(0.01));
      expect(p.scale, closeTo(1, 1e-4));
      expect(p.isActive, isFalse);
    });

    test('a burst runs its light across and catches the corners, then is '
        'done', () {
      final m = GlassMotion()..burst(0);
      // Half way through the shards' run, the first is the brightest.
      var p = m.update(0.22, 0.016);
      expect(p.shards, hasLength(3));
      expect(p.sparkles, hasLength(4));
      expect(p.shards!.first.opacity, greaterThan(0.6));
      expect(p.shards!.first.opacity, greaterThan(p.shards!.last.opacity));
      // The sparkles catch one corner after another.
      expect(p.sparkles!.first.opacity,
          greaterThan(p.sparkles!.last.opacity + 0.2));
      p = m.update(0.30, 0.016);
      expect(p.sparkles!.first.opacity, greaterThan(0.5));
      expect(p.isActive, isTrue);
      // Past 1.3 of its clock it is over, and says so.
      p = m.update(0.75, 0.016);
      expect(p.shards, isNotNull);
      p = m.update(0.8, 0.016);
      expect(p.shards, isNull);
      expect(p.sparkles, isNull);
      expect(p.isActive, isFalse);
    });

    test('the light moves with the lean: the sheen brightens, the edge turns',
        () {
      final m = GlassMotion();
      final rest = m.update(0, 0);
      expect(rest.sheenOpacity, closeTo(0.3, 1e-9));
      expect(rest.rimAngle, 135);
      m.aim(1, 0);
      late GlassPose p;
      for (var i = 1; i <= 60; i++) {
        p = m.update(i / 60, 1 / 60);
      }
      expect(p.sheenOpacity, greaterThan(0.75));
      expect(p.rimAngle, greaterThan(170));
      // The picture behind the glass moves against the lean.
      expect(p.slide.dx, lessThan(-1.5));
    });
  });

  group('the tile in a grid', () {
    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    Widget grid({
      required List<int> taps,
      ScrollController? controller,
      bool still = false,
    }) {
      return MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(
              body: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 9 / 16,
                ),
                itemCount: 42,
                itemBuilder: (_, i) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps.add(i),
                  child: GlassTile(
                    key: ValueKey(i),
                    child: ColoredBox(
                      color: Color.lerp(
                          const Color(0xFF1B3A5C), const Color(0xFF7A5A3A), i / 42)!,
                      child: Center(child: Text('$i')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// Real frames, as a phone draws them: the glass steps its clock by
    /// at most 50 ms a frame, so one long pump is not two seconds of it.
    Future<void> frames(WidgetTester t, int ms) async {
      for (var e = 0; e < ms; e += 16) {
        await t.pump(const Duration(milliseconds: 16));
      }
    }

    GlassTileState stateOf(WidgetTester t, String label) => t.state(find
        .ancestor(of: find.text(label), matching: find.byType(GlassTile))
        .first);

    testWidgets('a tap still taps, a quick one and a slow one', (t) async {
      phone(t);
      final taps = <int>[];
      await t.pumpWidget(grid(taps: taps));
      await t.tap(find.text('4'));
      await t.pump(const Duration(milliseconds: 50));
      expect(taps, [4]);

      // Held well past the glass's own threshold, then let go without
      // a slide: still a tap.
      final g = await t.startGesture(t.getCenter(find.text('5')));
      await frames(t, 400);
      await g.up();
      await t.pump();
      expect(taps, [4, 5]);
      await frames(t, 3200);
    });

    testWidgets('a plain drag scrolls the grid and chooses nothing',
        (t) async {
      phone(t);
      final taps = <int>[];
      final c = ScrollController();
      addTearDown(c.dispose);
      await t.pumpWidget(grid(taps: taps, controller: c));
      await t.drag(find.text('4'), const Offset(0, -300));
      await t.pump();
      expect(c.offset, greaterThan(100));
      expect(taps, isEmpty);
      await frames(t, 3200);
    });

    testWidgets('held, then slid: the grid holds still and each tile under '
        'the finger leans after it, with a tick for each', (t) async {
      phone(t);
      final haptics = <Object?>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final taps = <int>[];
      final c = ScrollController();
      addTearDown(c.dispose);
      await t.pumpWidget(grid(taps: taps, controller: c));

      final g = await t.startGesture(t.getCenter(find.text('4')));
      await frames(t, 200);
      expect(haptics, isEmpty, reason: 'nothing before the slide');
      // The slide that makes it the glass's.
      await g.moveBy(const Offset(0, 12));
      await t.pump(const Duration(milliseconds: 16));
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      // Down a row, onto 7.
      await g.moveTo(t.getCenter(find.text('7')));
      await frames(t, 300);
      expect(haptics, hasLength(2));
      expect(c.offset, 0, reason: 'the grid scrolled under a held finger');
      final seven = stateOf(t, '7');
      expect(seven.debugDepth, greaterThan(0.5));
      expect(seven.debugPose.scale, greaterThan(1.005));

      await g.up();
      await t.pump();
      expect(taps, isEmpty, reason: 'a slide over the tiles is not a tap');
      await frames(t, 3200);
      expect(seven.debugDepth, 0);
      expect(stateOf(t, '4').debugDepth, 0);
      expect(c.offset, 0);
    });

    testWidgets('a finger rested a moment and then thrown still scrolls the '
        'grid', (t) async {
      phone(t);
      final haptics = <Object?>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      });
      addTearDown(
          () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final taps = <int>[];
      final c = ScrollController();
      addTearDown(c.dispose);
      await t.pumpWidget(grid(taps: taps, controller: c));

      final g = await t.startGesture(t.getCenter(find.text('7')));
      await frames(t, 200);
      // Set off at a point and a half a millisecond, upward.
      const ms = Duration(milliseconds: 1);
      await g.moveBy(const Offset(0, -3), timeStamp: ms * 200);
      await g.moveBy(const Offset(0, -12), timeStamp: ms * 208);
      for (var i = 1; i <= 6; i++) {
        await g.moveBy(const Offset(0, -40), timeStamp: ms * (208 + 8 * i));
      }
      await g.up(timeStamp: ms * 260);
      await t.pump();
      expect(c.offset, greaterThan(100));
      expect(haptics, isEmpty);
      expect(taps, isEmpty);
      await frames(t, 3200);
    });

    testWidgets('leans toward the finger and lifts, then is flat again',
        (t) async {
      phone(t);
      await t.pumpWidget(grid(taps: <int>[]));
      final tile =
          find.ancestor(of: find.text('4'), matching: find.byType(GlassTile));
      final s = t.state<GlassTileState>(tile);
      expect(s.debugDepth, 0);
      expect(s.debugPose.yaw, 0);

      final box = t.getRect(tile);
      final g = await t.startGesture(box.topRight + const Offset(-4, 4));
      await frames(t, 320);
      expect(s.debugPose.yaw, greaterThan(5));
      expect(s.debugPose.pitch, greaterThan(3));
      expect(s.debugPose.scale, greaterThan(1.005));
      expect(s.debugDepth, greaterThan(0.9));

      await g.up();
      await frames(t, 3200);
      expect(s.debugDepth, 0);
      expect(s.debugPose.isActive, isFalse);
      expect(s.debugPose.yaw.abs(), lessThan(0.05));
    });

    testWidgets('with less motion asked for: the light follows the finger, '
        'the pane never leans', (t) async {
      phone(t);
      await t.pumpWidget(grid(taps: <int>[], still: true));
      final tile =
          find.ancestor(of: find.text('4'), matching: find.byType(GlassTile));
      final s = t.state<GlassTileState>(tile);
      final g = await t.startGesture(t.getRect(tile).topRight + const Offset(-4, 4));
      await frames(t, 320);
      expect(s.debugStill, isTrue);
      expect(s.debugDepth, 0);
      expect(s.debugPose.sheenOpacity, greaterThan(0.6));
      await g.up();
      await frames(t, 3200);
    });

    testWidgets('nothing is left running: the slow light never holds a frame '
        'open, and the glass stops once it is home', (t) async {
      phone(t);
      final taps = <int>[];
      await t.pumpWidget(grid(taps: taps));
      await t.pumpAndSettle();
      await t.tap(find.text('4'));
      await t.pumpAndSettle();
      expect(taps, [4]);
      expect(stateOf(t, '4').debugDepth, 0);
      // Gone: a ticker or a timer left behind fails the test here.
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });

    testWidgets('a tile under glass says what it said before, and still '
        'takes a reader\'s tap', (t) async {
      final h = t.ensureSemantics();
      var tapped = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 210,
              child: Semantics(
                container: true,
                button: true,
                label: 'Sky, 1 of 40',
                child: GestureDetector(
                  onTap: () => tapped++,
                  child: const GlassTile(child: ColoredBox(color: Colors.blue)),
                ),
              ),
            ),
          ),
        ),
      ));
      final node = t.getSemantics(find.bySemanticsLabel('Sky, 1 of 40'));
      expect(
        node,
        isSemantics(
          label: 'Sky, 1 of 40',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // Nothing of the glass's own: the tile is still one node.
      var children = 0;
      node.visitChildren((_) {
        children++;
        return true;
      });
      expect(children, 0);
      t.binding.renderViews.first.owner!.semanticsOwner!
          .performAction(node.id, SemanticsAction.tap);
      await t.pump();
      expect(tapped, 1);
      h.dispose();
    });
  });
}
