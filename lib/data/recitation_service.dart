import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'debug_log.dart';
import 'download.dart';
import 'ffmpeg_progress.dart';
import 'ffmpeg_setup.dart';
import 'models.dart';
import 'reel_limits.dart';
import 'surah_index.dart';
import 'surah_slice.dart';
import 'trouble.dart';
import 'whole_file.dart';

/// Builds and caches one [Recitation] per (reciter, surah, ayah range).
///
/// Beyond the bundled Al-Fatiha, audio comes one of two ways (see
/// [AudioSource]). Per-ayah files (EveryAyah and the like): each file
/// is downloaded once, its duration measured with ffprobe, and the
/// files joined into one file — so the timing table is exact by
/// construction, the same recipe used to build the bundled assets (see
/// tool/verify_timings.md), now run on-device for any surah. One file
/// per surah with a published ayah table: only the bytes of the range
/// are fetched, and the table's boundaries are moved into the
/// reciter's breath — see [SurahSlice].
///
/// Only the requested ayah range is fetched, so a whole long surah is
/// never downloaded for the sake of a few verses of it. The
/// per-ayah parts and their measured durations persist on disk, so a
/// later range of the same surah downloads and probes only the ayahs
/// it hasn't seen yet.
abstract final class RecitationService {
  /// Suffix on every assembled recitation, bumped when the way one is
  /// assembled changes so the files built the old way are not served.
  ///
  /// `j2`: the parts are re-encoded into the joined file rather than
  /// stream-copied into it. See [_join] for why, and for what a
  /// `j1` file could be holding.
  ///
  /// `j3`: that re-encode produces AAC in an MP4 container rather than
  /// MP3. Same single clean pass, different codec — see [_join]. The
  /// bump is what stops a `j2` mp3 left on disk from being served
  /// under a name the code now expects to be `.m4a`.
  static const _joinVersion = 'j3';

  /// Container extension of an assembled recitation. One place, because
  /// the writer and both cache lookups have to agree on it.
  static const _joinExt = 'm4a';

  /// Exact-range cache: one entry per (reciter, surah, start, end).
  static final _memory = <String, Recitation>{};

  /// Widest-coverage entry per (reciter, surah) — the sync lookup the
  /// verse picker uses for duration labels.
  static final _best = <String, Recitation>{};

  static final _inFlight = <String, _Job>{};

  /// Test seams, null in the app: a stand-in for FFmpegKit (runs one
  /// command line, says whether it succeeded), one for FFprobe's
  /// duration, and the folder recitations are kept in. They let
  /// test/tools/recitation_service_live_test.dart run everything else
  /// here as the phone does, with the desktop's ffmpeg underneath.
  @visibleForTesting
  static Future<bool> Function(String command)? debugFfmpeg;
  @visibleForTesting
  static Future<int> Function(String path)? debugProbeMs;
  @visibleForTesting
  static Directory? debugRoot;

  /// Forgets every recitation held in memory, as a fresh launch would.
  @visibleForTesting
  static void debugReset() => forgetAll();

  /// Forgets every recitation held in memory: for when the files behind
  /// them are deleted (the storage sheet's clear), so none is served
  /// from a path that no longer exists.
  static void forgetAll() {
    _memory.clear();
    _best.clear();
  }

  /// One per-ayah file, fetched as a build fetches it, from whatever
  /// [client] plays the server: one that drops, stalls or refuses.
  @visibleForTesting
  static Future<void> debugDownload(http.Client client, Uri url, File target,
          {void Function(double fraction)? onFraction}) =>
      _download(client, url, target, 'test', onFraction: onFraction);

  static String _rangeKey(String reciterId, int surah, int start, int end) =>
      '${reciterId}_${surah}_${start}_$end';

  static String _surahKey(String reciterId, int surah) =>
      '${reciterId}_$surah';

  /// Non-null if a recitation for this surah is ready without any work
  /// — used for instant duration labels in the verse picker. May cover
  /// only part of the surah: check [Recitation.covers] before indexing.
  static Recitation? cached(String reciterId, int surah) =>
      _best[_surahKey(reciterId, surah)];

  /// Fire-and-forget warm-up so the preview screen usually finds the
  /// recitation already prepared. Failures are ignored here — the
  /// preview screen loads (and surfaces errors) properly.
  static void prefetch(Reciter reciter, int surah,
      {int? startAyah, int? endAyah}) {
    rlog('rec: prefetch ${reciter.id} $surah:$startAyah-$endAyah');
    load(reciter, surah, startAyah: startAyah, endAyah: endAyah)
        .then<void>((_) => rlog('rec: prefetch done $surah'))
        // Ignored, but never unseen. This used to be `catchError((_) {})`
        // — the warm-up behind a Moment failing in complete silence,
        // and the preview then reporting the same failure a screen
        // later with nothing to say about where it came from.
        .catchError((Object e, StackTrace st) {
      rlogError('rec: prefetch ${reciter.id} $surah', e, st);
    });
  }

  /// Recitation covering [startAyah]..[endAyah] (whole surah when
  /// omitted). [onProgress] reports 0..1 across download+measure and
  /// concat.
  ///
  /// The fetch stops once the range on disk is already longer than a
  /// reel may be ([maxMs], the cap by default): audio past the cap is
  /// data spent on ayahs that could never appear in the export. The
  /// recitation then comes back covering fewer ayahs than were asked
  /// for — callers trim to what it covers, which is what they do with
  /// the cap anyway. Applied here rather than by each caller so that
  /// the preview and the prefetch behind it always agree on how much of
  /// a selection there is to fetch.
  static Future<Recitation> load(
    Reciter reciter,
    int surah, {
    int? startAyah,
    int? endAyah,
    int? maxMs,
    void Function(double progress)? onProgress,
  }) async {
    if (!reciter.hasSurah(surah)) throw SurahUnavailable(reciter, surah);
    final count = surahIndex.firstWhere((s) => s.number == surah).ayahCount;
    final start = (startAyah ?? 1).clamp(1, count);
    final end = (endAyah ?? count).clamp(start, count);

    // Any already-loaded recitation covering the range serves it: its
    // timings are absolute within its own file, so seeks stay exact.
    final key = _rangeKey(reciter.id, surah, start, end);
    rlog('rec: load $key (surah has $count ayahs)');
    // A hit whose file has gone since (cleared by the storage sheet) is
    // no hit: it is built again below.
    bool onDisk(Recitation r) => File(r.audioPath).existsSync();
    final exact = _memory[key];
    if (exact != null && onDisk(exact)) {
      rlog('rec: memory hit $key');
      onProgress?.call(1);
      return exact;
    }
    final cap = maxMs ?? ReelLimits.maxReelMs;
    final best = _best[_surahKey(reciter.id, surah)];
    if (best != null && onDisk(best) && _serves(best, start, end, cap)) {
      rlog('rec: memory hit via ${best.firstAyah}-${best.lastAyah}');
      onProgress?.call(1);
      return best;
    }
    // Coalesce concurrent requests (prefetch + preview screen).
    //
    // Joining an existing job has to bring your own progress with you.
    // It used to hand back the future and nothing else, and the one
    // caller who cared about progress was almost always the second one:
    // a Moment warms the recitation from the Home screen with no
    // progress callback at all, and the preview then arrives, joins
    // that job, and sits at nought per cent with no bar moving for as
    // long as the download takes. On a slow connection that is
    // indistinguishable from a screen that has hung, and if the fetch
    // then times out the user has watched nothing happen and been told
    // to check their connection.
    final existing = _inFlight[key];
    if (existing != null) {
      rlog('rec: joining in-flight $key');
      existing.listen(onProgress);
      try {
        return await existing.future;
      } finally {
        existing.unlisten(onProgress);
      }
    }

    final job = _Job()..listen(onProgress);
    _inFlight[key] = job;
    job.future = _build(reciter, surah, start, end, count, cap, job.report);
    try {
      final rec = await job.future;
      rlog('rec: built $key -> ${rec.firstAyah}-${rec.lastAyah} '
          '${rec.audioPath}');
      _store(rec);
      // Cut short by the cap, it is stored under the range it covers;
      // remembered under the one asked for too, or asking again misses
      // memory every time.
      if (maxMs == null) _memory[key] = rec;
      return rec;
    } catch (e, st) {
      rlogError('rec: build $key', e, st);
      rethrow;
    } finally {
      job.unlisten(onProgress);
      _inFlight.remove(key);
    }
  }

