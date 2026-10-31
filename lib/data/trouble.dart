import 'dart:async' show TimeoutException;
import 'dart:io';

import 'package:http/http.dart' as http;

/// What went wrong, in the terms of the person holding the phone —
/// which decides what they are told, and whether "check your
/// connection" is true.
///
/// It used to be said for every failure. A background isolate that
/// could not be sent a closure, and a join that choked on a reciter's
/// cover art, both reached the user as a connection problem, and both
/// sent people to their router over a fault on their own phone.
enum Trouble {
  /// The phone never got an answer: offline, a connection dropped or
  /// timed out, a network that would not finish the handshake.
  offline,

  /// A server answered, but not with what was asked for: a missing
  /// file, a server error, a table that doesn't fit its audio.
  host,

  /// The phone ran out of room to write to.
  storage,

  /// Something on the phone itself failed: decoding, joining, cutting,
  /// measuring.
  device,

  /// The voice never recorded this surah (`SurahUnavailable`).
  missing,
}

/// A failure that knows its [Trouble]. Thrown where the kind is known —
/// a download that never connected, a server that answered 404, an
/// encode that failed — and read by [troubleOf] everywhere else.
class TroubleException implements Exception {
  final Trouble trouble;

  /// What was being done, for a report: "downloading <url>".
  final String doing;

  /// What was thrown underneath, if anything.
  final Object? cause;

  const TroubleException(this.trouble, this.doing, [this.cause]);

  @override
  String toString() =>
      '${trouble.name}: $doing${cause == null ? '' : ' — $cause'}';
}

/// An HTTP answer that wasn't the one asked for.
class BadStatus implements Exception {
  final int code;
  final String? note;

  const BadStatus(this.code, [this.note]);

  @override
  String toString() => 'HTTP $code${note == null ? '' : ', $note'}';
}

/// The [Trouble] behind [e]: a [TroubleException] says so itself, and
/// anything else is read from its type. What isn't recognised is taken
/// to have happened on the phone — never blamed on the connection.
Trouble troubleOf(Object e) {
  if (e is TroubleException) return e.trouble;
  if (e is BadStatus) return Trouble.host;
  if (e is FileSystemException && _outOfSpace(e)) return Trouble.storage;
  if (e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is TlsException ||
      e is HttpException ||
      e is http.ClientException) {
    return Trouble.offline;
  }
  return Trouble.device;
}

/// Whether [e] says the phone ran out of room: an exception, a gallery
/// error, or the log FFmpeg wrote on its way out.
///
/// Read off the text because every layer reports it in its own words —
/// FFmpeg and the OS as ENOSPC, gal as `NOT_ENOUGH_SPACE`, MediaStore's
/// database as full — and none of them shares a type with the others.
bool saysOutOfSpace(Object? e) {
  if (e == null) return false;
  if (e is FileSystemException && _outOfSpace(e)) return true;
  final s = '$e'.toLowerCase();
  return s.contains('no space left') ||
      s.contains('enospc') ||
      s.contains('not_enough_space') ||
      s.contains('database or disk is full') ||
      s.contains('sqlite_full');
}

/// ENOSPC is 28 on Linux, Android and Darwin alike.
bool _outOfSpace(FileSystemException e) =>
    e.osError?.errorCode == 28 ||
    '${e.osError?.message ?? ''} ${e.message}'
        .toLowerCase()
        .contains('no space left');
