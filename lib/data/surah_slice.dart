import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;

import 'debug_log.dart';
import 'download.dart';
import 'models.dart';
import 'trouble.dart';

/// The arithmetic behind a reel cut out of one whole-surah file — what
/// [RecitationService] does for a [SurahFiles] voice, minus FFmpeg, so
/// every piece of it can be tested off-device.
///
/// Only the bytes a range needs are fetched. Every file of every voice
/// of this kind is constant-bitrate MP3 (tool/verify_reciters.py refuses
/// one that isn't), so a moment in it is a byte offset in it: Ayat
/// al-Kursi out of a two-hour Al-Baqarah is two and a half megabytes of
/// a hundred and thirteen. [Mp3Layout] says where the audio starts and
/// how long its frames are; [fetch] lands the request on a real frame
/// and works out when that frame plays.
///
/// The published table is trusted to the breath, not to the millisecond.
/// [plan] moves every boundary to the quietest moment within [snapMs] of
/// where the table puts it when that moment is a real pause, so a verse
/// changes in the reciter's breath and never inside a word; where the
/// reciter runs two verses together there is no breath to move to, and
/// the table's own time stands. The reel's two ends look [edgeMs]
/// outwards for their silence. The verification tool mirrors all of
/// this in Python and passes a voice only when its tables put boundaries
/// within [snapMs] of a breath.
abstract final class SurahSlice {
  /// How far a verse boundary may move to reach the reciter's breath.
  static const snapMs = 350;

  /// How far outwards the reel's own first and last cuts look for
  /// silence. Wider than [snapMs], and only outwards: cutting into the
  /// first or the last word is the one mistake every listener hears,
  /// and a little more breath around a reel costs nothing.
  static const edgeMs = 800;

  /// The shortest a verse window may become when two snapped boundaries
  /// crowd each other — a one-word verse between two long breaths.
  static const minVerseMs = 150;

  /// Sample rate the loudness envelope is measured at. Speech pauses are
  /// as plain at 4 kHz as at 44, for a tenth of the samples.
  static const envRate = 4000;

  /// A pause: at least [pauseMinMs] at the bottom [pauseRel] of a slice's
  /// range, from its silence floor to its speech level. The same
  /// numbers as tool/verify_reciters.py's PAUSE_REL and PAUSE_MIN_MS.
  static const pauseRel = 0.35;
  static const pauseMinMs = 200;

  /// The loudness at or below which [env] is quiet: [pauseRel] of the
  /// way up from its silence floor (5th percentile) to its speech level
  /// (90th). Digital silence, which some files open with, is far below
  /// any breath and is left out of the floor.
  static double quietBelow(List<double> env) {
    var live = [for (final e in env) if (e > 10) e];
    if (live.isEmpty) live = [...env];
    if (live.isEmpty) return 0;
    live.sort();
    final floor = live[(live.length * 0.05).floor()];
    final speech = live[(live.length * 0.9).floor()];
    return floor + pauseRel * (speech - floor);
  }

  /// Every pause in [env], as (from, to) in milliseconds of the slice.
  static List<(int, int)> pauses(List<double> env, double quiet) {
    final runs = <(int, int)>[];
    int? from;
    for (var k = 0; k <= env.length; k++) {
      if (k < env.length && env[k] <= quiet) {
        from ??= k;
      } else if (from != null) {
        if ((k - from) * 10 >= pauseMinMs) runs.add((from * 10, k * 10));
        from = null;
      }
    }
    return runs;
  }

