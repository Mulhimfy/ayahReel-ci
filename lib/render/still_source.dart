import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../data/debug_log.dart';

/// A photo from the phone, made into one FFmpeg can open.
///
/// The encode reads a still with `-loop 1`, an option of FFmpeg's
/// image-file reader alone, and that reader takes a file by its
/// extension. A JPEG named `.jpg` or a PNG named `.png` goes straight
/// through. Anything else is identified by its content and handed to
/// whichever reader claims it, and none of those has a `-loop`.
///
/// Samsung's cameras can save HEIC, and the picker passes the file on
/// as it is. HEIC is an MP4-family container, so FFmpeg hands it to its
/// movie reader, which can't decode it either: a save over such a photo
/// failed with "[mov,mp4,…] … is not implemented. Update your FFmpeg
/// version … Option loop not found." (a Galaxy S24 Ultra, 67 reels in,
/// 2026-10-06). The preview showed the photo all along, because
/// Flutter decodes through Android's own decoder, which knows HEIC,
/// AVIF, WebP and the rest. So the same decoder makes a PNG for the
/// encode, once per photo.
abstract final class StillSource {
  /// The frame the encode fills. A copy only needs to cover it.
  static const _coverW = 1080;
  static const _coverH = 1920;

  /// [src] if FFmpeg reads it as a picture already, else a PNG of it in
  /// [work]. Falls back to [src] if the photo can't be decoded here
  /// either, so the save fails exactly as it did before rather than
  /// differently.
  static Future<File> readable(File src, Directory work) async {
    try {
      if (!src.existsSync() || await ffmpegReads(src)) return src;
      final stat = src.statSync();
      final out = File('${work.path}/ayah_still_'
          '${src.path.hashCode.toRadixString(16)}_${stat.size}_'
          '${stat.modified.millisecondsSinceEpoch}.png');
      if (out.existsSync() && out.lengthSync() > 0) {
        try {
          out.setLastModifiedSync(DateTime.now());
        } catch (_) {}
        return out;
      }
      final png = await _decodeToPng(await src.readAsBytes());
      // Under a name of its own and renamed into place whole, like the
      // flattened backdrops: a render reading the shared name never
      // sees half of it.
      final part = File('${out.path.substring(0, out.path.length - 4)}'
          '.part${DateTime.now().microsecondsSinceEpoch}.png');
      await part.writeAsBytes(png, flush: true);
      part.renameSync(out.path);
      rlog('still: ${src.uri.pathSegments.last} -> PNG for the encode '
          '(${(png.length / 1024).round()} KB)');
      return out;
    } catch (e, s) {
      rlogError('still: could not convert ${src.uri.pathSegments.last}', e, s);
      return src;
    }
  }

  /// Whether FFmpeg's image-file reader takes [f] as it is: a JPEG or
  /// a PNG, under the extension that says so. The first bytes are
  /// read too, since a name can claim a format the file isn't.
  @visibleForTesting
  static Future<bool> ffmpegReads(File f) async {
    final name = f.path.toLowerCase();
    final head = await _head(f, 8);
    final jpeg = head.length >= 3 &&
        head[0] == 0xFF &&
        head[1] == 0xD8 &&
        head[2] == 0xFF;
    final png = head.length >= 8 &&
        head[0] == 0x89 &&
        head[1] == 0x50 &&
        head[2] == 0x4E &&
        head[3] == 0x47;
    return (jpeg && (name.endsWith('.jpg') || name.endsWith('.jpeg'))) ||
        (png && name.endsWith('.png'));
  }

  static Future<Uint8List> _head(File f, int n) async {
    final r = await f.open();
    try {
      return await r.read(n);
    } finally {
      await r.close();
    }
  }

  /// Decodes [bytes] at no more than the size that covers the frame,
  /// so a 200-megapixel photo isn't held whole to make a 1080x1920
  /// reel, and encodes it as PNG.
  static Future<Uint8List> _decodeToPng(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    final sx = _coverW / w;
    final sy = _coverH / h;
    final scale = sx > sy ? sx : sy;
    final codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1 ? (w * scale).ceil() : null,
      targetHeight: scale < 1 ? (h * scale).ceil() : null,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('no PNG from the decoder');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }
}
