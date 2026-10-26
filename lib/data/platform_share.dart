import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'hashtag_sets.dart';

/// Where a finished reel or card can be sent straight from its screen.
///
/// [instagramPost] is a card's way into Instagram's feed; a reel goes as
/// [instagramReel]. YouTube takes videos only, so a card never offers it.
enum ShareTarget {
  instagramReel,
  instagramPost,
  instagramStory,
  tiktok,
  youtube,
  facebook,
  whatsapp,
}

/// Hands a finished reel to TikTok, YouTube or Facebook — their
/// composer, with the reel loaded — or a finished card to Instagram,
/// TikTok, Facebook or WhatsApp, and writes the post's caption and
/// hashtags for whichever app it goes to.
///
/// The apps take a file differently on each platform:
///
///   Android — the file goes over as a FileProvider uri in an ACTION_SEND
///             pinned to the app's package, as a share sheet's row for it
///             would send it: TikTok opens its editor with the video, and
///             YouTube its upload screen, which makes a vertical reel of
///             three minutes or less a Short. Each package in turn
///             (TikTok's global app, its Asian one, TikTok Lite); false
///             when none takes it, and the caller opens the share sheet.
///   iOS     — none of them takes a file from another app without its own
///             SDK and a registered client key, so the reel or card is
///             saved to the photo library first (the caller does that)
///             and the app is opened by its URL scheme; the file is the
///             newest in its picker. false when the app isn't installed.
///
/// No app reads a caption from another app reliably, so the caption and
/// the hashtags go on the clipboard before the hand-off ([caption]), and
/// the screen says so: one paste in the app's caption box.
abstract final class PlatformShare {
  static const _channel = MethodChannel('ayahreel/apps');

  static const tiktokPackages = [
    'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill',
    'com.zhiliaoapp.musically.go',
  ];
  static const youtubePackages = ['com.google.android.youtube'];
  static const facebookPackages = ['com.facebook.katana', 'com.facebook.lite'];
  static const instagramPackages = ['com.instagram.android'];
  static const whatsappPackages = ['com.whatsapp', 'com.whatsapp.w4b'];

  /// TikTok's own schemes, newest first, then the generic one.
  static const tiktokSchemes = ['snssdk1233://', 'tiktok://', 'snssdk1180://'];
  static const youtubeSchemes = ['youtube://'];
  static const facebookSchemes = ['fb://'];
  static const instagramSchemes = ['instagram://app'];
  static const whatsappSchemes = ['whatsapp://'];

  /// Stands in for the platform under test.
  @visibleForTesting
  static bool? debugIOS;

  static bool get _ios => debugIOS ?? Platform.isIOS;

  /// Whose caption box [target] writes in: Instagram's rules (five tags)
  /// stand for Facebook's too.
  static TagPlatform tagPlatform(ShareTarget target) => switch (target) {
        ShareTarget.tiktok => TagPlatform.tiktok,
        ShareTarget.youtube => TagPlatform.youtube,
        _ => TagPlatform.instagram,
      };

  /// The tags [target]'s caption carries, each without its '#': the
  /// platform's leading block, the surah's tag in place of its last tag
  /// when there is one, and the mark in the middle — five in all, the
  /// most Instagram and TikTok keep. YouTube's are three or four, the
  /// mark again in the middle and #Shorts last, and WhatsApp's only the
  /// mark: a message to a person is no place for a wall of tags.
  static List<String> tags(ShareTarget target, {String? surahName}) {
    final surah = surahTag(surahName);
    if (target == ShareTarget.whatsapp) return const [HashtagSet.mark];
    if (target == ShareTarget.youtube) {
      return HashtagSet.withMark(
          [if (surah != null) 'Surah$surah', 'quran', 'Shorts']);
    }
    final base = hashtagSets(tagPlatform(target)).first.tags;
    final picked = [...base.take(HashtagSet.perBlock - 1)];
    if (surah != null && picked.isNotEmpty) picked.last = 'Surah$surah';
    return HashtagSet.withMark(picked);
  }