  /// A published table for [surah] as [timing] publishes it, as ayah
  /// windows 1..[count] in the surah file's own time — or a
  /// [FormatException] saying why it can't be used.
  ///
  /// Everything downstream indexes it by ayah, so it must have exactly
  /// [count] windows, numbered from 1, each positive, none starting
  /// before the one before it. Some mp3quran tables open with a verse 0
  /// — the isti'adha and basmala, kept apart from verse 1 as they
  /// should be — which the app has no text for and skips. A last verse
  /// whose end isn't after its start (a slip some tables have) is kept
  /// with no length, and [withFileEnd] gives it the end of the file.
  static List<AyahTiming> parseTable(
      SurahTiming timing, Object? json, int surah, int count) {
    final t = <AyahTiming>[];
    try {
      switch (timing) {
        case Mp3QuranTiming():
          if (json is! List) throw const FormatException('not a list');
          for (final r in json.cast<Map<String, dynamic>>()) {
            final ayah = (r['ayah'] as num).toInt();
            if (ayah == 0) continue;
            t.add(AyahTiming(ayah, (r['start_time'] as num).toInt(),
                (r['end_time'] as num).toInt()));
          }
          if (t.length == count && t.last.endMs <= t.last.startMs) {
            t.last = AyahTiming(count, t.last.startMs, t.last.startMs);
          }
        case QulTiming():
          final segments = json is Map ? json['segments'] : null;
          if (segments is! Map) throw const FormatException('no segments');
          for (var a = 1; a <= count; a++) {
            final w = segments['$surah:$a'];
            if (w is! Map) throw FormatException('verse $a is missing');
            t.add(AyahTiming(a, (w['time_from'] as num).toInt(),
                (w['time_to'] as num).toInt()));
          }
        case OwnTiming():
          // Never published, so never parsed: VerseTables has it.
          throw const FormatException('a table the app carries');
      }
    } on TypeError {
      throw const FormatException('a verse is malformed');
    }
    return checkedTable(t, count);
  }

  /// [t] if it is a usable table of [count] verses; see [parseTable].
  static List<AyahTiming> checkedTable(List<AyahTiming> t, int count) {
    if (t.length != count) {
      throw FormatException('${t.length} verses where there are $count');
    }
    for (var i = 0; i < t.length; i++) {
      final w = t[i];
      final last = i == t.length - 1;
      if (w.ayah != i + 1 ||
          w.endMs < w.startMs ||
          (w.endMs == w.startMs && !last) ||
          (i > 0 && w.startMs < t[i - 1].startMs)) {
        throw FormatException('verse ${i + 1} is malformed');
      }
    }
    return t;
  }

  /// [t] with a last verse that has no length ending where the file
  /// does, [fileMs] in; unchanged otherwise.
  static List<AyahTiming> withFileEnd(List<AyahTiming> t, double fileMs) {
    final last = t.last;
    if (last.endMs > last.startMs || fileMs <= last.startMs) return t;
    return [
      ...t.sublist(0, t.length - 1),
      AyahTiming(last.ayah, last.startMs, fileMs.floor()),
    ];
  }

