import 'dart:io';

import 'package:ayah_reels/render/video_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Every video fails right at the end" on an Android phone: each
/// styling the preview settled on was encoded in full and kept, and each
/// save left a named copy beside it, none of them ever deleted. The
/// sweep is what keeps the cache from filling the phone a reel at a
/// time.
void main() {
  late Directory tmp;
  final now = DateTime(2026, 10, 1, 12);

  setUp(() => tmp = Directory.systemTemp.createTempSync('render_sweep_test'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File put(String name, {required Duration age}) =>
      File('${tmp.path}/$name')
        ..writeAsStringSync('bytes')
        ..setLastModifiedSync(now.subtract(age));

  List<String> left() =>
      [for (final e in tmp.listSync()) e.uri.pathSegments.last]..sort();

  test('keeps the reel being made and the newest finished one, and only '
      'those', () {
    final keep = File('${tmp.path}/ayah_reel_new.mp4');
    put('ayah_reel_a.mp4', age: const Duration(days: 9));
    put('ayah_reel_b.mp4', age: const Duration(minutes: 1));
    put('ayah_reel_c.mp4', age: const Duration(hours: 3));

    VideoRenderer.sweepCache(tmp, keep: keep, now: now);

    expect(left(), ['ayah_reel_b.mp4']);
  });

  test('the reel being made is never touched, even when it is the oldest',
      () {
    final keep = put('ayah_reel_new.mp4', age: const Duration(days: 30));
    put('ayah_reel_b.mp4', age: const Duration(minutes: 1));

    VideoRenderer.sweepCache(tmp, keep: keep, now: now);

    expect(left(), ['ayah_reel_b.mp4', 'ayah_reel_new.mp4']);
  });

  test('leftover parts and named copies go once nothing can still own '
      'them', () {
    final keep = File('${tmp.path}/ayah_reel_new.mp4');
    put('ayah_reel_x.mp4.part', age: const Duration(hours: 1));
    put('ayah_reel_x.mp4.part.p0.mp4', age: const Duration(hours: 1));
    put('ayah_reel_x.mp4.part.list.txt', age: const Duration(hours: 1));
    put('AyahReel_Al_Fatiha_1_7.mp4', age: const Duration(days: 2));
    // Fresh: a save or an encode may be using these right now.
    put('ayah_reel_y.mp4.part', age: const Duration(seconds: 30));
    put('AyahReel_Al_Ikhlas_1_4.mp4', age: const Duration(seconds: 30));

    VideoRenderer.sweepCache(tmp, keep: keep, now: now);

    expect(left(), ['AyahReel_Al_Ikhlas_1_4.mp4', 'ayah_reel_y.mp4.part']);
  });

  test('files that are not renders are left alone', () {
    final keep = File('${tmp.path}/ayah_reel_new.mp4');
    put('ayah_card_3.png', age: const Duration(days: 9));
    put('wa_clip.mp4', age: const Duration(days: 9));
    put('AyahReel_card.png', age: const Duration(days: 9));

    VideoRenderer.sweepCache(tmp, keep: keep, now: now);

    expect(left(), ['AyahReel_card.png', 'ayah_card_3.png', 'wa_clip.mp4']);
  });

  test('one-off share copies go after minutes, render pictures after a day',
      () {
    final keep = File('${tmp.path}/ayah_reel_new.mp4');
    put('ig_ayah_reel_a.mp4', age: const Duration(hours: 1));
    put('tanafus_story_1.png', age: const Duration(hours: 1));
    put('ayahreel_round_1.png', age: const Duration(hours: 1));
    put('ayahreel_verses_1.png', age: const Duration(hours: 1));
    put('ayah_1f3a_2.png', age: const Duration(days: 3));
    put('ayah_1f3a_2_w0_3.png', age: const Duration(days: 3));
    put('ayah_bgflat_k.png', age: const Duration(days: 3));
    // The cards of verses cut into lines or moving, and what rides on
    // them.
    put('ayah_-1f3a_255_p0_base.png', age: const Duration(days: 3));
    put('ayah_1f3a_255_p2_w0_14_dx.png', age: const Duration(days: 3));
    put('ayah_1f3a_255_p1_wx_d0.png', age: const Duration(days: 3));
    put('ayah_1f3a_255_p1_w3_4_d4.png', age: const Duration(days: 3));
    put('ayah_1f3a_7_glint.png', age: const Duration(days: 3));
    put('ayah_thread_v1_ffeec96b.png', age: const Duration(days: 3));
    put('ayah_spark_v1_ffeec96b.png', age: const Duration(days: 3));
    put('ayah_title_v1_2_en_lt.png', age: const Duration(days: 3));
    // Cards kept under what they look like, and their numbers.
    put('ayah_c_0a1b2c3d4e5f60718293a4b5.png', age: const Duration(days: 3));
    put('ayah_c_0a1b2c3d4e5f60718293a4b5.json', age: const Duration(days: 3));
    // Drawn today: the session that drew them may want them again.
    put('ayah_1f3a_3.png', age: const Duration(hours: 2));
    put('ayah_1f3a_255_p0_base.png', age: const Duration(hours: 2));
    put('ayah_c_ffeeddccbbaa998877665544.png', age: const Duration(hours: 2));
    put('ayah_c_ffeeddccbbaa998877665544.json', age: const Duration(hours: 2));
    put('ig_ayah_reel_b.mp4', age: const Duration(seconds: 30));

    VideoRenderer.sweepCache(tmp, keep: keep, now: now);

    expect(left(), [
      'ayah_1f3a_255_p0_base.png',
      'ayah_1f3a_3.png',
      'ayah_c_ffeeddccbbaa998877665544.json',
      'ayah_c_ffeeddccbbaa998877665544.png',
      'ig_ayah_reel_b.mp4',
    ]);
  });
}
