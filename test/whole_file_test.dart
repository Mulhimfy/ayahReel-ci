import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/whole_file.dart';

/// The small JSON stores — settings, the quiz history, the reel
/// library — write through [writeWhole]. Two plain writes at once used
/// to leave the shorter text with the tail of the longer after it, and
/// the next launch read that as nothing saved: onboarding again, an
/// empty history, a library with no reels.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('whole_file'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writes that overlap leave the last one, whole', () async {
    final f = File('${dir.path}/settings.json');
    final long = jsonEncode({'name': 'x' * 200000});
    final short = jsonEncode({'name': 'y'});
    await Future.wait([writeWhole(f, long), writeWhole(f, short)]);
    expect(f.readAsStringSync(), short);
    expect(jsonDecode(f.readAsStringSync()), {'name': 'y'});
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  test('a write that failed does not hold up the next', () async {
    final f = File('${dir.path}/later/settings.json');
    await expectLater(writeWhole(f, '{}'), throwsA(isA<FileSystemException>()));
    Directory('${dir.path}/later').createSync();
    await writeWhole(f, '{"a":1}');
    expect(f.readAsStringSync(), '{"a":1}');
  });
}
