import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'trouble.dart';

/// How a gallery write ended. The distinction the user needs is
/// "your phone won't let me" (fixable in settings) versus "it broke"
/// (nothing they can do but retry) — a single thrown exception told
/// them neither.
enum GallerySaveStatus { saved, denied, failed }

class GallerySaveResult {
  final GallerySaveStatus status;

  /// The last platform error, for the log and the failure message.
  final Object? error;

  const GallerySaveResult(this.status, [this.error]);

  bool get ok => status == GallerySaveStatus.saved;

  /// The write failed because the phone is full. Neither a retry nor
  /// the settings screen changes that — only freeing space does, so it
  /// is the one failure worth a sentence of its own.
  bool get outOfSpace =>
      status == GallerySaveStatus.failed && saysOutOfSpace(error);
}

/// Writes a finished reel — or a finished card — into the device
/// gallery.
///
/// A plain `Gal.putVideo(path, album: …)` is one call with several
/// ways to fail on Android, and every one of them landed on the user
/// as "Export failed":
///
///  * The album write goes through legacy external storage on API 29
///    and below, a stricter path than a plain write — it can be
///    refused on its own, so a refusal falls back to the gallery root
///    rather than giving up.
///  * Gallery access can be denied outright, and a permission already
///    refused for good never prompts again — only the OS settings
///    screen can undo it, which is what [GallerySaveStatus.denied]
///    exists to say.
abstract final class GallerySaver {
  static const albumName = 'Ayah Reels';

  /// Which of the two puts a save goes through. The platform has a
  /// separate call per kind and only one of them takes a video, so
  /// this is not a detail the caller can be spared — everything after
  /// the call is identical, and that is the part worth sharing.
  static Future<Object?> _videoPut(String path, String? album) =>
      _guard(() => Gal.putVideo(path, album: album));
  static Future<Object?> _imagePut(String path, String? album) =>
      _guard(() => Gal.putImage(path, album: album));

  /// Saves [video], preferring the app's own album. [name] is what the
  /// user will see in their gallery; it is sanitized and may be
  /// dropped if nothing usable survives.
  static Future<GallerySaveResult> save(File video, {String? name}) =>
      _save(video, name: name, put: _videoPut, extension: 'mp4');

  /// The same, for a card. One path, one set of fallbacks, one place
  /// where a refused album write is told apart from a refused gallery
  /// — a second implementation of this is a second set of bugs, and
  /// this one was earned the hard way (see the class comment).
  ///
  /// A card is a few hundred KB, so the copy that gives it a readable
  /// name is never the one that is too big to make.
  static Future<GallerySaveResult> saveImage(File image, {String? name}) =>
      _save(image, name: name, put: _imagePut, extension: 'png');

  static Future<GallerySaveResult> _save(
    File media, {
    required String? name,
    required Future<Object?> Function(String, String?) put,
    required String extension,
  }) async {
    if (!media.existsSync() || media.lengthSync() == 0) {
      return const GallerySaveResult(
          GallerySaveStatus.failed, 'the rendered file is missing');
    }
    final standIn = await _standIn(media, name, extension);
    try {
      return await _put(standIn?.path ?? media.path, put);
    } finally {
      // The gallery has made its own copy by now, or failed to. Left
      // behind, the stand-in was a second whole reel in the cache for
      // every save, never deleted — on a phone short of room, enough of
      // them is what made every later save fail.
      if (standIn != null) _remove(standIn.path);
    }
  }

  static Future<GallerySaveResult> _put(
    String path,
    Future<Object?> Function(String, String?) put,
  ) async {
    // Exactly one native prompt, and it is gal's: every put asks for
    // access on the way in. Asking again around it — before the write,
    // or after it comes back refused — is what made the system dialog
    // appear twice in a row, which reads as a broken app rather than
    // as a question.
    //
    // So a refusal is final here. It cannot be re-asked anyway: a
    // permission denied for good never prompts again, on any app. The
    // caller answers it with our own dialog and a button into
    // settings, which is the only route left.
    final err = await put(path, albumName);
    if (err == null) return const GallerySaveResult(GallerySaveStatus.saved);
    rlogError('gallery album write', err);
    // A full phone refuses the gallery root exactly as it refused the
    // album, and a second attempt is only a second wait for the same
    // answer.
    if (saysOutOfSpace(err)) {
      return GallerySaveResult(GallerySaveStatus.failed, err);
    }
    // A refusal aimed at the album is not a refusal of the gallery:
    // saving to one needs more than saving to it plainly does, on both
    // platforms. So ask what access we hold — a question, never a
    // prompt — and give up only if there is none.
    if (_denied(err) && !await _hasAccess()) {
      return GallerySaveResult(GallerySaveStatus.denied, err);
    }

    // Retry without the album, with access already in hand, so no
    // second dialog can appear. An album write goes through legacy
    // external storage on API 29 and below, a stricter path than a
    // plain one, and can fail on its own. The reel lands in the
    // gallery root instead of its own folder, which is far better
    // than not landing at all.
    final flat = await put(path, null);
    if (flat == null) return const GallerySaveResult(GallerySaveStatus.saved);
    rlogError('gallery write', flat);
    return GallerySaveResult(
      _denied(flat) ? GallerySaveStatus.denied : GallerySaveStatus.failed,
      flat,
    );
  }