  /// Downloads the bytes of [url] that play from [fromMs] to [toMs]
  /// into [out], starting on a whole frame, and returns the moment (in
  /// the surah file's time) the first of them plays at.
  ///
  /// The request is aimed at where frame k should start — a constant-
  /// bitrate file's frames are all one length, give or take a padding
  /// byte — with a few frames of slack either side, and the frame
  /// nearest the aim, confirmed by the header of the frame after it, is
  /// where the written file begins. Its index is then exact, and so is
  /// its time. A decoder starting on a frame whose bit reservoir reaches
  /// back may lose that frame's sound; the edges look far wider than
  /// one frame.
  ///
  /// **A dropped connection carries on where it stopped.** The slice is
  /// one request, and for a long reel a big one: tens of megabytes, and
  /// minutes on a slow link. Any break used to throw all of it away and
  /// start again from nothing, three times, and then tell the user to
  /// check a connection that had been working for most of the download
  /// — the progress bar climbing, falling back to zero and climbing
  /// again. What has arrived is now kept and the next request asks for
  /// the rest, so every try moves the download on. It is called off
  /// after [attempts] tries in a row that brought nothing, with
  /// [Download.backoff] between them (see [Download]) — and even then
  /// what came stays on disk beside [out], so the next fetch of the same
  /// range (Try again, or the preview's own retry when the app comes
  /// back) carries on from it.
  static Future<double> fetch(
    http.Client client,
    Uri url,
    Mp3Layout lay,
    File out, {
    required int fromMs,
    required int toMs,
    int attempts = Download.attempts,
    void Function(double)? onProgress,
  }) async {
    final frameMs = lay.frameMs;
    final k = (max(0, fromMs) / frameMs).floor() + lay.firstAudioFrame;
    final want = lay.dataStart + (k * lay.frameBytes).round();
    final pad = (lay.frameBytes * 4).floor();
    final lo = max(lay.dataStart, want - pad);
    final hi = min(
        lay.total - 1,
        lay.dataStart +
            ((toMs / frameMs + lay.firstAudioFrame + 2) * lay.frameBytes)
                .ceil());
    final probe = 2 * pad + 2 * lay.frameBytes.ceil() + 4;
    final expected = hi - lo + 1;

    final tmp = File('${out.path}.part');
    // What [tmp] holds, for the next fetch of this range — the preview's
    // Try again, or its retry when the app comes back — to carry on
    // from, rather than from nothing. Written once the frame the file
    // starts on is known, and trusted only for the same bytes of the
    // same file.
    final note = File('${out.path}.part.json');
    final key = '$url bytes $lo-$hi of ${lay.total}';
    void forget() {
      for (final f in [tmp, note]) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }

    // Across every try: the bytes before the frame the file starts on
    // is known, that frame's offset in lo..hi, how many bytes of lo..hi
    // have arrived, and the tries in a row that brought none.
    final head = BytesBuilder(copy: false);
    var first = _carriedOver(tmp, note, key, expected);
    var got = first == null ? 0 : first + tmp.lengthSync();
    var misses = 0;
    IOSink? sink;
    Object? last;
    if (first == null) {
      forget();
    } else {
      sink = tmp.openWrite(mode: FileMode.append);
      onProgress?.call((got / expected).clamp(0.0, 1.0));
      rlog('rec: slice carries on from an earlier fetch at $got of '
          '$expected bytes');
    }
    try {
      while (got < expected) {
        final before = got;
        try {
          final from = lo + got;
          final res = await Download.send(client, url,
              headers: {'Range': 'bytes=$from-$hi'});
          if (res.statusCode != 206 ||
              !(res.headers['content-range'] ?? '')
                  .startsWith('bytes $from-')) {
            Download.discard(res);
            throw BadStatus(res.statusCode, 'not the range asked for');
          }
          await for (var chunk in Download.body(res)) {
            // Never past what was asked for, whatever the server sends.
            if (got + chunk.length > expected) {
              chunk = chunk.sublist(0, expected - got);
            }
            got += chunk.length;
            onProgress?.call((got / expected).clamp(0.0, 1.0));
            if (first != null) {
              sink!.add(chunk);
            } else {
              head.add(chunk);
              if (head.length >= probe) {
                final b = head.takeBytes();
                first = lay.frameNear(b, want - lo, limit: probe);
                if (first == null) throw _noFrame;
                sink = tmp.openWrite()..add(Uint8List.sublistView(b, first));
                note.writeAsStringSync(
                    jsonEncode({'key': key, 'first': first}));
              }
            }
            if (got == expected) break;
          }
          // The connection closed early: the network's doing, not the
          // file's. What came is kept; the next try asks for the rest.
          if (got < expected) {
            throw TroubleException(
                Trouble.offline, 'short read: $got of $expected bytes');
          }
        } catch (e) {
          last = e;
          // Not a network fault: asking again gets the same answer.
          // A full phone (ENOSPC) is final too.
          if (identical(e, _noFrame) ||
              Download.isFinal(e) ||
              e is FileSystemException) {
            break;
          }
          misses = got > before ? 0 : misses + 1;
          rlog('rec: slice try failed for $url at $got of $expected bytes, '
              '${misses == 0 ? 'after progress' : 'nothing new '
                  '$misses/$attempts in a row'} — $e');
          if (misses >= attempts) break;
          await Future<void>.delayed(Download.backoff(misses));
        }
      }
      if (got == expected) {
        if (first == null) {
          // A slice shorter than the look for its first frame.
          final b = head.takeBytes();
          first = lay.frameNear(b, want - lo, limit: b.length);
          if (first != null) {
            sink = tmp.openWrite()..add(Uint8List.sublistView(b, first));
          }
        }
        if (first != null) {
          try {
            await sink!.close();
            sink = null;
            tmp.renameSync(out.path);
            forget();
            return lay.timeOf(lo + first);
          } on FileSystemException catch (e) {
            // A full phone surfaces here, at the close: reported below
            // like any other failure, not thrown past the clean-up.
            last = e;
          }
        } else {
          last = _noFrame;
        }
      }
    } finally {
      // A sink whose write failed fails its close again.
      try {
        await sink?.close();
      } catch (_) {}
    }
    // Kept for the next fetch when it was the network that stopped this
    // one. Anything else, and the bytes are no use to anyone.
    final cause = last!;
    if (identical(cause, _noFrame) ||
        Download.isFinal(cause) ||
        cause is FileSystemException) {
      forget();
    }
    throw TroubleException(troubleOf(cause), 'downloading part of $url', cause);
  }