  /// Whether [rec] can answer a request for [start]..[end]: it covers
  /// the range, or it covers [start] and already runs past [maxMs] from
  /// there — all a build of the range would fetch, since the build
  /// stops at the verse that crosses the cap.
  static bool _serves(Recitation rec, int start, int end, int maxMs) {
    if (rec.covers(start, end)) return true;
    if (!rec.covers(start, start)) return false;
    return rec.timings.last.endMs - rec.timing(start).startMs > maxMs;
  }

  static void _store(Recitation rec) {
    _memory[_rangeKey(rec.reciterId, rec.surah, rec.firstAyah, rec.lastAyah)] =
        rec;
    final sKey = _surahKey(rec.reciterId, rec.surah);
    final best = _best[sKey];
    if (best == null ||
        rec.timings.length > best.timings.length ||
        !File(best.audioPath).existsSync()) {
      _best[sKey] = rec;
    }
  }

  static Future<Recitation> _build(
    Reciter reciter,
    int surah,
    int start,
    int end,
    int count,
    int maxMs,
    void Function(double)? onProgress,
  ) async {
    if (surah == 1 && reciter.hasBundledFatiha) {
      return _bundled(reciter, onProgress);
    }

    // Before the first probe, not after the first export: the ten
    // concurrent ffprobe sessions below are read back by id, and how
    // many of them still exist when that happens is a process-wide
    // setting this used to inherit from whatever the renderer had done.
    if (debugFfmpeg == null) await configureFfmpeg();

    final dir = await _reciterDir(reciter.id);

    // Disk cache from an earlier session — full surah or any stored
    // range that covers this one.
    final disk = _fromDisk(dir, reciter, surah, start, end, maxMs);
    if (disk != null) {
      rlog('rec: disk hit ${disk.audioPath}');
      onProgress?.call(1);
      return disk;
    }
    final source = reciter.source;
    if (source is SurahFiles) {
      return _fromSurahFile(
          reciter, source, dir, surah, start, end, count, maxMs, onProgress);
    }
    if (source is! AyahFiles) {
      throw StateError('${reciter.id} has no recitation to download');
    }
    rlog('rec: fetching ${source.folder} $surah:$start-$end');

    final parts = Directory('${dir.path}/parts_$surah')
      ..createSync(recursive: true);
    final durFile = File('${dir.path}/durations_$surah.json');
    final durations = _readDurations(durFile);

    // 1+2) Download and measure, fused: each lane probes its file the
    // moment the bytes land, so the measure phase rides inside the
    // network wait instead of running as its own pass afterwards.
    // Parts already on disk with a recorded duration cost nothing.
    final ayahs = [for (var a = start; a <= end; a++) a];
    final tag = '${start}_$end';
    var done = 0;
    // How far along each file in flight is. The bar used to move only
    // as files were finished, and on a slow link ten long verses can
    // take a minute or more to finish together: a minute at nought,
    // which looks like nothing happening at all.
    final partly = <int, double>{};
    void report() {
      final inFlight = partly.values.fold(0.0, (a, b) => a + b);
      onProgress
          ?.call(((done + inFlight) / ayahs.length * 0.95).clamp(0.0, 0.95));
    }

    const lanes = 10;
    final client = http.Client();
    try {
      for (var s = 0; s < ayahs.length; s += lanes) {
        final batch = <Future<void>>[];
        for (var i = s; i < ayahs.length && i < s + lanes; i++) {
          final a = ayahs[i];
          final f = File('${parts.path}/${_ayahFileName(surah, a)}');
          batch.add(() async {
            await _download(client, source.url(surah, a), f, tag,
                onFraction: onProgress == null
                    ? null
                    : (v) {
                        partly[a] = v;
                        report();
                      });
            try {
              durations[a] ??= await _probeMs(f);
            } catch (_) {
              // Unreadable bytes (a portal's page, a cut file) would be
              // reused by every later build: drop them so the next try
              // fetches the file again.
              _deleteQuietly(f);
              rethrow;
            }
            partly.remove(a);
            done++;
            report();
          }());
        }
        await Future.wait(batch);
        rlog('rec: $done/${ayahs.length} parts ready');
        // Stop once what is already on disk runs longer than a reel
        // may be. The ayah that crosses the line is kept — the preview
        // trims to the last one that *fits*, and it can only know which
        // that is from a timing that doesn't.
        var total = 0;
        for (var i = 0; i < ayahs.length; i++) {
          final d = durations[ayahs[i]];
          if (d == null) break; // not measured yet: settled next batch
          total += d;
          if (total > maxMs && i + 1 < ayahs.length) {
            rlog('rec: cap ${maxMs}ms reached at ayah ${ayahs[i]} — '
                'dropping ${ayahs.length - i - 1} more');
            ayahs.removeRange(i + 1, ayahs.length);
            break;
          }
        }
      }
    } finally {
      client.close();
    }
    await durFile.writeAsString(jsonEncode(
        {for (final e in durations.entries) '${e.key}': e.value}));

    // 3) Join the range into one file. The range is named for what was
    // actually fetched, which is not what was asked for when [maxMs]
    // cut it short.
    final last = ayahs.last;
    final rangeTag = '${start}_$last';
    final full = start == 1 && last == count;
    final stem = '${dir.path}/'
        '${full ? '$surah' : '${surah}_$rangeTag'}.$_joinVersion';
    final audio = File('$stem.$_joinExt');
    final meta = File('$stem.json');
    final files = [
      for (final a in ayahs) File('${parts.path}/${_ayahFileName(surah, a)}'),
    ];

    // Cumulative sums -> exact ayah windows for the joined file.
    final timings = <AyahTiming>[];
    var t = 0;
    for (final a in ayahs) {
      final d = durations[a]!;
      timings.add(AyahTiming(a, t, t + d));
      t += d;
    }
    rlog('rec: joining ${files.length} parts -> ${audio.path} (${t}ms)');
    await _join(
      files,
      audio,
      parts,
      tag,
      expectedMs: t,
      // The download owns 0..0.95; the encode fills what is left, so a
      // long reel's join is something the user can watch happen.
      onProgress:
          onProgress == null ? null : (v) => onProgress(0.95 + v * 0.05),
    );
    await meta.writeAsString(jsonEncode([
      for (final w in timings) {'a': w.ayah, 's': w.startMs, 'e': w.endMs},
    ]));
    // Parts stay on disk: they're the incremental cache that makes the
    // next range of this surah cheap. The storage sheet clears them.

    onProgress?.call(1);
    return Recitation(
      reciterId: reciter.id,
      surah: surah,
      audioPath: audio.path,
      timings: timings,
    );
  }

