import 'dart:io';

import 'package:ayah_reels/render/still_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Option loop not found" on every save over a Galaxy S24 Ultra photo
/// (2026-10-06): the camera's HEIC reached FFmpeg, whose `-loop` belongs
/// to the image-file reader alone, and that reader only takes a JPEG or
/// a PNG under its own extension. Everything else is converted first.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('still_source_test'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  // An ISO-BMFF `ftyp` box naming the HEIC brand, as Samsung writes it.
  const heic = [
    0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, //
    0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00,
  ];

  File put(String name, List<int> bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync([...bytes, 0, 0, 0, 0]);

  test('a JPEG or a PNG under its own extension goes straight through',
      () async {
    expect(await StillSource.ffmpegReads(put('a.jpg', jpeg)), isTrue);
    expect(await StillSource.ffmpegReads(put('b.JPEG', jpeg)), isTrue);
    expect(await StillSource.ffmpegReads(put('c.png', png)), isTrue);
  });

  test('a HEIC is converted, whatever it is called', () async {
    expect(await StillSource.ffmpegReads(put('d.heic', heic)), isFalse);
    expect(await StillSource.ffmpegReads(put('e.jpg', heic)), isFalse);
  });

  test('a picture under a name the image reader does not know is converted',
      () async {
    // Taken by its content, the file goes to a reader with no `-loop`.
    expect(await StillSource.ffmpegReads(put('f.jfif', jpeg)), isFalse);
    expect(await StillSource.ffmpegReads(put('g.png', jpeg)), isFalse);
  });

  test('a photo that is gone is handed back as it was', () async {
    final missing = File('${tmp.path}/gone.heic');
    expect((await StillSource.readable(missing, tmp)).path, missing.path);
  });
}