  /// The offset in its range of the frame [tmp] starts on, when [note]
  /// says [tmp] holds the start of the same bytes of the same file
  /// ([key]): what an earlier fetch of this range got before the
  /// network let it down. Null when there is nothing to carry on from.
  static int? _carriedOver(File tmp, File note, String key, int expected) {
    try {
      if (!tmp.existsSync() || !note.existsSync()) return null;
      final j = jsonDecode(note.readAsStringSync());
      if (j is! Map || j['key'] != key) return null;
      final first = j['first'];
      if (first is! int || first < 0) return null;
      if (first + tmp.lengthSync() > expected) return null;
      return first;
    } catch (_) {
      return null;
    }
  }

  static const _noFrame =
      TroubleException(Trouble.host, 'no MP3 frame near the slice start');

  /// Loudness of the raw mono 16-bit samples (at [envRate]) in [path],
  /// in 10 ms steps, in dB, each averaged over the 100 ms around it:
  /// long enough to ride over the gap inside a stop consonant, short
  /// enough to keep a breath between verses. Read in chunks, so an hour
  /// of recitation never sits in memory as samples; meant for its own
  /// isolate, being a loop over millions of them.
  static List<double> envelopeOf(String path) {
    const frame = envRate ~/ 100 * 2; // bytes in 10 ms of mono s16
    final power = <double>[];
    final r = File(path).openSync();
    try {
      final buf = Uint8List(frame * 2000);
      while (true) {
        final n = r.readIntoSync(buf);
        final data = ByteData.sublistView(buf, 0, n - n % frame);
        for (var off = 0; off < data.lengthInBytes; off += frame) {
          var acc = 0.0;
          for (var k = off; k < off + frame; k += 2) {
            final x = data.getInt16(k, Endian.little);
            acc += x * x;
          }
          power.add(acc / (frame ~/ 2));
        }
        if (n < buf.length) break;
      }
    } finally {
      r.closeSync();
    }
    const w = 5; // frames either side: 100 ms in all
    final sums = List<double>.filled(power.length + 1, 0);
    for (var i = 0; i < power.length; i++) {
      sums[i + 1] = sums[i] + power[i];
    }
    final out = List<double>.filled(power.length, 0);
    for (var i = 0; i < power.length; i++) {
      final lo = max(0, i - w), hi = min(power.length, i + w + 1);
      out[i] = 10 * log((sums[hi] - sums[lo]) / (hi - lo) + 1) / ln10;
    }
    return out;
  }