  // ---- one file per surah, and a table of where each ayah is -----------

  /// [start]..[end] of [surah] from a voice that comes as one file per
  /// surah and a published table of where each ayah sits in it. How the
  /// slice is found, cut and snapped to the reciter's breath is all in
  /// [SurahSlice]; this is the part with a network, a disk and FFmpeg.
  static Future<Recitation> _fromSurahFile(
    Reciter reciter,
    SurahFiles source,
    Directory dir,
    int surah,
    int start,
    int end,
    int count,
    int maxMs,
    void Function(double)? onProgress,
  ) async {
    final client = http.Client();
    final url = source.url(surah);
    final Mp3Layout lay;
    final List<AyahTiming> table;
    try {
      lay = await Mp3Layout.read(client, url);
      table = SurahSlice.withFileEnd(
          await _surahTable(source, dir, surah, count), lay.durationMs);
    } catch (_) {
      client.close();
      rethrow;
    }

    // The cap, from the table: nothing past the verse that crosses it
    // is fetched. The crossing verse is kept, as the per-ayah path
    // keeps it — the preview trims to the last verse that fits.
    var last = start;
    var total = 0;
    for (var a = start; a <= end; a++) {
      total += table[a - 1].durationMs;
      last = a;
      if (total > maxMs && a < end) {
        rlog('rec: cap ${maxMs}ms reached at ayah $a — '
            'dropping ${end - a} more');
        break;
      }
    }
    final from = table[start - 1].startMs;
    final to = table[last - 1].endMs;
    rlog('rec: slicing $url $surah:$start-$last (${from}ms..${to}ms)');

    final tag = '${start}_$last';
    final slice = File('${dir.path}/slice_${surah}_$tag.mp3');
    final pcm = File('${slice.path}.pcm');
    try {
      // Room past both ends for the edges to find their silence in.
      final originMs = await SurahSlice.fetch(
        client,
        url,
        lay,
        slice,
        fromMs: from - SurahSlice.edgeMs - 1000,
        toMs: to + SurahSlice.edgeMs + 1000,
        onProgress: onProgress == null ? null : (v) => onProgress(v * 0.85),
      );
      await _decodeMono(slice, pcm);
      // compute, not Isolate.run with a closure: a closure made in here
      // carries every variable any closure here captures — onProgress
      // among them, and through it the preview screen — and a screen
      // cannot be sent to another isolate. That failed every surah-file
      // voice on the phone as "check your connection".
      final env = await compute(SurahSlice.envelopeOf, pcm.path);
      onProgress?.call(0.9);
      final SlicePlan plan;
      try {
        plan = SurahSlice.plan(
          table: table,
          start: start,
          last: last,
          originMs: originMs,
          env: env,
          // At-Tawbah alone opens with no basmala before its verse 1.
          openingMs: start == 1 && surah != 9 ? source.openingMs : null,
        );
      } on FormatException catch (e) {
        throw TroubleException(Trouble.host,
            "surah $surah's ayah table doesn't fit its audio", e.message);
      }

      final full = start == 1 && last == count;
      final stem = '${dir.path}/'
          '${full ? '$surah' : '${surah}_$tag'}.$_joinVersion';
      final audio = File('$stem.$_joinExt');
      await _encode(
        '-i "${slice.path}" '
        '-ss ${plan.cutStart / 1000} -to ${plan.cutEnd / 1000}',
        audio,
        expectedMs: plan.cutEnd - plan.cutStart,
        what: 'slice of surah $surah',
        onProgress:
            onProgress == null ? null : (v) => onProgress(0.9 + v * 0.1),
      );
      // Where the cut starts in the surah's own file, kept beside it:
      // what places words timed against that file on this one.
      final origin = (originMs + plan.cutStart).round();
      await File('$stem.origin').writeAsString('$origin');
      await File('$stem.json').writeAsString(jsonEncode([
        for (final w in plan.timings)
          {'a': w.ayah, 's': w.startMs, 'e': w.endMs},
      ]));
      onProgress?.call(1);
      return Recitation(
        reciterId: reciter.id,
        surah: surah,
        audioPath: audio.path,
        timings: plan.timings,
        originMs: origin,
      );
    } finally {
      client.close();
      for (final f in [slice, pcm]) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// The published table for [surah], as checked by
  /// [SurahSlice.parseTable]. Fetched once and kept: it is a few
  /// kilobytes, and the file it describes doesn't change.
  static Future<List<AyahTiming>> _surahTable(
      SurahFiles source, Directory dir, int surah, int count) async {
    final f = File('${dir.path}/table_$surah.json');
    if (f.existsSync()) {
      try {
        return SurahSlice.checkedTable(
            _decodeTimings(f.readAsStringSync()), count);
      } catch (_) {
        // Corrupt, or from an older build: fetch it again.
      }
    }
    Object? last;
    final client = http.Client();
    try {
      for (var attempt = 1; attempt <= Download.attempts; attempt++) {
        try {
          final res =
              await Download.get(client, source.timing.url(surah, count));
          if (res.statusCode != 200) throw BadStatus(res.statusCode);
          final table = SurahSlice.parseTable(
              source.timing, jsonDecode(res.body), surah, count);
          await f.writeAsString(jsonEncode([
            for (final w in table) {'a': w.ayah, 's': w.startMs, 'e': w.endMs},
          ]));
          return table;
        } on FormatException catch (e) {
          // Retrying won't mend a table that is wrong.
          throw TroubleException(Trouble.host,
              'the ayah table for surah $surah is unusable', e.message);
        } catch (e) {
          last = e;
          rlog('rec: timing try $attempt/${Download.attempts} failed for '
              'surah $surah — $e');
          if (Download.isFinal(e)) break;
          if (attempt < Download.attempts) {
            await Future<void>.delayed(Download.backoff(attempt));
          }
        }
      }
    } finally {
      client.close();
    }
    throw TroubleException(troubleOf(last!),
        'fetching the ayah table for surah $surah', last);
  }

  /// The loudness of a whole recording, in 10 ms steps (see
  /// [SurahSlice.envelopeOf]): where its pauses are, which is what a
  /// verse cut into lines is timed by when the voice has no word
  /// timing, and where each verse's sound begins, which is what places
  /// QUL's words on it (see `QulWords`). Kept for the file it was
  /// measured from, while the file stays the same; null when it could
  /// not be decoded.
  static Future<List<double>?> loudness(String audioPath) async {
    final f = File(audioPath);
    if (!f.existsSync()) return null;
    final stamp = '$audioPath|${f.lengthSync()}|'
        '${f.lastModifiedSync().millisecondsSinceEpoch}';
    final kept = _loudness.remove(stamp);
    if (kept != null) return _loudness[stamp] = kept;
    final pcm = File('${(await getTemporaryDirectory()).path}/'
        'loudness_${stamp.hashCode.toUnsigned(32).toRadixString(36)}.pcm');
    try {
      if (debugFfmpeg == null) await configureFfmpeg();
      await _decodeMono(f, pcm);
      final env = await compute(SurahSlice.envelopeOf, pcm.path);
      _loudness[stamp] = env;
      while (_loudness.length > 4) {
        _loudness.remove(_loudness.keys.first);
      }
      return env;
    } catch (e) {
      rlog('rec: loudness of $audioPath failed ($e)');
      return null;
    } finally {
      try {
        if (pcm.existsSync()) pcm.deleteSync();
      } catch (_) {}
    }
  }

  /// The last few recordings measured, by file and version, oldest
  /// first: a reel's own, and the verses the picker's listen has just
  /// placed words on, without one pushing the other out.
  static final _loudness = <String, List<double>>{};

  /// [audio] decoded to raw mono 16-bit samples at [SurahSlice.envRate],
  /// for [SurahSlice.envelopeOf]. On this isolate: FFmpeg is a plugin,
  /// and a plugin's channel only answers the isolate that owns it.
  static Future<void> _decodeMono(File audio, File pcm) async {
    final command = '-i "${audio.path}" -ac 1 '
        '-ar ${SurahSlice.envRate} -f s16le -y "${pcm.path}"';
    final hook = debugFfmpeg;
    if (hook != null) {
      if (!await hook(command)) {
        throw const TroubleException(
            Trouble.device, 'decoding the recitation audio');
      }
      return;
    }
    final session = await FFmpegKit.executeAsync(command);
    var code = await session.getReturnCode();
    while (code == null) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      code = await session.getReturnCode();
    }
    if (!ReturnCode.isSuccess(code)) {
      throw const TroubleException(
          Trouble.device, 'decoding the recitation audio');
    }
  }

  /// Joins the per-ayah parts into the one file the preview plays and
  /// the exporter muxes, then checks the result really is as long as
  /// the timing table says.
  ///
  /// **Re-encoded, not stream-copied.** `-c copy` is the obvious way to
  /// join mp3s, and it was what this did: the frames are already mp3,
  /// so copying them is exact and instant. What it also does is carry
  /// every part's own file structure into the middle of the joined
  /// stream — each source's Xing/LAME header frame, and whatever
  /// trailing bytes (ID3v1, Lyrics3, APE) the encoder behind the CDN
  /// left on the end of it. FFmpeg reads straight past all of that.
  /// Android's own MP3 extractor does not: it meets the junk
  /// mid-stream, cannot resync, and reports the file as finished — at
  /// the same point every time, a verse or two in. The preview then
  /// loops that fragment for good and never reaches the rest of the
  /// recitation, which is exactly what it looked like.
  ///
  /// It went unseen because a reel was capped at ninety seconds until
  /// recently: a range was three or four files, and the odds of one of
  /// them carrying a trailer were small. An hour is hundreds of files,
  /// and the first bad one ends the recitation there.
  ///
  /// One encode over the joined stream leaves a single clean file with
  /// one header and nothing in the middle of it. The cost is a pass
  /// over audio already on disk, once per range, cached from then on;
  /// the timing table stays the sum of the measured parts, which the
  /// check below confirms the file agrees with.
  ///
  /// **AAC in MP4, not MP3.** The encoder is FFmpeg's own, which every
  /// ffmpeg-kit build carries; LAME is an external library that only
  /// the full package ships, and carrying the full package for one
  /// encoder costs the download more than the whole rest of the app.
  /// The property that matters here survives the swap intact — this is
  /// still one pass producing one file with one header — and MP4
  /// improves on it: the player seeks by the container's own index
  /// instead of scanning for frame sync, which is the very thing
  /// Android's MP3 extractor was failing at.
  static Future<void> _join(
    List<File> files,
    File audio,
    Directory parts,
    String tag, {
    required int expectedMs,
    void Function(double)? onProgress,
  }) async {
    final list = File('${parts.path}/list_$tag.txt');
    await list.writeAsString(files
        .map((f) => "file '${f.path.replaceAll("'", r"'\''")}'")
        .join('\n'));
    try {
      await _encode('-f concat -safe 0 -i "${list.path}"', audio,
          expectedMs: expectedMs,
          what: '${files.length} parts',
          onProgress: onProgress);
    } finally {
      try {
        list.deleteSync();
      } catch (_) {}
    }
  }

  /// The one encode every assembled recitation goes through: whatever
  /// [input] names, out as AAC in MP4 (see [_join] for why that and not
  /// MP3), then checked to run as long as its timing table says.
  static Future<void> _encode(
    String input,
    File audio, {
    required int expectedMs,
    required String what,
    void Function(double)? onProgress,
  }) async {
    // Asynchronous, and watched: an hour of recitation is a real
    // encode, and a progress bar that stops dead for a minute at the
    // end is indistinguishable from one that has hung.
    // -vn: audio only. Some sets tag their files with cover art, which
    // FFmpeg would otherwise try to carry into the output as a video
    // stream — Fares Abbad's 171x144 picture failed every join of his
    // that had it ("check your connection").
    // faststart so the index sits at the front of the file: the
    // preview opens it the moment the join lands, and a seek into an
    // hour of recitation should not have to read to the end first.
    // Written beside the real name and renamed over it once checked:
    // an encode killed half way, or one redoing a range already on
    // disk, must never leave a short file next to a whole timing table
    // that the disk lookup would then trust.
    final part = File('${audio.path}.part');
    final command = '$input -vn '
        '-c:a aac -b:a 128k -movflags +faststart -f mp4 -y "${part.path}"';
    final hook = debugFfmpeg;
    final bool ok;
    if (hook != null) {
      ok = await hook(command);
    } else {
      // Progress comes off a file, not FFmpegKit's statistics events:
      // see FfmpegProgressFile for why those are switched off.
      Future<bool> run(FfmpegProgressFile? progress) async {
        final session =
            await FFmpegKit.executeAsync('${progress?.arg ?? ''}$command');
        var code = await session.getReturnCode();
        while (code == null) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final at = progress?.readMs();
          if (at != null && at > 0 && expectedMs > 0 && onProgress != null) {
            onProgress((at / expectedMs).clamp(0.0, 1.0));
          }
          code = await session.getReturnCode();
        }
        if (ReturnCode.isSuccess(code)) return true;
        if (progress == null) return false;
        // FFmpeg refusing the progress file fails the command before
        // it starts; the same command without one is the fair retry.
        var logs = '';
        try {
          logs = await session.getAllLogsAsString() ?? '';
        } catch (_) {}
        if (FfmpegProgressFile.refusedIn(logs)) {
          rlog('recitation: FFmpeg refused the progress file — '
              'encoding without');
          return run(null);
        }
        return false;
      }

      final progress =
          onProgress == null ? null : FfmpegProgressFile.beside(audio);
      try {
        ok = await run(progress);
      } finally {
        progress?.delete();
      }
    }
    try {
      if (!ok || !part.existsSync()) {
        throw TroubleException(
            Trouble.device, 'assembling the recitation audio ($what)');
      }
      await _checkJoined(part, expectedMs: expectedMs, what: what);
      part.renameSync(audio.path);
    } finally {
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {}
    }
  }

