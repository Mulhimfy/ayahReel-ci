import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'hashtag_sets.dart';

/// Where a finished reel can be sent straight from the reel screen.
enum ShareTarget { instagramReel, instagramStory, tiktok, youtube, whatsapp }

/// Hands a finished reel to TikTok or YouTube — their composer, with the
/// reel loaded — and writes the post's caption and hashtags for whichever
/// app it goes to.
///
/// The two apps take a video differently on each platform:
///
///   Android — the mp4 goes over as a FileProvider uri in an ACTION_SEND
///             pinned to the app's package, as a share sheet's row for it
///             would send it: TikTok opens its editor with the video, and
///             YouTube its upload screen, which makes a vertical reel of
///             three minutes or less a Short. Each package in turn
///             (TikTok's global app, its Asian one, TikTok Lite); false
///             when none takes it, and the caller opens the share sheet.
///   iOS     — neither app takes a video from another app without its own
///             SDK and a registered client key, so the reel is saved to
///             the photo library first (the caller does that) and the app
///             is opened by its URL scheme; the reel is the newest video
///             in its picker. false when the app isn't installed.
///
/// Neither app reads a caption from another app reliably, so the caption
/// and the hashtags go on the clipboard before the hand-off ([caption]),
/// and the screen says so: one paste in the app's caption box.
abstract final class PlatformShare {
  static const _channel = MethodChannel('ayahreel/apps');

  static const tiktokPackages = [
    'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill',
    'com.zhiliaoapp.musically.go',
  ];
  static const youtubePackages = ['com.google.android.youtube'];

  /// TikTok's own schemes, newest first, then the generic one.
  static const tiktokSchemes = ['snssdk1233://', 'tiktok://', 'snssdk1180://'];
  static const youtubeSchemes = ['youtube://'];

  /// Stands in for the platform under test.
  @visibleForTesting
  static bool? debugIOS;

  static bool get _ios => debugIOS ?? Platform.isIOS;

  /// What goes on the clipboard for [target]: the reel's line and the
  /// platform's own block of tags, the surah's tag added when there is
  /// one. YouTube's ends on #Shorts, which is what files a reel there as
  /// a Short whatever its title says.
  static String caption(ShareTarget target,
      {required String line, String? surahName}) {
    final platform = switch (target) {
      ShareTarget.tiktok => TagPlatform.tiktok,
      ShareTarget.youtube => TagPlatform.youtube,
      _ => TagPlatform.instagram,
    };
    final sets = hashtagSets(platform, surahName: surahName);
    final tags = <String>[
      if (sets.isNotEmpty) sets.first.text,
      if (surahTag(surahName) case final s?) '#Surah$s',
      if (target == ShareTarget.youtube) '#Shorts',
    ];
    return [line, if (tags.isNotEmpty) tags.join(' ')].join('\n\n');
  }

  /// Sends [video] into TikTok's or YouTube's composer on Android, or
  /// opens the app on iOS (where the reel has been saved to the library
  /// first). False when the app isn't there to take it. Never throws.
  static Future<bool> send(ShareTarget target, File video,
      {String text = '', String title = ''}) async {
    final (packages, schemes) = switch (target) {
      ShareTarget.tiktok => (tiktokPackages, tiktokSchemes),
      ShareTarget.youtube => (youtubePackages, youtubeSchemes),
      _ => (const <String>[], const <String>[]),
    };
    if (packages.isEmpty) return false;
    try {
      if (_ios) {
        final ok =
            await _channel.invokeMethod<bool>('open', {'urls': schemes});
        rlog('share ${target.name}: ${ok == true ? 'opened' : 'not installed'}');
        return ok ?? false;
      }
      final staged = await _stage(video);
      final ok = await _channel.invokeMethod<bool>('shareVideo', {
        'path': staged.path,
        'packages': packages,
        'text': text,
        'title': title,
      });
      rlog('share ${target.name}: ${ok == true ? 'handed over' : 'unavailable'}');
      return ok ?? false;
    } catch (e) {
      rlog('share ${target.name}: failed $e');
      return false;
    }
  }

  /// The caption and tags on the clipboard, for a paste in the app.
  static Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// Android's FileProvider exposes only the cache dir, so a reel kept
  /// in documents is staged into it first; the same reel staged twice
  /// reuses its copy.
  static Future<File> _stage(File video) async {
    final tmp = await getTemporaryDirectory();
    if (video.path.startsWith(tmp.path)) return video;
    final dest = File('${tmp.path}/share_${video.uri.pathSegments.last}');
    if (dest.existsSync() && dest.lengthSync() == video.lengthSync()) {
      return dest;
    }
    return video.copy(dest.path);
  }
}
