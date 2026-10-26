import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../data/band_glow.dart';
import '../data/debug_log.dart';
import '../data/export_budget.dart';
import '../data/ffmpeg_progress.dart';
import '../data/ffmpeg_setup.dart';
import '../data/media_aspect.dart';
import '../data/models.dart';
import '../data/quran_text_service.dart';
import '../data/reel_effects.dart';
import '../data/surah_title_look.dart';
import '../data/trouble.dart' show saysOutOfSpace;
import '../data/verse_font.dart';
import '../data/verse_follow.dart';
import '../data/verse_ink.dart';
import '../data/verse_lines.dart';
import '../data/verse_motion.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
import '../state/creation_state.dart'
    show
        TextPreset,
        ReelLayout,
        LetterboxBackdrop,
        SceneTransition,
        isLightGround;
import '../widgets/ayah_overlay.dart' show AyahOverlay;
import '../widgets/reel_watermark.dart' show ReelDedication;
import '../widgets/surah_title.dart';
import '../widgets/verse_geometry.dart';
import '../widgets/verse_unit_card.dart';
import 'ayah_rasterizer.dart';
import 'letterbox_layout.dart';
import 'motion_graph.dart';
import 'on_screen.dart';
import 'render_dir.dart';
import 'render_plan.dart';
import 'render_process.dart';
import 'scene_plan.dart';
import 'still_source.dart';

/// Why an export stopped, when it stopped for a reason the user can be
/// told something useful about.
enum RenderFailure {
  /// FFmpeg could not get the memory the graph asked for. Not the
  /// phone's storage and usually not its free RAM either: the filter
  /// graph holds one decoded verse card per overlay for the whole
  /// encode, so a busy reel can ask for more address space than the
  /// process is allowed, on a phone with gigabytes to spare.
  outOfMemory,

  /// The phone ran out of storage while the reel was being written.
  /// Nothing about the reel can fix that, and "try again" only fails
  /// the same way at the same point — so it is said for what it is.
  noSpace,

  /// Anything else. The logs are in the debug log; the user gets a
  /// sentence, not a log tail.
  other,
}

/// Thrown by [VideoRenderer.render] when the encode failed for good —
/// after every fallback it had. [kind] is what to tell the user;
/// [detail] is for the debug log and the feedback report.
final class RenderFailed implements Exception {
  final RenderFailure kind;
  final String detail;

  const RenderFailed(this.kind, this.detail);

  @override
  String toString() => 'RenderFailed(${kind.name}): $detail';
}

/// Thrown by [VideoRenderer.render] when the render was superseded or
/// canceled. Callers treat it as "result no longer wanted" — never as
/// a failure to show the user.
/// FFmpeg could not open the encode's progress file, and so never
/// started: [VideoRenderer._runEncode] runs it again without one.
final class _ProgressRefused implements Exception {
  const _ProgressRefused();
}

final class RenderCancelled implements Exception {
  const RenderCancelled();
}

/// One scenery of a multi-scene reel, resolved to a readable file and
/// the length the graph must take from it.
class _SceneInput {
  final String path;
  final bool isImage;

  /// How long this scenery is on screen, plus the crossfade it hands
  /// over on — the fade is played out of the *next* scene's head and
  /// this one's tail, so both have to be that much longer than the cut.
  final double seconds;

  /// Where in the clip this input starts. Zero everywhere except the
  /// first scenery of a pass that begins in the middle of one, which
  /// only ever happens where the clip is long enough to be seeked into
  /// rather than looped — see [RenderPlan].
  final double seekS;

  /// The clip's own length, when it could be measured. Null for a
  /// still, and for a file ffprobe could not read.
  final int? sourceMs;

  /// The file is already the finished 1080x1920 base frame: scaled,
  /// cropped and scrimmed. The graph then reads it as it is instead of
  /// doing that work again on every frame it is on screen for.
  final bool ready;

  const _SceneInput(
    this.path,
    this.isImage,
    this.seconds, {
    this.seekS = 0,
    this.sourceMs,
    this.ready = false,
  });
}

/// One overlay PNG and the window (recording-absolute ms) it is shown.
/// Without word highlighting there is one clip per ayah; with it, an
/// ayah becomes a base clip plus one clip per highlighted word window.
class _OverlayClip {
  final File file;
  final int startMs;
  final int endMs;

  /// How tall the card in [file] shrink-wrapped to, which is what the
  /// full-frame mark hangs off — see [AyahRasterizer.watermarkInsetFor].
  ///
  /// The height and not the mark's position, deliberately. Position
  /// also depends on the user's drag and on the format, and neither is
  /// in the raster memo's key: a reel re-rendered with the verse moved
  /// reuses these very cards, and a stored position would be the one
  /// from before the drag. The height is the part rasterizing actually
  /// decided, so it is the part worth keeping.
  ///
  /// Identical across the highlight clips of one ayah, since those are
  /// the same card lit differently.
  final double cardH;

  /// The unit — a whole verse, or one part of a verse cut into lines —
  /// this card belongs to, uncut by any pass: what its motion is timed
  /// by. Null on the path every reel without motion takes.
  final int? unitStartMs;
  final int? unitEndMs;

  const _OverlayClip(this.file, this.startMs, this.endMs, this.cardH,
      {this.unitStartMs, this.unitEndMs});
}

/// One unit's flourishes, as the cards were rasterized: its card's
/// height, the lines its Arabic was laid out in (card pixels), how the
/// recitation crosses each, and the glint card its light is cut from.
/// Where the card sits in the frame is left to the command, since the
/// verse's drag moves it without the cards being drawn again.
class _UnitShow {
  final int startMs;
  final int endMs;
  final double cardH;
  final List<MotionRow> rows;
  final File? glint;

  const _UnitShow(this.startMs, this.endMs, this.cardH, this.rows, this.glint);
}

/// Composites background + ayah PNG overlays + recitation audio into a
/// 1080x1920 (9:16) mp4, entirely on-device.
///
/// The overlay schedule comes straight from [Recitation.timings]; the
/// exporter is just FFmpeg obeying the same numbers the preview used.
///
/// Renders are cached per full styling key: Share followed by Save
/// reuses the same file instead of rendering twice.
abstract final class VideoRenderer {
  /// The last rasterized overlay set. Re-renders that change only the
  /// background skip the slow widget-to-PNG pass.
  static String? _rasterMemoKey;
  static List<_OverlayClip> _rasterMemoClips = const [];
  static List<_UnitShow> _rasterMemoShows = const [];

  /// Monotonic render generation. Every [render] call and every
  /// [cancelActive] bumps it; a running render aborts at its next
  /// checkpoint once its generation is stale. This closes the race a
  /// session id alone can't: a render canceled BEFORE its FFmpeg
  /// session launched used to keep going and start a zombie encode
  /// that saturated every core and froze the next preview.
  static int _generation = 0;

  /// The FFmpeg session of the current-generation render, if launched.
  static EncodeRun? _active;

  /// Whether this device's MediaCodec H.264 encoder actually works,
  /// probed once per process (null = not probed yet).
  ///
  /// The encode is what a render costs: the entire filter graph —
  /// scale, scrim, every verse card, watermark, dither, colour
  /// conversion — measures at roughly a quarter of what libx264 alone
  /// spends on the same frames. So the encoder is the only lever worth
  /// pulling, and MediaCodec is several times faster than x264 at the
  /// preset we can afford.
  ///
  /// The bundled FFmpeg is built with --enable-mediacodec, so the
  /// encoder is always compiled in; whether a given *device* hands out
  /// an encoder and muxes cleanly to mp4 is another matter, so we find
  /// out with a six-frame encode rather than assume. Any failure at any
  /// point falls back to libx264, which stays the reference path.
  static bool? _hwOk;

  /// How long the hardware probe may take. Six frames are encoded in a
  /// second or two; an encoder still busy with them after this is one
  /// that will never answer, and the probe waited on it for ever.
  static const _probeLimit = Duration(seconds: 30);

  /// How long a hardware encode may go without writing a frame before
  /// it is taken for stalled and the reel is redone on x264. A device
  /// encoder that stops answering does not fail — it waits, and the
  /// progress bar waited with it, for as long as the user did.
  static const _hwStallLimit = Duration(seconds: 60);

  /// A wait between two looks at an encode that ran this much longer
  /// than the 200 ms asked for is the app having been frozen — sent to
  /// the background and stopped by Android, or the phone asleep — not
  /// the encoder being slow. FFmpeg runs in this process and was frozen
  /// with it, so the stall clock starts again: counted through the
  /// freeze, an encode left behind for a minute was given up on the
  /// moment the user came back, and the reel started again on x264.
  static const _frozenGap = Duration(seconds: 5);

  /// How long a cancelled hardware encode is given to end before it is
  /// left behind.
  static const _cancelGrace = Duration(seconds: 30);

  /// How soon after the app came back a render-process death still
  /// counts as one it suffered while away: Android holds a background
  /// app still, and the app hears of the death once it thaws.
  static const _awayGrace = Duration(seconds: 10);

  /// Encodes that were given up on while still running: wedged inside
  /// the device encoder, where a cancel may never reach them. Their
  /// logs are not asked for — the plugin answers that on the main
  /// thread, and waits there for a live session's log to arrive.
  static final _abandoned = Expando<bool>();

  /// The most verse cards one pass may hold under [budget] — null for
  /// the plan's own limits — and the threads its encoder may take.
  ///
  /// A phone that has already refused an encode for want of memory is
  /// planned one step smaller for the rest of the process (see
  /// [PhoneBudget.outOfMemory]) rather than failing its way there
  /// again — the same shape as [_hwOk], and for the same reason.
  static int? _clipsFor(ExportBudget budget) => switch (budget) {
        ExportBudget.roomy => null,
        ExportBudget.tight => RenderPlan.clipsPerPassLowMemory,
        ExportBudget.tightest => RenderPlan.clipsPerPassLeast,
        ExportBudget.smallest => RenderPlan.clipsPerPassSmallest,
      };
  static int _threadsFor(ExportBudget budget) => switch (budget) {
        ExportBudget.roomy => 16,
        ExportBudget.tight => 4,
        ExportBudget.tightest || ExportBudget.smallest => 2,
      };

  /// The decoder threads a scenery input may take under [budget], or
  /// null for FFmpeg's own choice — one per core and one more, each
  /// holding a picture of its own. On a phone short of memory those
  /// are pictures it can't spare; two still decode faster than the
  /// encoder after them can take the frames.
  static int? _sceneThreadsFor(ExportBudget budget) =>
      budget == ExportBudget.roomy ? null : 2;

  /// Whether the picture check below can be trusted on this device
  /// (null = not established yet).
  ///
  /// The check runs FFmpeg against the finished mp4, so a build or a
  /// device where that can't work would report every export as
  /// pictureless and refuse them all. It is therefore proved first,
  /// against a file the reference encoder has just produced: if a
  /// known-good reel doesn't pass, the verdict is worthless and no
  /// export is judged by it.
  static bool? _verifyOk;

  /// How a long reel's progress bar is divided: turning verses into
  /// PNGs, then the passes, then the join. A short reel still reports
  /// the encode alone, from zero.
  static const _prepShare = 0.03;
  static const _joinShare = 0.97;

  /// Hardware target bitrate. libx264 at CRF 20 lands between ~1 Mbps
  /// (still background) and ~4 Mbps (gradient clip) on this content;
  /// hardware AVC needs roughly double the bits for the same look, so
  /// this is comfortably transparent rather than merely adequate.
  /// Gradients band before anything else here — if an export ever looks
  /// worse than the x264 path, raise this first.
  static const _hwBitrate = '6M';

  /// The same picture at a length the phone can actually hold.
  ///
  /// Six megabits is transparent and, for a reel of a minute or two, it
  /// costs nothing worth counting. An hour of it is two and a half
  /// gigabytes — written once by the encode, again by the copy that
  /// puts the reel in My Reels, and a third time by the gallery. So
  /// past a few minutes the bitrate comes down with the length: this
  /// content is a mostly still frame over slow scenery, which is
  /// exactly what an encoder spends the fewest bits on, and an hour
  /// lands near 900 MB instead.
  ///
  /// [high] is the switch in Settings, off unless the user turns it
  /// on: a short reel gets twice the bits, and every longer one moves
  /// up a rung, so an hour still fits on a phone. Twelve megabits is
  /// as far as it is worth going — the scenery arrives at 2.5, and
  /// the feeds re-encode every upload whatever it was sent at.
  static String _hwBitrateFor(int reelMs, {bool high = false}) => (high
      ? const ['12M', '6M', '4M', '3M']
      : const [_hwBitrate, '4M', '3M', '2M'])[_rung(reelMs)];

  /// The x264 half of the same ladder. CRF is a quality target rather
  /// than a rate, so the steps are smaller; 17 is past the point where
  /// x264 output is held to look like its source.
  static int _crfFor(int reelMs, {bool high = false}) =>
      (high ? const [17, 20, 22, 24] : const [20, 22, 24, 26])[_rung(reelMs)];

  /// Which step of the ladder a reel of [reelMs] is on: up to five
  /// minutes, twenty, forty, and past that.
  static int _rung(int reelMs) => reelMs <= 5 * 60000
      ? 0
      : reelMs <= 20 * 60000
          ? 1
          : reelMs <= 40 * 60000
              ? 2
              : 3;

  /// The video encoder's half of an FFmpeg command: MediaCodec where
  /// the device allows it, x264 as the reference fallback.
  ///
  /// Deliberately spare: bitrate_mode/level/operating_rate all exist
  /// in this build but device support for them is uneven, and one
  /// rejected option costs a whole wasted encode. [threads] applies to
  /// x264 only — MediaCodec does its own thing, and the filter graph
  /// threads independently of both.
  @visibleForTesting
  static String videoCodec({
    required bool hardware,
    required int reelMs,
    required int threads,
    bool high = false,
    bool lean = false,
  }) =>
      hardware
          ? '-c:v h264_mediacodec -b:v ${_hwBitrateFor(reelMs, high: high)} '
              '-g 60 $_hwTagBsf'
          : '-c:v libx264 -preset ${lean ? leanPreset : 'veryfast'} '
              '-crf ${_crfFor(reelMs, high: high)} -threads $threads '
              '${_x264CeilingFor(reelMs)}'
              '${lean ? leanX264 : ''}';

  /// Whether [file], a reel [reelMs] long, is heavier than any reel
  /// made since the ceiling: a lean or grainy reel from before
  /// 2026-10-13 (26 to 58 Mbps), which budget phones would not play.
  /// Reels since average under the 12 Mbps ceiling; a join of short
  /// passes peaks near 18, so 18 on average is past anything made now.
  /// Beside it, 2 MB any reel carries whatever its length: the
  /// encoder's first buffer (up to 12 Mbit under the ceiling), the
  /// sound's start and the mp4's boxes. Over a reel of a second or two
  /// they are most of the file, and a reel made now read as too heavy.
  static bool tooHeavyToPlay(File file, int reelMs) {
    if (reelMs <= 0 || !file.existsSync()) return false;
    return file.lengthSync() * 8 > 18e6 * reelMs / 1000 + 16e6;
  }

  /// Keys made again this run for being too heavy: once each, so a
  /// reel that somehow comes out heavy again is served rather than
  /// encoded at every Save.
  static final _remade = <String>{};

  /// The most an x264 encode may spend, whatever its CRF would ask
  /// for: twice what the hardware encoder is given at the same length,
  /// over a buffer of one second.
  ///
  /// CRF alone has no ceiling, and the grain every reel carries (see
  /// the noise filter in [_buildCommand]) is new in every frame. Most
  /// of the time x264 quantizes it away, but at the top of the Grain
  /// slider a 1080x1920 reel ran 58 Mbps, and the lean encode did 26 at
  /// the slider's bottom (see [leanX264]). The stream still says Level
  /// 4.0, which is 25 Mbps for High profile, and that is the limit a
  /// budget phone's decoder is built to. Past it the reel saved and
  /// then would not play: "every reel I save says playback error"
  /// (Realme RMX3830, 1.0.9, 2026-10-13). Under the ceiling a
  /// stream-copy join of short passes peaks near 18 Mbps (desktop
  /// FFmpeg 8.0.1, grain at its top, three-second passes), and the
  /// level holds. A reel that never reaches the ceiling is unchanged.
  /// The same for both rungs of quality: it is what phones can play,
  /// not how good the reel looks.
  static String _x264CeilingFor(int reelMs) {
    final mbps = const [12, 8, 6, 4][_rung(reelMs)];
    return '-maxrate:v ${mbps}M -bufsize:v ${mbps}M ';
  }

  /// libx264 holding as few frames as it can: a five-frame lookahead,
  /// no B-frames, no lookahead thread. For [ExportBudget.tightest], the
  /// phones that die mid-save — see EXPORT_MEMORY.md.
  ///
  /// The macroblock tree stays on, and it has to. It is what tells x264
  /// that the scenery under the verse is the same picture frame after
  /// frame, so the grain on it is not worth coding again. From
  /// 2026-10-08 to 2026-10-13 lean ran without it (`rc-lookahead=0`,
  /// `mbtree=0`, and the superfast preset turns it off too), measured
  /// only on FFmpeg's grainless test pattern. On a real reel it coded
  /// the grain in full in every frame. Desktop FFmpeg 8.0.1, 1080x1920,
  /// two threads, eight cards, 150 frames: 26.4 Mbps over a still sky
  /// against 0.05 for the roomy encode, and 12 against 1.3 over moving
  /// scenery. The reels were huge, slower to make than veryfast's, and
  /// past what the stream's level promises, so phones would not play
  /// them. With the tree on a five-frame lookahead: 0.05 and 1.3 Mbps,
  /// faster still, and 30 MB more than without (220 MB for the bare
  /// encode against 189; veryfast is 325).
  static const leanX264 =
      '-x264-params rc-lookahead=5:mbtree=1:bframes=0:sync-lookahead=0 ';

  /// And a faster preset with it. The phones on the tightest budget are
  /// the slowest ones, encoding on two threads — and since 2026-10-11
  /// the ones whose saves died in the hardware encoder, which now run
  /// x264 where they used to run MediaCodec. A save there took long
  /// enough to be reported as broken ("the saving is slow"). superfast
  /// is veryfast's analysis cut down (one subpel pass, diamond search,
  /// fewer partitions), and keeps CABAC and the deblocking filter — the
  /// two whose loss shows as blocks and banding on a gradient sky. It
  /// turns the lookahead and the macroblock tree off, which
  /// [leanX264] turns back on.
  static const leanPreset = 'superfast';

  /// Whether this export's software encodes run [leanX264]: set from
  /// its budget when the export plans, and again when it steps down.
  static bool _lean = false;

  /// Hardware encoders drop the BT.709 tags: where x264 writes
  /// `tv/bt709`, MediaCodec-style encoders hand the muxer a stream
  /// tagged `unknown` on every colour field, and players left guessing
  /// wash the picture out — the exact failure the explicit conversion
  /// at the end of the filter graph exists to prevent. Stamping the SPS
  /// VUI directly is the only reliable fix, so the hardware path always
  /// carries it (values are the H.264 code points for BT.709, limited
  /// range: the frames the graph produces).
  static const _hwTagBsf = '-bsf:v h264_metadata=colour_primaries=1:'
      'transfer_characteristics=1:matrix_coefficients=1:'
      'video_full_range_flag=0 ';