  static Future<void> _checkJoined(
    File audio, {
    required int expectedMs,
    required String what,
  }) async {
    // The timing table is the sum of the parts; the file is what the
    // player actually runs. If those two disagree, every verse after
    // the disagreement is on screen at the wrong moment — and a file
    // that came out far short is the failure this whole method exists
    // to stop shipping. Better to fail here, where the preview offers
    // a retry, than there, where it would quietly play the wrong
    // thing.
    final joinedMs = await _probeMs(audio);
    final drift = (joinedMs - expectedMs).abs();
    rlog('recitation: joined ${joinedMs}ms vs ${expectedMs}ms expected '
        '($what, drift ${drift}ms)');
    // A flat threshold, not a share of the length: one encode adds the
    // LAME delay and at most a frame of padding — under a tenth of a
    // second whether the reel is twenty seconds or an hour. A second
    // and a half is far past anything the encoder can account for and
    // far short of anything a truncated file would show.
    if (drift > 1500) {
      throw TroubleException(
          Trouble.device,
          'the assembled recitation runs ${joinedMs}ms where its verses '
          'come to ${expectedMs}ms ($what)');
    }
  }

  /// Best on-disk recitation covering [start]..[end]: the whole-surah
  /// pair first, then any stored range file.
  ///
  /// Only files carrying the current [_joinVersion] are looked at, so
  /// a recitation assembled the old way is rebuilt rather than served
  /// — the old way is what [_join] exists to stop doing, and a file it
  /// already left on the device is exactly as broken as the day it was
  /// written.
  static Recitation? _fromDisk(Directory dir, Reciter reciter, int surah,
      int start, int end, int maxMs) {
    Recitation? tryPair(File audio, File meta) {
      if (!audio.existsSync() || !meta.existsSync()) return null;
      try {
        final origin = File(
            '${meta.path.substring(0, meta.path.length - 5)}.origin');
        final rec = Recitation(
          reciterId: reciter.id,
          surah: surah,
          audioPath: audio.path,
          timings: _decodeTimings(meta.readAsStringSync()),
          originMs: origin.existsSync()
              ? int.tryParse(origin.readAsStringSync().trim())
              : null,
        );
        return _serves(rec, start, end, maxMs) ? rec : null;
      } catch (_) {
        return null; // corrupt: rebuild
      }
    }

    final full = tryPair(
        File('${dir.path}/$surah.$_joinVersion.$_joinExt'),
        File('${dir.path}/$surah.$_joinVersion.json'));
    if (full != null) return full;

    final re = RegExp('^${surah}_(\\d+)_(\\d+)\\.$_joinVersion\\.json\$');
    for (final f in dir.listSync()) {
      if (f is! File) continue;
      final m = re.firstMatch(f.uri.pathSegments.last);
      if (m == null) continue;
      // Only the start is filtered on the name: a range the cap cut
      // short ends before [end] and can still serve (see [_serves]).
      if (int.parse(m.group(1)!) > start || start > int.parse(m.group(2)!)) {
        continue;
      }
      final rec = tryPair(
          File('${f.path.substring(0, f.path.length - 5)}.$_joinExt'), f);
      if (rec != null) return rec;
    }
    return null;
  }