  /// The quietest 10 ms of [env] from [before] ms before [atMs] to
  /// [after] ms after it, clamped to the slice; the nearer of two equals.
  static int snap(List<double> env, int atMs,
      {required int before, required int after}) {
    final i = (atMs / 10).round();
    final lo = max(0, i - before ~/ 10);
    final hi = min(env.length - 1, i + after ~/ 10);
    if (lo > hi) return min(max(i, 0), env.length) * 10;
    var best = lo;
    for (var k = lo + 1; k <= hi; k++) {
      if (env[k] < env[best] ||
          (env[k] == env[best] && (k - i).abs() < (best - i).abs())) {
        best = k;
      }
    }
    return best * 10;
  }

  /// Where the words a surah opens with end, when [table] counts them as
  /// verse 1's: the pause that follows [openingMs] or so of speech after
  /// the table's verse 1 begins, as (from, to) in the slice. Null when
  /// there is no such pause. Looked for from 0.6 to 1.6 times
  /// [openingMs] into the speech, which the tool checks every surah of a
  /// voice against.
  static (int, int)? openingPause(List<(int, int)> pauses, int verse1At,
      {required int openingMs}) {
    // Speech starts where the table's verse 1 does, or at the end of
    // the silence it starts in.
    var onset = verse1At;
    for (final (a, b) in pauses) {
      if (a <= verse1At && verse1At < b) onset = b;
    }
    for (final p in pauses) {
      final gap = p.$1 - onset;
      if (gap >= openingMs * 0.6 && gap <= openingMs * 1.6) return p;
    }
    return null;
  }

  /// Where to cut [start]..[last] out of a slice whose first sample
  /// plays at [originMs] of the surah and whose loudness is [env], and
  /// the verse windows inside the cut — in the cut's own time, the first
  /// starting at 0.
  ///
  /// [openingMs] is the voice's [SurahFiles.openingMs], passed when the
  /// cut starts at a verse 1 whose table window opens with the basmala
  /// (or the isti'adha): the reel then starts in the breath after them.
  static SlicePlan plan({
    required List<AyahTiming> table,
    required int start,
    required int last,
    required double originMs,
    required List<double> env,
    int? openingMs,
  }) {
    final sliceMs = env.length * 10;
    int at(int surahMs) => (surahMs - originMs).round();
    final from = table[start - 1].startMs;
    final to = table[last - 1].endMs;
    final quiet = quietBelow(env);
    final gaps = pauses(env, quiet);
    var cutStart = snap(env, at(from), before: edgeMs, after: snapMs);
    if (openingMs != null) {
      final p = openingPause(gaps, at(from), openingMs: openingMs);
      if (p != null) {
        cutStart = snap(env, (p.$1 + p.$2) ~/ 2,
            before: (p.$2 - p.$1) ~/ 2, after: (p.$2 - p.$1) ~/ 2);
      } else {
        rlog('rec: no pause after the opening of verse 1 at '
            '${at(from)}ms — the reel keeps it');
      }
    }
    final bounds = <int>[cutStart];
    for (var a = start + 1; a <= last; a++) {
      final t = at(table[a - 1].startMs);
      var b = snap(env, t, before: snapMs, after: snapMs);
      // No breath in reach: the verses are joined, and the quietest
      // moment near the table's time is only a gap between consonants.
      // The table's own time is the better guess there.
      if (b ~/ 10 < env.length && env[b ~/ 10] > quiet) {
        b = t.clamp(0, sliceMs);
      }
      bounds.add(max(b, bounds.last + minVerseMs));
    }
    // A last verse whose table runs past the end of the file (by up to
    // a second or so, which the tool allows) ends where the audio does.
    final cutEnd = min(
      sliceMs,
      max(snap(env, min(at(to), sliceMs), before: snapMs, after: edgeMs),
          bounds.last + minVerseMs),
    );
    if (cutEnd <= cutStart || bounds.last >= cutEnd) {
      throw FormatException('verses $start-$last are not in this slice '
          '(${sliceMs}ms from ${originMs.round()}ms)');
    }
    bounds.add(cutEnd);
    return SlicePlan(cutStart, cutEnd, [
      for (var i = 0; i < bounds.length - 1; i++)
        AyahTiming(start + i, bounds[i] - cutStart, bounds[i + 1] - cutStart),
    ]);
  }
}