  /// What access we already hold. A check, not a request: it never
  /// puts a dialog on screen.
  static Future<bool> _hasAccess() async {
    try {
      return await Gal.hasAccess();
    } catch (e) {
      rlogError('gallery hasAccess', e);
      return false;
    }
  }

  static Future<Object?> _guard(Future<void> Function() put) async {
    try {
      await put();
      return null;
    } catch (e) {
      return e;
    }
  }

  static bool _denied(Object e) =>
      e is GalException && e.type == GalExceptionType.accessDenied;

  /// The gallery names the entry after the file it is handed, and a
  /// render is named for its styling key — `ayah_reel_v10_alafasy_…`.
  /// A stand-in under the reel's own name is what the user will
  /// recognize when they go looking for what they just saved. Null
  /// means the gallery is handed [media] itself.
  ///
  /// On Android the stand-in is a link: gal reads the file through a
  /// stream, which follows it, so the name costs no bytes at all. It
  /// used to be a copy — a whole second reel written for the sake of a
  /// name, on top of the render, the My Reels copy and the gallery's
  /// own — and on a phone short of room that copy is what tipped every
  /// save into failing at the very end. iOS hands Photos a file URL,
  /// and nothing here can check that Photos follows a link, so it
  /// keeps the copy; either way the stand-in is gone once the gallery
  /// has the reel.
  ///
  /// Best effort in every direction: any failure hands back null,
  /// because an ugly name beats no save. And past [_copyForNameMax] a
  /// copy is not made at all: the gallery makes its own on the way in,
  /// and a long reel would be written three times over for its name.
  static const _copyForNameMax = 512 * 1024 * 1024;

  /// Forces the link (true) or the copy (false) where the platform
  /// would pick the other, so a test on any host can take either path.
  @visibleForTesting
  static bool? linkForTest;

  static Future<FileSystemEntity?> _standIn(
      File media, String? name, String extension) async {
    final clean = _sanitize(name);
    if (clean == null) return null;
    final String path;
    try {
      path = '${(await getTemporaryDirectory()).path}/$clean.$extension';
    } catch (e) {
      rlog('gallery: no folder for a named stand-in: $e');
      return null;
    }
    if (path == media.path) return null;
    // Whatever holds the name now is a stand-in an earlier save (or an
    // earlier version, which never deleted them) left behind.
    _remove(path);
    if (linkForTest ?? Platform.isAndroid) {
      try {
        return Link(path)..createSync(media.absolute.path);
      } catch (e) {
        rlog('gallery: naming link failed: $e');
        _remove(path);
      }
    }
    if (media.lengthSync() > _copyForNameMax) {
      rlog('gallery: ${media.lengthSync() ~/ (1024 * 1024)} MB is too big '
          'to copy for a nicer name');
      return null;
    }
    try {
      return await media.copy(path);
    } catch (e) {
      // A copy that ran out of room stops halfway, and half a reel left
      // in the cache is the worst of both.
      rlog('gallery: naming copy failed: $e');
      _remove(path);
      return null;
    }
  }

  /// Deletes whatever is at [path] — a link itself, never its target.
  static void _remove(String path) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        Link(path).deleteSync();
      } else if (type == FileSystemEntityType.file) {
        File(path).deleteSync();
      }
    } catch (_) {}
  }

  /// Anything a FAT32 volume or a MediaStore display name might choke
  /// on becomes an underscore, and the result is kept short.
  static String? _sanitize(String? name) {
    if (name == null) return null;
    final s = name
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.isEmpty) return null;
    return s.length <= 60 ? s : s.substring(0, 60);
  }
}