  /// ayah -> exact ffprobe duration in ms, persisted across sessions so
  /// no file is ever measured twice.
  static Map<int, int> _readDurations(File f) {
    if (!f.existsSync()) return {};
    try {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {for (final e in raw.entries) int.parse(e.key): e.value as int};
    } catch (_) {
      return {}; // corrupt: re-measure as needed
    }
  }

  /// Al-Fatiha ships in assets with a verified timing table: copy the
  /// asset to a real file once so callers get a uniform [Recitation].
  static Future<Recitation> _bundled(
    Reciter reciter,
    void Function(double)? onProgress,
  ) async {
    final dir = await _reciterDir(reciter.id);
    final audio = File('${dir.path}/1.mp3');
    if (!audio.existsSync()) {
      final data = await rootBundle.load(reciter.audioAsset!);
      await audio.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    onProgress?.call(1);
    return Recitation(
      reciterId: reciter.id,
      surah: 1,
      audioPath: audio.path,
      timings: reciter.timings!,
    );
  }

  /// One ayah on disk — the reciter-picker preview for voices that
  /// don't ship a bundled sample. Downloaded on the first tap of that
  /// voice, kept for every tap after it.
  ///
  /// The picker used to hand the URL straight to the player as a
  /// `UrlSource`, and Play caught the ANR that follows on 1.0.5+15:
  /// MediaPlayer opens its own `MediaHTTPConnection`, and the binder
  /// thread doing that holds the connection's monitor for the whole of
  /// the DNS lookup and the handshake behind it. Tapping a second
  /// voice while the first was still resolving put `stop()` — a
  /// synchronous `MediaPlayer.reset()` on the platform main thread —
  /// behind that same monitor, so the UI thread sat waiting on
  /// somebody else's `getaddrinfo`. On a slow network that is well
  /// past the five seconds Android allows.
  ///
  /// Fetching it here keeps the network on Dart's I/O threads, where a
  /// stall costs a silent preview and nothing else: the player is only
  /// ever given a local file, so its `reset()` has no connection to
  /// tear down and cannot block on one.
  ///
  /// A surah-file voice has no one-ayah file to fetch, so its sample is
  /// that ayah cut from the surah the way a reel's range is — a few
  /// hundred kilobytes, not the surah — and cached the way a reel's
  /// range is.
  static Future<File> sampleAyah(Reciter reciter, int surah, int ayah) async {
    // Calls for the same sample share one fetch: apart, they would
    // write the same 'sample' temp file at the same time.
    final key = '${reciter.id}_${surah}_$ayah';
    final running = _samples[key];
    if (running != null) return running;
    final job = _sampleAyah(reciter, surah, ayah);
    _samples[key] = job;
    try {
      return await job;
    } finally {
      _samples.remove(key);
    }
  }

  static final _samples = <String, Future<File>>{};

  static Future<File> _sampleAyah(Reciter reciter, int surah, int ayah) async {
    final source = reciter.source;
    if (source is SurahFiles) {
      final rec = await load(reciter, surah, startAyah: ayah, endAyah: ayah);
      return File(rec.audioPath);
    }
    if (source is! AyahFiles) {
      throw StateError('${reciter.id} has no sample to download');
    }
    final dir = Directory('${(await _reciterDir(reciter.id)).path}/samples');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}/${_ayahFileName(surah, ayah)}');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    final client = http.Client();
    try {
      await _download(client, source.url(surah, ayah), f, 'sample');
    } finally {
      client.close();
    }
    // Checked once, when fresh: bytes that aren't audio (a portal's
    // page) would otherwise be served from here forever.
    if (debugFfmpeg == null) await configureFfmpeg();
    try {
      await _probeMs(f);
    } catch (_) {
      _deleteQuietly(f);
      rethrow;
    }
    return f;
  }

