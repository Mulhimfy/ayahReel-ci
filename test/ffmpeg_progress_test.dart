import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayah_reels/data/ffmpeg_progress.dart';

/// One `-progress` block as FFmpeg 6 writes it.
String _block(String us, {String state = 'continue'}) => 'frame=120\n'
    'fps=30.00\n'
    'bitrate=1200.1kbits/s\n'
    'total_size=600000\n'
    'out_time_us=$us\n'
    'out_time_ms=$us\n'
    'out_time=00:00:04.000000\n'
    'dup_frames=0\n'
    'drop_frames=0\n'
    'speed=1.2x\n'
    'progress=$state\n';

void main() {
  group('outTimeMs', () {
    test('reads the last block, in milliseconds', () {
      expect(outTimeMs(_block('1000000') + _block('4000000')), 4000);
    });

    test('is null before the first frame has a time', () {
      expect(outTimeMs(_block('N/A')), isNull);
      expect(outTimeMs(''), isNull);
    });

    test('takes out_time_ms alone, which is microseconds too', () {
      expect(outTimeMs('out_time_ms=2500000\nprogress=continue\n'), 2500);
    });

    test('reads a block cut off at the front, as a tail read leaves it',
        () {
      final text = _block('1000000') + _block('9000000', state: 'end');
      expect(outTimeMs(text.substring(text.length - 120)), 9000);
    });
  });

  group('FfmpegProgressFile', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('progress_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('sits beside the output and quotes its path for the command',
        () {
      final p = FfmpegProgressFile.beside(File('${dir.path}/a b.mp4'))!;
      expect(p.file.path, '${dir.path}/a b.mp4.progress');
      expect(p.arg, '-progress "${dir.path}/a b.mp4.progress" ');
    });

    test('reads the end of a long report, and null before it exists', () {
      final p = FfmpegProgressFile.beside(File('${dir.path}/out.mp4'))!;
      expect(p.readMs(), isNull);
      final b = StringBuffer();
      for (var s = 0; s < 600; s++) {
        b.write(_block('${s * 500000}'));
      }
      p.file.writeAsStringSync(b.toString());
      expect(p.file.lengthSync(), greaterThan(4096));
      expect(p.readMs(), 599 * 500);
      p.delete();
      expect(p.file.existsSync(), isFalse);
      p.delete(); // a second delete is harmless
    });

    test('a refusal turns progress files off for the process', () {
      final out = File('${dir.path}/out.mp4');
      expect(FfmpegProgressFile.refusedIn('Conversion failed!'), isFalse);
      expect(FfmpegProgressFile.beside(out), isNotNull);
      expect(
          FfmpegProgressFile.refusedIn('Failed to open progress URL '
              '"/x/out.mp4.progress": Permission denied'),
          isTrue);
      expect(FfmpegProgressFile.beside(out), isNull);
    });
  });
}
