import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../data/debug_log.dart';
import '../data/reel_library.dart';

/// Grabs the still that a saved reel shows on its card in My Reels.
///
/// A grid of identical gradients with a play triangle is unreadable
/// once there are more than a couple of reels, so each card gets a
/// frame from its own video. The frame is written next to the mp4 and
/// kept, so this costs one cheap FFmpeg call per reel, ever.
abstract final class ReelPoster {
  /// Card width in the 2-column grid is ~160dp; 320px covers 2x and
  /// keeps each poster well under 30 KB.
  static const _width = 320;

  /// Half a second in: frame 0 of a reel is the background alone,
  /// before the first verse has faded up, which makes every card of a
  /// given background look the same.
  static const _seekSeconds = '0.5';

  /// Posters being extracted right now, keyed by output path. A grid
  /// builds all its visible cards at once and each would otherwise
  /// launch its own FFmpeg session over the same file.
  static final Map<String, Future<File?>> _inFlight = {};

  /// Stands in for the extraction under test, where there is no encoder
  /// and no documents directory to write one into.
  @visibleForTesting
  static Future<File?> Function(SavedReel)? testResolver;

  /// The poster for [reel], extracting it if this is the first time.
  /// Returns null when there is no video to read or FFmpeg fails —
  /// callers fall back to the stored background gradient.
  static Future<File?> ensure(SavedReel reel) async {
    final override = testResolver;
    if (override != null) return override(reel);
    final poster = await ReelLibrary.posterFile(reel);
    if (poster.existsSync() && poster.lengthSync() > 0) return poster;
    return _inFlight[poster.path] ??= _extract(reel, poster).whenComplete(() {
      // A block body, and it has to stay one: `whenComplete` awaits
      // whatever its callback returns, and `Map.remove` hands back the
      // value it removed — this very future. As an arrow it waits on
      // itself, and the first extraction of a poster never completes,
      // so a brand new reel keeps showing its bare gradient until some
      // later visit finds the jpg already on disk.
      _inFlight.remove(poster.path);
    });
  }

  static Future<File?> _extract(SavedReel reel, File poster) async {
    final video = await ReelLibrary.videoFile(reel);
    if (!video.existsSync()) return null;
    try {
      // -ss before -i seeks by keyframe without decoding the run-up,
      // so this stays a few milliseconds however long the reel is.
      final session = await FFmpegKit.execute(
        '-ss $_seekSeconds -i "${video.path}" -frames:v 1 '
        '-vf scale=$_width:-2 -q:v 4 -y "${poster.path}"',
      );
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          poster.existsSync() &&
          poster.lengthSync() > 0) {
        return poster;
      }
      rlog('poster: extract failed for ${reel.fileName}');
    } catch (e) {
      rlog('poster: extract threw $e');
    }
    // A half-written jpg would be served forever after; drop it so the
    // next visit retries.
    if (poster.existsSync()) {
      try {
        poster.deleteSync();
      } catch (_) {}
    }
    return null;
  }
}