/// Where a reel's audio is cut out of its slice, and its verse windows.
@immutable
final class SlicePlan {
  /// In the slice's time.
  final int cutStart;
  final int cutEnd;

  /// In the cut's time: the first starts at 0, the last ends at
  /// `cutEnd - cutStart`.
  final List<AyahTiming> timings;

  const SlicePlan(this.cutStart, this.cutEnd, this.timings);
}

/// Where the audio in a constant-bitrate MP3 starts, and how long its
/// frames are — what turns a moment in the recording into a byte offset
/// in the file. Read from the file's first bytes, never assumed: one
/// reciter's files differ in bitrate and sample rate from surah to
/// surah. tool/verify_reciters.py does the same arithmetic in Python.
final class Mp3Layout {
  /// Size of the whole file, in bytes.
  final int total;

  /// Offset of the first frame, past any ID3v2 tag.
  final int dataStart;

  final int kbps;
  final int rate;
  final int samplesPerFrame;

  /// Whether the first frame is a LAME "Info" header rather than sound.
  final bool info;

  const Mp3Layout({
    required this.total,
    required this.dataStart,
    required this.kbps,
    required this.rate,
    required this.samplesPerFrame,
    required this.info,
  });

  /// Average bytes per frame. Exact on average: a constant-bitrate
  /// encoder pads one frame in so many by a byte to hold the rate.
  double get frameBytes =>
      (samplesPerFrame == 1152 ? 144 : 72) * kbps * 1000 / rate;

  double get frameMs => samplesPerFrame * 1000 / rate;

  /// How long the file's audio plays.
  double get durationMs =>
      ((total - dataStart) / frameBytes - firstAudioFrame) * frameMs;

  int get firstAudioFrame => info ? 1 : 0;

  /// When the frame starting at byte [offset] of the file plays.
  double timeOf(int offset) =>
      (((offset - dataStart) / frameBytes).round() - firstAudioFrame) *
      frameMs;

  /// The layout of the file whose first bytes are [head] (the ten of an
  /// ID3 header at least) and whose bytes from the end of that tag are
  /// [body]; [total] is the size of the whole file.
  ///
  /// Throws for a variable-bitrate file: its frames are not one length,
  /// so no moment in it is a byte offset.
  factory Mp3Layout.parse(Uint8List head, Uint8List body, int total) {
    final start = id3Size(head);
    // A few stray bytes after the tag are tolerated, as players do.
    for (var i = 0; i < min(2048, body.length - 4); i++) {
      final h = header(body, i);
      if (h == null || header(body, i + h.length) == null) continue;
      final first =
          String.fromCharCodes(body.sublist(i, min(body.length, i + h.length)));
      if (first.contains('Xing') || first.contains('VBRI')) {
        throw const FormatException('variable bitrate: cannot be sliced');
      }
      return Mp3Layout(
        total: total,
        dataStart: start + i,
        kbps: h.kbps,
        rate: h.rate,
        samplesPerFrame: h.samplesPerFrame,
        info: first.contains('Info'),
      );
    }
    throw const FormatException('no MP3 audio at the start');
  }

  static Future<Mp3Layout> read(http.Client client, Uri url) async {
    final (head, total) = await _range(client, url, 0, 9);
    final start = id3Size(head);
    final (body, _) = await _range(client, url, start, start + 8191);
    try {
      return Mp3Layout.parse(head, body, total);
    } on FormatException catch (e) {
      throw TroubleException(Trouble.host, 'reading $url', e.message);
    }
  }

