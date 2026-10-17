import 'dart:convert';
import 'dart:io';

import 'package:ayah_reels/data/reel_library.dart';
import 'package:ayah_reels/render/video_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Points the documents directory at a throwaway folder so the library
/// can be exercised without a device.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docs);
  final String docs;

  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('reel_library_test');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    ReelLibrary.debugReset();
  });

  tearDown(() {
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } catch (_) {/* Windows holds the handle; the runner cleans up */}
  });

  /// Stands in for a finished render. Content is irrelevant to the
  /// library; only the identity it is added under matters.
  File render(String name, {String bytes = 'mp4'}) =>
      File('${root.path}/$name')..writeAsStringSync(bytes);

  Future<SavedReel> add(File video, String sourceKey) => ReelLibrary.add(
        video: video,
        sourceKey: sourceKey,
        reciterName: 'Husary',
        surahName: 'Al-Fatiha',
        startAyah: 1,
        endAyah: 2,
        gradientArgb: const [0xFF000000, 0xFF101010],
      );

  int mp4sInLibrary() => Directory('${root.path}/reels')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.mp4'))
      .length;

  test('sourceKeyOf reads the styling key out of a render file name', () {
    final key = VideoRenderer.sourceKeyOf(File('/tmp/ayah_reel_v5_husary_'
        'desert_stars_50_s1_1_2_ffffffff_100_p0_h0.mp4'));
    expect(
      key,
      'v5_husary_desert_stars_50_s1_1_2_ffffffff_100_p0_h0',
    );
  });

  test('exporting the same reel twice keeps one entry and one file', () async {
    // The reported case: Save, then Save again 39 seconds later. The
    // renderer serves its cached mp4 both times, so both exports carry
    // the same key.
    final video = render('ayah_reel_v5_husary_desert_50_s1_1_2.mp4');
    const key = 'v5_husary_desert_50_s1_1_2';

    final first = await add(video, key);
    final second = await add(video, key);

    expect(second.id, first.id, reason: 'the repeat export is the same reel');
    expect(second.fileName, first.fileName);
    expect((await ReelLibrary.load()).length, 1);
    expect(mp4sInLibrary(), 1, reason: 'no second copy on disk');
  });

  test('a different styling exports as its own reel', () async {
    await add(render('a.mp4'), 'v5_husary_desert_50_s1_1_2');
    await add(render('b.mp4'), 'v5_husary_desert_50_s1_1_7');

    expect((await ReelLibrary.load()).length, 2);
    expect(mp4sInLibrary(), 2);
  });

  test('gallery mark survives a reload, so a repeat Save can decline',
      () async {
    final reel = await add(render('a.mp4'), 'v5_key');
    expect(reel.inGallery, isFalse);

    await ReelLibrary.markInGallery(reel);

    final reloaded = (await ReelLibrary.load()).single;
    expect(reloaded.id, reel.id);
    expect(reloaded.inGallery, isTrue);
  });

  test('entries written before sourceKey existed still load', () async {
    // An index from an older build: no sourceKey, no inGallery.
    final dir = Directory('${root.path}/reels')..createSync(recursive: true);
    File('${dir.path}/reel_1.mp4').writeAsStringSync('mp4');
    File('${dir.path}/library.json').writeAsStringSync(jsonEncode([
      {
        'id': '1',
        'fileName': 'reel_1.mp4',
        'reciterName': 'Husary',
        'surahName': 'Al-Fatiha',
        'startAyah': 1,
        'endAyah': 2,
        'gradientArgb': [0xFF000000, 0xFF101010],
        'createdAt': '2026-07-30T10:00:00.000',
      }
    ]));

    final reel = (await ReelLibrary.load()).single;
    expect(reel.sourceKey, isEmpty);
    expect(reel.inGallery, isFalse);
    // An empty key must never match another empty key, or every legacy
    // reel would look like a re-export of the first one.
    expect(await ReelLibrary.findBySource(''), isNull);
  });

  test('the sweep takes cut-short copies, never a reel an index names',
      () async {
    final dir = Directory('${root.path}/reels')..createSync(recursive: true);
    for (final n in ['reel_1', 'reel_2', 'reel_3', 'reel_4.mp4.tmp']) {
      File('${dir.path}/${n.contains('.') ? n : '$n.mp4'}')
          .writeAsStringSync('mp4');
    }
    // reel_1: an entry this build can't read.
    File('${dir.path}/library.json').writeAsStringSync(jsonEncode([
      {'id': '1', 'fileName': 'reel_1.mp4'},
    ]));
    // reel_2: named only by an index set aside as unreadable.
    File('${dir.path}/library.json.bad')
        .writeAsStringSync('[{"id": "2", "fileName": "reel_2.mp4", "rec');

    await add(render('a.mp4'), 'v5_key');
    expect(File('${dir.path}/reel_3.mp4').existsSync(), isFalse,
        reason: 'named nowhere: a copy an older build cut short');
    expect(File('${dir.path}/reel_4.mp4.tmp').existsSync(), isFalse);

    // The save kept the entry it couldn't read, so a launch later its
    // reel is still named.
    ReelLibrary.debugReset();
    await ReelLibrary.sweepStrays();
    expect(File('${dir.path}/reel_1.mp4').existsSync(), isTrue);
    expect(File('${dir.path}/reel_2.mp4').existsSync(), isTrue);
    expect((await ReelLibrary.load()).length, 1);
    expect(File('${dir.path}/library.json').readAsStringSync(),
        contains('reel_1.mp4'));
  });

  test('removing a reel takes its poster with it', () async {
    final reel = await add(render('a.mp4'), 'v5_key');
    final poster = await ReelLibrary.posterFile(reel);
    poster.writeAsStringSync('jpg');

    await ReelLibrary.remove(reel);

    expect(poster.existsSync(), isFalse);
    expect((await ReelLibrary.videoFile(reel)).existsSync(), isFalse);
    expect(await ReelLibrary.load(), isEmpty);
  });
}