  // ---- the verse picker's live recitation ----------------------------

  /// One ayah of [surah] on the disk, for the recitation that plays at
  /// the head of the verse picker (see [LiveRecitation]): the file, and
  /// the window of it the ayah fills.
  ///
  /// Never a URL handed to a player — see [sampleAyah] for the ANR that
  /// cost. Each source the way it is cheapest:
  ///
  ///  * the bundled Al-Fatiha: the one file, every ayah a window of it;
  ///  * a per-ayah voice: the ayah's own file, fetched into the very
  ///    folder a reel's build keeps its parts in, so listening here is
  ///    the download a reel of these verses would have made anyway;
  ///  * a surah-file voice: the bytes of the ayah's window, cut on whole
  ///    frames out of the surah's file the way a reel's range is, but
  ///    not decoded or re-encoded — the player takes the frames as they
  ///    are, and a listen should not cost an encode per verse.
  ///
  /// Calls for one ayah share one fetch.
  static Future<LiveClip> liveClip(Reciter reciter, int surah, int ayah) async {
    final key = '${reciter.id}_${surah}_$ayah';
    final running = _liveJobs[key];
    if (running != null) return running;
    final job = _liveClip(reciter, surah, ayah);
    _liveJobs[key] = job;
    try {
      return await job;
    } finally {
      _liveJobs.remove(key);
    }
  }

  static final _liveJobs = <String, Future<LiveClip>>{};

  /// What [liveClip] has measured, per reciter and surah — so a second
  /// visit's timeline starts out exact where the first one listened.
  static final _liveMeasured = <String, Map<int, int>>{};

  /// Where the ayah itself starts and ends inside a per-ayah file, the
  /// silence either side of it left out: what the live listen plays.
  ///
  /// These files are recorded one ayah at a time, each with a breath of
  /// silence at its head and a longer one at its tail. Played back to
  /// back they leave a gap of half a second and more between ayahs —
  /// the stop a listener hears as the voice pausing to think. A reel
  /// keeps its own timings; this is only the listen.
  static final _liveTrims = <String, Map<int, (int, int)>>{};

  static Future<(int, int)> _liveTrim(Reciter reciter, Directory dir,
      int surah, int ayah, File f, int ms) async {
    final store = File('${dir.path}/live_trim_$surah.json');
    final mem = _liveTrims[_surahKey(reciter.id, surah)] ??= _readTrims(store);
    final have = mem[ayah];
    if (have != null && have.$2 <= ms) return have;
    final found = await _silenceEdges(f, ms);
    mem[ayah] = found;
    try {
      await writeWhole(
          store,
          jsonEncode({
            for (final e in mem.entries) '${e.key}': [e.value.$1, e.value.$2],
          }));
    } catch (_) {/* a trim not kept is a trim measured again */}
    return found;
  }

