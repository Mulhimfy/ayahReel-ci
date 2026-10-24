import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'debug_log.dart';

/// Hands a finished reel straight to WhatsApp — no share sheet.
///
/// Android only, via a tiny platform channel (an ACTION_SEND intent
/// pinned to WhatsApp's package). Everywhere it can't work — iOS,
/// WhatsApp not installed, any platform hiccup — it returns false and
/// the caller falls back to the normal share sheet. Never throws.
abstract final class WhatsAppShare {
  static const _channel = MethodChannel('ayahreel/whatsapp');

  static Future<bool> shareVideo(File video, {String text = ''}) async {
    if (!Platform.isAndroid) return false;
    try {
      final staged = await _stage(video);
      final ok = await _channel.invokeMethod<bool>('shareVideo', {
        'path': staged.path,
        'text': text,
      });
      rlog('wa share: ${ok == true ? "handed to WhatsApp" : "unavailable"}');
      return ok ?? false;
    } catch (e) {
      rlog('wa share: failed $e');
      return false;
    }
  }

  /// Our FileProvider exposes only the cache dir (where renders already
  /// live). Library copies live in documents — stage those into cache
  /// first. Same file staged twice reuses the copy.
  static Future<File> _stage(File video) async {
    final tmp = await getTemporaryDirectory();
    if (video.path.startsWith(tmp.path)) return video;
    final dest = File('${tmp.path}/wa_${video.uri.pathSegments.last}');
    if (dest.existsSync() && dest.lengthSync() == video.lengthSync()) {
      return dest;
    }
    return video.copy(dest.path);
  }
}
