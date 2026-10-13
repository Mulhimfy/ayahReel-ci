import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/render/reel_poster.dart';
import 'package:ayah_reels/widgets/reel_thumb.dart';

/// My Reels is newest-first and its cards carry no keys, so adding a
/// reel does not give the newest one a new card — it takes over the
/// card already sitting at index 0, and that card's [State] comes with
/// it. Anything a card resolved once and kept therefore belongs to
/// whichever reel used to be at that index.
///
/// That is what a poster held in a `late final` field did: the newest
/// reel wore the previous reel's frame, the previous one wore the frame
/// before that, the whole column shifted by one. The list data was
/// never wrong, which is why a hot reload — throwing every card state
/// away — appeared to fix it.
///
/// So: pin that a card whose reel changes underneath it re-resolves.
void main() {
  SavedReel reel(String id) => SavedReel(
        id: id,
        fileName: 'reel_$id.mp4',
        reciterName: 'Alafasy',
        surahName: 'Al-Fatihah',
        startAyah: 1,
        endAyah: 7,
        gradientArgb: const [0xFF101418, 0xFF202830],
        createdAt: DateTime(2026, 1, 1),
      );

  /// Every reel resolves to a distinct path, so which one a card is
  /// showing is readable straight off the widget tree.
  final asked = <String>[];

  setUp(() {
    asked.clear();
    ReelPoster.testResolver = (r) async {
      asked.add(r.id);
      return File('poster_${r.id}.jpg');
    };
  });

  tearDown(() => ReelPoster.testResolver = null);

  /// The path the card is actually painting, or null while it has none.
  String? shownPoster(WidgetTester tester) {
    final images = tester.widgetList<Image>(find.byType(Image));
    if (images.isEmpty) return null;
    return (images.first.image as FileImage).file.path;
  }

  /// The unkeyed newest-first list, exactly as both grids build it.
  Widget grid(List<SavedReel> reels) => MaterialApp(
        home: Column(
          children: [
            for (final r in reels)
              SizedBox(height: 100, width: 100, child: ReelThumb(reel: r)),
          ],
        ),
      );

  testWidgets('a new reel at the front does not inherit the old poster',
      (tester) async {
    await tester.pumpWidget(grid([reel('first')]));
    await tester.pumpAndSettle();
    expect(shownPoster(tester), 'poster_first.jpg');

    // A second reel is exported. The library reloads newest-first, so
    // 'second' lands at index 0 and 'first' shifts down to index 1 —
    // and neither card is torn down.
    await tester.pumpWidget(grid([reel('second'), reel('first')]));
    await tester.pumpAndSettle();

    final posters = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => (i.image as FileImage).file.path)
        .toList();
    expect(posters, ['poster_second.jpg', 'poster_first.jpg'],
        reason: 'each card must show its own reel, not the one that was '
            'at its index before');
  });

  testWidgets('the card asks for the poster of the reel it was handed',
      (tester) async {
    await tester.pumpWidget(grid([reel('a')]));
    await tester.pumpAndSettle();
    expect(asked, ['a']);

    await tester.pumpWidget(grid([reel('b')]));
    await tester.pumpAndSettle();
    expect(asked, ['a', 'b'],
        reason: 'a reel swapped in under a live card must be re-resolved');
  });

  testWidgets('a card rebuilt with the same reel does not re-extract',
      (tester) async {
    // The other half of the bargain: these cards rebuild on every
    // scroll, and re-running an FFmpeg extraction each time is what
    // holding the future in state was for.
    await tester.pumpWidget(grid([reel('a')]));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid([reel('a')]));
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid([reel('a')]));
    await tester.pumpAndSettle();

    expect(asked, ['a'], reason: 'one extraction per reel, however often '
        'the card rebuilds');
  });

  testWidgets('deleting the top reel leaves the rest showing their own',
      (tester) async {
    await tester.pumpWidget(grid([reel('c'), reel('b'), reel('a')]));
    await tester.pumpAndSettle();

    // Removing index 0 shifts every remaining card up one position —
    // the same reuse, in the other direction.
    await tester.pumpWidget(grid([reel('b'), reel('a')]));
    await tester.pumpAndSettle();

    final posters = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => (i.image as FileImage).file.path)
        .toList();
    expect(posters, ['poster_b.jpg', 'poster_a.jpg']);
  });
}