  static Map<int, (int, int)> _readTrims(File f) {
    try {
      if (!f.existsSync()) return {};
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          if (e.value is List && (e.value as List).length == 2)
            int.parse(e.key): (
              ((e.value as List)[0] as num).round(),
              ((e.value as List)[1] as num).round(),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  /// The first and last moment of sound in [f], [ms] long, by FFmpeg's
  /// silence detector — written to a file by `ametadata`, because the
  /// log the detector speaks on is turned down to warnings app-wide.
  /// The whole file when anything goes wrong, or when what is left would
  /// be too short to be an ayah.
  static Future<(int, int)> _silenceEdges(File f, int ms) async {
    if (debugFfmpeg != null || debugProbeMs != null) return (0, ms);
    final out = File('${f.path}.silence.txt');
    try {
      final session = await FFmpegKit.execute(
          '-hide_banner -nostats -i "${f.path}" -af '
          '"silencedetect=noise=-38dB:d=0.12,'
          "ametadata=mode=print:file='${out.path}'\" -f null -");
      if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
          !out.existsSync()) {
        return (0, ms);
      }
      final text = out.readAsStringSync();
      List<double> all(String key) => [
            for (final m
                in RegExp('lavfi\\.$key=([0-9.]+)').allMatches(text))
              double.parse(m.group(1)!),
          ];
      final starts = all('silence_start');
      final ends = all('silence_end');
      var from = 0;
      var to = ms;
      // Silence from the very first sample: the ayah starts where it
      // ends, a beat early so no consonant is clipped.
      if (starts.isNotEmpty && starts.first <= 0.05 && ends.isNotEmpty) {
        from = math.max(0, (ends.first * 1000).round() - 60);
      }
      // Silence that runs to the end of the file: the ayah ends where it
      // starts, with a breath left on.
      if (starts.isNotEmpty) {
        final open = starts.length > ends.length ||
            (ends.isNotEmpty && ends.last * 1000 >= ms - 60);
        final last = (starts.last * 1000).round();
        if (open && last > from + 400) to = math.min(ms, last + 140);
      }
      if (to - from < 400) return (0, ms);
      return (from, to);
    } catch (e) {
      rlog('rec: silence edges of ${f.uri.pathSegments.last} — $e');
      return (0, ms);
    } finally {
      try {
        if (out.existsSync()) out.deleteSync();
      } catch (_) {}
    }
  }

  /// A surah file's layout and its ayah table, per reciter and surah:
  /// read once a session, however many ayahs ask for them at once.
  static final _liveSurahs = <String, Future<(Mp3Layout, List<AyahTiming>)>>{};

  static Future<(Mp3Layout, List<AyahTiming>)> _liveSurah(
      Reciter reciter, SurahFiles source, Directory dir, int surah) {
    final key = _surahKey(reciter.id, surah);
    final known = _liveSurahs[key];
    if (known != null) return known;
    Future<(Mp3Layout, List<AyahTiming>)> read() async {
      final count = surahIndex.firstWhere((s) => s.number == surah).ayahCount;
      final client = http.Client();
      try {
        final lay = await Mp3Layout.read(client, source.url(surah));
        final table = SurahSlice.withFileEnd(
            await _surahTable(source, dir, surah, count), lay.durationMs);
        return (lay, table);
      } finally {
        client.close();
      }
    }

    final job = read();
    _liveSurahs[key] = job;
    // A failure is not kept: the next ask tries again.
    job.then<void>((_) {}, onError: (Object _) {
      _liveSurahs.remove(key);
    });
    return job;
  }

  static Future<LiveClip> _liveClip(Reciter reciter, int surah, int ayah) async {
    if (!reciter.hasSurah(surah)) throw SurahUnavailable(reciter, surah);
    if (surah == 1 && reciter.hasBundledFatiha) {
      final rec = await _bundled(reciter, null);
      final w = rec.timing(ayah);
      return LiveClip(ayah, rec.audioPath, w.startMs, w.endMs);
    }
    final dir = await _reciterDir(reciter.id);
    final source = reciter.source;
    if (source is AyahFiles) {
      final parts = Directory('${dir.path}/parts_$surah')
        ..createSync(recursive: true);
      final f = File('${parts.path}/${_ayahFileName(surah, ayah)}');
      final known = _liveMeasured[_surahKey(reciter.id, surah)]?[ayah];
      if (known != null && f.existsSync() && f.lengthSync() > 0) {
        final (from, to) = await _liveTrim(reciter, dir, surah, ayah, f, known);
        return LiveClip(ayah, f.path, from, to, windowMs: 0);
      }
      final client = http.Client();
      try {
        await _download(client, source.url(surah, ayah), f, 'live');
      } finally {
        client.close();
      }
      if (debugFfmpeg == null) await configureFfmpeg();
      final int ms;
      try {
        ms = await _probeMs(f);
      } catch (_) {
        // Not audio (a portal's page): dropped, or every reel built
        // from this folder would trip over it too.
        _deleteQuietly(f);
        rethrow;
      }
      (_liveMeasured[_surahKey(reciter.id, surah)] ??= {})[ayah] = ms;
      final (from, to) = await _liveTrim(reciter, dir, surah, ayah, f, ms);
      return LiveClip(ayah, f.path, from, to, windowMs: 0);
    }
    if (source is SurahFiles) {
      final live = Directory('${dir.path}/live_$surah')
        ..createSync(recursive: true);
      final out = File('${live.path}/${_ayahFileName(surah, ayah)}');
      // The ayah's window in the file, kept beside it: a second listen
      // fetches nothing, and needs no network to find its place.
      final note = File('${out.path}.json');
      if (out.existsSync() && note.existsSync()) {
        try {
          final m = jsonDecode(note.readAsStringSync()) as Map<String, dynamic>;
          return LiveClip(ayah, out.path, m['f'] as int, m['t'] as int,
              originMs: m['o'] as int?);
        } catch (_) {
          // Unreadable: fetched again below.
        }
      }
      final (lay, table) = await _liveSurah(reciter, source, dir, surah);
      final w = table[ayah - 1];
      final client = http.Client();
      try {
        final at = await SurahSlice.fetch(client, source.url(surah), lay, out,
            fromMs: w.startMs, toMs: w.endMs);
        final from = (w.startMs - at).round();
        final clip = LiveClip(
            ayah, out.path, from < 0 ? 0 : from, (w.endMs - at).round(),
            originMs: at.round());
        await note.writeAsString(jsonEncode(
            {'f': clip.fromMs, 't': clip.toMs, 'o': clip.originMs}));
        return clip;
      } finally {
        client.close();
      }
    }
    throw StateError('${reciter.id} has no recitation to play live');
  }

  /// The ayah table of a surah-file voice's [surah] — the whole
  /// timeline, exact, before a byte of audio has come — or null for a
  /// voice of any other kind.
  static Future<List<AyahTiming>?> liveTable(Reciter reciter, int surah) async {
    final source = reciter.source;
    if (source is! SurahFiles || !reciter.hasSurah(surah)) return null;
    final dir = await _reciterDir(reciter.id);
    final (_, table) = await _liveSurah(reciter, source, dir, surah);
    return table;
  }

  /// How long each ayah of a per-ayah voice's [surah] runs, wherever
  /// this device has already measured it: by a reel built from them, or
  /// by an earlier listen. Empty for a voice of any other kind.
  static Future<Map<int, int>> liveDurations(Reciter reciter, int surah) async {
    if (reciter.source is! AyahFiles) return const {};
    final dir = await _reciterDir(reciter.id);
    return {
      ..._readDurations(File('${dir.path}/durations_$surah.json')),
      ...?_liveMeasured[_surahKey(reciter.id, surah)],
    };
  }

  static List<AyahTiming> _decodeTimings(String json) {
    final raw = jsonDecode(json) as List;
    return [
      for (final e in raw.cast<Map<String, dynamic>>())
        AyahTiming(e['a'] as int, e['s'] as int, e['e'] as int),
    ];
  }

  static String _ayahFileName(int surah, int ayah) =>
      '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}.mp3';

  /// Downloads over the shared [client] (one connection pool for the
  /// whole batch — no per-file TLS handshake). Writes land in a
  /// build-tagged temp file first, so overlapping builds of the same
  /// surah can never read each other's half-written parts.
  ///
  /// Retried — a reel can run an hour, which is hundreds of files, and
  /// one flaky request somewhere in the middle is close to expected —
  /// under [Download]'s rules: streamed to the temp file as it arrives,
  /// limited by how long it goes without a byte rather than by how long
  /// it takes, and a download that breaks off carries on from the byte
  /// it reached wherever the server allows that. The whole-file limit
  /// this replaces failed long verses on slow links outright: ten of
  /// them share the link, and a minute's download was given thirty
  /// seconds on every try.
  static Future<void> _download(
      http.Client client, Uri url, File target, String tag,
      {void Function(double fraction)? onFraction}) async {
    if (target.existsSync() && target.lengthSync() > 0) return;
    final tmp = File('${target.path}.$tag.part');
    var have = 0;
    var misses = 0;
    IOSink? sink;
    Object? last;
    try {
      while (true) {
        final before = have;
        try {
          final res = await Download.send(client, url,
              headers: have > 0 ? {'Range': 'bytes=$have-'} : const {});
          final range = res.headers['content-range'] ?? '';
          final resumed = have > 0 &&
              res.statusCode == 206 &&
              range.startsWith('bytes $have-');
          if (have > 0 && !resumed && res.statusCode != 200) {
            // The server can't carry on from there (a 416, or another
            // range than the one asked for): the next try starts the
            // file again from the top.
            Download.discard(res);
            await sink?.close();
            sink = null;
            have = 0;
            throw TroubleException(Trouble.host,
                'resuming at $before bytes', BadStatus(res.statusCode));
          }
          if (res.statusCode != 200 && !resumed) {
            Download.discard(res);
            throw BadStatus(res.statusCode);
          }
          if (!resumed) {
            // From the top: the first try, or a server that answered a
            // resume with the whole file.
            await sink?.close();
            sink = tmp.openWrite();
            have = 0;
          }
          final total =
              resumed ? int.tryParse(range.split('/').last) : res.contentLength;
          await for (final chunk in Download.body(res)) {
            sink!.add(chunk);
            have += chunk.length;
            if (total != null && total > 0) {
              onFraction?.call((have / total).clamp(0.0, 1.0));
            }
            // All of it: whatever the connection does next is moot.
            if (total != null && have >= total) break;
          }
          if (total != null && have < total) {
            throw TroubleException(
                Trouble.offline, 'short read: $have of $total bytes');
          }
          if (have == 0) throw BadStatus(res.statusCode, 'no body');
          await sink!.close();
          sink = null;
          tmp.renameSync(target.path);
          return;
        } catch (e) {
          last = e;
          misses = have > before ? 0 : misses + 1;
          rlog('rec: download try failed for $url at $have bytes, '
              '${misses == 0 ? 'after progress' : 'nothing new '
                  '$misses/${Download.attempts} in a row'} — $e');
          // A full phone (ENOSPC, raised at the close) is not the
          // network: asking again gets the same answer.
          if (misses >= Download.attempts ||
              Download.isFinal(e) ||
              e is FileSystemException) {
            break;
          }
          await Future<void>.delayed(Download.backoff(misses));
        }
      }
    } finally {
      // A sink whose write failed fails its close again; that must not
      // skip the clean-up below or replace the error it reports.
      try {
        await sink?.close();
      } catch (_) {}
    }
    _deleteQuietly(tmp);
    throw TroubleException(troubleOf(last), 'downloading $url', last);
  }

  static void _deleteQuietly(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Measures one part, and tries twice.
  ///
  /// The second attempt is not for a bad file — a file ffprobe cannot
  /// read is not going to become readable — but for a lost session. The
  /// result of a probe lives on the native side under a session id, and
  /// a burst of concurrent probes can push an earlier one out of
  /// FFmpeg's session history before its result is read. A fresh probe
  /// gets a fresh session, so the retry costs milliseconds and turns
  /// what used to fail a whole reel into nothing at all.
  static Future<int> _probeMs(File f) async {
    final hook = debugProbeMs;
    if (hook != null) return hook(f.path);
    Object? last;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final session = await FFprobeKit.getMediaInformation(f.path);
        final seconds = double.tryParse(
            session.getMediaInformation()?.getDuration() ?? '');
        if (seconds == null || seconds <= 0) {
          throw Exception('Could not measure ${f.path}.');
        }
        return (seconds * 1000).round();
      } catch (e) {
        last = e;
        rlog('rec: probe attempt $attempt failed for ${f.path} — $e');
      }
    }
    throw TroubleException(Trouble.device,
        'measuring ${f.uri.pathSegments.last}', last);
  }

  static Future<Directory> _reciterDir(String reciterId) async {
    final root = debugRoot ?? await getApplicationSupportDirectory();
    final d = Directory('${root.path}/recitations/$reciterId');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }
}

/// Asked for a surah a voice hasn't recorded (see
/// [SurahFiles.missing]). The pickers don't offer such a pair; this is
/// what reaches the preview if one gets through anyway, so it can say
/// what is wrong rather than blame the connection.
class SurahUnavailable extends TroubleException {
  final Reciter reciter;
  final int surah;
  const SurahUnavailable(this.reciter, this.surah)
      : super(Trouble.missing, 'a surah the voice never recorded');

