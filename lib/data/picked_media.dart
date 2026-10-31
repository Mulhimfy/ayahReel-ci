import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';

/// A photo or video the user picked, which is no longer on the phone
/// when a reel is about to be made from it.
///
/// Thrown rather than rendered round: the renderer's stand-in for a
/// missing picked file is the near-black gradient a picked file shows
/// before it loads, and a reel made on it was a black video with a
/// verse on it ("why are some of my videos black", 2026-10-31).
class SceneryGone implements Exception {
  /// Whether the missing file was a photo (else a video).
  final bool isImage;

  const SceneryGone({required this.isImage});

  @override
  String toString() =>
      'SceneryGone: the picked ${isImage ? 'photo' : 'video'} is no longer '
      'on the phone';
}

/// Where the photos and videos picked for a reel are kept.
///
/// The gallery picker hands over a *copy* in the app's cache folder,
/// and Android empties that folder whenever storage runs low — on a
/// 3–4 GB phone that is during a session, even mid-save (see
/// EXPORT_MEMORY.md). The preview never noticed: a still already
/// decoded, and a video player holding the file open, keep showing a
/// file that has been deleted. The render opened the path afresh,
/// found nothing, and laid the verses over a black gradient instead.
///
/// So a pick is moved into the app's own support folder, which the
/// system never clears. A move, not a copy: both folders are on the
/// app's own volume, so it is a rename and costs neither time nor room.
abstract final class PickedMedia {
  /// Picks kept at most, newest first; older ones go once a new one
  /// arrives. A reel remade from My Reels whose pick has gone goes on
  /// without it, as it always has for a deleted photo.
  static const keepFiles = 16;

  /// And at most this much of them, so a few long videos don't hold a
  /// nearly full phone's last gigabyte. The newest pick is always kept,
  /// whatever its size.
  static const keepBytes = 600 * 1024 * 1024;

  /// Stands in for the support folder under test.
  @visibleForTesting
  static Directory? debugDir;

  static Future<Directory> _dir() async {
    final d = debugDir ??
        Directory('${(await getApplicationSupportDirectory()).path}/picked');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// [path], a file the picker just handed over, moved into the kept
  /// folder; returns where it is now. Never throws: a pick that can't
  /// be moved stays where the picker put it, as every pick did before.
  static Future<String> keep(String path) async {
    try {
      final src = File(path);
      if (!src.existsSync()) return path;
      final dir = await _dir();
      // Already ours (a pick restored from an earlier session).
      if (File(path).parent.absolute.path == dir.absolute.path) return path;
      final name = src.uri.pathSegments.last;
      final dest = File('${dir.path}/'
          '${DateTime.now().microsecondsSinceEpoch}_$name');
      try {
        src.renameSync(dest.path);
      } on FileSystemException {
        // Another volume after all: copied whole under a name of its
        // own, then renamed, so a copy cut short is never used.
        final part = File('${dest.path}.part');
        src.copySync(part.path);
        part.renameSync(dest.path);
        try {
          src.deleteSync();
        } catch (_) {/* the cache folder's to clear */}
      }
      _prune(dir, dest);
      rlog('picked: kept ${dest.uri.pathSegments.last} '
          '(${(dest.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB)');
      return dest.path;
    } catch (e) {
      rlog('picked: could not keep $path — $e');
      return path;
    }
  }

  /// Drops the oldest picks beyond [keepFiles] or [keepBytes]; never
  /// [newest], and never a half-made copy another pick is writing.
  static void _prune(Directory dir, File newest) {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.part'))
          .toList()
        ..sort((a, b) => _mtime(b).compareTo(_mtime(a)));
      var bytes = 0;
      var n = 0;
      for (final f in files) {
        final size = f.lengthSync();
        final isNewest = f.absolute.path == newest.absolute.path;
        if (isNewest || (n < keepFiles && bytes + size <= keepBytes)) {
          n++;
          bytes += size;
          continue;
        }
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      rlog('picked: prune stopped — $e');
    }
  }

  static DateTime _mtime(File f) {
    try {
      return f.lastModifiedSync();
    } catch (_) {
      return DateTime(0);
    }
  }
}