  /// One tiny real encode through the same mp4 output path an export
  /// uses, played back through a decoder before it is believed.
  /// [probeSrc] is any 1080x1920 PNG we have already rasterized.
  ///
  /// A return code and a non-empty file were not enough: a MediaCodec
  /// encoder can accept every frame, mux a plausible mp4 and still
  /// write a track nothing will play. Decoding a frame back out is
  /// what separates an encoder that works from one that only says so.
  static Future<bool> _hardwareEncoderWorks(String probeSrc, Directory tmp) {
    final known = _hwOk;
    if (known != null) return Future.value(known);
    // One probe for every render that asks while it runs: two at once
    // wrote and deleted the same file under each other.
    return _hwProbing ??=
        _probeHardware(probeSrc, tmp).whenComplete(() => _hwProbing = null);
  }

  static Future<bool>? _hwProbing;
  static Future<bool>? _verifyProbing;

  static Future<bool> _probeHardware(String probeSrc, Directory tmp) async {
    final canVerify = await _pictureCheckWorks(probeSrc, tmp);
    final probe = File('${tmp.path}/ayah_hwprobe.mp4');
    var ok = false;
    try {
      final session = await _runWithin(
        '-loop 1 -framerate 30 -i "$probeSrc" -frames:v 6 '
        '-c:v h264_mediacodec -b:v $_hwBitrate -pix_fmt yuv420p '
        '$_hwTagBsf'
        '-movflags +faststart -y "${probe.path}"',
        _probeLimit,
      );
      if (session == null) {
        rlogError('render: hardware probe',
            'no answer in ${_probeLimit.inSeconds}s — using x264');
      }
      ok = session != null &&
          ReturnCode.isSuccess(await session.getReturnCode()) &&
          probe.existsSync() &&
          probe.lengthSync() > 0 &&
          (!canVerify || await _decodesToPicture(probe, tmp));
    } catch (e) {
      rlog('render: hw probe threw $e');
    }
    if (probe.existsSync()) {
      try {
        probe.deleteSync();
      } catch (_) {}
    }
    rlog('render: hardware encoder ${ok ? "available" : "unavailable"}');
    return _hwOk = ok;
  }

