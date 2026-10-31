import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'trouble.dart';

/// How the recitation downloads wait, give up and try again — on a
/// phone, where the network comes and goes.
///
/// **A stall, not a deadline.** Every download used to be given thirty
/// seconds, start to finish. That is plenty for an ayah on a good
/// connection and nothing like enough on a slow one, where ten of them
/// share the radio: a long verse at 128 kbps, a tenth of a one-megabit
/// link, takes a minute and was given up on at thirty seconds every
/// time it was tried. What is limited now is silence — [stall] without
/// a byte — and a download that keeps moving may take as long as it
/// takes.
///
/// **Nothing left running.** `client.get(url).timeout(...)` stops
/// waiting and leaves the request going. The retry then shared the link
/// with the download it replaced, and with every other one abandoned
/// the same way, so on a slow link each round of retries was slower
/// than the last. [send] aborts a request that doesn't answer in time,
/// and a body that stalls is cancelled by the `await for` that reads
/// it.
///
/// **Patience measured in progress.** A phone locks its screen while
/// the user watches a progress bar, and the app is suspended with a
/// download half done; a train goes into a tunnel; Wi-Fi hands over to
/// the mobile network. Three tries 0.4 s and 0.8 s apart were over
/// before any of those were. A download is now called off after
/// [attempts] tries in a row that brought nothing, [backoff] apart, and
/// a try that brought bytes doesn't count against it — the callers keep
/// what came and ask for the rest.
abstract final class Download {
  /// The longest a request may go without a byte: no answer to it, or
  /// a body that stops coming.
  static Duration get stall => _stall;
  static Duration _stall = _defaultStall;
  static const _defaultStall = Duration(seconds: 30);

  /// Tries in a row that brought nothing before a download is called
  /// off.
  static const attempts = 4;

  /// The pause after the [miss]th try in a row that brought nothing
  /// (counted from 1): 1, 2, 4 s between the [attempts] tries, seven
  /// seconds of waiting on top of the tries themselves, which outlasts
  /// a hand-over from Wi-Fi to the mobile network. After a try that
  /// brought something, [miss] is 0 and the next one goes in a second.
  static Duration backoff(int miss) =>
      _backoffUnit * (1 << min(max(miss - 1, 0), 3));
  static Duration _backoffUnit = _defaultBackoffUnit;
  static const _defaultBackoffUnit = Duration(seconds: 1);

  /// Shorter waits for tests, which can't sit through real ones; called
  /// with nothing, puts the real ones back.
  @visibleForTesting
  static void debugTiming({
    Duration stall = _defaultStall,
    Duration backoffUnit = _defaultBackoffUnit,
  }) {
    _stall = stall;
    _backoffUnit = backoffUnit;
  }

  /// Whether asking again can't help: the server understood and said no
  /// — a file it doesn't have, a range it can't serve. Not a timeout or
  /// a dropped connection, not a server error (5xx), not "too many
  /// requests": those are worth the next try.
  static bool isFinal(Object e) =>
      e is BadStatus &&
      e.code >= 400 &&
      e.code < 500 &&
      e.code != 408 &&
      e.code != 429;

  /// Asks for [url], and gives the answer [stall] to begin. One that
  /// hasn't begun by then is aborted rather than left running behind
  /// the retry.
  static Future<http.StreamedResponse> send(
    http.Client client,
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final abort = Completer<void>();
    final req = http.AbortableRequest('GET', url, abortTrigger: abort.future)
      ..headers.addAll(headers);
    try {
      return await client.send(req).timeout(stall);
    } on TimeoutException {
      abort.complete();
      rethrow;
    }
  }

  /// Lets go of an answer that won't be read — a refused range, a server
  /// error — so its body doesn't hold a connection open behind the next
  /// try.
  static void discard(http.StreamedResponse res) {
    res.stream.listen(null, onError: (Object _) {}).cancel();
  }

  /// [res]'s body as it arrives, failing with a [TimeoutException] when
  /// [stall] passes without a byte. Leaving the `await for` that reads
  /// it, for that or any other reason, cancels the rest of the body.
  static Stream<List<int>> body(http.StreamedResponse res) =>
      res.stream.timeout(stall);

  /// All of [res]'s body, for an answer of a few bytes already checked
  /// (the head of a file, read to find its first frame).
  static Future<Uint8List> readAll(http.StreamedResponse res) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in body(res)) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  /// [url]'s whole answer, as `client.get` would give it, for the small
  /// ones read whole (a table, a surah's text): [stall] for it to begin
  /// and [stall] again for the rest to arrive, and aborted rather than
  /// left running when either runs out.
  static Future<http.Response> get(
    http.Client client,
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final abort = Completer<void>();
    final req = http.AbortableRequest('GET', url, abortTrigger: abort.future)
      ..headers.addAll(headers);
    try {
      final res = await client.send(req).timeout(stall);
      return await http.Response.fromStream(res).timeout(stall);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      rethrow;
    }
  }
}
