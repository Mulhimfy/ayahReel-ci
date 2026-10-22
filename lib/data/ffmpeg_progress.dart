import 'dart:io';

/// How far a long encode has got, read off a file rather than sent
/// across the main thread.
///
/// FFmpegKit's own progress report is a statistics event, and its
/// Android plugin posts every one of them to the main thread and
/// encodes it there for Flutter, as fast as FFmpeg makes them. On a
/// slow phone a save queued them faster than the main thread could
/// drain them: Play's ANR traces (1.0.7, build 17) have the main thread
/// inside that encode and FFmpeg's callback thread posting the next.
/// So [configureFfmpeg] turns those events off, and an encode that
/// wants a progress bar writes FFmpeg's `-progress` report to a file
/// instead: a dozen short lines twice a second, whose end the loop that
/// already waits on the session reads.
final class FfmpegProgressFile {
  FfmpegProgressFile._(this.file);

  final File file;

  /// False once FFmpeg has refused a progress file, for the rest of the
  /// process: every encode after that runs without one, and its bar
  /// waits at the start until the encode is done.
  static bool _usable = true;

  /// A progress file for an encode writing to [output], or null if
  /// FFmpeg has already refused one.
  static FfmpegProgressFile? beside(File output) =>
      _usable ? FfmpegProgressFile._(File('${output.path}.progress')) : null;

  /// Whether [logs], from a session that failed, say FFmpeg could not
  /// open its progress file — which fails the whole command before it
  /// encodes a frame. Turns progress files off when they do, so the
  /// caller's one retry runs without.
  ///
  /// Except when the phone was only full at the time: room comes back,
  /// and an encode without a progress file is one the stall watchdog
  /// can't see, so the next one gets its file again.
  static bool refusedIn(String logs) {
    final l = logs.toLowerCase();
    if (!l.contains('progress url')) return false;
    if (!l.contains('no space left')) _usable = false;
    return true;
  }

  /// Goes at the front of the command: `-progress` is a global option.
  String get arg => '-progress "${file.path}" ';

  /// Milliseconds of output written so far, or null before the first
  /// report or when the file can't be read. Reads the last kilobyte
  /// only: the file grows for as long as the encode runs.
  int? readMs() {
    RandomAccessFile? raf;
    try {
      raf = file.openSync();
      final len = raf.lengthSync();
      raf.setPositionSync(len > 1024 ? len - 1024 : 0);
      return outTimeMs(String.fromCharCodes(raf.readSync(1024)));
    } catch (_) {
      return null;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  void delete() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

/// The last output time in an FFmpeg `-progress` report, in ms.
///
/// `out_time_us` is in microseconds, and so is `out_time_ms`, despite
/// its name: an old FFmpeg mistake, kept for compatibility, and the one
/// field an older build writes. Before the first frame both say "N/A".
int? outTimeMs(String report) {
  final m = RegExp(r'out_time_(?:us|ms)=(\d+)').allMatches(report);
  if (m.isEmpty) return null;
  final us = int.tryParse(m.last.group(1)!);
  return us == null ? null : us ~/ 1000;
}