  /// What goes on the clipboard for [target]: the post's line and the
  /// platform's tags (see [tags]).
  ///
  /// YouTube's goes in a Short's title, which holds
  /// [HashtagSet.youtubeTitleMax] characters: one line, the line's first
  /// row cut at a word with an ellipsis where it has to be, and the tags
  /// after it — the surah's tag the first to go when even that is too
  /// long, the mark never. Counted in UTF-16 units, which is never fewer
  /// than the characters YouTube counts.
  static String caption(ShareTarget target,
      {required String line, String? surahName}) {
    if (target != ShareTarget.youtube) {
      final t = tags(target, surahName: surahName);
      return [line, t.map((x) => '#$x').join(' ')].join('\n\n');
    }
    const max = HashtagSet.youtubeTitleMax;
    final first = line.split('\n').first.trim();
    var t = tags(target, surahName: surahName).map((x) => '#$x').join(' ');
    if (first.length + 1 + t.length > max && surahName != null) {
      t = tags(target).map((x) => '#$x').join(' ');
    }
    final room = max - t.length - 1;
    if (room < 4) return t;
    return '${_cut(first, room)} $t';
  }

  /// [s] in [room] characters or fewer: whole when it fits, else up to
  /// the last word that fits and an ellipsis.
  static String _cut(String s, int room) {
    if (s.length <= room) return s;
    var cut = s.substring(0, room - 1);
    final space = cut.lastIndexOf(' ');
    if (space > room ~/ 2) cut = cut.substring(0, space);
    // Never half an emoji: a cut between its two halves leaves a
    // character no app can draw.
    final end = cut.isEmpty ? 0 : cut.codeUnitAt(cut.length - 1);
    if (end >= 0xD800 && end <= 0xDBFF) cut = cut.substring(0, cut.length - 1);
    return '${cut.trimRight()}…';
  }

  /// The packages an Android hand-off to [target] tries, in turn.
  static List<String> packagesFor(ShareTarget target) => switch (target) {
        ShareTarget.tiktok => tiktokPackages,
        ShareTarget.youtube => youtubePackages,
        ShareTarget.facebook => facebookPackages,
        ShareTarget.whatsapp => whatsappPackages,
        ShareTarget.instagramPost ||
        ShareTarget.instagramReel ||
        ShareTarget.instagramStory =>
          instagramPackages,
      };

  /// The schemes that open [target] on iOS, in turn.
  static List<String> schemesFor(ShareTarget target) => switch (target) {
        ShareTarget.tiktok => tiktokSchemes,
        ShareTarget.youtube => youtubeSchemes,
        ShareTarget.facebook => facebookSchemes,
        ShareTarget.whatsapp => whatsappSchemes,
        ShareTarget.instagramPost ||
        ShareTarget.instagramReel ||
        ShareTarget.instagramStory =>
          instagramSchemes,
      };

  /// Sends [images] (a card, or a carousel of them) into [target]'s
  /// composer on Android, or opens the app on iOS, where they have been
  /// saved to the library first. False when the app isn't there to take
  /// them. Never throws.
  static Future<bool> sendImages(ShareTarget target, List<File> images,
      {String text = ''}) async {
    if (images.isEmpty) return false;
    try {
      if (_ios) {
        final ok = await _channel
            .invokeMethod<bool>('open', {'urls': schemesFor(target)});
        rlog('share card ${target.name}: '
            '${ok == true ? 'opened' : 'not installed'}');
        return ok ?? false;
      }
      final staged = [for (final f in images) await _stage(f)];
      final ok = await _channel.invokeMethod<bool>('shareFiles', {
        'paths': [for (final f in staged) f.path],
        'mime': 'image/png',
        'packages': packagesFor(target),
        'text': text,
      });
      rlog('share card ${target.name}: '
          '${ok == true ? 'handed over' : 'unavailable'}');
      return ok ?? false;
    } catch (e) {
      rlog('share card ${target.name}: failed $e');
      return false;
    }
  }

  /// Sends [video] into TikTok's, YouTube's or Facebook's composer on
  /// Android, or opens the app on iOS (where the reel has been saved to
  /// the library first). False when the app isn't there to take it.
  /// Never throws.
  static Future<bool> send(ShareTarget target, File video,
      {String text = '', String title = ''}) async {
    final packages = switch (target) {
      ShareTarget.tiktok || ShareTarget.youtube || ShareTarget.facebook =>
        packagesFor(target),
      _ => const <String>[],
    };
    if (packages.isEmpty) return false;
    try {
      if (_ios) {
        final ok = await _channel
            .invokeMethod<bool>('open', {'urls': schemesFor(target)});
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

  /// Android's FileProvider exposes only the cache dir, so a file kept
  /// in documents is staged into it first; the same file staged twice
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
