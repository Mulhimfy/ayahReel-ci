import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';

import '../render/render_dir.dart';
import '../render/still_source.dart';
import 'debug_log.dart';
import 'models.dart';

/// The displayed width/height of a background's source media.
///
/// The letterbox card is shaped by this number, so preview and export
/// must agree on it exactly — a card one aspect in the preview and
/// another in the file is the whole feature going wrong. FFprobe is the
/// authority rather than the video player, because FFmpeg is what
/// actually renders the export.
///
/// Cached per source: probing costs a platform round trip and a picked
/// video's dimensions never change under us.
abstract final class MediaAspect {
  /// Every bundled scenery is authored 1080x1920.
  static const bundled = 1080 / 1920;

  /// What a source we cannot read is assumed to be. Landscape, because
  /// letterbox is a landscape format and a wrong guess should at least
  /// be a plausible one.
  static const fallback = 16 / 9;

  static final Map<String, double> _cache = {};

  static Future<double> of(ReelBackground background) async {
    // Catalog sceneries carry their shape with them — the library is
    // authored at exactly two sizes — so a downloaded wide scene never
    // has to be probed to know it is a letterbox.
    final known = background.knownAspect;
    if (known != null) return known;
    final path = background.filePath!;
    final hit = _cache[path];
    if (hit != null) return hit;
    // A photo FFmpeg can't open (a HEIC) is measured as the PNG the
    // encode will read in its place: ffprobe takes a HEIC for a movie
    // and reports one tile of it, or nothing.
    final a = await _probe(background.isImage ? await _readable(path) : path);
    return _cache[path] = a;
  }

  static Future<String> _readable(String path) async {
    try {
      return (await StillSource.readable(File(path), await renderDir())).path;
    } catch (_) {
      return path;
    }
  }

  /// The cached aspect if one has been resolved, else null. Lets the
  /// preview lay out on the first frame instead of after a probe.
  static double? cached(ReelBackground background) =>
      background.knownAspect ?? _cache[background.filePath!];

  static Future<double> _probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final streams = session.getMediaInformation()?.getStreams();
      if (streams == null) return fallback;
      for (final s in streams) {
        final w = s.getWidth();
        final h = s.getHeight();
        if (w == null || h == null || w <= 0 || h <= 0) continue;
        // FFmpeg auto-rotates on decode, so a phone video shot upright
        // arrives at the filter graph already turned: the coded
        // dimensions ffprobe reports are the wrong way round for it.
        final rotated = _quarterTurned(s.getAllProperties());
        final aspect = rotated ? h / w : w / h;
        rlog('aspect: $path -> ${w}x$h${rotated ? " (rotated)" : ""} '
            '= ${aspect.toStringAsFixed(3)}');
        return aspect;
      }
    } catch (e) {
      rlog('aspect: probe threw $e');
    }
    return fallback;
  }

  /// True when the stream carries a 90 or 270 degree display rotation,
  /// in either the modern side-data form or the legacy tag.
  static bool _quarterTurned(Map<dynamic, dynamic>? props) {
    if (props == null) return false;
    num? rotation;
    final side = props['side_data_list'];
    if (side is List) {
      for (final entry in side) {
        if (entry is Map && entry['rotation'] is num) {
          rotation = entry['rotation'] as num;
          break;
        }
      }
    }
    if (rotation == null) {
      final tags = props['tags'];
      if (tags is Map) {
        final raw = tags['rotate'];
        rotation = raw is num ? raw : num.tryParse('${raw ?? ''}');
      }
    }
    if (rotation == null) return false;
    final turns = (rotation.abs() / 90).round() % 2;
    return turns == 1;
  }
}

/// How long a background's source media runs, in milliseconds.
///
/// Only asked of a reel that runs through several sceneries, where a
/// clip shorter than the turn it was given would have to be frozen or
/// looped to fill it — which is exactly what such a reel must not do.
/// A single-background reel never asks: one scenery loops for the whole
/// recitation by design, and always has.
///
/// Cached per path like [MediaAspect], and for the same reason: the
/// probe is a platform round trip and a file's length never changes
/// under us.
abstract final class MediaDuration {
  static final Map<String, int> _cache = {};

  /// Milliseconds, or null when the source has no length to speak of —
  /// a still, a scenery from the app's own library, or a file ffprobe
  /// cannot read.
  ///
  /// "The app's own library" is the whole library, not just the part
  /// of it that ships inside the app. Every catalog scene is authored
  /// to loop seamlessly, which is exactly what makes looping one
  /// invisible; whether a given scene happened to be bundled or
  /// fetched on demand is an accident of install size and says nothing
  /// about the picture. Asking [isDeviceFile] instead of
  /// [ReelBackground.isUserFile] made it say something: a downloaded
  /// scene has a file path, so a fifteen-second catalog clip given a
  /// two-minute turn was reported as a clip too short to finish the
  /// reel — and the export was blocked over it — while the identical
  /// bundled scene next to it in the grid was fine.
  static Future<int?> of(ReelBackground background) async {
    if (background.isImage || !background.isUserFile) return null;
    final path = background.filePath!;
    final hit = _cache[path];
    if (hit != null) return hit;
    final ms = await _probe(path);
    if (ms == null) return null;
    return _cache[path] = ms;
  }

  /// Milliseconds of whatever file [path] points at, measured once and
  /// cached by path.
  ///
  /// [of] answers for a *scenery*, and deliberately says nothing about
  /// a bundled one: for choosing a background, a clip authored to loop
  /// has no length worth knowing. The exporter needs the number for a
  /// different question — where a long reel may be cut into passes
  /// without the loop jumping — and there every clip has a length,
  /// bundled or not.
  static Future<int?> ofPath(String path) async {
    final hit = _cache[path];
    if (hit != null) return hit;
    final ms = await _probe(path);
    if (ms == null) return null;
    return _cache[path] = ms;
  }

  /// The cached length if one has been resolved, else null.
  static int? cached(ReelBackground background) =>
      background.isImage || !background.isUserFile
          ? null
          : _cache[background.filePath!];

  static Future<int?> _probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final seconds = session.getMediaInformation()?.getDuration();
      final value = seconds == null ? null : double.tryParse(seconds);
      if (value == null || value <= 0) return null;
      final ms = (value * 1000).round();
      rlog('duration: $path -> ${ms}ms');
      return ms;
    } catch (e) {
      rlog('duration: probe threw $e');
      return null;
    }
  }
}
