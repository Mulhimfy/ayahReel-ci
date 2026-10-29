import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/level.dart';
import 'debug_log.dart';

/// FFmpeg's process-wide settings, set once, in one place, as the app
/// starts and again, harmlessly, before the first encode.
///
/// All of these are global to the process, which is the whole reason
/// this file exists. They used to be set from inside the renderer, the
/// first time a reel was exported — so their values depended on whether
/// the user had exported anything yet, and the part of the app that
/// suffered most from them never set them at all.
///
/// **The log level** is the memory lever. FFmpeg holds every log line
/// of every session it remembers in the Java heap, and an export that
/// talks per frame parks tens of thousands of strings there while the
/// preview's decoders are still asking for buffers. The allocation that
/// finally fails is the one inside MediaCodec's callback thread, which
/// aborts the process rather than throwing. Warnings and up are all we
/// ever read.
///
/// **The history size** is not a memory lever, and using it as one is
/// what broke the Moments. Every getter on a session — including the
/// media information an ffprobe was run for — is a call back into
/// native that looks the session up by id, and a session that has
/// fallen out of the history is simply gone: `SESSION_NOT_FOUND`.
/// [RecitationService] probes ten ayah files at once, so ten sessions
/// exist before the first result is read; the renderer had set the
/// history to two. Eight of them could never be read, the fetch failed,
/// and the preview told the user to check a connection that was working
/// perfectly. The number has to be larger than the widest burst of
/// sessions that are still going to be read — not smaller than it.
///
/// Thirty-two is three times the widest fan-out in the app, and at
/// warning level a remembered session holds almost nothing.
///
/// **The log and statistics events** are switched off. The plugin turns
/// both on when it loads, and then posts every log line and every
/// progress report of every session to the main thread, encodes it
/// there and hands it to Dart — where nothing listens for logs, and
/// progress is read off a file instead (`FfmpegProgressFile`). A long
/// save on a slow phone queued them faster than the main thread could
/// drain them: Play's ANR (1.0.7, build 17) is the main thread stuck in
/// exactly that encode, with FFmpeg's callback thread posting the next.
/// Sessions still keep their own logs, which is what
/// `getAllLogsAsString` reads; only the forwarding stops.
const _sessionHistory = 32;

Future<void>? _done;

/// Idempotent, and safe to await from several places at once: every
/// caller after the first gets the same future.
Future<void> configureFfmpeg() => _done ??= _configure();

Future<void> _configure() async {
  try {
    await FFmpegKitConfig.setLogLevel(Level.avLogWarning);
    await FFmpegKitConfig.setSessionHistorySize(_sessionHistory);
    await FFmpegKitConfig.disableLogs();
    await FFmpegKitConfig.disableStatistics();
  } catch (e, st) {
    // Not fatal: these are all tuning. Logged rather than swallowed,
    // because a failure here is invisible until something much later
    // behaves oddly for no apparent reason.
    rlogError('ffmpeg: config', e, st);
  }
}