  /// Runs [cmd] to its end, but not for ever: null if it was still
  /// going after [limit], in which case it is cancelled and left.
  ///
  /// Only for an encode that should be over in moments. A device
  /// encoder that never answers is not one this phone has, and nothing
  /// else stands between it and a progress bar that never moves.
  static Future<FFmpegSession?> _runWithin(String cmd, Duration limit) async {
    final session = await FFmpegKit.executeAsync(cmd);
    final clock = Stopwatch()..start();
    // Time the app spent frozen in the background is not time the
    // encoder took: a poll that comes back seconds late was asleep, and
    // that stretch isn't counted (the same rule as the stall watchdog).
    var counted = Duration.zero;
    var last = Duration.zero;
    while (await session.getReturnCode() == null) {
      final now = clock.elapsed;
      final step = now - last;
      last = now;
      if (step < const Duration(seconds: 2)) counted += step;
      if (counted > limit) {
        final id = session.getSessionId();
        if (id != null) {
          try {
            await FFmpegKit.cancel(id);
          } catch (_) {}
        }
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return session;
  }

  /// Six frames through libx264 — the reference encoder, whose output
  /// is correct by definition here — put through the picture check.
  /// A pass means a failed check on a real export says something about
  /// the export; a fail means the check says nothing at all, and
  /// nothing is judged by it for the rest of the process.
  static Future<bool> _pictureCheckWorks(String probeSrc, Directory tmp) {
    final known = _verifyOk;
    if (known != null) return Future.value(known);
    return _verifyProbing ??= _probePictureCheck(probeSrc, tmp)
        .whenComplete(() => _verifyProbing = null);
  }

  static Future<bool> _probePictureCheck(String probeSrc, Directory tmp) async {
    final probe = File('${tmp.path}/ayah_refprobe.mp4');
    var ok = false;
    try {
      final session = await FFmpegKit.execute(
        '-loop 1 -framerate 30 -i "$probeSrc" -frames:v 6 '
        '-c:v libx264 -preset ultrafast -crf 30 -pix_fmt yuv420p '
        '-movflags +faststart -y "${probe.path}"',
      );
      ok = ReturnCode.isSuccess(await session.getReturnCode()) &&
          probe.existsSync() &&
          probe.lengthSync() > 0 &&
          await _decodesToPicture(probe, tmp);
    } catch (e) {
      rlog('render: picture-check probe threw $e');
    }
    if (probe.existsSync()) {
      try {
        probe.deleteSync();
      } catch (_) {}
    }
    rlog(
        'render: picture check ${ok ? "usable" : "UNUSABLE — exports go unchecked"}');
    return _verifyOk = ok;
  }

  /// Whether [file] really holds a picture: a video track that decodes
  /// to at least one frame.
  ///
  /// An encode that reports success is not the same as a reel someone
  /// can watch. A hardware encoder that hands the muxer a stream no
  /// decoder accepts produces an mp4 of the right length, with working
  /// audio and a video track that plays as nothing — and because the
  /// preview screen plays its own widgets rather than the export,
  /// nothing in the app ever looks at the file. The first person to
  /// open it is the user, in their gallery, where it played the
  /// recitation over a black screen ("only the audio was saved").
  ///
  /// So the export is opened here, before it is handed to anyone.
  static Future<bool> _decodesToPicture(File file, Directory tmp) async {
    // Named for what it is checking: a probe and an export can be
    // checked in the same breath, and neither may read the other's
    // frame.
    final still = File(
        '${tmp.path}/ayah_verify_${file.path.hashCode.toRadixString(16)}.jpg');
    try {
      if (still.existsSync()) still.deleteSync();
      final session = await FFmpegKit.execute(
        '-v error -i "${file.path}" -map 0:v:0 -frames:v 1 '
        '-f mjpeg -y "${still.path}"',
      );
      final ok = ReturnCode.isSuccess(await session.getReturnCode()) &&
          still.existsSync() &&
          still.lengthSync() > 0;
      // Survives into release: this is the verdict behind an export
      // that plays as black, and the only trace of it a field report
      // can be answered with.
      if (!ok) rlogError('render picture check', 'no picture in ${file.path}');
      return ok;
    } catch (e) {
      rlog('render: picture check threw $e');
      return false;
    } finally {
      if (still.existsSync()) {
        try {
          still.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// The styling key baked into a render's file name by [render].
  /// Two exports that produce the same key are the same reel, byte for
  /// byte, which is what lets the library keep one copy of it.
  static String sourceKeyOf(File render) => render.uri.pathSegments.last
      .replaceFirst('ayah_reel_', '')
      .replaceFirst(RegExp(r'\.mp4$'), '');

  /// The render a Save or Share has joined while it ran as the eager
  /// render: its later encodes (passes, the join) take every core, as
  /// one started for the progress bar does. One already running keeps
  /// the threads it started with.
  static void promote() => _promoted = _generation;
  static int? _promoted;

  /// Whether the encode running now is the device encoder's, whose pace
  /// the thread count doesn't change ([promote] gains it nothing it
  /// would not have had, and starting it over only loses its work).
  static bool get encodingOnHardware => _active?.hardware ?? false;

  /// Stops the in-flight render, if one exists — including one that
  /// hasn't reached FFmpeg yet. Safe to call when nothing is running.
  static Future<void> cancelActive() async {
    _generation++;
    final run = _active;
    _active = null;
    rlog('render: cancelActive (gen now $_generation, '
        '${run?.name ?? "not launched"})');
    await run?.cancel();
  }

  /// Clears what earlier renders left in the cache folder, before a
  /// new one adds a reel of its own.
  ///
  /// Every styling the preview settled on for two seconds was encoded
  /// in full and kept under its own key, and nothing ever deleted one;
  /// beside them sat a named copy of every reel ever saved to the
  /// gallery, which older builds made and never deleted either (see
  /// `GallerySaver`). A phone that made reels for a few weeks carried
  /// all of them, and on one short of room the export after that ran
  /// out of space at its last step — every time, for every reel.
  ///
  /// The newest finished reel other than [keep] stays: it is the one
  /// just saved or shared, still offered by "Save again" and perhaps
  /// still being read by the app it was shared to. Any other is a cache
  /// miss away from being made again. Half-written files and named
  /// copies go once they are old enough that nothing live can still be
  /// writing or reading them.
  @visibleForTesting
  static void sweepCache(Directory tmp, {required File keep, DateTime? now}) {
    final stale =
        (now ?? DateTime.now()).subtract(const Duration(minutes: 10));
    // The pictures a render is made of (verse cards, lit words, flattened
    // backdrops, the dedication line) are redrawn in moments when wanted
    // again, and one of every styling ever tried piled up for good. A
    // day keeps them for the session they were drawn in; this sweep runs
    // before the render's own cards are looked up, so one taken here is
    // simply drawn again.
    final old = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    final finished = <File>[];
    var freed = 0;
    void drop(File f) {
      try {
        final n = f.lengthSync();
        f.deleteSync();
        freed += n;
      } catch (_) {}
    }

    try {
      for (final e in tmp.listSync(followLinks: false)) {
        if (e is! File || e.path == keep.path) continue;
        final name = e.uri.pathSegments.last;
        final render = name.startsWith('ayah_reel_');
        final partial = render && name.contains('.part');
        if (render && !partial && name.endsWith('.mp4')) {
          finished.add(e);
        } else if (partial ||
            // The gallery's named copies: `AyahReel_<surah>_<from>_<to>`.
            (name.startsWith('AyahReel_') && name.endsWith('.mp4')) ||
            // Graded gradient backdrops, a full frame each. Builds
            // before their names were stable left a new one behind
            // every launch; one still wanted is drawn again in a blink.
            (name.startsWith('ayah_grad_') &&
                name.contains('_g') &&
                name.endsWith('.png')) ||
            // Instagram's staged copy of a saved reel (a whole reel each)
            // and the arena's story pictures: each made for one hand-off.
            // (The pictures were `tanafus_story_` before they were named
            // for the app; old ones still go.)
            (name.startsWith('ig_') && name.endsWith('.mp4')) ||
            ((name.startsWith('ayahreel_round_') ||
                    name.startsWith('ayahreel_verses_') ||
                    name.startsWith('tanafus_story_')) &&
                name.endsWith('.png'))) {
          if (e.lastModifiedSync().isBefore(stale)) drop(e);
        } else if (_drawnForARender.hasMatch(name) ||
            _keptCard.hasMatch(name)) {
          if (e.lastModifiedSync().isBefore(old)) drop(e);
        }
      }
    } catch (e) {
      rlog('render: cache sweep stopped: $e');
    }
    finished.sort((a, b) => _mtime(b).compareTo(_mtime(a)));
    for (final f in finished.skip(1)) {
      drop(f);
    }
    if (freed > 0) {
      rlog('render: cache sweep freed '
          '${(freed / (1024 * 1024)).toStringAsFixed(1)} MB');
    }
  }

  /// Verse cards (`ayah_<tag><n>.png`), their lit words (`…_w<a>_<b>`),
  /// flattened backdrops, the dedication line and photos converted for
  /// FFmpeg ([StillSource]): see [sweepCache].
  static final _drawnForARender = RegExp(
      r'^ayah_(?:-?[0-9a-f]+_\d+(?:_w\d+_\d+)?'
      // A unit's cards — a whole verse, or one part of a cut one — in
      // each state a follow card draws, and its glint.
      r'|-?[0-9a-f]+_\d+(?:_p\d+)?_(?:base|glint|w(?:x|\d+_\d+)_d(?:x|\d+))'
      r'|bgflat_.+|lbflat_.+|band_v1_.+|ded_v1_.+|title_v1_.+|thread_v1_.+'
      r'|spark_v1_.+'
      r'|still_.+)\.png$');

  /// A verse card kept under what it looks like, and its numbers beside
  /// it (`ayah_c_<digest>.png` / `.json`, see `AyahRasterizer`): reused
  /// by any render that wants the same card, gone a day after drawing.
  static final _keptCard = RegExp(r'^ayah_c_[0-9a-f]+\.(?:png|json)$');

  static DateTime _mtime(File f) {
    try {
      return f.lastModifiedSync();
    } catch (_) {
      return DateTime(0);
    }
  }

  /// An encode that said it succeeded, whose file isn't there: deleted
  /// under it. Said in the words a vanished input is said in, so the
  /// save renders once more (see `_export` in the preview) instead of
  /// reporting a reel with no picture.
  static void _ensureLanded(File part) {
    if (part.existsSync()) return;
    rlog('render: the encode finished but its file is gone');
    throw RenderFailed(RenderFailure.other,
        '${part.uri.pathSegments.last}: No such file or directory');
  }

  /// Gives the checked [part] the name the cache reads. A rename, as
  /// both folders are the app's own; a copy if a phone ever puts them
  /// on different volumes, made beside [out] and renamed, so a copy
  /// cut short is never served as a finished reel.
  static void _claim(File part, File out) {
    try {
      part.renameSync(out.path);
    } on FileSystemException {
      part.copySync('${out.path}.part').renameSync(out.path);
      try {
        part.deleteSync();
      } catch (_) {}
    }
  }

  static void _checkCurrent(int gen) {
    if (gen != _generation) throw const RenderCancelled();
  }

  static Future<File> render({
    required Recitation recitation,
    required ReelBackground background,
    required List<Ayah> ayahs,

    /// Every scenery the reel runs through, and the timeline dividing
    /// it between them. One scene (or none) is the single-background
    /// reel this always rendered, on exactly the path it always took.
    List<ReelBackground> scenes = const [],
    List<SceneCut> cuts = const [],
    SceneTransition transition = SceneTransition.fade,
    int startAyah = 1,
    int? endAyah,
    double overlayAlign = 0.5,
    int textArgb = 0xFFFFFFFF,
    int accentArgb = 0xFFEEC96B,

    /// The luminous inks the verse and the accent are drawn in, if any.
    /// [textArgb] and [accentArgb] hold their bases.
    VerseInk verseInk = VerseInk.none,
    VerseInk accentInk = VerseInk.none,
    double textScale = 1.0,
    TextPreset preset = TextPreset.classic,

    /// The pair of faces the card is typeset in.
    ReelTypography typography = const ReelTypography(),

    /// Who the reel was made for, already written as a sentence —
    /// "A gift for Aisha", "Sadaqah jariyah for Fatima" — or empty,
    /// which is every reel nobody dedicated. Drawn along the bottom of
    /// the frame as its own overlay; see [ReelDedication].
    String dedication = '',

    /// Where the dedication line was dragged to: its centre, as
    /// fractions of the frame. Null is its place at the foot.
    Offset? dedicationAt,

    /// The edition printed under the verse.
    ///
    /// Handed over rather than read off Settings inside the card, and
    /// in the key rather than only on the card — those are the same
    /// requirement. Two editions in the same script resolve to the
    /// same face (English, Indonesian and German are all Inter), so
    /// the typography alone does not tell them apart: without this,
    /// changing the edition and remaking the same passage served the
    /// old reel, with the old language burned into it.
    VerseTranslation? edition,

    /// Whether each verse card carries its number — the end-of-verse
    /// sign, the reference line, or both. In the raster key for the
    /// same reason [edition] is.
    VerseNumbering numbering = VerseNumbering.off,

    /// False leaves the translation off every verse card ("None" in
    /// the picker). In the raster key for the same reason [edition] is.
    bool showTranslation = true,

    /// Whether the reel is encoded on the higher rung of the bitrate
    /// ladder — the Settings switch. In the key: the same reel at the
    /// other quality is a different file.
    bool highQuality = false,

    /// What the picture is graded and finished with. [ReelEffects.off]
    /// — the default, and what every reel made before this existed is
    /// re-rendered as — takes the whole feature out of the graph.
    ReelEffects effects = ReelEffects.off,
    Map<int, List<HighlightSpan>>? highlight,

    /// The voice's word windows whether or not the word highlight is
    /// on — what the trail and the unveil follow. Null without word
    /// timing.
    Map<int, List<HighlightSpan>>? words,

    /// Each verse's tokens' recited windows, from word timing: what the
    /// thread and the light are timed by. Null without word timing,
    /// and they cross each line at an even pace instead.
    Map<int, List<(int, int)?>>? wordTimes,

    /// Long verses cut into lines; null or empty shows every verse
    /// whole, on exactly the path it always took.
    VerseLinePlan? lines,

    /// What the verse does as it is recited. [VerseMotion.none], the
    /// default, keeps every graph as it was.
    VerseMotion motion = VerseMotion.none,

    /// The surah's name at the head of the reel, and where its centre
    /// was dragged to (null for its place at the top).
    bool surahTitle = false,
    Offset? surahTitleAt,

    /// How far the surah's name was pinched from its own size.
    double surahTitleScale = 1.0,

    /// Its face, colour and frame.
    SurahTitleLook surahTitleLook = SurahTitleLook.classic,

    /// The basmala's card (Al-Fatiha 1:1 in the reel's edition), for a
    /// reel that opens a surah on verse 1 with a recording that carries
    /// the basmala (see [Recitation.opensWithBasmala]). Null otherwise.
    Ayah? basmala,
    ReelLayout layout = ReelLayout.fullFrame,
    bool roundedCorners = true,
    LetterboxBackdrop backdrop = LetterboxBackdrop.colour,
    int backdropArgb = 0xFF000000,

    /// The luminous ground drawn behind a wide card when [backdrop] is
    /// [LetterboxBackdrop.glow].
    BandGlow bandGlow = BandGlow.midnight,
    double sourceAspect = 16 / 9,

    /// Where the reel is cut short, absolute in the recording's clock.
    /// Null — and anything at or past the selection's own end — is the
    /// whole of it. The verses past the cut are still drawn (their
    /// cards are memoized for the untrimmed render) but nothing past
    /// it reaches FFmpeg: the picture, the recitation and the scene
    /// run all end here.
    int? trimEndMs,
    bool foreground = false,
    void Function(double progress)? onProgress,
  }) async {
    await configureFfmpeg();
    // A new render supersedes any previous one: only one encode may
    // ever run, or playback starves.
    final gen = ++_generation;
    final prev = _active;
    _active = null;
    await prev?.cancel();

    final tmp = await getTemporaryDirectory();
    // What the encode reads is made here; what it writes stays in the
    // cache folder, where the share sheets' file providers can reach it.
    // See [renderDir].
    final work = await renderDir();
    _checkCurrent(gen);
    final end = endAyah ?? ayahs.length;

    // A reel runs through several sceneries only when it was given
    // several *and* a timeline dividing them; anything less is the
    // single-background reel, which takes the path it always took.
    final multi = scenes.length > 1 && cuts.length == scenes.length;
    final fadeMs = multi ? ScenePlan.fadeMsFor(cuts, transition) : 0;

    // Segment of the recording covered by the chosen ayah range, up
    // to wherever the user cut it.
    // The basmala, when the reel opens on it: drawn as a unit of its
    // own before verse 1, which only the unit path does.
    final opening = startAyah == 1 && recitation.opensWithBasmala
        ? basmala
        : null;
    final segStartMs = opening != null
        ? recitation.startOf(startAyah)
        : recitation.timing(startAyah).startMs;
    final rangeEndMs = recitation.timing(end).endMs;
    final trimmed = trimEndMs != null && trimEndMs < rangeEndMs;
    final segEndMs = trimmed ? trimEndMs : rangeEndMs;
    final segMs = segEndMs - segStartMs;

    // A pale letterbox band turns every colour the verse card picks for
    // itself the other way round; see [isLightGround]. The watermark
    // used to ask this too, and no longer does — it sits on the card
    // now, which is scenery whatever the band is painted.
    final onLight = isLightGround(
      layout: layout,
      backdrop: backdrop,
      backdropArgb: backdropArgb,
    );
    // Surah is part of the key: without it, "surah 1 ayahs 1-3" and
    // "surah 2 ayahs 1-3" would collide and serve a stale reel. The
    // ground belongs here too, and not only in the layout key below:
    // this is what the rasterized cards are memoized on, so without it
    // a switch to a white backdrop would reuse the dark-halo PNGs.
    final rasterKey = 's${recitation.surah}_${startAyah}_$end'
        '_${textArgb.toRadixString(16)}_${accentArgb.toRadixString(16)}'
        '_${(textScale * 100).round()}'
        '_p${preset.index}_${typography.key}'
        '_e${(edition ?? QuranTextService.edition).code}'
        '_h${_highlightFingerprint(highlight)}'
        '${onLight ? '_lt' : ''}'
        // The recited word glows on a dark ground since 2026-10-21; a
        // reel with lit words cached before then is drawn again.
        '${!onLight && (highlight != null || motion.followsWords) ? '_gl' : ''}'
        // Only when set, so every reel cached before inks existed keeps
        // the key it was cached under. The bases alone would not tell
        // two inks that share one apart.
        '${verseInk.isNone ? '' : '_k${verseInk.key}'}'
        '${accentInk.isNone ? '' : '_ka${accentInk.key}'}'
        // Only when on, so every reel cached before numbering existed
        // keeps the key it was cached under.
        '${numbering == VerseNumbering.off ? '' : '_n${numbering.code}'}'
        // Only when off, for the same reason.
        '${showTranslation ? '' : '_t0'}'
        // Only when a verse is cut, or the verse moves, for the same
        // reason again.
        '${lines == null || lines.isEmpty ? '' : '_L${lines.fingerprint}'}'
        '${motion.isNone ? '' : '_M${motion.key}${_wordTimesFingerprint(wordTimes)}'}'
        // The light takes the accent's colour since 2026-10-21; a glint
        // cached in gold under another accent is drawn again.
        '${motion.light && !AyahOverlay.isHouseGold(AyahOverlay.lightTintOf(Color(accentArgb), accentInk)) ? '_gc' : ''}'
        '${motion.followsWords ? '_w${_highlightFingerprint(words)}' : ''}'
        // Opening on the basmala: a card more, and every verse later.
        '${opening != null ? '_bs${recitation.timings.first.endMs}' : ''}';
    // The letterbox card's shape, corners and backdrop all change the
    // finished picture, so they all belong in the key; full-frame
    // renders carry a single 'f' and are unaffected.
    final letterbox = layout == ReelLayout.letterbox
        ? LetterboxGeometry.of(sourceAspect)
        : null;
    final layoutKey = letterbox == null
        ? 'f'
        : 'l${letterbox.key}_${roundedCorners ? 'r' : 's'}_'
            '${_bandKey(backdrop, backdropArgb, bandGlow)}';
    // _v13: bump whenever the render pipeline or bundled background
    // assets change look, so stale cached reels aren't served.
    // (v3: AyahReel watermark added. v4: hardware encoder. v5: cropped
    // watermark + pre-flattened still backgrounds. v6: letterbox.
    // v7: verse card and watermark answer to a pale backdrop.
    // v8: the blurred backdrop is scaled down rather than subtracted
    // from, so the sceneries it used to clip to black now show.
    // v9: the watermark left the feed's caption UI — up the frame in
    // full frame, onto the card's bottom edge in letterbox.
    // v10: every export is checked for a decodable picture before it
    // is served, so the reels cached by builds that couldn't tell a
    // good encode from a silent-black one have to be re-rendered.
    // v11: reels can run through several sceneries, so the key carries
    // the whole run and its timeline rather than one background id.
    // v12: the full-frame mark hangs off the verse card's bottom edge
    // instead of the frame's, so it can no longer be cropped off the
    // bottom without taking the verse's last line with it.
    // v13: the picture can be graded, vignetted, grained and faded,
    // the card typeset in a chosen pair of faces, and — at last — the
    // translation's own edition is in the key, so the same passage in
    // German is no longer served the English render. Reels cached
    // before any of it existed are keyed as the neutral,
    // default-faced, English reels they are.)
    final sceneKey = multi
        ? 'm${scenes.length}_${_sceneFingerprint(scenes, cuts, fadeMs)}'
        : background.id;
    // How this phone's saves are planned, read once: the encode below
    // answers to it. The key answers to what lasts past this run (see
    // the `_lx` below).
    final planned = PhoneBudget.now;
    final leanKey = PhoneBudget.lasting.lean;
    final key = 'v13_${recitation.reciterId}_${sceneKey}_$layoutKey'
        '_${(overlayAlign * 100).round()}_${rasterKey}_fx${effects.key}'
        // A cut reel is a different file from the whole one, so it
        // cannot be allowed to answer to the same cache entry.
        '${trimmed ? '_c$segMs' : ''}'
        // A dedication is burned into the frame, so two reels that
        // differ only by who they were made for are two files. Absent
        // when there is none, which keeps every reel rendered before
        // this existed on the key it already has. `_gb` rather than the
        // `_g` it started as: the line moved from the mark to the
        // bottom of the frame, and only the dedicated reels — not
        // every cached reel — had to be rendered again for it.
        '${dedication.isEmpty ? '' : '_gb${dedication.hashCode.toUnsigned(32).toRadixString(36)}'}'
        // A line dragged off its place is a different file. Absent
        // when it was not, which keeps every dedicated reel rendered
        // before the line could move on its key.
        '${dedication.isEmpty || dedicationAt == null ? '' : '_at${(dedicationAt.dx * 1000).round()}_${(dedicationAt.dy * 1000).round()}'}'
        // Only when on, so every reel cached before the switch existed
        // keeps its key.
        '${highQuality ? '_hq' : ''}'
        // The surah's name, and where it was put. Absent without it, so
        // every reel rendered before the title existed keeps its key.
        '${surahTitle ? '_st${surahTitleAt == null ? '' : '${(surahTitleAt.dx * 1000).round()}_${(surahTitleAt.dy * 1000).round()}'}' : ''}'
        // And its size, once pinched from its own.
        '${surahTitle && (surahTitleScale * 100).round() != 100 ? '_sz${(surahTitleScale * 100).round()}' : ''}'
        // And its look, once it is not the one it always had.
        '${surahTitle && !surahTitleLook.isClassic ? '_tl${surahTitleLook.code}' : ''}'
        // A phone on the tightest budget encodes lean (see [leanX264]),
        // and the lean reels made before 2026-10-13 were too heavy to
        // play. Keyed as they were, a Save of the same reel would be
        // handed the old file again — from this cache, and from My
        // Reels, which keeps one entry per key and says the gallery
        // has it already. Every other phone keeps the key it had, one
        // planned tightest for this run only (an out-of-memory retry)
        // too: the next launch asks for it by that key. A reel from
        // before the ceiling found there is made again (see
        // [tooHeavyToPlay]).
        '${leanKey ? '_lx' : ''}';
    final out = File('${tmp.path}/ayah_reel_$key.mp4');
    // Where the reel goes if the phone is planned tightest for good by
    // the time it is done (a render-process death in this save): the
    // next Save asks for it by that key. Under [out] it was missed, and
    // the whole reel was encoded again for a second My Reels entry. A
    // step down for this run only stays under [out], which the next
    // launch asks for.
    final leanOut =
        leanKey ? out : File('${tmp.path}/ayah_reel_${key}_lx.mp4');
    // FFmpeg writes here; [out] is claimed by a rename once the result
    // has been checked, so the cache below can only ever see finished,
    // verified reels.
    //
    // In the render folder, not beside [out]: Android empties the cache
    // folder of a phone running short of room while the app runs, and
    // the encode is what makes it short. An encode whose file was
    // deleted under it still finishes "successfully" into the unlinked
    // file, and the check after it found nothing to open: "the rendered
    // reel has no picture" (a 3.6 GB phone's first save, 2026-10-06).
    // Both folders are on the app's own volume, so the rename at the
    // end is still a rename. The passes and the progress file are made
    // beside this, so they move with it.
    final part = File('${work.path}/${out.uri.pathSegments.last}.part');
    // One kept from before the ceiling is made again, not handed out.
    if (out.existsSync() && tooHeavyToPlay(out, segMs) && _remade.add(key)) {
      rlog('render: cached $key is too heavy to play — making it again');
      try {
        out.deleteSync();
      } catch (_) {}
    }
    if (out.existsSync() && out.lengthSync() > 0) {
      rlog('render: cache hit $key');
      // Used now, so it counts as the newest for [sweepCache].
      try {
        out.setLastModifiedSync(DateTime.now());
      } catch (_) {}
      onProgress?.call(1.0);
      return out; // cached from a previous Share/Save this session
    }
    rlog('render: start gen $gen key $key (${segMs}ms segment)');
    sweepCache(tmp, keep: out);
    if (work.path != tmp.path) sweepCache(work, keep: out);
    // Phase timing: without it there is no way to tell whether a slow
    // export is spending its time turning verses into PNGs or inside
    // FFmpeg, and the two have nothing in common to optimize.
    final clock = Stopwatch()..start();
    var prepMs = 0;

    // The grade the scenery is put through, as an FFmpeg chain. Empty
    // for every reel nobody has graded, which takes the two colour
    // filters out of the graph entirely rather than running a pair of
    // identity transforms over two million pixels a frame.
    //
    // It is spliced in wherever the *scenery* is read and nowhere
    // else: the scrim above it is legibility, a letterbox band is a
    // colour the user picked, and the verse is ink. None of those is
    // footage, and none of them is graded.
    final grade = effects.grade.ffmpeg;

    final audio = File(recitation.audioPath);
    // Resolved per scene below when the reel runs through several.
    final bg = multi
        ? null
        : background.isDeviceFile
            ? background.isImage
                ? await StillSource.readable(File(background.filePath!), work)
                : File(background.filePath!)
            : await _materializeAssetOrNull(background.assetPath, work);

    // The backdrop must be pixel-identical to the preview: a real
    // video/photo gets the preview's graduated scrim composited on
    // top; a gradient fallback uses the same Flutter-rendered gradient
    // the preview showed (scrim baked in).
    //
    // A still backdrop produces the same base frame every time, so the
    // scale, the crop and the scrim composite are folded into one
    // 1080x1920 PNG here instead of being recomputed for all 2700-odd
    // frames of the encode. [bgReady] says the graph can use input 0
    // untouched.
    final hasRealBg = bg != null && bg.existsSync();
    // A luminous band is one picture for the whole reel, drawn by the
    // painter the preview draws it with.
    final bandPath = letterbox != null && backdrop == LetterboxBackdrop.glow
        ? (await AyahRasterizer.rasterizeBandGlow(bandGlow, letterbox)).path
        : null;
    // Not final: a run of stills has its scenes folded into finished
    // base frames below, which replaces the first of them.
    String bgPath;
    bool bgIsImage;
    String? scrimPath;
    String? maskPath;
    var bgReady = false;
    List<_SceneInput>? sceneInputs;
    if (multi) {
      // Nothing here can be folded into a single still: the base frame
      // is a different picture on either side of every cut. So the
      // scrim and the card mask ride the graph, and the flattening
      // below — all of it an optimization for a reel whose backdrop
      // never changes — is skipped.
      sceneInputs = await _resolveScenes(scenes, cuts, fadeMs, work);
      bgPath = sceneInputs.first.path;
      bgIsImage = sceneInputs.first.isImage;
      if (letterbox != null) {
        if (roundedCorners) {
          maskPath = (await AyahRasterizer.rasterizeCardMask(
            width: letterbox.cardW,
            height: letterbox.cardH,
            radius: LetterboxGeometry.radius,
          ))
              .path;
        }
      } else {
        // One scrim over the whole reel rather than one per scene: it
        // is the same darkening whatever is underneath it, so it goes
        // on after the scenes are joined.
        final scrim =
            (await AyahRasterizer.rasterizeScrim(vignette: effects.vignette))
                .path;
        // Unless every scene is a still, in which case each of them
        // folds into a finished base frame here — scale, crop and
        // scrim baked once — exactly as a single still background
        // already does.
        //
        // This used to be skipped for a run of sceneries on the
        // grounds that "the base frame is a different picture on
        // either side of every cut", which is true and beside the
        // point: it is a different picture, but each of them is still
        // the *same* picture for every frame it is on screen. Leaving
        // it out meant a five-scene reel scaled, cropped and scrimmed
        // 1080x1920 on every one of its thousand frames, work a
        // one-scene reel does exactly five times. Measured on a
        // 35-second reel: 71.8s of encode against 41.3s for the same
        // reel on one still — three quarters of the difference, and
        // all of it work already done.
        //
        // Baking the scrim per scene rather than over the join is the
        // same picture: the scrim is one fixed composite and a
        // crossfade is a linear blend, so blending two scrimmed
        // frames and scrimming a blend give the same pixels.
        //
        // All or nothing. A run with a video in it keeps the path it
        // had — half the scenes pre-scrimmed and half not would
        // double-darken the stills or leave the clips bare.
        final flat = sceneInputs.every((s) => s.isImage)
            ? await _flattenScenes(sceneInputs, scrim, work, grade)
            : null;
        if (flat != null) {
          sceneInputs = flat;
          bgPath = flat.first.path;
          bgIsImage = true;
        } else {
          scrimPath = scrim;
        }
      }
    } else if (letterbox != null) {
      // Letterbox keeps the scenery inside a card, so the full-frame
      // scrim has no place here: nothing needs darkening for the verse
      // to read, because the verse sits on the backdrop rather than on
      // the picture. The card is what gets prepared instead.
      if (roundedCorners) {
        maskPath = (await AyahRasterizer.rasterizeCardMask(
          width: letterbox.cardW,
          height: letterbox.cardH,
          radius: LetterboxGeometry.radius,
        ))
            .path;
      }
      final source = hasRealBg
          ? bg
          : await AyahRasterizer.rasterizeGradientBackdrop(
              background.gradientArgb,
              withScrim: false,
            );
      final still = hasRealBg ? background.isImage : true;
      if (still) {
        // Every frame of a still-sourced letterbox reel has the same
        // backdrop and the same card, so the whole base frame is folded
        // into one PNG here rather than recomposited 2700 times.
        final flat = await _flattenLetterbox(
          source,
          letterbox,
          maskPath,
          backdrop,
          backdropArgb,
          work,
          grade,
          bandGlow: bandGlow,
          bandPath: bandPath,
        );
        bgIsImage = true;
        if (flat != null) {
          bgPath = flat.path;
          bgReady = true;
        } else {
          bgPath = source.path; // per-frame graph is still correct
        }
      } else {
        bgPath = source.path;
        bgIsImage = false;
      }
    } else if (hasRealBg && !background.isImage) {
      bgPath = bg.path; // video: the scrim has to ride every frame
      bgIsImage = false;
      scrimPath =
          (await AyahRasterizer.rasterizeScrim(vignette: effects.vignette))
              .path;
    } else if (hasRealBg) {
      final scrim =
          (await AyahRasterizer.rasterizeScrim(vignette: effects.vignette))
              .path;
      final flat = await _flattenStill(bg, scrim, work, grade);
      bgIsImage = true;
      if (flat != null) {
        bgPath = flat.path;
        scrimPath = null;
        bgReady = true;
      } else {
        // Flatten failed: the per-frame graph is still correct.
        bgPath = bg.path;
        scrimPath = scrim;
      }
    } else {
      // Gradient backdrop: already exactly 1080x1920 with the scrim
      // baked in by the rasterizer, so it needs no preparation at all.
      // The gradient is the bottom of the picture, and both previews
      // grade it, so this does too — baked in here rather than left to
      // the filtergraph, because this PNG is the finished base frame
      // and the graph reads it untouched.
      bgPath = (await AyahRasterizer.rasterizeGradientBackdrop(
              background.gradientArgb,
              vignette: effects.vignette,
              grade: effects.grade.filters))
          .path;
      bgIsImage = true;
      scrimPath = null;
      bgReady = true;
    }
    // Letterbox has no scrim to paint a vignette into — the verse sits
    // on a band rather than on the picture, so nothing is darkened for
    // it — so this is the one format that needs a layer of its own.
    // Full frame never reaches here: there the vignette rides the
    // scrim, which is one PNG that was already being composited, and
    // costs the encode nothing.
    //
    // Over the whole frame rather than over the card, because that is
    // what a vignette is: light falling off at the corners of a film
    // frame does not stop at the edge of the photograph inside it.
    //
    // Laid per frame even where the base was pre-flattened. Baking it
    // into the flatten would be free, and it is not worth the second
    // way of doing this: the flatten is an optimization that is
    // allowed to fail, and a vignette that quietly vanished whenever
    // it did would be a bug nobody could reproduce.
    final vignettePath = effects.vignette > 0 && letterbox != null
        ? (await AyahRasterizer.rasterizeVignette(effects.vignette)).path
        : null;

    // The mark's ground is scenery in both formats — full frame's
    // picture under the scrim, or the letterbox card, which has none.
    // It is the scrim's absence it answers to, not the band's colour.
    final wmPath =
        (await AyahRasterizer.rasterizeWatermark(undimmed: letterbox != null))
            .path;
    // The dedication lands on the bottom of the frame, which in
    // letterbox is the band — so, unlike the mark, it does answer to
    // the band's colour. Unless it was dragged up onto the card, which
    // is scenery whatever the band is painted.
    final dedPath = dedication.isEmpty
        ? null
        : (await AyahRasterizer.rasterizeDedication(dedication,
                onLight: ReelDedication.onLightAt(dedicationAt,
                    onLightGround: onLight, letterbox: letterbox)))
            .path;
    _checkCurrent(gen);

    List<_OverlayClip> clips;
    // Only for a reel whose verses are cut into lines or move: every
    // other reel takes the path below exactly as it always has.
    var shows = const <_UnitShow>[];
    final byUnits = (lines != null && !lines.isEmpty) ||
        !motion.isNone ||
        opening != null;
    var fromMemo = false;
    // The memo holds clips, and a clip is a card *and* the moment it
    // shows: the same verses and styling read by another voice (or by
    // the user's own recording, timed again) are the same cards at other
    // times. So the memo answers to the timings too; the cards' files
    // stay named by [rasterKey] alone, and are drawn again only when the
    // styling changes.
    final memoKey = '$rasterKey|${recitation.reciterId}'
        '|${_timingFingerprint(recitation, startAyah, end)}';
    if (_rasterMemoKey == memoKey &&
        _rasterMemoClips.every((c) => c.file.existsSync()) &&
        _rasterMemoShows.every((u) => u.glint?.existsSync() ?? true)) {
      clips = _rasterMemoClips; // e.g. only the background changed
      shows = _rasterMemoShows;
      fromMemo = true;
    } else if (byUnits) {
      final tag = '${rasterKey.hashCode.toRadixString(16)}_';
      final showPrep = segMs > RenderPlan.singlePassMaxMs;
      PhoneBudget.exportStage('cards');
      final built = await _unitCards(
        recitation: recitation,
        ayahs: ayahs,
        startAyah: startAyah,
        endAyah: end,
        lines: lines,
        motion: motion,
        highlight: highlight,
        words: words,
        wordTimes: wordTimes,
        basmala: opening,
        keepGoing: () => gen == _generation,
        onUnit: showPrep && onProgress != null
            ? (v) => onProgress(v * _prepShare)
            : null,
        draw: (ayah, part, name,
                {lit, dim, glint = false, measure = false, bare = false}) =>
            AyahRasterizer.rasterizeUnit(
              ayah,
              part: part,
              name: name,
              highlight: lit,
              dimFrom: dim,
              glint: glint,
              measure: measure,
              textColor: Color(textArgb),
              accent: Color(accentArgb),
              ink: verseInk,
              accentInk: accentInk,
              textScale: textScale,
              preset: preset,
              onLight: onLight,
              typography: typography,
              edition: edition,
              numbering: bare ? VerseNumbering.off : numbering,
              showTranslation: showTranslation,
              surah: recitation.surah,
              fileTag: bare ? '${tag}b_' : tag,
            ),
      );
      _checkCurrent(gen);
      clips = built.clips;
      shows = built.shows;
      _rasterMemoKey = memoKey;
      _rasterMemoClips = clips;
      _rasterMemoShows = shows;
    } else {
      final tag = '${rasterKey.hashCode.toRadixString(16)}_';
      // Hundreds of cards is a real wait; a few is over before it
      // could be drawn. So the bar only moves for a reel long enough
      // for the wait to be visible — the short ones keep the progress
      // they have always shown, which is the encode's own.
      final showPrep = segMs > RenderPlan.singlePassMaxMs;
      PhoneBudget.exportStage('cards');
      final cards = await AyahRasterizer.rasterize(
        ayahs.sublist(startAyah - 1, end),
        textColor: Color(textArgb),
        accent: Color(accentArgb),
        ink: verseInk,
        accentInk: accentInk,
        textScale: textScale,
        preset: preset,
        onLight: onLight,
        typography: typography,
        edition: edition,
        numbering: numbering,
        showTranslation: showTranslation,
        surah: recitation.surah,
        fileTag: tag,
        onProgress: showPrep && onProgress != null
            ? (v) => onProgress(v * _prepShare)
            : null,
        keepGoing: () => gen == _generation,
      );
      _checkCurrent(gen);
      clips = <_OverlayClip>[];
      for (var i = 0; i < cards.length; i++) {
        final t = recitation.timing(startAyah + i);
        final cardH = cards[i].height;
        final file = cards[i].file;
        final spans = highlight?[t.ayah];
        if (spans == null || spans.isEmpty) {
          clips.add(_OverlayClip(file, t.startMs, t.endMs, cardH));
          continue;
        }
        // Base card until the first word lights up, then one clip per
        // word window (windows are pre-gap-filled, so together they
        // tile the ayah exactly — nothing ever draws stacked).
        if (spans.first.startMs > 0) {
          clips.add(_OverlayClip(
              file, t.startMs, t.startMs + spans.first.startMs, cardH));
        }
        for (final h in spans) {
          final f = await AyahRasterizer.rasterizeHighlight(
            ayahs[startAyah - 1 + i],
            tokenStart: h.tokenStart,
            tokenEnd: h.tokenEnd,
            textColor: Color(textArgb),
            accent: Color(accentArgb),
            ink: verseInk,
            accentInk: accentInk,
            textScale: textScale,
            preset: preset,
            onLight: onLight,
            typography: typography,
            edition: edition,
            numbering: numbering,
            showTranslation: showTranslation,
            surah: recitation.surah,
            fileTag: tag,
          );
          // Same card, lit differently — so the same height.
          clips.add(_OverlayClip(
              f, t.startMs + h.startMs, t.startMs + h.endMs, cardH));
          _checkCurrent(gen);
        }
      }
      _rasterMemoKey = memoKey;
      _rasterMemoClips = clips;
      _rasterMemoShows = const [];
    }
    // The cut comes off after the memo, not before it: the cards past
    // it belong to the selection and are worth keeping for the render
    // of the whole thing; this reel just never reaches them.
    if (trimmed) {
      clips = [for (final c in clips) if (c.startMs < segEndMs) c];
      shows = [for (final u in shows) if (u.startMs < segEndMs) u];
    }
    // What rides on the cards: the thread's strip and its spark, drawn
    // in the reel's accent. Only when the motion has a thread.
    final threadPath = motion.thread && shows.isNotEmpty
        ? (await AyahRasterizer.rasterizeThreadStrip(accentArgb)).path
        : null;
    final sparkPath = motion.thread && shows.isNotEmpty
        ? (await AyahRasterizer.rasterizeSpark(accentArgb)).path
        : null;
    // The surah's name, on the ground its centre lands on: the band of
    // a pale letterbox flips its ink, the card does not.
    final titleCentre =
        surahTitleAt ?? ReelSurahTitle.defaultCentre(letterbox);
    final titlePath = surahTitle
        ? (await AyahRasterizer.rasterizeSurahTitle(recitation.surah,
                edition: edition ?? QuranTextService.edition,
                onLight: ReelDedication.onLightAt(titleCentre,
                    onLightGround: onLight, letterbox: letterbox),
                scale: surahTitleScale,
                look: surahTitleLook))
            .path
        : null;
    _checkCurrent(gen);
    prepMs = clock.elapsedMilliseconds;
    rlog('render: ${clips.length} overlays ready in ${prepMs}ms '
        '(${fromMemo ? "memo" : "rasterized"}), launching ffmpeg');

    // Only one encode ever runs, so the eager render has to leave the
    // preview enough CPU to keep playing. An export the user is
    // watching a progress bar for has no such obligation.
    // And a phone short of memory gets fewer of them, and smaller
    // passes, from its very first encode; see [ExportBudget].
    var budget = planned;
    _lean = budget.lean;
    PhoneBudget.exportPlanned(budget);
    // Read per encode: an eager render the user then taps Save on is
    // waited on from that pass on ([promote]).
    int threads() =>
        (foreground || _promoted == gen
                ? Platform.numberOfProcessors.clamp(2, 16)
                : (Platform.numberOfProcessors - 2).clamp(2, 6))
            .clamp(2, _threadsFor(budget));
    var sceneThreads = _sceneThreadsFor(budget);

    // The probe wants a full-size still with even dimensions: the scrim
    // when there is one, otherwise a flattened backdrop is itself a
    // 1080x1920 PNG. A letterbox render over video has neither, so it
    // falls back to the scrim — cached, and this is the only thing that
    // still asks for it. (Not the watermark any more, and not a verse
    // card: those PNGs are cropped to their content.)
    final probeSrc = scrimPath ??
        (bgReady
            ? bgPath
            : (await AyahRasterizer.rasterizeScrim(vignette: effects.vignette))
                .path);
    // A phone whose saves have died in the device encoder doesn't use
    // it again (see [PhoneBudget.hardwareTrusted]); the picture check
    // the hardware probe would have set up is still wanted for x264.
    final trusted = PhoneBudget.hardwareTrusted;
    if (!trusted) {
      rlog('render: a save died in the hardware encoder here — x264 only');
      await _pictureCheckWorks(probeSrc, work);
    }
    // The probe runs the device encoder in the app's own process, the
    // one encode that does: a vendor encoder that crashes there takes
    // the app with it, and the next launch has to know it was the
    // encoder (counted as a hardware loss, see [PhoneBudget.load])
    // rather than the cards drawn before it.
    final probing = trusted && _hwOk == null;
    if (probing) PhoneBudget.exportStage('hardware probe');
    var hardware = trusted && await _hardwareEncoderWorks(probeSrc, work);
    // Past the probe: a death from here to the first encode is not the
    // device encoder's.
    if (probing) PhoneBudget.exportStage('planning');
    _checkCurrent(gen);

    // Where the picture may be cut in two, which is what decides how a
    // long reel is divided into passes. One span per scenery, or one
    // for the whole reel when it runs on a single background.
    final spans = <PictureSpan>[];
    if (sceneInputs != null) {
      for (var i = 0; i < sceneInputs.length && i < cuts.length; i++) {
        spans.add(PictureSpan(
          startMs: cuts[i].startMs,
          endMs: cuts[i].endMs,
          isImage: sceneInputs[i].isImage,
          sourceMs: sceneInputs[i].sourceMs,
          needsMs:
              cuts[i].durationMs + (i == sceneInputs.length - 1 ? 0 : fadeMs),
        ));
      }
    } else {
      spans.add(PictureSpan(
        startMs: segStartMs,
        endMs: segEndMs,
        isImage: bgIsImage,
        sourceMs: bgIsImage ? null : await MediaDuration.ofPath(bgPath),
      ));
    }
    _checkCurrent(gen);
    List<RenderPass> planPasses({int? maxClips}) => RenderPlan.of(
          segStartMs: segStartMs,
          segEndMs: segEndMs,
          spans: spans,
          // A unit's glint card is an input like any card, held for the
          // whole pass, so it counts against the pass's budget as one.
          clips: [
            for (final c in clips) (startMs: c.startMs, endMs: c.endMs),
            for (final u in shows)
              if (u.glint != null) (startMs: u.startMs, endMs: u.endMs),
          ]..sort((a, b) => a.startMs.compareTo(b.startMs)),
          fadeMs: fadeMs,
          maxClips: maxClips,
        );
    var passes = planPasses(maxClips: _clipsFor(budget));
    var chunked = passes.length > 1;
    if (chunked) {
      rlog('render: ${passes.length} passes over ${segMs}ms '
          '(${clips.length} overlays), ${budget.name} budget');
    }

    String cmdFor(bool hw) => _buildCommand(
          audioPath: audio.path,
          bgPath: bgPath,
          bgIsImage: bgIsImage,
          bgReady: bgReady,
          sceneInputs: sceneInputs,
          cuts: cuts,
          fadeMs: fadeMs,
          scrimPath: scrimPath,
          maskPath: maskPath,
          vignettePath: vignettePath,
          watermarkPath: wmPath,
          dedicationPath: dedPath,
          dedicationAt: dedicationAt,
          clips: clips,
          motion: motion,
          shows: shows,
          threadPath: threadPath,
          sparkPath: sparkPath,
          titlePath: titlePath,
          titleAt: titleCentre,
          segStartMs: segStartMs,
          segMs: segMs,
          overlayAlign: overlayAlign,
          letterbox: letterbox,
          backdrop: backdrop,
          backdropArgb: backdropArgb,
          bandPath: bandPath,
          grade: grade,
          effects: effects,
          outPath: part.path,
          hardware: hw,
          threads: threads(),
          sceneThreads: sceneThreads,
          reelMs: segMs,
          highQuality: highQuality,
          small: budget.small,
        );

    // The picture-only files a chunked render leaves behind between the
    // passes and the join.
    final passParts = <File>[];
    void dropPassParts() {
      for (final f in passParts) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
      passParts.clear();
    }

    /// Encodes the whole reel and leaves it at [part].
    ///
    /// One FFmpeg run for a reel the old cap would have allowed — the
    /// path this has always taken, unchanged. A longer one is encoded a
    /// pass at a time, picture only, and the passes are joined with a
    /// stream copy while the recitation is laid over the join in one
    /// piece: no frame is encoded twice, and the audio never meets a
    /// seam it could click at.
    Future<EncodeRun?> encode(bool hw) async {
      if (!chunked) {
        PhoneBudget.exportStage(
            '${clips.length} cards in one pass${hw ? ', hardware' : ''}');
        return _runEncode(
          cmd: cmdFor(hw),
          gen: gen,
          segMs: segMs,
          dest: part,
          stallLimit: hw ? _hwStallLimit : null,
          onProgress: onProgress,
        );
      }
      dropPassParts();
      var doneMs = 0;
      for (var i = 0; i < passes.length; i++) {
        final p = passes[i];
        final pf = File('${part.path}.p$i.mp4');
        if (pf.existsSync()) pf.deleteSync();
        passParts.add(pf);
        final pClips = _clipsIn(clips, p);
        PhoneBudget.exportStage('pass ${i + 1}/${passes.length}, '
            '${pClips.length} cards${hw ? ', hardware' : ''}');
        final pScenes = sceneInputs == null
            ? null
            : _scenesIn(sceneInputs, cuts, fadeMs, p);
        final at = doneMs;
        final failed = await _runEncode(
          cmd: _buildCommand(
            audioPath: null,
            bgPath: bgPath,
            bgIsImage: bgIsImage,
            bgReady: bgReady,
            sceneInputs: pScenes?.scenes,
            cuts: pScenes?.cuts ?? const [],
            fadeMs: fadeMs,
            scrimPath: scrimPath,
            maskPath: maskPath,
            vignettePath: vignettePath,
            watermarkPath: wmPath,
            dedicationPath: dedPath,
            dedicationAt: dedicationAt,
            clips: pClips,
            motion: motion,
            shows: shows,
            threadPath: threadPath,
            sparkPath: sparkPath,
            titlePath: titlePath,
            titleAt: titleCentre,
            segStartMs: p.startMs,
            segMs: p.durationMs,
            overlayAlign: overlayAlign,
            letterbox: letterbox,
            backdrop: backdrop,
            backdropArgb: backdropArgb,
            bandPath: bandPath,
            grade: grade,
            effects: effects,
            // Where this pass sits in the whole reel, which is the
            // only thing the fade needs that the pass itself does not
            // know: a reel fades out at its own end, not at the end of
            // whichever slice of it is being encoded.
            passStartMs: p.startMs - segStartMs,
            outPath: pf.path,
            hardware: hw,
            threads: threads(),
            sceneThreads: sceneThreads,
            reelMs: segMs,
            highQuality: highQuality,
            small: budget.small,
            frames: p.frames,
            bgSeekS: sceneInputs != null || bgIsImage
                ? 0
                : _bgSeekFor(spans.first, p),
          ),
          gen: gen,
          segMs: p.durationMs,
          dest: pf,
          stallLimit: hw ? _hwStallLimit : null,
          onProgress: onProgress == null
              ? null
              : (v) => onProgress((_prepShare +
                      (at + v * p.durationMs) /
                          segMs *
                          (_joinShare - _prepShare))
                  .clamp(0.0, _joinShare)),
        );
        if (failed != null) return failed;
        doneMs += p.durationMs;
        _checkCurrent(gen);
      }
      // Join, and lay the recitation over the whole of it. A stream
      // copy: every pass was encoded with the same settings at the same
      // size, so the joined track is the passes themselves.
      PhoneBudget.exportStage('join');
      final joined = await _joinPasses(
        parts: passParts,
        audioPath: audio.path,
        segStartMs: segStartMs,
        segMs: segMs,
        dest: part,
        gen: gen,
        copyVideo: true,
        high: highQuality,
        threads: threads(),
        onProgress: onProgress,
      );
      if (joined == null) return null;
      // A copy the muxer refused (a device encoder that changed its
      // parameters between passes would do it) is worth one honest
      // re-encode rather than a failed export.
      if (gen != _generation) return joined;
      rlog('render: stream-copy join refused — re-encoding the join');
      return _joinPasses(
        parts: passParts,
        audioPath: audio.path,
        segStartMs: segStartMs,
        segMs: segMs,
        dest: part,
        gen: gen,
        copyVideo: false,
        high: highQuality,
        threads: threads(),
        onProgress: onProgress,
      );
    }

    EncodeRun? failure;
    var unplayable = false;
    try {
      failure = await encode(hardware);

      // A device whose encoder passed the probe can still refuse the
      // real thing (unsupported option, muxer quirk, encoder busy), and
      // it can do worse: return success over a track that plays as
      // black. Both retire hardware for the rest of the process and redo
      // the encode on x264 — the reference path, always verified against
      // a decoder before it is trusted — rather than hand the user a
      // failed export or a silent one.
      if (failure == null && hardware && _verifyOk == true) {
        unplayable = !await _decodesToPicture(part, work);
        if (unplayable && part.existsSync()) part.deleteSync();
      }
      // A hardware encode left running still holds its whole graph. On
      // a phone already planned short of memory, an x264 redo beside it
      // would ask for all of that a second time, and the system kills
      // the app for it — the very loss the budget is there to prevent.
      // Hardware is retired, so the next try is x264 alone.
      if (failure != null &&
          _abandoned[failure] == true &&
          budget != ExportBudget.roomy) {
        _hwOk = false;
        rlog('render: stalled hardware encode left running on a '
            '${budget.name} budget — not redoing beside it');
        throw const RenderFailed(
            RenderFailure.other, 'the video encoder stopped responding');
      }
      // Except for want of room: x264 would write the same bytes onto
      // the same full disk, after making the user wait for it again.
      if ((failure != null || unplayable) &&
          hardware &&
          !(failure != null && await _outOfSpace(failure))) {
        rlog('render: hardware encode unusable '
            '(${failure != null ? "failed" : "no picture"}) — redoing on libx264');
        hardware = false;
        unplayable = false;
        failure = await encode(false);
        // Retired for the session only when the reference encoder then
        // managed the same reel: a graph or an input that fails both
        // ways says nothing against the hardware, and every later save
        // would have run slower for it.
        if (failure == null) _hwOk = false;
      }

      // Out of memory is not out of luck: the graph holds one decoded
      // card per overlay for the whole pass, so the same reel cut into
      // smaller pieces asks for a fraction of what this one did. Every
      // frame is still encoded exactly once — the pieces are joined
      // with a stream copy — so the retry costs launches, not quality.
      // Fewer threads go with it, each of which held frames of its own.
      // Down to the smallest budget if need be, a step per death: one
      // step and then a failure left a phone whose tightest encode died
      // with no reel at all, at every Save (2026-10-15: "tightest, 7
      // lost, 5 survived … the render process died during the encode").
      while (failure != null && await _outOfMemory(failure)) {
        final next = budget.tighter;
        if (next == budget) break;
        final tighter = planPasses(maxClips: _clipsFor(next));
        rlog('render: out of memory on ${passes.length} pass(es) — '
            'retrying on ${tighter.length}, ${next.name} budget');
        PhoneBudget.outOfMemory(budget);
        budget = next;
        _lean = budget.lean;
        PhoneBudget.exportPlanned(budget);
        passes = tighter;
        chunked = passes.length > 1;
        sceneThreads = _sceneThreadsFor(next);
        failure = await encode(hardware);
      }
    } finally {
      dropPassParts();
    }

    if (failure != null) {
      final logs = await _logsOf(failure);
      final tail = logs.isEmpty
          ? 'no logs'
          : logs.substring(logs.length < 600 ? 0 : logs.length - 600);
      final oom = await _outOfMemory(failure);
      final full = !oom && await _outOfSpace(failure);
      rlog('render: FFMPEG FAILED${oom ? " (out of memory)" : ""}'
          '${full ? " (out of space)" : ""}\n$tail');
      // The log tail goes to the debug log, never to the user: FFmpeg's
      // last 600 characters are unreadable to anyone who did not write
      // this file, and a phone that ran out of room deserves a sentence
      // saying what to do about it.
      throw RenderFailed(
          oom
              ? RenderFailure.outOfMemory
              : full
                  ? RenderFailure.noSpace
                  : RenderFailure.other,
          tail);
    }
    // x264 is the encoder every other path falls back to, so a picture
    // it can't produce is a bug in the graph rather than a device
    // quirk to route around: reported, not silently re-encoded.
    _ensureLanded(part);
    if (!hardware && _verifyOk == true && !await _decodesToPicture(part, work)) {
      if (part.existsSync()) part.deleteSync();
      rlog('render: x264 output has no decodable picture');
      throw const RenderFailed(
          RenderFailure.other, 'the rendered reel has no picture');
    }
    // Superseded while the result was being checked: the .part file
    // belongs to the render that replaced this one now, so claiming
    // [out] with it would publish a file still being written.
    _checkCurrent(gen);
    // Only now does the file take the name the cache reads: a render
    // killed with the app (low memory, force quit) leaves a
    // half-written .part behind rather than a truncated mp4 that every
    // later export would serve as a finished reel.
    final made = budget.lean && PhoneBudget.lasting.lean ? leanOut : out;
    _claim(part, made);
    rlog('render: done gen $gen -> ${made.path} '
        '(${(made.lengthSync() / 1024).round()} KB, '
        '${hardware ? "hardware" : "x264"}, ${budget.name}) — '
        'prep ${prepMs}ms + encode ${clock.elapsedMilliseconds - prepMs}ms '
        '= ${clock.elapsedMilliseconds}ms for a ${segMs}ms reel');
    return made;
  }

  /// Whether [session] died for want of memory rather than for a
  /// reason another encoder or another try would fix.
  ///
  /// Read off the logs because that is where it is said: FFmpeg exits
  /// with the same code for a graph it could not allocate as for a
  /// file it could not open. Each of these is one library's way of
  /// reporting the same ENOMEM — libav's strerror, x264's own
  /// allocator, and the message the filter chain prints when a frame
  /// never arrived.
  static Future<bool> _outOfMemory(EncodeRun session) async {
    // A render process that died under the encode is taken for one
    // the system killed for memory: the retry plans smaller, which is
    // also the answer if it was the encoder that crashed.
    if (session.died) return true;
    final logs = (await _logsOf(session)).toLowerCase();
    return logs.contains('cannot allocate memory') ||
        logs.contains('out of memory') ||
        logs.contains('enomem') ||
        logs.contains('malloc of size') ||
        logs.contains('unable to allocate');
  }

  /// Whether [session] died because the disk filled up: FFmpeg prints
  /// the OS's own words for it, on the write that failed.
  static Future<bool> _outOfSpace(EncodeRun session) async =>
      saysOutOfSpace(await _logsOf(session));

  static final _logs = Expando<String>();

  /// [session]'s whole log, fetched from native once and kept. A failed
  /// encode is asked about its log up to four times — out of space, out
  /// of memory, the tail for the debug log — and every fetch encodes the
  /// entire log as one string on the main thread to send it across.
  /// Empty if it can't be read.
  static Future<String> _logsOf(EncodeRun session) async {
    final kept = _logs[session];
    if (kept != null) return kept;
    if (_abandoned[session] == true) return _logs[session] = '';
    return _logs[session] = await session.logs();
  }

  /// Runs one encode to completion. Returns null on success, or the
  /// finished session on failure so the caller can choose between
  /// retrying on another encoder and surfacing the error. Throws
  /// [RenderCancelled] if this render is superseded at any point.
  static Future<EncodeRun?> _runEncode({
    required String cmd,
    required int gen,
    required int segMs,
    required File dest,
    Duration? stallLimit,
    void Function(double progress)? onProgress,
  }) async {
    // The progress file is also how a stall is seen, so an encode with
    // a [stallLimit] writes one whether or not anybody draws a bar.
    final progress = onProgress == null && stallLimit == null
        ? null
        : FfmpegProgressFile.beside(dest);
    try {
      return await _encodeOnce(
          cmd: cmd,
          gen: gen,
          segMs: segMs,
          dest: dest,
          progress: progress,
          stallLimit: stallLimit,
          onProgress: onProgress);
    } on _ProgressRefused {
      rlog('render: FFmpeg refused the progress file — encoding without');
      return _encodeOnce(cmd: cmd, gen: gen, segMs: segMs, dest: dest);
    } finally {
      progress?.delete();
    }
  }

  /// [stallLimit], when given, is how long the encode may go without
  /// writing a frame: past it the session is cancelled and comes back
  /// as a failure, which the caller answers on another encoder. It
  /// needs [progress] to see frames by, and does nothing without it.
  static Future<EncodeRun?> _encodeOnce({
    required String cmd,
    required int gen,
    required int segMs,
    required File dest,
    FfmpegProgressFile? progress,
    Duration? stallLimit,
    void Function(double progress)? onProgress,
  }) async {
    final departures = OnScreen.departures;
    // Already away as it starts: a pass begun with the app out of sight,
    // whose trip away was counted before this encode existed.
    final awayAtStart = OnScreen.away;
    // Progress comes off a file, not FFmpegKit's statistics events:
    // see FfmpegProgressFile for why those are switched off. The file
    // is also what makes the render process's progress the app's.
    final session = await _start('${progress?.arg ?? ''}$cmd', gen);
    rlog('render: ffmpeg ${session.name} running (gen $gen)');
    if (gen != _generation) {
      // Canceled while the session was launching: kill it here, since
      // cancelActive() ran before it had an id to cancel.
      rlog('render: gen $gen superseded during launch — killing session');
      await session.cancel();
      throw const RenderCancelled();
    }
    _active = session;

    // The encode starts and returns at once; wait for it to finish.
    var code = await session.returnCode();
    // Time since the encode last wrote a frame, and since it was given
    // up on for not writing any.
    final quiet = Stopwatch()..start();
    Stopwatch? givenUp;
    // Time since the last look, to tell a freeze from a stall.
    final tick = Stopwatch()..start();
    var lastMs = -1;
    // A wedged remote encode whose process has been ended.
    var ended = false;
    while (code == null) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (tick.elapsed > _frozenGap) {
        rlog('render: app was frozen for ${tick.elapsed.inSeconds}s '
            'mid-encode — stall clock restarted');
        quiet.reset();
        givenUp?.reset();
      }
      tick.reset();
      if (gen != _generation) {
        rlog('render: gen $gen superseded mid-encode — killing session');
        await session.cancel();
        // Never leave a half-written file where the cache check would
        // serve it as a finished reel.
        if (dest.existsSync()) dest.deleteSync();
        throw const RenderCancelled();
      }
      final t = progress?.readMs();
      if (t != null && t > 0 && onProgress != null) {
        onProgress((t / segMs).clamp(0.0, 1.0));
      }
      if (t != null && t != lastMs) {
        lastMs = t;
        quiet.reset();
      }
      if (stallLimit != null &&
          progress != null &&
          givenUp == null &&
          quiet.elapsed > stallLimit) {
        rlogError('render: encode',
            'no frame written in ${stallLimit.inSeconds}s — encoder stalled');
        givenUp = Stopwatch()..start();
        await session.cancel();
      }
      code = await session.returnCode();
      // Cancelled and still not over: wedged inside the device encoder,
      // where a cancel may never reach it. In the render process the
      // process is ended with it, which frees what it held, and the
      // next look finds the encode dead. In the app it is left behind,
      // and marked, so nothing asks it for its log and the caller knows
      // its memory is still taken.
      if (code == null && givenUp != null && givenUp.elapsed > _cancelGrace) {
        if (session is RemoteRun && !ended) {
          ended = await RenderProcess.kill();
          if (ended) {
            rlogError('render: encode',
                'stalled encode ended with its render process');
            continue;
          }
        }
        if (!ended || givenUp.elapsed > _cancelGrace * 2) {
          rlogError('render: encode',
              'stalled encode still running ${_cancelGrace.inSeconds}s after '
              'its cancel — left behind');
          _abandoned[session] = true;
          break;
        }
      }
    }
    if (identical(_active, session)) _active = null;

    if (code == null || !ReturnCode.isSuccess(code)) {
      Future<EncodeRun?> again() => _encodeOnce(
          cmd: cmd,
          gen: gen,
          segMs: segMs,
          dest: dest,
          progress: progress,
          stallLimit: stallLimit,
          onProgress: onProgress);
      if (dest.existsSync()) dest.deleteSync();
      if (gen != _generation) {
        rlog('render: gen $gen canceled (ffmpeg code ${code?.getValue()})');
        throw const RenderCancelled();
      }
      // The render process couldn't run FFmpeg at all: the app does,
      // as it always had, and leaves the render process alone after.
      if (session is RemoteRun && session.unavailable) {
        RenderProcess.noteUnavailable(await session.logs());
        return again();
      }
      // Reclaimed with the app out of sight, not killed for what the
      // encode asked: Android ends a background app's processes on any
      // phone, the render process first, and Android Go phones within
      // moments. 2026-10-14: an Infinix Go phone (1.0.9) lost a save as
      // "out of memory" after its owner left the slow save running; its
      // note counted no death, so every encode that died there died with
      // the app away. A smaller budget or x264 would fare no better, so
      // the same encode runs again once the app is back, and the phone's
      // record stays as it was. No limit: each run again needs its
      // owner to leave and come back.
      // Android's own record of the death, where it keeps one, says
      // whether the app was in front for it. Not asked about an encode
      // the watchdog gave up on: that is the encoder's, whatever it says.
      final exit = session.died && givenUp == null
          ? await RenderProcess.lastExit()
          : null;
      if (exit != null) rlog('render: the render process ended: $exit');
      if (reclaimedAway(
          died: session.died,
          givenUp: givenUp != null,
          departed: awayAtStart || OnScreen.departures != departures,
          away: OnScreen.away,
          backFor: OnScreen.backFor,
          exit: exit)) {
        rlogError('render: encode',
            'the render process died with the app out of sight — '
            'the same encode again once it is back');
        RenderProcess.noteAwayDeath();
        await OnScreen.back();
        if (gen != _generation) throw const RenderCancelled();
        return again();
      }
      // It died under the encode, and the app lived: the caller plans
      // the encode again, on x264 or smaller (see [_outOfMemory]), and
      // the phone is planned as a lost save would plan it.
      if (session.died) {
        rlogError('render: encode',
            'the render process died under a '
            '${session.hardware ? "hardware" : "x264"} encode — going on');
        RenderProcess.noteDeath();
        await PhoneBudget.renderDied(
            hardware: session.hardware,
            crashed: exit?.crashed ?? false);
        return session;
      }
      if (progress != null &&
          FfmpegProgressFile.refusedIn(await _logsOf(session))) {
        throw const _ProgressRefused();
      }
      rlog('render: encode failed, code ${code?.getValue()}');
      return session;
    }
    return null;
  }

  /// Whether an encode that died in the render process was reclaimed
  /// by Android with the app away, rather than ended by what it asked
  /// for: the app is away as the death is heard, or came back moments
  /// before after being away during the encode ([departed], which
  /// includes an encode that started with the app away; [_awayGrace]).
  /// Not one the stall watchdog had given up on ([givenUp]): that is a
  /// wedged encoder, whether the watchdog's kill or something else
  /// ended it.
  ///
  /// Where Android recorded the death ([exit], Android 11 and up, from
  /// the 1.0.10 store build), its record decides instead of the
  /// timing: a crash is the encode's, a death with the app in front is
  /// the encode's, and one out of sight is a reclaim.
  @visibleForTesting
  static bool reclaimedAway({
    required bool died,
    required bool givenUp,
    required bool departed,
    required bool away,
    required Duration backFor,
    RenderExit? exit,
  }) {
    if (!died || givenUp) return false;
    if (exit != null) {
      if (exit.reclaimed) return true;
      if (exit.crashed || exit.inFront) return false;
    }
    return away || (departed && backFor < _awayGrace);
  }

  /// Starts [cmd] in the render process where there is one (Android),
  /// and in the app where there isn't or it can't take it.
  ///
  /// First it lets a cancelled encode there end, or ends its process
  /// ([RenderProcess.settleCancelled]). After a death there it waits
  /// for Android to start the process again, and a render superseded
  /// meanwhile ([gen]) stops
  /// here: its encode would reach the process the next render runs in,
  /// where its cancel would end whatever is running.
  static Future<EncodeRun> _start(String cmd, int gen) async {
    await RenderProcess.settleCancelled();
    await RenderProcess.awaitRestart(stillWanted: () => gen == _generation);
    if (gen != _generation) throw const RenderCancelled();
    final hw = cmd.contains('h264_mediacodec');
    final remote = await RenderProcess.start(cmd,
        hardware: hw, stillWanted: () => gen == _generation);
    PhoneBudget.renderPid = remote == null ? null : RenderProcess.knownPid;
    if (remote != null) return remote;
    // Superseded while the render process was waited for: no encode in
    // the app for a render nobody wants.
    if (gen != _generation) throw const RenderCancelled();
    if (Platform.isAndroid) PhoneBudget.encodeInApp();
    return LocalRun(await FFmpegKit.executeAsync(cmd), hardware: hw);
  }

  /// The verse cards one pass draws, with their windows clipped to it.
  ///
  /// A card that straddles a boundary is drawn by both passes, each for
  /// its own share of the card's window — which is why a boundary is
  /// free to fall anywhere the *picture* allows, with no regard for
  /// where the verses change.
  static List<_OverlayClip> _clipsIn(List<_OverlayClip> clips, RenderPass p) =>
      [
        for (final c in clips)
          if (c.endMs > p.startMs && c.startMs < p.endMs)
            _OverlayClip(
              c.file,
              c.startMs < p.startMs ? p.startMs : c.startMs,
              c.endMs > p.endMs ? p.endMs : c.endMs,
              c.cardH,
              unitStartMs: c.unitStartMs,
              unitEndMs: c.unitEndMs,
            ),
      ];

  /// The cards and the sceneries one pass of a long reel is built from,
  /// as plain values.
  ///
  /// Exposed for the reason [sceneRunGraph] is: a pass that seeks to
  /// the wrong place, holds a card a frame too long or drops one at a
  /// boundary is a fault nothing short of an encode on a device would
  /// otherwise show, and by then it is in the user's file.
  @visibleForTesting
  static List<({int startMs, int endMs})> passClips(
    List<({int startMs, int endMs})> clips,
    RenderPass pass,
  ) {
    final out = _clipsIn(
      [
        for (final c in clips)
          _OverlayClip(File('x.png'), c.startMs, c.endMs, 0)
      ],
      pass,
    );
    return [for (final c in out) (startMs: c.startMs, endMs: c.endMs)];
  }

  /// See [passClips]: the scenery half of the same seam. [lengths] and
  /// [seeks] are the input's `-t` and `-ss`, in seconds.
  @visibleForTesting
  static ({List<double> lengths, List<double> seeks, List<SceneCut> cuts})
      passScenes({
    required List<({bool isImage, int? sourceMs})> scenes,
    required List<SceneCut> cuts,
    required int fadeMs,
    required RenderPass pass,
  }) {
    final r = _scenesIn(
      [
        for (final s in scenes)
          _SceneInput('x.mp4', s.isImage, 0, sourceMs: s.sourceMs),
      ],
      cuts,
      fadeMs,
      pass,
    );
    return (
      lengths: [for (final s in r.scenes) s.seconds],
      seeks: [for (final s in r.scenes) s.seekS],
      cuts: r.cuts,
    );
  }

  /// The sceneries one pass runs through, renumbered from zero, with
  /// their cuts clipped to it.
  ///
  /// A pass can open in the middle of a scene. The input seeks to
  /// where the pass begins in the clip — into its turn when the clip
  /// covers it, into the lap when it loops and the pass is over before
  /// the lap is — and otherwise reads the clip from its top, which is
  /// right because [RenderPlan] starts such a pass on a lap. See
  /// [RenderPlan.seekInto].
  static ({List<_SceneInput> scenes, List<SceneCut> cuts}) _scenesIn(
    List<_SceneInput> all,
    List<SceneCut> cuts,
    int fadeMs,
    RenderPass p,
  ) {
    final picked = <({_SceneInput src, SceneCut cut, int from, int to})>[];
    for (var i = 0; i < all.length && i < cuts.length; i++) {
      final c = cuts[i];
      if (c.endMs <= p.startMs || c.startMs >= p.endMs) continue;
      picked.add((
        src: all[i],
        cut: c,
        from: c.startMs < p.startMs ? p.startMs : c.startMs,
        to: c.endMs > p.endMs ? p.endMs : c.endMs,
      ));
    }
    final scenes = <_SceneInput>[];
    final out = <SceneCut>[];
    for (var k = 0; k < picked.length; k++) {
      final e = picked[k];
      final last = k == picked.length - 1;
      final span = e.to - e.from;
      // Every scene but the pass's last plays the crossfade it hands
      // over on, exactly as it does in a single-pass render.
      final ms = span + (last ? 0 : fadeMs);
      final len = e.src.sourceMs;
      final seekMs = RenderPlan.seekInto(
          isImage: e.src.isImage,
          sourceMs: len,
          into: e.from - e.cut.startMs,
          ms: ms);
      scenes.add(_SceneInput(
        e.src.path,
        e.src.isImage,
        ms / 1000,
        seekS: seekMs / 1000,
        sourceMs: len,
        ready: e.src.ready,
      ));
      out.add(SceneCut(
        scene: k,
        startMs: e.from,
        endMs: e.to,
        firstAyah: e.cut.firstAyah,
        lastAyah: e.cut.lastAyah,
      ));
    }
    return (scenes: scenes, cuts: out);
  }

  /// Where in a single-background reel's clip a pass starts reading,
  /// in seconds; see [RenderPlan.seekInto].
  static double _bgSeekFor(PictureSpan span, RenderPass p) =>
      RenderPlan.seekInto(
              isImage: span.isImage,
              sourceMs: span.sourceMs,
              into: p.startMs - span.startMs,
              ms: p.durationMs) /
          1000;

  /// Joins the picture-only passes and lays the recitation over them.
  ///
  /// [copyVideo] is the whole point of encoding in passes: the joined
  /// track is the passes' own frames, copied rather than re-compressed,
  /// so a reel cut into forty pieces is bit-for-bit what one long
  /// encode would have produced. The audio is encoded here, once, from
  /// the untouched recording — so its fades and its timing never meet a
  /// seam.
  static Future<EncodeRun?> _joinPasses({
    required List<File> parts,
    required String audioPath,
    required int segStartMs,
    required int segMs,
    required File dest,
    required int gen,
    required bool copyVideo,
    required bool high,
    required int threads,
    void Function(double progress)? onProgress,
  }) async {
    final list = File('${dest.path}.list.txt');
    await list.writeAsString(parts
        .map((f) => "file '${f.path.replaceAll("'", r"'\''")}'")
        .join('\n'));
    final durS = segMs / 1000;
    final dur = durS.toStringAsFixed(3);
    final fadeOut = (durS - 0.3).clamp(0, double.infinity).toStringAsFixed(3);
    // A join that has to re-encode is x264 like any pass: the same
    // settings, ceiling and all.
    final video = copyVideo
        ? '-c:v copy '
        : '${videoCodec(hardware: false, reelMs: segMs, threads: threads, high: high, lean: _lean)}'
            '-pix_fmt yuv420p '
            '-colorspace bt709 -color_primaries bt709 -color_trc bt709 ';
    final cmd = '-f concat -safe 0 -i "${list.path}" '
        '-ss ${(segStartMs / 1000).toStringAsFixed(3)} -t $dur '
        '-i "$audioPath" '
        '-filter_complex "[1:a]afade=t=in:st=0:d=0.3,'
        'afade=t=out:st=$fadeOut:d=0.3[aout]" '
        '-map 0:v -map "[aout]" '
        '-t $dur '
        '$video'
        '-c:a aac -b:a 192k '
        '-movflags +faststart '
        '-f mp4 '
        '-y "${dest.path}"';
    try {
      return await _runEncode(
        cmd: cmd,
        gen: gen,
        segMs: segMs,
        dest: dest,
        onProgress: onProgress == null
            ? null
            : (v) =>
                onProgress((_joinShare + v * (1 - _joinShare)).clamp(0.0, 1.0)),
      );
    } finally {
      try {
        if (list.existsSync()) list.deleteSync();
      } catch (_) {}
    }
  }

  /// Every scenery of a multi-scene reel, resolved to a file FFmpeg can
  /// read and the length the graph takes from it.
  ///
  /// A scenery that cannot be materialized falls back to its own poster
  /// gradient — the same picture the picker showed for it — so one
  /// missing file costs that scene its footage and the reel nothing.
  static Future<List<_SceneInput>> _resolveScenes(
    List<ReelBackground> scenes,
    List<SceneCut> cuts,
    int fadeMs,
    Directory tmp,
  ) async {
    final out = <_SceneInput>[];
    for (var i = 0; i < scenes.length; i++) {
      final s = scenes[i];
      // Every scene but the last plays the crossfade it hands over on,
      // so it is read that much longer than its own cut.
      final ms = cuts[i].durationMs + (i == scenes.length - 1 ? 0 : fadeMs);
      final secs = ms / 1000;
      final f = s.isDeviceFile
          ? s.isImage
              ? await StillSource.readable(File(s.filePath!), tmp)
              : File(s.filePath!)
          : await _materializeAssetOrNull(s.assetPath, tmp);
      if (f != null && f.existsSync()) {
        // The clip's own length is what says whether a long reel may be
        // cut in two inside this scene; a still has none to ask for.
        final len = s.isImage ? null : await MediaDuration.ofPath(f.path);
        out.add(_SceneInput(f.path, s.isImage, secs, sourceMs: len));
        continue;
      }
      final g = await AyahRasterizer.rasterizeGradientBackdrop(
        s.gradientArgb,
        withScrim: false,
      );
      out.add(_SceneInput(g.path, true, secs));
    }
    return out;
  }

  /// Identity of a scene run for the render cache: which sceneries, in
  /// which order, cut where, blended for how long. Same FNV-1a as the
  /// highlight fingerprint, and deterministic for the same reason —
  /// String.hashCode is not stable across launches, and a cached mp4
  /// outlives the process that made it.
  static String _sceneFingerprint(
    List<ReelBackground> scenes,
    List<SceneCut> cuts,
    int fadeMs,
  ) {
    var x = 0x811c9dc5;
    void mix(int v) {
      x = ((x ^ v) * 0x01000193) & 0xFFFFFFFF;
    }

    mix(fadeMs);
    for (final s in scenes) {
      for (final unit in s.id.codeUnits) {
        mix(unit);
      }
      mix(0);
    }
    for (final c in cuts) {
      mix(c.startMs);
      mix(c.endMs);
    }
    return x.toRadixString(16);
  }

  /// Deterministic across app restarts (unlike Object.hash), so cached
  /// mp4s keyed on it survive a relaunch: FNV-1a over the plan's ints.
  /// Where each verse of [start]..[end] begins and ends in [r], as one
  /// number: FNV-1a, like the fingerprints below.
  static String _timingFingerprint(Recitation r, int start, int end) {
    var x = 0x811c9dc5;
    void mix(int v) {
      x = ((x ^ v) * 0x01000193) & 0xFFFFFFFF;
    }

    for (var a = start; a <= end; a++) {
      final t = r.timing(a);
      mix(t.startMs);
      mix(t.endMs);
    }
    return x.toRadixString(36);
  }

  static String _wordTimesFingerprint(Map<int, List<(int, int)?>>? w) {
    if (w == null || w.isEmpty) return '';
    var x = 0x811c9dc5;
    void mix(int v) {
      x = ((x ^ (v & 0xFFFFFFFF)) * 0x01000193) & 0xFFFFFFFF;
    }

    for (final ayah in w.keys.toList()..sort()) {
      mix(ayah);
      for (final t in w[ayah]!) {
        mix(t?.$1 ?? -1);
        mix(t?.$2 ?? -1);
      }
    }
    return '_wt${x.toRadixString(36)}';
  }

  static String _highlightFingerprint(Map<int, List<HighlightSpan>>? h) {
    if (h == null || h.isEmpty) return '0';
    var x = 0x811c9dc5;
    void mix(int v) {
      x = ((x ^ v) * 0x01000193) & 0xFFFFFFFF;
    }

    for (final ayah in h.keys.toList()..sort()) {
      mix(ayah);
      for (final s in h[ayah]!) {
        mix(s.startMs);
        mix(s.endMs);
        mix(s.tokenStart);
        mix(s.tokenEnd);
      }
    }
    return x.toRadixString(16);
  }

  /// Every unit's cards — a whole verse, or each line of a cut one — the
  /// windows they show in, and what rides on them: the path a reel takes
  /// when its verses are cut into lines or move. Every other reel keeps
  /// the per-verse path it always had.
  ///
  /// [draw] rasterizes one card of a unit in the reel's styling; see
  /// [AyahRasterizer.rasterizeUnit].
  static Future<({List<_OverlayClip> clips, List<_UnitShow> shows})>
      _unitCards({
    required Recitation recitation,
    required List<Ayah> ayahs,
    required int startAyah,
    required int endAyah,
    required VerseLinePlan? lines,
    required VerseMotion motion,
    required Map<int, List<HighlightSpan>>? highlight,
    required Map<int, List<HighlightSpan>>? words,
    required Map<int, List<(int, int)?>>? wordTimes,
    required Future<({File file, double height, List<VerseRow> rows})>
            Function(Ayah ayah, VersePart? part, String name,
                {({int start, int end})? lit,
                int? dim,
                bool glint,
                bool measure,
                bool bare})
        draw,
    required bool Function() keepGoing,
    void Function(double done)? onUnit,

    /// The basmala's card, for the unit numbered 0 a reel opening a
    /// surah on verse 1 starts with; drawn bare (no verse number, no
    /// reference). Without it that unit is left out.
    Ayah? basmala,
  }) async {
    final units = [
      for (final u in VerseUnit.of(recitation, startAyah, endAyah, lines))
        if (u.ayah != 0 || basmala != null) u,
    ];
    final follow = highlight ?? words;
    final needRows = motion.thread || motion.light;
    final clips = <_OverlayClip>[];
    final shows = <_UnitShow>[];
    for (var i = 0; i < units.length; i++) {
      if (!keepGoing()) throw const RenderCancelled();
      final u = units[i];
      final bare = u.ayah == 0;
      final ayah = bare ? basmala! : ayahs[u.ayah - 1];
      final verseStart = recitation.timing(u.ayah).startMs;
      final windows = VerseFollow.of(
        unit: u,
        verseStartMs: verseStart,
        spans: follow?[u.ayah],
        highlight: highlight != null,
        trail: motion.trail,
        unveil: motion.unveil,
      );
      // One card per state the unit passes through, however many
      // windows show it.
      final drawn = <String, ({File file, double height})>{};
      var rows = const <VerseRow>[];
      var cardH = 0.0;
      for (final w in windows) {
        var c = drawn[w.key];
        if (c == null) {
          final r = await draw(ayah, u.part, w.key,
              lit: w.lit,
              dim: w.dimFrom,
              measure: needRows && rows.isEmpty,
              bare: bare);
          if (needRows && rows.isEmpty) rows = r.rows;
          c = (file: r.file, height: r.height);
          drawn[w.key] = c;
          if (!keepGoing()) throw const RenderCancelled();
        }
        cardH = c.height;
        clips.add(_OverlayClip(c.file, w.startMs, w.endMs, c.height,
            unitStartMs: u.startMs, unitEndMs: u.endMs));
      }
      File? glint;
      if (motion.light && rows.isNotEmpty) {
        glint =
            (await draw(ayah, u.part, 'glint', glint: true, bare: bare)).file;
      }
      final times = u.timesIn(wordTimes?[u.ayah], verseStart);
      final voiced = VerseRows.voicedIn(u.durationMs);
      final progress = rows.isEmpty
          ? const <RowProgress>[]
          : times != null
              ? [for (final r in rows) r.progressFromWords(times, 0)]
              : VerseRows.even(
                  rows,
                  VerseUnitCard.textOf(ayah, u.part).arabic.split(' '),
                  voiced.fromMs,
                  voiced.toMs);
      shows.add(_UnitShow(
        u.startMs,
        u.endMs,
        cardH,
        [
          for (var k = 0; k < rows.length; k++)
            MotionRow(
              left: rows[k].left,
              right: rows[k].right,
              top: rows[k].top,
              bottom: rows[k].bottom,
              threadY: rows[k].threadY,
              progress: progress[k],
            ),
        ],
        glint,
      ));
      onUnit?.call((i + 1) / units.length);
    }
    return (clips: clips, shows: shows);
  }

  /// The whole FFmpeg command for a reel whose verses are cut into lines
  /// or move, on one still background, drawn by the real cards: what a
  /// desktop FFmpeg is pointed at to see that the motion's graph runs
  /// and lands where the preview draws it. Picture only when [audio] is
  /// null. See test/tools/export_motion_tool_test.dart.
  @visibleForTesting
  static Future<String> unitReelCommand({
    required Recitation recitation,
    required List<Ayah> ayahs,
    required int startAyah,
    required int endAyah,
    required String background,
    required String out,
    VerseLinePlan? lines,
    VerseMotion motion = VerseMotion.none,
    Map<int, List<HighlightSpan>>? highlight,
    Map<int, List<HighlightSpan>>? words,
    Map<int, List<(int, int)?>>? wordTimes,
    int accentArgb = 0xFFEEC96B,
    double overlayAlign = 0.5,
    bool surahTitle = false,
    VerseTranslation edition = VerseTranslation.english,
    VerseNumbering numbering = VerseNumbering.off,
    String? audio,

    /// What the cards' files start with: one per reel, when a tool makes
    /// several that cut the same verses differently.
    String fileTag = 'tool_',

    /// The surah's name pinched to this size (see [render]).
    double surahTitleScale = 1.0,

    /// A wide card of this shape over a luminous band, instead of the
    /// full frame: the graph a wide-card reel on a video scenery runs.
    double? letterboxAspect,
    BandGlow? band,
  }) async {
    final box =
        letterboxAspect == null ? null : LetterboxGeometry.of(letterboxAspect);
    final built = await _unitCards(
      recitation: recitation,
      ayahs: ayahs,
      startAyah: startAyah,
      endAyah: endAyah,
      lines: lines,
      motion: motion,
      highlight: highlight,
      words: words,
      wordTimes: wordTimes,
      keepGoing: () => true,
      draw: (ayah, part, name,
              {lit, dim, glint = false, measure = false, bare = false}) =>
          AyahRasterizer.rasterizeUnit(
        ayah,
        part: part,
        name: name,
        highlight: lit,
        dimFrom: dim,
        glint: glint,
        measure: measure,
        accent: Color(accentArgb),
        edition: edition,
        numbering: numbering,
        surah: recitation.surah,
        fileTag: fileTag,
      ),
    );
    final segStart = recitation.timing(startAyah).startMs;
    final segMs = recitation.timing(endAyah).endMs - segStart;
    final wm = await AyahRasterizer.rasterizeWatermark();
    return _buildCommand(
      audioPath: audio,
      bgPath: background,
      bgIsImage: true,
      bgReady: box == null,
      sceneInputs: null,
      cuts: const [],
      fadeMs: 0,
      scrimPath: null,
      maskPath: null,
      watermarkPath: wm.path,
      clips: built.clips,
      motion: motion,
      shows: built.shows,
      threadPath: motion.thread
          ? (await AyahRasterizer.rasterizeThreadStrip(accentArgb)).path
          : null,
      sparkPath: motion.thread
          ? (await AyahRasterizer.rasterizeSpark(accentArgb)).path
          : null,
      titlePath: surahTitle
          ? (await AyahRasterizer.rasterizeSurahTitle(recitation.surah,
                  edition: edition, scale: surahTitleScale))
              .path
          : null,
      titleAt: surahTitle ? ReelSurahTitle.defaultCentre(box) : null,
      segStartMs: segStart,
      segMs: segMs,
      overlayAlign: overlayAlign,
      letterbox: box,
      backdrop: band == null ? LetterboxBackdrop.colour : LetterboxBackdrop.glow,
      backdropArgb: band?.base ?? 0xFF000000,
      bandPath: band == null || box == null
          ? null
          : (await AyahRasterizer.rasterizeBandGlow(band, box)).path,
      outPath: out,
      hardware: false,
      threads: 2,
      reelMs: segMs,
      frames: audio == null ? (segMs * 30 / 1000).round() : null,
    );
  }

  static String _buildCommand({
    /// Null for one pass of a long reel: those carry picture only, and
    /// the recitation is laid over the joined result in one piece.
    required String? audioPath,
    required String bgPath,
    required bool bgIsImage,
    required bool bgReady,
    required List<_SceneInput>? sceneInputs,
    required List<SceneCut> cuts,
    required int fadeMs,
    required String? scrimPath,
    required String? maskPath,

    /// The vignette layer, for the one case that cannot bake it into
    /// something already being composited. Null everywhere else.
    String? vignettePath,
    required String watermarkPath,

    /// The dedication line as a cropped PNG, laid along the bottom of
    /// the frame after the mark — or null, which is every reel nobody
    /// dedicated and adds nothing to the graph.
    String? dedicationPath,

    /// Where the dedication's centre goes, as fractions of the frame;
    /// null for the foot of it.
    Offset? dedicationAt,
    required List<_OverlayClip> clips,

    /// The verse's motion, and what rides on its cards (see
    /// [VerseMotionGraph]). [VerseMotion.none] writes the cards' overlays
    /// exactly as they always were.
    VerseMotion motion = VerseMotion.none,
    List<_UnitShow> shows = const [],
    String? threadPath,
    String? sparkPath,

    /// The surah's name as a cropped PNG, centred at [titleAt]; null
    /// adds nothing to the graph.
    String? titlePath,
    Offset? titleAt,
    required int segStartMs,
    required int segMs,
    required double overlayAlign,
    required LetterboxGeometry? letterbox,
    required LetterboxBackdrop backdrop,
    required int backdropArgb,

    /// The luminous band's picture, for [LetterboxBackdrop.glow].
    String? bandPath,

    /// The colour grade as a filter chain, with a trailing comma, or
    /// empty. Spliced in wherever the scenery is read — and nowhere
    /// else: the scrim over it is legibility, a letterbox band is a
    /// colour the user picked, and the verse is ink.
    String grade = '',
    ReelEffects effects = ReelEffects.off,

    /// How far into the whole reel this pass begins. Zero for a reel
    /// encoded in one, which is most of them.
    int passStartMs = 0,
    required String outPath,
    required bool hardware,
    required int threads,

    /// Decoder threads for each scenery input; null leaves it to
    /// FFmpeg. See [_sceneThreadsFor].
    int? sceneThreads,

    /// The whole reel's length, which the encoder settings answer to —
    /// [segMs] is only this pass's share of it.
    int? reelMs,

    /// Exact frame count for a pass of a long reel. Passes are joined
    /// end to end afterwards, so each one is bounded by frames rather
    /// than by a time that could round a frame either way.
    int? frames,

    /// How far into the background clip this pass starts; see
    /// [_SceneInput.seekS].
    double bgSeekS = 0,

    /// The higher rung of the encoder ladder; see [_hwBitrateFor].
    bool highQuality = false,

    /// Hands the encoder 720x1280 ([ExportBudget.smallest]); see
    /// [outputScale].
    bool small = false,
  }) {
    final durS = segMs / 1000;
    final dur = durS.toStringAsFixed(3);
    final audioSeek = (segStartMs / 1000).toStringAsFixed(3);
    final wholeMs = reelMs ?? segMs;

    // A letterbox card only needs its own mask, and a flat backdrop
    // only needs a colour source, when the base frame wasn't already
    // flattened into one PNG upstream.
    final needsCard = letterbox != null && !bgReady;
    // A band that is a picture of its own rather than the scenery
    // blurred: a flat colour, or a luminous ground's PNG.
    final glowBand = backdrop == LetterboxBackdrop.glow && bandPath != null;
    final colourBackdrop = backdrop == LetterboxBackdrop.colour || glowBand;

    final inputs = StringBuffer();
    final scene = sceneThreads == null ? '' : '-threads $sceneThreads ';
    if (sceneInputs != null) {
      // One input per scenery, each read for exactly as long as it is
      // on screen. Videos are looped at the input rather than trusted
      // to be long enough: a scene that ran out would leave the reel
      // short of its own audio. Whether a clip is long enough to never
      // reach that loop is settled before an export is offered.
      for (final sc in sceneInputs) {
        final len = sc.seconds.toStringAsFixed(3);
        if (sc.isImage) {
          inputs.write('$scene-loop 1 -framerate 30 -t $len -i "${sc.path}" ');
        } else if (sc.seekS > 0) {
          // A pass that starts mid-scene, in a clip long enough to be
          // seeked into: no loop, or the seek would be re-applied to
          // every lap of it.
          inputs.write('$scene-ss ${sc.seekS.toStringAsFixed(3)} '
              '-t $len -i "${sc.path}" ');
        } else {
          inputs.write('$scene-stream_loop -1 -t $len -i "${sc.path}" ');
        }
      }
    } else if (bgIsImage) {
      // Still image: emit it as a constant 30fps stream; output -t trims.
      //
      // Decoded afresh for every frame, which held in the graph instead
      // (as a luminous band is, [_bandLoop]) was 60 MB lighter at its
      // peak but a third slower on FFmpeg 6.1 with decoder threads to
      // spare (2026-10-21, EXPORT_MEMORY.md): kept as it was.
      inputs.write('$scene-loop 1 -framerate 30 -i "$bgPath" ');
    } else if (bgSeekS > 0) {
      inputs.write('$scene-ss ${bgSeekS.toStringAsFixed(3)} -i "$bgPath" ');
    } else {
      // Loop the background clip for the full segment length.
      inputs.write('$scene-stream_loop -1 -i "$bgPath" ');
    }
    // The scenery occupies input 0 — or inputs 0..n-1 when the reel
    // runs through several — and everything after it is numbered in
    // the order it is added.
    final sceneCount = sceneInputs?.length ?? 1;
    final audioIdx = sceneCount;
    final clipBase = sceneCount + (audioPath == null ? 0 : 1);
    // Trim the recording to the chosen ayah range.
    if (audioPath != null) {
      inputs.write('-ss $audioSeek -t $dur -i "$audioPath" ');
    }
    // Every PNG below is one picture, decoded once and held, so each is
    // given a single decoder thread. Left to itself FFmpeg gives every
    // input one per core and one more, each with a stack and decoder
    // state of its own: on an eight-core phone a reel of forty verse
    // cards ran some four hundred threads to decode forty pictures.
    // Measured with this graph on FFmpeg 8, on two cores: 228 threads
    // and 4.4 GB of address space, against 105 and 3.4 GB on one each.
    const still = '-threads 1 ';
    for (final c in clips) {
      inputs.write('$still-i "${c.file.path}" ');
    }
    var nextIdx = clipBase + clips.length;
    int? scrimIdx;
    if (scrimPath != null) {
      inputs.write('$still-i "$scrimPath" ');
      scrimIdx = nextIdx++;
    }
    final wmIdx = nextIdx++;
    inputs.write('$still-i "$watermarkPath" ');
    int? dedIdx;
    if (dedicationPath != null) {
      inputs.write('$still-i "$dedicationPath" ');
      dedIdx = nextIdx++;
    }
    int? maskIdx;
    if (needsCard && maskPath != null) {
      inputs.write('$still-i "$maskPath" ');
      maskIdx = nextIdx++;
    }
    int? vignetteIdx;
    if (vignettePath != null) {
      inputs.write('$still-i "$vignettePath" ');
      vignetteIdx = nextIdx++;
    }
    int? colourIdx;
    // A multi-scene reel builds its flat backdrop inside the graph,
    // once per scene, rather than off one input every scene would have
    // to share.
    if (needsCard && colourBackdrop && sceneInputs == null) {
      if (glowBand) {
        // One picture, decoded once and repeated in the graph (see
        // [_bandLoop]) rather than read off the disk and decoded again
        // for every frame: on two cores that was 40 ms a frame.
        inputs.write('$still-framerate 30 -i "$bandPath" ');
      } else {
        inputs.write('-f lavfi -t $dur -i '
            '"color=c=${_ffColor(backdropArgb)}:s=1080x1920:r=30" ');
      }
      colourIdx = nextIdx++;
    }
    // A luminous band in a run of sceneries: its one picture, split to
    // every scene before it is held for that scene's turn. Split while it
    // is still a single frame, so each scene holds a reference to the
    // same picture rather than a queue of frames waiting for the join to
    // reach it.
    int? bandIdx;
    if (needsCard && glowBand && sceneInputs != null) {
      inputs.write('$still-framerate 30 -i "$bandPath" ');
      bandIdx = nextIdx++;
    }
    // The verse's flourishes, for the units this pass shows: each one's
    // glint card when its light is on, and the thread's strip and spark.
    final passEndMs = segStartMs + segMs;
    double cardTopOf(double cardH) => letterbox == null
        ? (LetterboxGeometry.frameH - cardH) * overlayAlign.clamp(0.0, 1.0)
        : letterbox.verseTop(cardH, overlayAlign);
    var motionUnits = <MotionUnit>[
      for (final u in shows)
        if (u.endMs > segStartMs && u.startMs < passEndMs)
          MotionUnit(
            startMs: u.startMs,
            endMs: u.endMs,
            cardTop: cardTopOf(u.cardH),
            cardH: u.cardH,
            rows: u.rows,
            glintInput: u.glint == null ? null : -1,
          ),
    ];
    int? threadIdx;
    int? sparkIdx;
    if (!motion.isNone && motionUnits.isNotEmpty) {
      final use = VerseMotionGraph.uses(
          units: motionUnits,
          motion: motion,
          passStartMs: segStartMs,
          passEndMs: passEndMs);
      final shown = [
        for (final u in shows)
          if (u.endMs > segStartMs && u.startMs < passEndMs) u,
      ];
      final withGlints = <MotionUnit>[];
      for (var i = 0; i < motionUnits.length; i++) {
        final glint = shown[i].glint;
        if (use.glintUnits.contains(i) && glint != null) {
          inputs.write('$still-i "${glint.path}" ');
          withGlints.add(motionUnits[i].withGlint(nextIdx++));
        } else {
          withGlints.add(motionUnits[i].withGlint(null));
        }
      }
      motionUnits = withGlints;
      if (use.thread && threadPath != null) {
        inputs.write('$still-i "$threadPath" ');
        threadIdx = nextIdx++;
      }
      if (use.spark && sparkPath != null) {
        inputs.write('$still-i "$sparkPath" ');
        sparkIdx = nextIdx++;
      }
    }
    int? titleIdx;
    if (titlePath != null && titleAt != null) {
      inputs.write('$still-i "$titlePath" ');
      titleIdx = nextIdx++;
    }

    // Filtergraph: build the 1080x1920 base frame, then chain one timed
    // overlay per ayah (segment-relative times).
    final f = StringBuffer();
    // A pass of a reel encoded in pieces is counted in frames at 30 a
    // second, and the passes are joined end to end: its picture has to
    // arrive at 30 whatever the clip was shot at, and may not come up a
    // frame short where a clip ends a hair before its measured length.
    // A reel in one piece is bounded by time instead, and keeps the
    // graph it always had.
    var src = '0:v';
    if (sceneInputs == null && !bgIsImage && !bgReady && frames != null) {
      f.write('[0:v]fps=30,tpad=stop_mode=clone:stop_duration=1[src];');
      src = 'src';
    }
    if (sceneInputs != null) {
      _writeSceneRun(
        f,
        sceneInputs,
        cuts: cuts,
        fadeMs: fadeMs,
        segStartMs: segStartMs,
        letterbox: letterbox,
        colourBackdrop: colourBackdrop,
        backdropArgb: backdropArgb,
        bandIdx: bandIdx,
        maskIdx: maskIdx,
        scrimIdx: scrimIdx,
        grade: grade,
      );
    } else if (bgReady) {
      // Already the finished 1080x1920 base — scale, crop, and either
      // the scrim or the whole letterbox composite were done once, off
      // the per-frame path, so the base frame arrives ready.
      f.write('[0:v]null[v0];');
    } else if (letterbox != null) {
      if (glowBand && colourIdx != null) {
        f.write('[$colourIdx:v]${_bandLoop(dur)}[bandloop];');
      }
      _writeLetterboxBase(
        f,
        letterbox,
        source: src,
        backdrop: !colourBackdrop
            ? null
            : glowBand
                ? 'bandloop'
                : '$colourIdx:v',
        mask: maskIdx == null ? null : '$maskIdx:v',
        out: 'v0',
        grade: grade,
      );
    } else {
      // The one branch that hands the graded stream straight to an
      // overlay, so it is the one that has to put the pixel format
      // back: everything downstream of `[base]` — the scrim's blend,
      // the verse card's, the mark's — would otherwise composite in
      // RGB on a graded reel and in YUV on every other one, and the
      // difference would show up only in the file. The other two
      // branches already name the format they need a filter later.
      f.write('[$src]scale=1080:1920:force_original_aspect_ratio=increase,'
          'crop=1080:1920,$grade'
          '${grade.isEmpty ? '' : 'format=yuv420p,'}'
          'null[base];');
      if (scrimIdx != null) {
        f.write('[base][$scrimIdx:v]overlay=0:0[v0];');
      } else {
        f.write('[base]null[v0];');
      }
    }
    // The vignette, where it could not ride something already being
    // composited — see [render], which only ever hands one over in
    // that case.
    if (vignetteIdx != null) {
      f.write('[v0][$vignetteIdx:v]overlay=0:0[v0v];');
    }
    // Where a verse card sits. Full frame: anywhere in the frame, the
    // user's drag. Letterbox: anywhere in the band the crop freed below
    // the card, so it can never end up back on the picture.
    final verseY = letterbox != null
        ? letterbox.verseYExpr(overlayAlign)
        : '(H-h)*${overlayAlign.toStringAsFixed(3)}';
    var prev = vignetteIdx == null ? 'v0' : 'v0v';
    if (motion.isNone) {
      for (var i = 0; i < clips.length; i++) {
        final s = ((clips[i].startMs - segStartMs) / 1000).toStringAsFixed(3);
        final e = ((clips[i].endMs - segStartMs) / 1000).toStringAsFixed(3);
        final label = 'v${i + 1}';
        // The y expression is quoted: the letterbox form contains commas,
        // which would otherwise read as the end of the filter. The window
        // is half-open: between() holds both ends, and at a seam that
        // lands on a frame two cards drew on it, one over the other.
        f.write("[$prev][${clipBase + i}:v]overlay=(W-w)/2:'$verseY':"
            "enable='gte(t,$s)*lt(t,$e)'[$label];");
        prev = label;
      }
    } else {
      prev = VerseMotionGraph.write(
        f,
        prev: prev,
        cards: [
          for (var i = 0; i < clips.length; i++)
            MotionCard(
              input: clipBase + i,
              startMs: clips[i].startMs,
              endMs: clips[i].endMs,
              unitStartMs: clips[i].unitStartMs ?? clips[i].startMs,
              unitEndMs: clips[i].unitEndMs ?? clips[i].endMs,
            ),
        ],
        units: motionUnits,
        motion: motion,
        passStartMs: segStartMs,
        passEndMs: passEndMs,
        baseY: verseY,
        threadInput: threadIdx,
        sparkInput: sparkIdx,
      );
    }
    // The surah's name, over the verse and under the mark, centred
    // where the preview puts it and held inside the frame the same way.
    if (titleIdx != null) {
      f.write('[$prev][$titleIdx:v]overlay=${surahTitleOverlay(titleAt!)}'
          '[vtitle];');
      prev = 'vtitle';
    }
    // Watermark last, above the verse card — exactly where the preview
    // draws it. The PNG is cropped to the mark, so it is placed rather
    // than laid over the whole frame: centered horizontally, its own
    // inset up from the bottom edge.
    //
    // That inset hangs off the composition, not the frame, which is
    // what stops a crop lifting the mark out for free. In letterbox it
    // is the card's bottom edge, the same for every clip, and this
    // writes the single untimed overlay it always did. In full frame it
    // is the verse card's bottom edge, so it moves whenever the card
    // changes height — one overlay per run of clips that agree on it,
    // which is one per ayah at worst and usually far fewer, since an
    // ayah's highlight clips are all the same card lit differently.
    //
    // The windows tile the segment end to end and never overlap: the
    // first has no lower bound, so a lead-in before the first ayah
    // still carries the mark, and the last has no upper bound, so a
    // tail after the final word does too. Half-open, because
    // `between` is inclusive at both ends and two marks would draw for
    // one frame at every seam.
    //
    // Read off the card's height rather than stored with it: the mark's
    // place depends on the drag too, and the drag can move without the
    // cards being rasterized again.
    String insetAt(int i) => AyahRasterizer.watermarkInsetFor(
          letterbox,
          verseBottom: letterbox == null
              ? (LetterboxGeometry.frameH - clips[i].cardH) * overlayAlign +
                  clips[i].cardH
              : letterbox.verseTop(clips[i].cardH, overlayAlign) +
                  clips[i].cardH,
        ).toStringAsFixed(0);
    if (clips.isEmpty) {
      final wmY = AyahRasterizer.watermarkInsetFor(letterbox).toStringAsFixed(0);
      f.write('[$prev][$wmIdx:v]overlay=(W-w)/2:H-h-$wmY[vwm];');
      prev = 'vwm';
    } else {
      String at(int i) =>
          ((clips[i].startMs - segStartMs) / 1000).toStringAsFixed(3);
      var runStart = 0;
      var runY = insetAt(0);
      for (var i = 1; i <= clips.length; i++) {
        final y = i < clips.length ? insetAt(i) : null;
        if (y == runY) continue;
        final label = 'vwm$runStart';
        final gate = <String>[
          if (runStart > 0) 'gte(t,${at(runStart)})',
          if (i < clips.length) 'lt(t,${at(i)})',
        ].join('*');
        f.write('[$prev][$wmIdx:v]overlay=(W-w)/2:H-h-$runY'
            "${gate.isEmpty ? '' : ":enable='$gate'"}[$label];");
        prev = label;
        runStart = i;
        if (y != null) runY = y;
      }
    }
    // The dedication, along the bottom edge — a fixed inset off the
    // frame, the same for every clip and both formats, so it is one
    // untimed overlay wherever the verse and the mark went.
    if (dedIdx != null) {
      if (dedicationAt == null) {
        final dedY = AyahRasterizer.dedicationInset.toStringAsFixed(0);
        f.write('[$prev][$dedIdx:v]overlay=(W-w)/2:H-h-$dedY[vded];');
      } else {
        // Dragged: the PNG centred on the point, and held inside the
        // frame. The PNG carries its shadow margin all round, so the
        // line itself stops that margin short of an edge — the clamp
        // the preview's [ReelDedication] applies to the line.
        final cx = (dedicationAt.dx * 1080).toStringAsFixed(0);
        final cy = (dedicationAt.dy * 1920).toStringAsFixed(0);
        f.write("[$prev][$dedIdx:v]overlay=x='max(0,min(W-w,$cx-w/2))'"
            ":y='max(0,min(H-h,$cy-h/2))'[vded];");
      }
      prev = 'vded';
    }
    // Fine luma-only temporal grain before the encode: smooth gradients
    // band badly after x264 quantization at full-screen scale (the
    // preview hides it by shrinking the frame); dither breaks the bands
    // up. Luma only — chroma noise reads as colored speckle.
    //
    // Skipped over a flat letterbox backdrop, where it would be doing
    // the opposite of its job: there is no gradient left to band, and
    // grain over two-thirds of a frame of solid black is plainly
    // visible as speckle.
    final grain = letterbox != null &&
            backdrop == LetterboxBackdrop.colour &&
            effects.grain == 0
        ? ''
        : 'noise=c0s=${effects.noiseStrength}:c0f=t+u,';
    // Then explicit BT.709 conversion + tags: without them the RGB->YUV
    // step uses a mismatched matrix and players wash the colors out.
    f.write('[$prev]$grain${fadeChain(effects, wholeMs, passStartMs, segMs)}'
        '${outputScale(small: small)}'
        '[vout];');
    // Fade the recitation in/out so range edges never hard-cut
    // mid-breath. A picture-only pass has none to fade: the recitation
    // is laid over the joined passes in one piece, fades and all.
    if (audioPath != null) {
      final fadeOut = (durS - 0.3).clamp(0, double.infinity).toStringAsFixed(3);
      f.write('[$audioIdx:a]afade=t=in:st=0:d=0.3,'
          'afade=t=out:st=$fadeOut:d=0.3[aout]');
    }

    final codec = videoCodec(
        hardware: hardware,
        reelMs: wholeMs,
        threads: threads,
        high: highQuality,
        lean: _lean);

    // A picture-only pass leaves the graph ending on its last label,
    // and a filtergraph may not end on a semicolon.
    var graph = f.toString();
    if (graph.endsWith(';')) graph = graph.substring(0, graph.length - 1);

    return '$inputs-filter_complex "$graph" '
        '-map "[vout]" ${audioPath == null ? '' : '-map "[aout]" '}'
        '${frames == null ? '-t $dur ' : '-frames:v $frames '}'
        '$codec'
        '-pix_fmt yuv420p '
        '-colorspace bt709 -color_primaries bt709 -color_trc bt709 '
        '${audioPath == null ? '' : '-c:a aac -b:a 192k '}'
        '${frames == null ? '-movflags +faststart ' : ''}'
        // Named explicitly because the encode writes to a .part file
        // and is renamed once it has been checked: FFmpeg picks its
        // muxer off the extension, and ".part" is not one it knows.
        '-f mp4 '
        '-y "$outPath"';
  }

  /// The last filter before the encoder: the frame to the size it is
  /// encoded at, with an explicit BT.709 conversion and tags.
  ///
  /// 1080x1920, except on [ExportBudget.smallest], where the graph still
  /// composes at 1080x1920 and only the encoder is handed 720x1280. The
  /// encoder's frames are the bulk of what a pass costs, and 2.25 times
  /// smaller there: desktop FFmpeg 8.0.1, the app's graph, lean x264 on
  /// two threads, 150 frames, 4 cards: 299 MB at 1080x1920, 233 MB at
  /// 720x1280, and 40% faster. Composing at 720 throughout would save
  /// another 25 MB for a reworked graph. Area averaging keeps the verse's
  /// thin strokes from shimmering as they shrink.
  @visibleForTesting
  static String outputScale({bool small = false}) => small
      ? 'scale=720:1280:flags=area:out_color_matrix=bt709:out_range=tv'
      : 'scale=1080:1920:out_color_matrix=bt709:out_range=tv';

  /// The reel opening out of black and closing back into it, as the
  /// filters for *this* pass of it.
  ///
  /// A long reel is encoded a slice at a time and the slices are
  /// joined with a stream copy, so a fade written into every pass
  /// would open and close the reel forty times. It belongs to the
  /// whole: the opening fade only to the pass that starts at zero, the
  /// closing one only to the pass that reaches the end — and there, at
  /// a start time measured in that pass's own clock.
  ///
  /// Passes are never shorter than twenty seconds and a fade is never
  /// longer than six tenths of one, so neither ever straddles a
  /// boundary. The clamp is there for the reel shorter than a pass,
  /// which is encoded in one and whose fade is cut to a fraction of
  /// its length anyway.
  @visibleForTesting
  static String fadeChain(
      ReelEffects effects, int reelMs, int passStartMs, int passMs) {
    final d = effects.fadeMsFor(reelMs);
    if (d <= 0) return '';
    final secs = (d / 1000).toStringAsFixed(3);
    final out = StringBuffer();
    if (passStartMs <= 0) out.write('fade=t=in:st=0:d=$secs,');
    if (passStartMs + passMs >= reelMs) {
      final st = ((reelMs - d - passStartMs) / 1000).clamp(0.0, double.infinity);
      out.write('fade=t=out:st=${st.toStringAsFixed(3)}:d=$secs,');
    }
    return out.toString();
  }

  /// The whole FFmpeg command for a full-frame reel on one background,
  /// from plain values: [cards] are the verse PNGs, each shown for
  /// [cardMs] in turn. With [pass] it is that pass of the reel in
  /// pieces instead — picture only, bounded in frames, and reading its
  /// clip from where [_bgSeekFor] says, for a clip [sourceMs] long.
  ///
  /// Exposed so the command can be checked off-device, and run through
  /// a desktop FFmpeg: which thread a card is decoded on, or where a
  /// pass picks its clip up, is invisible in the code and shows only in
  /// a phone that ran out of memory or a reel that jumps.
  @visibleForTesting
  static String stillReelCommand({
    required String background,
    required List<String> cards,
    int cardMs = 1000,
    String audio = 'a.m4a',
    String watermark = 'wm.png',
    String out = 'out.mp4',
    bool bgIsImage = true,
    int? sourceMs,
    RenderPass? pass,
    int threads = 4,
    int? sceneThreads,
    bool small = false,
  }) {
    final segMs = cards.length * cardMs;
    final clips = [
      for (var i = 0; i < cards.length; i++)
        _OverlayClip(File(cards[i]), i * cardMs, (i + 1) * cardMs, 400),
    ];
    return _buildCommand(
      audioPath: pass == null ? audio : null,
      bgPath: background,
      bgIsImage: bgIsImage,
      bgReady: bgIsImage,
      sceneInputs: null,
      cuts: const [],
      fadeMs: 0,
      scrimPath: null,
      maskPath: null,
      watermarkPath: watermark,
      clips: pass == null ? clips : _clipsIn(clips, pass),
      segStartMs: pass?.startMs ?? 0,
      segMs: pass?.durationMs ?? segMs,
      passStartMs: pass?.startMs ?? 0,
      overlayAlign: 0.5,
      letterbox: null,
      backdrop: LetterboxBackdrop.colour,
      backdropArgb: 0xFF000000,
      outPath: out,
      hardware: false,
      threads: threads,
      sceneThreads: sceneThreads,
      reelMs: segMs,
      small: small,
      frames: pass?.frames,
      bgSeekS: pass == null || bgIsImage
          ? 0
          : _bgSeekFor(
              PictureSpan(
                  startMs: 0,
                  endMs: segMs,
                  isImage: bgIsImage,
                  sourceMs: sourceMs),
              pass),
    );
  }

  /// The scene-run half of the filter graph, built from plain values.
  ///
  /// Exposed because nothing else can check it: the labels, the trim
  /// lengths and the crossfade offsets are the difference between a
  /// reel that cuts where the plan says and one that drifts, and they
  /// are only ever proved right by an encode on a device.
  @visibleForTesting
  static String sceneRunGraph({
    required List<double> lengths,
    required List<SceneCut> cuts,
    required int fadeMs,
    required int segStartMs,
    LetterboxGeometry? letterbox,
    bool colourBackdrop = true,
    int backdropArgb = 0xFF000000,
    int? bandIdx,
    int? maskIdx,
    int? scrimIdx,
    String grade = '',
  }) {
    final f = StringBuffer();
    _writeSceneRun(
      f,
      [for (final l in lengths) _SceneInput('x.mp4', false, l)],
      cuts: cuts,
      fadeMs: fadeMs,
      segStartMs: segStartMs,
      letterbox: letterbox,
      colourBackdrop: colourBackdrop,
      backdropArgb: backdropArgb,
      bandIdx: bandIdx,
      maskIdx: maskIdx,
      scrimIdx: scrimIdx,
      grade: grade,
    );
    return f.toString();
  }

  /// Writes the run of sceneries into [f], ending at label `[v0]`.
  ///
  /// Each scenery becomes its own base frame — the same picture the
  /// single-background graph builds, in whichever format the reel is —
  /// normalised to one size, rate and pixel format, because that is
  /// what joining them requires. Then they are joined: a straight cut
  /// is a concat, a blend is a chain of crossfades whose offsets are
  /// the cut times themselves, so the boundaries land exactly where
  /// [ScenePlan] put them and the run comes out the length of the
  /// recitation to the millisecond.
  ///
  /// The scrim goes on once, after the join: it is the same darkening
  /// whatever is underneath it.
  static void _writeSceneRun(
    StringBuffer f,
    List<_SceneInput> scenes, {
    required List<SceneCut> cuts,
    required int fadeMs,
    required int segStartMs,
    required LetterboxGeometry? letterbox,
    required bool colourBackdrop,
    required int backdropArgb,

    /// The luminous band's input, when the band is one.
    int? bandIdx,
    required int? maskIdx,
    required int? scrimIdx,
    String grade = '',
  }) {
    final n = scenes.length;
    if (letterbox != null && bandIdx != null) {
      f.write('[$bandIdx:v]split=$n');
      for (var i = 0; i < n; i++) {
        f.write('[band$i]');
      }
      f.write(';');
    }
    // One mask, one card per scene: a filter input can only be
    // consumed once, so it is split as many ways as there are cards.
    if (letterbox != null && maskIdx != null) {
      f.write('[$maskIdx:v]split=$n');
      for (var i = 0; i < n; i++) {
        f.write('[m$i]');
      }
      f.write(';');
    }
    for (var i = 0; i < n; i++) {
      final len = scenes[i].seconds.toStringAsFixed(3);
      final source = '$i:v';
      if (letterbox != null) {
        if (bandIdx != null) {
          f.write('[band$i]${_bandLoop(len)}[bgc$i];');
        } else if (colourBackdrop) {
          // In-graph rather than an input per scene: a flat colour is
          // free to generate and costs the command line nothing.
          f.write('color=c=${_ffColor(backdropArgb)}:s=1080x1920:r=30:'
              'd=$len[bgc$i];');
        }
        _writeLetterboxBase(
          f,
          letterbox,
          source: source,
          backdrop: colourBackdrop ? 'bgc$i' : null,
          mask: maskIdx == null ? null : 'm$i',
          out: 'raw$i',
          tag: 's$i',
          // A scene already folded into a finished base frame carries
          // its grade baked in; one the graph still builds takes it
          // here. Half a run graded twice would be the one thing
          // worse than a run not graded at all.
          grade: scenes[i].ready ? '' : grade,
        );
      } else if (scenes[i].ready) {
        // Already the finished 1080x1920 base frame — see the flatten
        // in [render]. Nothing to scale, nothing to crop, no scrim to
        // lay on: the graph reads it and moves on.
        f.write('[$source]null[raw$i];');
      } else {
        f.write('[$source]scale=1080:1920:force_original_aspect_ratio=increase,'
            'crop=1080:1920,${grade}null[raw$i];');
      }
      // Same size, same rate, same pixel format, square pixels,
      // timestamps from zero: xfade and concat both refuse anything
      // less. Some sceneries carry no aspect at all (0:1) and a scaled
      // wide one comes out a hair off 1:1, and either beside a still
      // was a graph the encoder never got to see.
      f.write('[raw$i]fps=30,format=yuv420p,setsar=1,trim=duration=$len,'
          'setpts=PTS-STARTPTS[b$i];');
    }
    if (n == 1) {
      f.write('[b0]null[joined];');
    } else if (fadeMs == 0) {
      for (var i = 0; i < n; i++) {
        f.write('[b$i]');
      }
      f.write('concat=n=$n:v=1:a=0[joined];');
    } else {
      final d = (fadeMs / 1000).toStringAsFixed(3);
      var prev = 'b0';
      for (var i = 1; i < n; i++) {
        // Every scene but the last was read a blend longer than its
        // cut, which is exactly what makes each offset the cut time.
        final at = ((cuts[i].startMs - segStartMs) / 1000).toStringAsFixed(3);
        final label = i == n - 1 ? 'joined' : 'xf$i';
        f.write('[$prev][b$i]xfade=transition=fade:duration=$d:'
            'offset=$at[$label];');
        prev = label;
      }
    }
    if (scrimIdx != null) {
      f.write('[joined][$scrimIdx:v]overlay=0:0[v0];');
    } else {
      f.write('[joined]null[v0];');
    }
  }

  /// Writes one scenery's letterbox base frame into [f], ending at
  /// label [out]: the backdrop, with the card composited onto it.
  ///
  /// [source] is the scenery's stream. With a blurred backdrop it is
  /// used twice — once filled to the frame and blurred, once cropped
  /// into the card — which is what the split is for; [backdrop] names
  /// a ready one (the flat colour) instead. [tag] keeps the
  /// intermediate labels apart when a reel builds one of these per
  /// scene.
  ///
  /// [grade] is applied once, before the split: the blurred backdrop
  /// and the card are the same photograph. The backdrop colour is not
  /// graded — it is a colour the user picked, not footage.
  static void _writeLetterboxBase(
    StringBuffer f,
    LetterboxGeometry box, {
    required String source,
    required String? backdrop,
    required String? mask,
    required String out,
    String tag = '',
    String grade = '',
  }) {
    // Graded once, before the split: the blurred backdrop and the card
    // are the same photograph, and grading them separately is two
    // passes over the pixels to reach the same frame.
    var src = source;
    if (grade.isNotEmpty) {
      f.write('[$src]${grade}null[graded$tag];');
      src = 'graded$tag';
    }
    final String cardSrc;
    if (backdrop != null) {
      f.write('[$backdrop]null[bgbase$tag];');
      cardSrc = src;
    } else {
      f.write('[$src]split=2[bgsrc$tag][cardsrc$tag];');
      // Blur at a fraction of the size and let the upscale do the
      // smoothing: a wide gaussian over two megapixels a frame is not
      // something a phone can spend its render budget on, and at this
      // radius the result is indistinguishable. Darkened and
      // desaturated so the backdrop stays backdrop.
      //
      // flags=area on the way down: swscale's default bicubic samples
      // rather than averages, so a twelvefold reduction aliased every
      // fine texture — foliage, water sparkle, city lights — into
      // high-frequency speckle that the upscale then magnified. The
      // blur was always the same; how blurred it *looked* depended
      // entirely on how busy the picture was. Area averaging is the
      // reduction this step always meant.
      //
      // The tone rides *before* the upscale, where there are 144 times
      // fewer pixels to touch — a scaling matrix commutes with a linear
      // resize, and measured against doing it after, the frame differs
      // by about one level with no loss of distinct tones.
      f.write('[bgsrc$tag]scale=1080:1920:'
          'force_original_aspect_ratio=increase,'
          'crop=1080:1920,scale=90:160:flags=area,gblur=sigma=6,'
          'format=gbrp,colorchannelmixer=${BackdropTone.ffmpegMix},'
          'scale=1080:1920[bgbase$tag];');
      cardSrc = 'cardsrc$tag';
    }
    final w = box.cardW.round();
    final h = box.cardH.round();
    f.write('[$cardSrc]scale=$w:$h:force_original_aspect_ratio=increase,'
        'crop=$w:$h');
    if (mask != null) {
      // The mask's luma becomes the card's alpha, so the corners are
      // cut by a static PNG instead of a per-pixel expression.
      f.write(',format=rgba[cardsq$tag];[$mask]format=gray[cardmask$tag];'
          '[cardsq$tag][cardmask$tag]alphamerge[card$tag];');
    } else {
      f.write('[card$tag];');
    }
    f.write('[bgbase$tag][card$tag]overlay=${box.cardX.round()}:'
        '${box.cardY.round()}[$out];');
  }

  /// An ARGB int as an FFmpeg colour literal. Alpha is dropped: the
  /// backdrop is the bottom of the frame and has nothing to blend with.
  /// A luminous band's one decoded frame, held and repeated for [seconds]
  /// (a fixed-point string) at the input's 30 fps. The filter keeps that
  /// one frame; read as a looped input, the PNG was decoded afresh for
  /// every frame — the band reel's encode went from 43 s to 35 s on the
  /// runner, and 80 MB lighter at its peak (2026-10-21).
  static String _bandLoop(String seconds) =>
      'loop=loop=-1:size=1:start=0,trim=duration=$seconds';

  /// What a band behind a wide card is, for a cache key: the blur, a
  /// luminous ground by name, or a flat colour by its value.
  static String _bandKey(
          LetterboxBackdrop backdrop, int backdropArgb, BandGlow glow) =>
      switch (backdrop) {
        LetterboxBackdrop.blur => 'blur',
        LetterboxBackdrop.glow => 'g${glow.key}',
        LetterboxBackdrop.colour => backdropArgb.toRadixString(16),
      };

  static String _ffColor(int argb) =>
      '0x${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Bakes a still-sourced letterbox reel's entire base frame — the
  /// backdrop plus the card, corners and all — into one 1080x1920 PNG.
  ///
  /// Every frame of such a reel has an identical base, so doing it here
  /// takes the blur, the scale, the crop and the alphamerge off the
  /// per-frame path entirely. Returns null on any failure, in which
  /// case the caller keeps the per-frame graph: this is an
  /// optimization, never a correctness requirement.
  static Future<File?> _flattenLetterbox(
    File src,
    LetterboxGeometry box,
    String? maskPath,
    LetterboxBackdrop backdrop,
    int backdropArgb,
    Directory tmp,
    String grade, {
    BandGlow bandGlow = BandGlow.midnight,
    String? bandPath,
  }) async {
    File? out;
    File? part;
    try {
      final stat = src.statSync();
      // v3: the backdrop's darkening went from a fixed subtraction to a
      // scaling, so every flattened base frame cached before it is now
      // wrong. (v2 was the downscale moving to area averaging.)
      final key = 'v3_${src.path.hashCode.toRadixString(16)}_'
          '${stat.size}_${stat.modified.millisecondsSinceEpoch}_'
          '${box.key}_${maskPath != null ? 'r' : 's'}_'
          '${_bandKey(backdrop, backdropArgb, bandGlow)}'
          // A base frame graded one way must never be served for a reel
          // graded another.
          '${grade.isEmpty ? '' : '_g${grade.hashCode.toRadixString(16)}'}';
      out = File('${tmp.path}/ayah_lbflat_$key.png');
      if (_reuse(out)) return out;
      part = _partOf(out);

      final f = StringBuffer();
      final inputs = StringBuffer('-i "${src.path}" ');
      int? maskIdx;
      if (maskPath != null) {
        inputs.write('-i "$maskPath" ');
        maskIdx = 1;
      }
      int? colourIdx;
      if (backdrop == LetterboxBackdrop.glow && bandPath != null) {
        inputs.write('-i "$bandPath" ');
        colourIdx = maskIdx == null ? 1 : 2;
      } else if (backdrop == LetterboxBackdrop.colour) {
        inputs.write('-f lavfi -i '
            '"color=c=${_ffColor(backdropArgb)}:s=1080x1920:d=1" ');
        colourIdx = maskIdx == null ? 1 : 2;
      }
      _writeLetterboxBase(
        f,
        box,
        source: '0:v',
        backdrop: colourIdx == null ? null : '$colourIdx:v',
        mask: maskIdx == null ? null : '$maskIdx:v',
        out: 'v0',
        grade: grade,
      );
      // Trailing separator would read as an empty filterchain.
      final graph = f.toString().replaceFirst(RegExp(r';$'), '');
      final session = await FFmpegKit.execute(
        '$inputs-filter_complex "$graph" -map "[v0]" '
        '-frames:v 1 -pix_fmt rgb24 -y "${part.path}"',
      );
      if (await _landedOk(session, part, out)) return out;
      rlog('render: letterbox flatten failed — using per-frame graph');
    } catch (e) {
      rlog('render: letterbox flatten threw $e');
    }
    _dropPart(part);
    return null;
  }

  /// Bakes a still backdrop into the finished 1080x1920 base frame:
  /// the same fill-and-crop the graph used to do per frame, with the
  /// scrim composited on top. Returns null if anything goes wrong, in
  /// which case the caller keeps the per-frame path — this is an
  /// optimization, never a correctness requirement.
  ///
  /// Blending is forced through RGB and written as rgb24 so the
  /// intermediate never round-trips through subsampled chroma; the one
  /// colour conversion still happens where it always did, at the end of
  /// the render graph.
  ///
  /// Cached on the source's identity (path, size, mtime), so re-picking
  /// the same photo costs nothing.
  /// Folds every scenery in a run into its own finished base frame.
  ///
  /// All or nothing: one scene that will not flatten leaves the whole
  /// run on the per-frame path, because a half-baked run would scrim
  /// some of its scenes twice and others not at all.
  static Future<List<_SceneInput>?> _flattenScenes(
    List<_SceneInput> scenes,
    String scrimPath,
    Directory tmp,
    String grade,
  ) async {
    final out = <_SceneInput>[];
    for (final s in scenes) {
      final flat = await _flattenStill(File(s.path), scrimPath, tmp, grade);
      if (flat == null) {
        rlog('render: scene flatten failed — keeping the per-frame graph');
        return null;
      }
      out.add(_SceneInput(
        flat.path,
        true,
        s.seconds,
        seekS: s.seekS,
        sourceMs: s.sourceMs,
        ready: true,
      ));
    }
    rlog('render: ${out.length} scenes pre-flattened');
    return out;
  }

  static Future<File?> _flattenStill(
      File src, String scrimPath, Directory tmp, String grade) async {
    File? out;
    File? part;
    try {
      final stat = src.statSync();
      final key = '${src.path.hashCode.toRadixString(16)}_'
          '${stat.size}_${stat.modified.millisecondsSinceEpoch}'
          // Both of the things composited into this PNG that the
          // source file cannot account for: the grade, and the scrim —
          // whose own file name already carries whatever vignette was
          // painted into it, so its path is the whole of what
          // distinguishes one from another.
          '${grade.isEmpty ? '' : '_g${grade.hashCode.toRadixString(16)}'}'
          '_s${scrimPath.hashCode.toRadixString(16)}';
      out = File('${tmp.path}/ayah_bgflat_$key.png');
      if (_reuse(out)) return out;
      part = _partOf(out);
      final session = await FFmpegKit.execute(
        '-i "${src.path}" -i "$scrimPath" -filter_complex '
        '"[0:v]scale=1080:1920:force_original_aspect_ratio=increase,'
        'crop=1080:1920,${grade}format=rgba[b];'
        '[b][1:v]overlay=0:0:format=rgb[o]" '
        '-map "[o]" -frames:v 1 -pix_fmt rgb24 -y "${part.path}"',
      );
      if (await _landedOk(session, part, out)) return out;
      rlog('render: background flatten failed — using per-frame scrim');
    } catch (e) {
      rlog('render: background flatten threw $e');
    }
    _dropPart(part);
    return null;
  }

  // A flattened base frame is made under a name of its own and renamed
  // into place whole. Made straight onto the shared name, a render that
  // came along while it was being written took a half-written frame,
  // and one that failed deleted the frame another render was about to
  // encode from ("ayah_bgflat_….png: No such file or directory").

  /// One already made, whole: used again, and marked as used now so the
  /// cache sweep counts it from its last use rather than its first.
  static bool _reuse(File out) {
    if (!out.existsSync() || out.lengthSync() == 0) return false;
    try {
      out.setLastModifiedSync(DateTime.now());
    } catch (_) {}
    return true;
  }

  static File _partOf(File out) => File(
      '${out.path.substring(0, out.path.length - '.png'.length)}'
      '.part${DateTime.now().microsecondsSinceEpoch}.png');

  /// Whether [session] wrote [part] whole, which then becomes [out].
  static Future<bool> _landedOk(
      FFmpegSession session, File part, File out) async {
    if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
        !part.existsSync() ||
        part.lengthSync() == 0) {
      return false;
    }
    part.renameSync(out.path);
    return true;
  }

  static void _dropPart(File? part) {
    if (part == null) return;
    try {
      if (part.existsSync()) part.deleteSync();
    } catch (_) {}
  }

  /// Bundled assets already copied out this process, by path, with the
  /// length written — see [_materializeAsset].
  static final Map<String, int> _materialized = {};

  static Future<File> _materializeAsset(String asset, Directory dir) async {
    final f = File('${dir.path}/${asset.split('/').last}');
    // Once per process, not once per render. A bundled clip is several
    // megabytes, and this used to read it out of the bundle and write
    // it to disk again on *every* render — every eager re-render after
    // a slider nudge included — for a file already sitting there.
    final known = _materialized[f.path];
    if (known != null && f.existsSync() && f.lengthSync() == known) return f;
    final data = await rootBundle.load(asset);
    if (!(f.existsSync() && f.lengthSync() == data.lengthInBytes)) {
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    _materialized[f.path] = data.lengthInBytes;
    return f;
  }

  static Future<File?> _materializeAssetOrNull(
      String asset, Directory dir) async {
    try {
      return await _materializeAsset(asset, dir);
    } catch (_) {
      return null;
    }
  }
}