  /// Offset in [b] of the frame nearest [aim] that has this file's
  /// bitrate and sample rate and is followed by another such frame,
  /// looking no further than [limit]. Null if there is none.
  int? frameNear(Uint8List b, int aim, {required int limit}) {
    int? best;
    for (var i = 0; i < min(limit, b.length - 4); i++) {
      final h = header(b, i);
      if (h == null || h.kbps != kbps || h.rate != rate) continue;
      final h2 = header(b, i + h.length);
      if (h2 == null || h2.kbps != kbps || h2.rate != rate) continue;
      if (best == null || (i - aim).abs() < (best - aim).abs()) best = i;
    }
    return best;
  }

  static const _kbpsV1 = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, //
  ];
  static const _kbpsV2 = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, //
  ];
  static const _rates = {
    3: [44100, 48000, 32000],
    2: [22050, 24000, 16000],
    0: [11025, 12000, 8000],
  };

  /// The MPEG Layer III frame header at [b][i], or null if there isn't
  /// one there.
  static ({int kbps, int rate, int samplesPerFrame, int length})? header(
      Uint8List b, int i) {
    if (i < 0 || i + 4 > b.length) return null;
    if (b[i] != 0xFF || (b[i + 1] & 0xE0) != 0xE0) return null;
    final version = (b[i + 1] >> 3) & 3;
    final layer = (b[i + 1] >> 1) & 3;
    final bri = b[i + 2] >> 4;
    final sri = (b[i + 2] >> 2) & 3;
    final pad = (b[i + 2] >> 1) & 1;
    if (version == 1 || layer != 1 || bri == 0 || bri == 15 || sri == 3) {
      return null;
    }
    final mpeg1 = version == 3;
    final kbps = (mpeg1 ? _kbpsV1 : _kbpsV2)[bri];
    final rate = _rates[version]![sri];
    return (
      kbps: kbps,
      rate: rate,
      samplesPerFrame: mpeg1 ? 1152 : 576,
      length: (mpeg1 ? 144 : 72) * kbps * 1000 ~/ rate + pad,
    );
  }

  /// Bytes taken by an ID3v2 tag at the start of [h], footer included;
  /// 0 when there is none.
  static int id3Size(Uint8List h) {
    if (h.length < 10 || h[0] != 0x49 || h[1] != 0x44 || h[2] != 0x33) {
      return 0; // no "ID3"
    }
    final size = (h[6] & 127) << 21 |
        (h[7] & 127) << 14 |
        (h[8] & 127) << 7 |
        h[9] & 127;
    final footer = h[5] & 0x10 != 0 ? 10 : 0;
    return 10 + size + footer;
  }

  /// Bytes [from]..[to] of [url], and the size of the whole file.
  ///
  /// A few kilobytes, so a try either brings them or it doesn't: tried
  /// [Download.attempts] times, [Download.backoff] apart.
  static Future<(Uint8List, int)> _range(
      http.Client client, Uri url, int from, int to) async {
    Object? last;
    for (var attempt = 1; attempt <= Download.attempts; attempt++) {
      try {
        final res = await Download.send(client, url,
            headers: {'Range': 'bytes=$from-$to'});
        final range = res.headers['content-range'] ?? '';
        if (res.statusCode != 206 || !range.contains('/')) {
          Download.discard(res);
          throw BadStatus(res.statusCode, 'not a byte range');
        }
        return (
          await Download.readAll(res),
          int.parse(range.split('/').last)
        );
      } catch (e) {
        last = e;
        rlog('rec: range try $attempt/${Download.attempts} failed for '
            '$url — $e');
        if (Download.isFinal(e)) break;
        if (attempt < Download.attempts) {
          await Future<void>.delayed(Download.backoff(attempt));
        }
      }
    }
    throw TroubleException(troubleOf(last!), 'reading $url', last);
  }
}
