import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';

/// The home-screen widget's backgrounds are cut by
/// tool/widget_backgrounds.sh into both native resource folders, and
/// each widget rotates through a count of its own (`BACKGROUNDS` in
/// VerseWidget.kt, `backgroundCount` in AyahWidget.swift), because
/// neither is drawn by Flutter and neither can read a Dart constant.
/// A count past the files is a picture that is never found — Android
/// falls back to the first frame, iOS to a plain dark slab — and a
/// count short of them is frames that never show. So: the script
/// writes the count, and this test refuses a build where the files
/// and the two constants disagree.
void main() {
  // `flutter test` runs from the project root.
  const android = 'android/app/src/main/res/drawable-nodpi';
  const ios = 'ios/AyahWidget/Backgrounds';
  const rerun = 'run `bash tool/widget_backgrounds.sh`';

  String name(int i) => 'wbg_${i.toString().padLeft(2, '0')}.jpg';

  /// The frames in [dir], checked to be numbered from wbg_00 without a
  /// gap — the rotation lands on every number below the count.
  int frames(String dir) {
    final d = Directory(dir);
    expect(d.existsSync(), isTrue, reason: '$dir is missing; $rerun');
    final names = d
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((n) => RegExp(r'^wbg_\d\d\.jpg$').hasMatch(n))
        .toList()
      ..sort();
    for (var i = 0; i < names.length; i++) {
      expect(names[i], name(i), reason: '$dir has a gap; $rerun');
    }
    return names.length;
  }

  int constant(String path, RegExp pattern) {
    final m = pattern.firstMatch(File(path).readAsStringSync());
    expect(m, isNotNull,
        reason: '$path no longer has the count where '
            'tool/widget_backgrounds.sh writes it');
    return int.parse(m!.group(1)!);
  }

  test('both platforms carry the same frames, byte for byte', () {
    final count = frames(android);
    expect(count, greaterThan(0), reason: '$android is empty; $rerun');
    expect(frames(ios), count, reason: 'the two folders differ; $rerun');
    for (var i = 0; i < count; i++) {
      final a = File('$android/${name(i)}').readAsBytesSync();
      final b = File('$ios/${name(i)}').readAsBytesSync();
      expect(listEquals(a, b), isTrue,
          reason: '${name(i)} differs between the platforms; $rerun');
    }
  });

  test('each widget rotates through exactly the frames it has', () {
    final count = frames(android);
    expect(
      constant('android/app/src/main/kotlin/com/ayahreel/app/VerseWidget.kt',
          RegExp(r'private const val BACKGROUNDS = (\d+)')),
      count,
      reason: 'VerseWidget.kt counts a different number of frames; $rerun',
    );
    expect(
      constant('ios/AyahWidget/AyahWidget.swift',
          RegExp(r'private let backgroundCount = (\d+)')),
      count,
      reason: 'AyahWidget.swift counts a different number of frames; $rerun',
    );
  });
}
