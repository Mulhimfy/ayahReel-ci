import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/picked_media.dart';
import 'package:ayah_reels/render/video_renderer.dart';

/// "Why are some of my videos black" (2026-10-31, a 3.6 GB phone): the
/// gallery picker's copy of a photo lived in the cache folder Android
/// empties when storage runs low, and a reel made after that was laid
/// on a near-black gradient instead of the photo. A pick is kept in the
/// app's own folder now.
void main() {
  late Directory root;
  late Directory cache;
  late Directory kept;

  File picked(String name, {int bytes = 1024, DateTime? at}) {
    final f = File('${cache.path}/$name')..writeAsBytesSync(List.filled(bytes, 7));
    if (at != null) f.setLastModifiedSync(at);
    return f;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('ayah_picked');
    cache = Directory('${root.path}/cache')..createSync();
    kept = Directory('${root.path}/picked');
    PickedMedia.debugDir = kept;
  });

  tearDown(() {
    PickedMedia.debugDir = null;
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a pick leaves the cache folder for the kept one, bytes intact',
      () async {
    final src = picked('image_picker_1.jpg', bytes: 4096);
    final path = await PickedMedia.keep(src.path);
    expect(File(path).parent.path, kept.path);
    expect(File(path).lengthSync(), 4096);
    expect(src.existsSync(), isFalse, reason: 'moved, not copied');
    expect(path, endsWith('_image_picker_1.jpg'));
  });

  test('a pick already kept, or one that is gone, is left as it is',
      () async {
    final first = await PickedMedia.keep(picked('a.jpg').path);
    expect(await PickedMedia.keep(first), first);
    final gone = '${cache.path}/never_there.jpg';
    expect(await PickedMedia.keep(gone), gone);
  });

  test('old picks go once there are more than the folder keeps', () async {
    final base = DateTime(2026, 10, 1);
    final paths = <String>[];
    for (var i = 0; i < PickedMedia.keepFiles + 3; i++) {
      paths.add(await PickedMedia.keep(
          picked('p$i.jpg', at: base.add(Duration(minutes: i))).path));
    }
    final left = kept.listSync().whereType<File>().map((f) => f.path).toSet();
    expect(left.length, PickedMedia.keepFiles);
    expect(left, contains(paths.last), reason: 'the newest always stays');
    expect(left, isNot(contains(paths.first)), reason: 'the oldest goes');
  });

  group('a black picture', () {
    test('flat black, with the dither averaged away, is black', () {
      // 0 once turned to gray, 16 where the limited range is kept.
      expect(
          VideoRenderer.lumaIsBlack(List.filled(27 * 48, 0), 27 * 48), isTrue);
      expect(
          VideoRenderer.lumaIsBlack(List.filled(27 * 48, 16), 27 * 48), isTrue);
    });

    test('one block of the mark or a verse is not', () {
      // A near-black reel with nothing but a faint mark peaks at 30.
      final px = List.filled(27 * 48, 6);
      px[40 * 27 + 13] = 30;
      expect(VideoRenderer.lumaIsBlack(px, 27 * 48), isFalse);
    });

    test('a short read is never called black', () {
      expect(VideoRenderer.lumaIsBlack(List.filled(10, 16), 27 * 48), isFalse);
    });
  });
}
