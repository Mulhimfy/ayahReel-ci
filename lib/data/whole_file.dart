import 'dart:async';
import 'dart:io';

/// The writes still running or waiting, by path.
final _queue = <String, Future<void>>{};

/// Replaces [file] with [contents], whole or not at all, after every
/// earlier [writeWhole] to the same path has finished.
///
/// What the app's small JSON stores used to do instead was
/// `writeAsString` straight onto the file, and nothing kept two of those
/// apart: the second truncates while the first is still writing, both
/// write from byte 0, and the file ends with the shorter text followed
/// by the tail of the longer — JSON that no longer parses. Every store
/// reads that as "nothing saved yet", so the next launch opened on
/// defaults: onboarding again, an empty quiz history, a library with no
/// reels in it. A death mid-write did the same with one writer.
///
/// So each write goes to a temporary file beside the real one and is
/// renamed over it, which the file system does in one step, and writes
/// to one path wait their turn. The last one asked for is the one left
/// on disk.
Future<void> writeWhole(File file, String contents) =>
    _inTurn(file, (tmp) => tmp.writeAsString(contents, flush: true));

/// [writeWhole] for bytes: a picture a render reuses whenever it finds
/// one, so a half-written one (a full phone, the app killed) was reused
/// for good.
Future<void> writeWholeBytes(File file, List<int> bytes) =>
    _inTurn(file, (tmp) => tmp.writeAsBytes(bytes, flush: true));

/// Copies [source] to [file] the same way: a copy cut short (a phone
/// out of room, the app killed) leaves no half file under the final
/// name, holding exactly the room that was missing, for good.
Future<void> copyWhole(File source, File file) =>
    _inTurn(file, (tmp) => source.copy(tmp.path));

Future<void> _inTurn(File file, Future<void> Function(File tmp) write) {
  final path = file.path;
  final run = (_queue[path] ?? Future<void>.value())
      .then((_) => _replace(file, write));
  // The next write waits on this one however it ended: a write that
  // failed must not stop the ones after it.
  final settled = run.then((_) {}, onError: (_) {});
  _queue[path] = settled;
  unawaited(settled.then((_) {
    if (identical(_queue[path], settled)) _queue.remove(path);
  }));
  return run;
}

Future<void> _replace(File file, Future<void> Function(File tmp) write) async {
  final tmp = File('${file.path}.tmp');
  try {
    await write(tmp);
    await tmp.rename(file.path);
  } catch (_) {
    // Nothing half-written left behind to take room or be mistaken for
    // the real thing.
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    rethrow;
  }
}
