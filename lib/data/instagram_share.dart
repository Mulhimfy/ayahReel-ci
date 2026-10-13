import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'debug_log.dart';

/// Hands a finished reel straight into Instagram's Reels composer — the
/// camera/edit screen a reel is actually made in, not Stories and not
/// the OS share sheet — and, separately, hands a picture straight into
/// its Stories composer as the story's background ([shareStory]).
///
/// The reel half is Meta's "Sharing to Reels" handoff, which is a
/// different contract on each platform:
///
///   Android — the mp4 goes over as a FileProvider uri (the same
///             provider [WhatsAppShare] uses), handed to Instagram's
///             own share handler so it opens the reel composer rather
///             than the OS share sheet. Meta's dedicated
///             `com.instagram.share.ADD_TO_REEL` action is used ahead
///             of it *only* when the build carries a [metaAppId]:
///             Instagram refuses that action from an app it cannot
///             name and says so in its own dialog ("doesn't support
///             sharing to Instagram at this time"), which from here is
///             indistinguishable from success.
///   iOS     — the video *bytes* go on the general pasteboard under
///             `com.instagram.sharedSticker.backgroundVideo`, then the
///             app opens `instagram-reels://share`. Instagram reads the
///             pasteboard on launch; the items expire after 5 minutes.
///
/// A Meta App ID rides along when the build has one (see [metaAppId]),
/// but neither half needs it to work. Anything that does stop the
/// hand-off — Instagram not installed, a build too old to know the
/// action, a platform error — returns false and the caller falls back
/// to the share sheet. Never throws.
abstract final class InstagramShare {
  static const _channel = MethodChannel('ayahreel/instagram');

  /// A Meta App ID, when there is one. Optional on purpose.
  ///
  /// Meta's docs ask for one, and it is what earns the "shared from
  /// AyahReel" attribution line on the finished reel — and what Meta's
  /// ADD_TO_REEL hand-off checks for before it will open anything.
  /// On Android the button still lands in Instagram's composer without
  /// one; on iOS Instagram refuses outright ("doesn't support sharing
  /// to Instagram at this time"). The default is the Meta app
  /// "aahreel" (developers.facebook.com), in development mode, which
  /// is all the hand-off needs. Override for a different app:
  ///
  ///   flutter build appbundle --dart-define=META_APP_ID=1234567890
  static const metaAppId =
      String.fromEnvironment('META_APP_ID', defaultValue: '989696730806980');

  /// Whether the hand-off is worth offering. Both platforms have a
  /// route; whether Instagram is actually installed is answered by
  /// [shareReel], which falls back to the share sheet when it isn't.
  static bool get supported =>
      debugSupported ?? (Platform.isAndroid || Platform.isIOS);

  /// Stands in for the platform check under test.
  ///
  /// [supported] reads `dart:io`, which a widget test cannot move, so
  /// without this seam the story button is off screen in every test
  /// there is — and it shares the composer's top bar with the gold
  /// Share, which is the one place that bar runs out of room.
  @visibleForTesting
  static bool? debugSupported;

  /// Opens Instagram on the Reels composer with [video] loaded.
  ///
  /// Returns false — without having shown the user anything — when the
  /// hand-off could not be made, which is the caller's cue to open the
  /// normal share sheet instead. [supported] decides whether the button
  /// exists; this decides whether the tap landed, and a platform with
  /// no channel at all answers the same "no" as a phone without
  /// Instagram.
  static Future<bool> shareReel(File video) async {
    try {
      final staged = await _stage(video);
      final ok = await _channel.invokeMethod<bool>('shareReel', {
        'path': staged.path,
        'appId': metaAppId,
      });
      rlog('ig share: ${ok == true ? "handed to Instagram" : "unavailable"}');
      return ok ?? false;
    } catch (e) {
      rlog('ig share: failed $e');
      return false;
    }
  }

  /// Opens Instagram on the Stories composer with [image] laid over the
  /// whole story as its background.
  ///
  /// Meta's "Sharing to Stories" handoff, the same shape as the reel
  /// one: on Android the PNG goes over as a FileProvider uri under the
  /// `com.instagram.share.ADD_TO_STORY` action; on iOS the bytes go on
  /// the pasteboard under `com.instagram.sharedSticker.backgroundImage`
  /// and the app opens `instagram-stories://share`. Same answers as
  /// [shareReel]: true means Instagram has it, false means open the
  /// share sheet instead. Never throws.
  static Future<bool> shareStory(File image) async {
    try {
      final staged = await _stage(image);
      final ok = await _channel.invokeMethod<bool>('shareStory', {
        'path': staged.path,
        'appId': metaAppId,
      });
      rlog('ig story: ${ok == true ? "handed to Instagram" : "unavailable"}');
      return ok ?? false;
    } catch (e) {
      rlog('ig story: failed $e');
      return false;
    }
  }

  /// Opens Instagram on the Stories composer with a finished reel as
  /// the story — the other half of the reel screen's "To Instagram",
  /// beside [shareReel].
  ///
  /// The same contract as [shareStory] with a video: on Android the
  /// mp4 goes to Instagram's own Stories share target (which takes a
  /// reel of any length and cuts it into story parts), then to Meta's
  /// `ADD_TO_STORY`; on iOS its bytes go on the pasteboard under
  /// `com.instagram.sharedSticker.backgroundVideo`. A build whose
  /// native side predates this answers "not implemented", which lands
  /// here as false, so the caller opens the share sheet. Never throws.
  static Future<bool> shareStoryVideo(File video) async {
    try {
      final staged = await _stage(video);
      final ok = await _channel.invokeMethod<bool>('shareStoryVideo', {
        'path': staged.path,
        'appId': metaAppId,
      });
      rlog('ig story video: ${ok == true ? "handed to Instagram" : "unavailable"}');
      return ok ?? false;
    } catch (e) {
      rlog('ig story video: failed $e');
      return false;
    }
  }

  /// Android's FileProvider exposes only the cache dir (where renders
  /// already live), so library copies — which sit in documents — are
  /// staged into it first. Same file staged twice reuses the copy.
  ///
  /// iOS reads the bytes itself and needs no provider, but staging
  /// there too keeps one code path and costs a copy of a file the
  /// pasteboard is about to hold in memory anyway.
  static Future<File> _stage(File video) async {
    final tmp = await getTemporaryDirectory();
    if (video.path.startsWith(tmp.path)) return video;
    final dest = File('${tmp.path}/ig_${video.uri.pathSegments.last}');
    if (dest.existsSync() && dest.lengthSync() == video.lengthSync()) {
      return dest;
    }
    return video.copy(dest.path);
  }
}