  @override
  String toString() => 'missing: ${reciter.id} has no surah $surah';
}

/// One ayah on the disk, as the verse picker's live recitation plays
/// it: the file, and the window of it, in milliseconds, the ayah fills.
/// The window is the whole file for a per-ayah voice, a span of the one
/// file for the bundled Al-Fatiha, and the ayah inside a few frames of
/// slack for a surah-file voice.
@immutable
class LiveClip {
  final int ayah;
  final String path;
  final int fromMs;
  final int toMs;

  /// Where in [path] the ayah's own window begins: what its word timings
  /// count from. [fromMs] for a window cut out of a longer file; 0 for a
  /// per-ayah file, whose window is the whole file though the clip plays
  /// it without the silence at its head.
  final int windowMs;

  /// Where [path]'s first moment sits in the voice's whole-surah file,
  /// when the clip was cut out of one; see [Recitation.originMs].
  final int? originMs;

  const LiveClip(this.ayah, this.path, this.fromMs, this.toMs,
      {int? windowMs, this.originMs})
      : windowMs = windowMs ?? fromMs;

  int get durationMs => toMs - fromMs;
}

/// One in-flight fetch, and everybody waiting on it.
///
/// The download runs once however many screens ask for it; each of them
/// gets the progress as it happens, and a caller who joins late is told
/// straight away how far along it already is rather than watching a bar
/// sit at zero until the next tick.
class _Job {
  late final Future<Recitation> future;

  final _listeners = <void Function(double)>[];
  double _progress = 0;

  void listen(void Function(double)? f) {
    if (f == null) return;
    _listeners.add(f);
    if (_progress > 0) f(_progress);
  }

  void unlisten(void Function(double)? f) {
    if (f != null) _listeners.remove(f);
  }

  void report(double p) {
    _progress = p;
    // Copied: a listener that removes itself while being told would
    // otherwise mutate the list mid-iteration.
    for (final f in List.of(_listeners)) {
      f(p);
    }
  }
}
