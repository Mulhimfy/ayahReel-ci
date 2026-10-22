import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'card_deck.dart';
import 'card_style.dart';
import 'debug_log.dart';
import 'scene_catalog.dart';

/// Resolves a card's background to one decoded picture.
///
/// A card is a still, so whatever is behind it — a bundled scenery, a
/// scenery downloaded from the catalog, a clip, a photograph out of
/// the user's gallery — has to become one [ui.Image] before it can be
/// drawn. This is the one place that happens, and it happens once per
/// background: the composer draws the same decoded picture the
/// exporter rasterizes, so what is saved is the picture that was on
/// screen, down to the pixel.
///
/// ## Why the pictures are not disposed
///
/// A decoded 1080x1920 scenery is about 8 MB, and up to four are kept.
/// They are dropped from the map rather than disposed because a card
/// that is still on screen — a filmstrip thumbnail, a preview mid-
/// export — may still be holding one, and drawing a disposed image is
/// a crash where holding a few extra megabytes until the collector
/// runs is not. Four is a ceiling of about 33 MB, reached only by
/// someone trying four sceneries in a row.
abstract final class CardImages {
  /// Decoded pictures, newest last. Keyed by [keyOf].
  static final Map<String, ui.Image> _cache = {};
  static const _maxCached = 4;

  /// Decodes in flight, so two widgets asking for the same background
  /// in the same frame share one decode.
  static final Map<String, Future<ui.Image?>> _inFlight = {};

  /// Everything a background is decoded from, in one string.
  static String keyOf(CardBackground bg) =>
      bg.filePath.isNotEmpty ? 'file:${bg.filePath}' : 'scene:${bg.sceneId}';

  /// The picture for [bg] if it is already decoded — what a widget
  /// should ask first, so a rebuild never flashes.
  static ui.Image? peek(CardBackground bg) =>
      bg.hasPicture ? _cache[keyOf(bg)] : null;

  /// The picture for [bg], decoding it — and, for a scenery that is
  /// still on the server, downloading it — if need be. Null when there
  /// is no picture, or when it could not be had: the card then stands
  /// on its paper, which is what it was standing on anyway.
  static Future<ui.Image?> resolve(
    CardBackground bg, {
    void Function(double)? onProgress,
  }) {
    if (!bg.hasPicture) return Future.value();
    final key = keyOf(bg);
    final have = _cache[key];
    if (have != null) return Future.value(have);
    return _inFlight[key] ??= _resolve(bg, onProgress).whenComplete(() {
      // A block body: `whenComplete` awaits what its callback returns
      // and `Map.remove` hands back this very future, so an arrow body
      // here would make every decode wait on itself.
      _inFlight.remove(key);
    });
  }

  static Future<ui.Image?> _resolve(
      CardBackground bg, void Function(double)? onProgress) async {
    try {
      final bytes = await _bytes(bg, onProgress);
      if (bytes == null) return null;
      final image = await decode(bytes);
      _cache[keyOf(bg)] = image;
      while (_cache.length > _maxCached) {
        _cache.remove(_cache.keys.first);
      }
      return image;
    } catch (e, s) {
      rlogError('card background ${keyOf(bg)}', e, s);
      return null;
    }
  }

  /// Decodes [bytes] at card resolution. Every card is 1080 across, so
  /// nothing is ever decoded larger than that — a 12 megapixel phone
  /// photo would otherwise be 48 MB of memory to draw a card with.
  @visibleForTesting
  static Future<ui.Image> decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    // Upright sceneries are 1080 wide already; a wide one is 1920, and
    // scaling it to 1080 wide would leave it 608 tall — shorter than a
    // square card. Scale by the shorter side instead, so whatever the
    // shape, the card has at least 1080 pixels to crop out of it.
    final scale = CardFormat.exportWidth /
        (descriptor.width < descriptor.height
            ? descriptor.width
            : descriptor.height);
    final codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
      targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
    );
    final frame = await codec.getNextFrame();
    buffer.dispose();
    descriptor.dispose();
    codec.dispose();
    return frame.image;
  }

  static Future<Uint8List?> _bytes(
      CardBackground bg, void Function(double)? onProgress) async {
    if (bg.filePath.isNotEmpty) {
      final f = File(bg.filePath);
      return f.existsSync() ? await f.readAsBytes() : null;
    }
    // The catalog is a lazy singleton and the reel flow is what warms
    // it; a card never passes through there. Without this a cold launch
    // straight into Cards resolves every scenery to null and the card
    // is exported on bare paper with nothing on screen saying so —
    // `hasPicture` is true, so the composer does not even offer the
    // scenery note. Loading is a no-op once it has run.
    await SceneCatalog.load();
    final scene = SceneCatalog.byId(bg.sceneId);
    if (scene == null) return null;
    if (scene.isVideo) {
      final still = await _still(scene, onProgress);
      return still == null ? null : await still.readAsBytes();
    }
    if (scene.bundled) {
      return (await rootBundle.load(scene.bundledAsset)).buffer.asUint8List();
    }
    final file = await SceneCatalog.download(scene, onProgress: onProgress);
    return file == null ? null : await file.readAsBytes();
  }

  /// A still out of a clip, kept beside the downloaded clip so it is
  /// pulled once ever.
  ///
  /// The scenery library is half moving pictures, and a card cannot
  /// use one — but it can use a frame of one, and the app already
  /// carries the encoder that can cut it out. Half a second in, which
  /// is past whatever fade the clip opens on.
  static Future<File?> _still(
      Scene scene, void Function(double)? onProgress) async {
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/card_stills');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final out = File('${dir.path}/${scene.id}.jpg');
    if (out.existsSync() && out.lengthSync() > 0) return out;

    String source;
    if (scene.bundled) {
      // FFmpeg reads files, and a bundled clip is inside the app
      // package rather than on the filesystem, so it is copied out
      // once — to the same directory, under its own name.
      final copy = File('${dir.path}/${scene.fileName}');
      if (!copy.existsSync() || copy.lengthSync() == 0) {
        final data = await rootBundle.load(scene.bundledAsset);
        await copy.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      source = copy.path;
    } else {
      final file = await SceneCatalog.download(scene, onProgress: onProgress);
      if (file == null) return null;
      source = file.path;
    }
    try {
      // -ss before -i seeks by keyframe without decoding the run-up.
      final session = await FFmpegKit.execute(
          '-ss 0.5 -i "$source" -frames:v 1 -q:v 2 -y "${out.path}"');
      if (ReturnCode.isSuccess(await session.getReturnCode()) &&
          out.existsSync() &&
          out.lengthSync() > 0) {
        return out;
      }
      rlog('card still: extract failed for ${scene.id}');
    } catch (e) {
      rlog('card still: extract threw $e');
    }
    if (out.existsSync()) {
      try {
        out.deleteSync();
      } catch (_) {/* the next visit retries */}
    }
    return null;
  }

  /// How much room the stills cut out of clips are taking, for the
  /// storage sheet.
  static Future<int> cacheBytes() async {
    try {
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/card_stills');
      if (!dir.existsSync()) return 0;
      return dir
          .listSync()
          .whereType<File>()
          .fold<int>(0, (a, f) => a + f.lengthSync());
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearCache() async {
    _cache.clear();
    try {
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/card_stills');
      if (!dir.existsSync()) return;
      for (final f in dir.listSync().whereType<File>()) {
        f.deleteSync();
      }
    } catch (_) {/* the sheet re-measures either way */}
  }

  @visibleForTesting
  static void seedForTest(String key, ui.Image image) => _cache[key] = image;
}
