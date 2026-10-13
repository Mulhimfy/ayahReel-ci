import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_log.dart';
import 'models.dart';
import 'reel_duration.dart';
import 'whole_file.dart';

/// A recitation the user brought in themselves, instead of choosing a
/// voice the app can fetch.
///
/// Everything downstream of the wizard — the preview, the exporter, the
/// verse card — works from a [Recitation]: one audio file plus a table
/// saying which slice of it is which ayah. For the app's own reciters
/// that table is exact by construction, because the file is assembled
/// out of one-ayah parts whose durations were measured on the way in.
/// An uploaded file has no joints to count: it is one blob, and where
/// each verse begins inside it has to be *found*.
///
/// This is where it is found. See [UserAudioService.plan].
@immutable
class UserAudio {
  /// Stands in for a reciter id everywhere one is needed. Derived from
  /// the file itself, so re-importing the same recording lands on the
  /// same id — and on the same already-converted audio on disk.
  final String id;

  /// The file name the user picked, shown so they can tell one upload
  /// from the next.
  final String label;

  /// Absolute path of the normalized audio on device. Always AAC in
  /// MP4, whatever came in — see [UserAudioService.import].
  final String audioPath;

  final int durationMs;

  const UserAudio({
    required this.id,
    required this.label,
    required this.audioPath,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'path': audioPath,
        'ms': durationMs,
      };

  static UserAudio? fromJson(Map<String, dynamic> j) {
    try {
      return UserAudio(
        id: j['id'] as String,
        label: j['label'] as String,
        audioPath: j['path'] as String,
        durationMs: j['ms'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One stretch of near-silence found in a recording, in milliseconds.
@immutable
class SilenceGap {
  final int startMs;
  final int endMs;
  const SilenceGap(this.startMs, this.endMs);

  int get durationMs => endMs - startMs;
  int get midMs => (startMs + endMs) ~/ 2;
}

/// Raised when an imported file cannot become a recitation. [kind] is a
/// key the UI turns into a localized line; the message is never shown
/// raw.
class UserAudioError implements Exception {
  /// One of: 'unreadable', 'noAudio', 'tooShort'.
  final String kind;
  const UserAudioError(this.kind);
  @override
  String toString() => 'UserAudioError($kind)';
}

/// Imports, measures and aligns a recording the user supplied.
abstract final class UserAudioService {
  /// Shortest file worth calling a recitation. Below this there is
  /// nothing to place verses in.
  static const minDurationMs = 1200;

  /// Smallest slice a single ayah may be given. Boundaries are pushed
  /// apart to keep it, so an edit can never collapse a verse to nothing
  /// — which would leave the preview with a card that is never on
  /// screen and the exporter with a zero-length clip.
  static const minAyahMs = 350;

  /// The one upload in play. Kept in memory for the session and
  /// remembered on disk so a later session can offer it again.
  static UserAudio? _current;
  static UserAudio? get current => _current;

  /// Aligned recitations, keyed by '<reciter id>_<surah>'. The timing
  /// screen writes one here when the user leaves it; the preview and
  /// the verse picker read it back through `QuranRepository`. In
  /// memory only: an alignment belongs to the run being built, not to
  /// the file.
  static final _aligned = <String, Recitation>{};

  static String _key(String reciterId, int surah) => '${reciterId}_$surah';

  /// The stand-in voice for [a]. Its source is [OwnAudio], which is
  /// what marks it as the user's own everywhere else — see
  /// [Reciter.isUserAudio].
  static Reciter reciterFor(UserAudio a) => Reciter(
        id: a.id,
        name: 'Your recitation',
        arabicName: 'تسجيلك',
        style: 'Your own audio',
        source: const OwnAudio(),
      );

  /// True when [reciterId] belongs to an upload rather than to a voice
  /// from the app's own list.
  static bool isUserId(String reciterId) => reciterId.startsWith('user_');

  // ---- alignment registry -------------------------------------------

  /// The alignment in force for this upload and surah, once the user
  /// has been through the timing screen. Null otherwise — which is what
  /// tells the verse picker it has no exact length to quote yet.
  static Recitation? aligned(String reciterId, int surah) {
    if (!isUserId(reciterId)) return null;
    return _aligned[_key(reciterId, surah)];
  }

  /// Files the timings the user settled on. The [Recitation]'s own
  /// reciter id carries a signature of those timings, so a re-align of
  /// the same file can never be served a reel rendered against the old
  /// ones — the export cache is keyed on that id.
  static Recitation register({
    required UserAudio audio,
    required int surah,
    required List<AyahTiming> timings,
  }) {
    final rec = Recitation(
      reciterId: '${audio.id}_a${_signature(timings)}',
      surah: surah,
      audioPath: audio.audioPath,
      timings: timings,
    );
    _aligned[_key(audio.id, surah)] = rec;
    return rec;
  }

  /// Drops every alignment of this upload. Called when a *different*
  /// file is imported, so nothing of the last one can be served under
  /// it.
  static void forget(String reciterId) =>
      _aligned.removeWhere((k, _) => k.startsWith('${reciterId}_'));

  /// Forgets the upload and every alignment of it: for when the storage
  /// sheet has deleted the files behind them. [restore] finds nothing
  /// on disk after that, so the next visit asks for the file again.
  static void forgetAll() {
    _current = null;
    _aligned.clear();
  }

  static String _signature(List<AyahTiming> t) {
    final s = t.map((w) => '${w.ayah}:${w.startMs}:${w.endMs}').join(',');
    return sha1.convert(utf8.encode(s)).toString().substring(0, 8);
  }

  // ---- import --------------------------------------------------------

  /// Brings [source] in: strips any picture, re-encodes the sound to
  /// AAC in MP4, measures it, and returns the result.
  ///
  /// **Always re-encoded, never copied.** A file out of a phone's
  /// gallery or a chat app can be anything — an MP4 with a video track,
  /// an OGG, a WAV, an MP3 with a trailer glued on the end. The rest of
  /// the app plays and muxes one shape of audio file, the same one
  /// `RecitationService` assembles its own recitations into, and this
  /// is the single pass that guarantees it: `-vn` takes the sound out
  /// of a video, and the encode leaves one clean track with one header
  /// and a seek index at the front of it.
  ///
  /// The conversion is keyed on what the recording *is*, so re-picking
  /// the same file costs nothing the second time — see [_idFor].
  static Future<UserAudio> import(File source, {String? name}) async {
    if (!source.existsSync()) throw const UserAudioError('unreadable');
    final label = name ?? source.uri.pathSegments.last;
    final id = 'user_${await _idFor(source, label)}';

    final dir = await _dirFor(id);
    final out = File('${dir.path}/source.m4a');

    if (!out.existsSync() || out.lengthSync() == 0) {
      if (!await _hasAudioStream(source.path)) {
        throw const UserAudioError('noAudio');
      }
      // Encoded beside the real name and renamed when it is whole: a
      // conversion killed half way must not leave a `source.m4a` that
      // the check above would then reuse forever.
      final part = File('${out.path}.part');
      final session = await FFmpegKit.execute(
        '-hide_banner -nostats -i "${source.path}" -vn -map 0:a:0 '
        '-c:a aac -b:a 160k -movflags +faststart -f mp4 -y "${part.path}"',
      );
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code) ||
          !part.existsSync() ||
          part.lengthSync() == 0) {
        if (part.existsSync()) part.deleteSync();
        rlog('user audio: convert failed for $label');
        throw const UserAudioError('unreadable');
      }
      part.renameSync(out.path);
    }

    final int ms;
    try {
      ms = await _probeMs(out);
    } on UserAudioError {
      // Unreadable, so not worth keeping: the next pick converts again
      // instead of reusing it (an older build could leave one behind).
      try {
        out.deleteSync();
      } catch (_) {}
      rethrow;
    }
    if (ms < minDurationMs) throw const UserAudioError('tooShort');

    final audio = UserAudio(
      id: id,
      label: label,
      audioPath: out.path,
      durationMs: ms,
    );
    // A different file replaces the last one outright: any alignment
    // left over belonged to audio nobody is using any more.
    final was = _current;
    if (was != null && was.id != id) forget(was.id);
    _current = audio;
    await _remember(audio);
    await _pruneOthers(id);
    rlog('user audio: ready $id (${ms}ms) from $label');
    return audio;
  }

  /// Deletes the converted audio of every upload but [keep].
  ///
  /// One upload is in play at a time — the reciter screen offers the
  /// last one and nothing else — so an older conversion is dead weight
  /// the moment a new file replaces it, and these are whole
  /// recitations, not thumbnails. Failures are ignored: this is
  /// housekeeping, and the storage sheet clears the folder outright.
  static Future<void> _pruneOthers(String keep) async {
    try {
      final root = Directory(
          '${(await getApplicationSupportDirectory()).path}/recitations');
      if (!root.existsSync()) return;
      for (final e in root.listSync()) {
        final name = e.uri.pathSegments.where((p) => p.isNotEmpty).last;
        if (e is! Directory || !isUserId(name) || name == keep) continue;
        e.deleteSync(recursive: true);
        forget(name);
        rlog('user audio: pruned $name');
      }
    } catch (_) {}
  }

  /// The last upload, if its converted audio is still on disk. Lets a
  /// new session offer the recording the user brought in before instead
  /// of asking for the file again.
  static Future<UserAudio?> restore() async {
    final held = _current;
    if (held != null) return held;
    try {
      final f = await _memoFile();
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final a = UserAudio.fromJson(raw);
      if (a == null || !File(a.audioPath).existsSync()) return null;
      _current = a;
      return a;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _remember(UserAudio a) async {
    try {
      await writeWhole(await _memoFile(), jsonEncode(a.toJson()));
    } catch (_) {
      // Remembering is a convenience; the upload itself already works.
    }
  }

  static Future<File> _memoFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/user_audio.json');

  /// Under `recitations/`, like every other assembled recitation — so
  /// an upload is counted and cleared by the storage sheet exactly the
  /// way a downloaded one is.
  static Future<Directory> _dirFor(String id) async {
    final d = Directory(
        '${(await getApplicationSupportDirectory()).path}/recitations/$id');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// A stable name for this recording, derived from the recording.
  ///
  /// Not from the file's path or its modified time, which is what this
  /// used and what made every pick a new upload: Android's document
  /// picker hands back a *fresh copy* in the app's cache each time, so
  /// the same recording arrived with a new timestamp on every visit —
  /// re-converting it, and leaving the last conversion behind.
  ///
  /// Length plus a hash of the first quarter-megabyte is enough to tell
  /// two recordings apart while costing one short read; hashing an hour
  /// of audio to answer "have I seen this before" would cost more than
  /// the conversion it saves.
  static Future<String> _idFor(File source, String name) async {
    final size = source.lengthSync();
    final head = await source.openRead(0, size < 262144 ? size : 262144).fold(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
    return sha1
        .convert(utf8.encode('$name|$size|${sha1.convert(head)}'))
        .toString()
        .substring(0, 10);
  }

  static Future<bool> _hasAudioStream(String path) async {
    try {
      final info = await FFprobeKit.getMediaInformation(path);
      final streams = info.getMediaInformation()?.getStreams() ?? [];
      return streams.any((s) => s.getType() == 'audio');
    } catch (_) {
      return false;
    }
  }

  static Future<int> _probeMs(File f) async {
    final info = await FFprobeKit.getMediaInformation(f.path);
    final seconds =
        double.tryParse(info.getMediaInformation()?.getDuration() ?? '');
    if (seconds == null || seconds <= 0) {
      throw const UserAudioError('unreadable');
    }
    return (seconds * 1000).round();
  }

  // ---- listening to the file -----------------------------------------

  /// Every stretch of near-silence in [path].
  ///
  /// A reciter breathes between ayahs, so the gaps between verses are
  /// both longer and quieter than anything inside one. That is the
  /// whole signal this looks for; what it does *not* do is assume the
  /// gaps it finds are the verse joints, because a long verse has
  /// pauses in it too and a noisy recording hides the short ones.
  /// Deciding which gap is which is [plan]'s job.
  static Future<List<SilenceGap>> detectSilence(
    String path, {
    double noiseDb = -35,
    double minSeconds = 0.28,
  }) async {
    // The filter's own log lines are info level, and start-up turns
    // FFmpeg's log down to warnings (`configureFfmpeg`), so the session
    // log never has them. `ametadata` writes the same marks to a file
    // whatever the log level.
    File? marks;
    try {
      final tmp = await getTemporaryDirectory();
      marks = File('${tmp.path}/ua_silence_'
          '${DateTime.now().microsecondsSinceEpoch}.txt');
      final session = await FFmpegKit.execute(
        '-hide_banner -nostats -i "$path" '
        '-af "silencedetect=noise=${noiseDb}dB:d=$minSeconds,'
        'ametadata=mode=print:file=${filterPath(marks.path)}" '
        '-f null -',
      );
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code) || !marks.existsSync()) {
        return const [];
      }
      return parseSilence(marks.readAsStringSync());
    } catch (e) {
      rlog('user audio: silencedetect failed ($e)');
      return const [];
    } finally {
      try {
        if (marks != null && marks.existsSync()) marks.deleteSync();
      } catch (_) {}
    }
  }

  /// [path] escaped to be a filter option value inside `-af`. FFmpeg
  /// unescapes twice: once for the graph (`,` `;` `[` `]` split it) and
  /// once for the option (`:` starts the next one); `\` and `'` are
  /// the escapes at both levels.
  @visibleForTesting
  static String filterPath(String path) => path
      .replaceAllMapped(RegExp(r"[\\':]"), (m) => '\\${m[0]}')
      .replaceAllMapped(RegExp(r"[\\'\[\],;]"), (m) => '\\${m[0]}');

  /// Pulls the gaps out of FFmpeg's `silencedetect` marks — either its
  /// log (`silence_start: 1.2`) or `ametadata`'s print-out of the same
  /// marks (`lavfi.silence_start=1.2`).
  ///
  /// The filter reports a start and an end per gap, on separate lines
  /// and interleaved with everything else FFmpeg has to say; a run cut
  /// short can leave a start with no end, which is simply not a gap.
  /// Pure, so the parsing is testable without a device.
  @visibleForTesting
  static List<SilenceGap> parseSilence(String log) {
    final starts = <double>[];
    final gaps = <SilenceGap>[];
    final re = RegExp(r'silence_(start|end)\s*[:=]\s*(-?[\d.]+)');
    for (final m in re.allMatches(log)) {
      final v = double.tryParse(m.group(2)!);
      if (v == null) continue;
      if (m.group(1) == 'start') {
        starts.add(v < 0 ? 0 : v);
      } else if (starts.isNotEmpty) {
        final from = starts.removeLast();
        if (v > from) {
          gaps.add(SilenceGap((from * 1000).round(), (v * 1000).round()));
        }
      }
    }
    gaps.sort((a, b) => a.startMs.compareTo(b.startMs));
    return gaps;
  }

  /// The gaps in [path], looked for harder when the first pass did not
  /// find enough of them to separate [wanted] verses.
  ///
  /// One threshold cannot serve every recording: a clean studio
  /// murattal has -50 dB between its verses, a phone recording in a
  /// room has -28 dB, and a pass tuned for one finds nothing in the
  /// other. So the quiet, confident pass runs first, and a looser one
  /// only runs when it has to — its extra gaps are noisier, but [plan]
  /// treats every gap as a suggestion anyway.
  static Future<List<SilenceGap>> detectSilenceFor(
    String path, {
    required int wanted,
  }) async {
    final first = await detectSilence(path);
    if (first.length >= wanted - 1) return first;
    final second =
        await detectSilence(path, noiseDb: -28, minSeconds: 0.16);
    return second.length > first.length ? second : first;
  }

  /// A rough loudness envelope of [path], [buckets] values in 0..1, for
  /// drawing a waveform. Null when it cannot be produced — the timing
  /// screen then falls back to a plain bar, which every control on it
  /// works against just as well.
  static Future<List<double>?> peaks(
    String path, {
    required int durationMs,
    int buckets = 320,
  }) async {
    File? raw;
    try {
      final seconds = durationMs / 1000;
      // A fixed sample budget, not a fixed rate: a one-minute upload is
      // read finely, and a one-hour upload does not turn into hundreds
      // of megabytes of PCM to draw 320 bars from.
      final rate =
          (600000 / (seconds <= 0 ? 1 : seconds)).clamp(200, 4000).round();
      final tmp = await getTemporaryDirectory();
      raw = File('${tmp.path}/ua_peaks.pcm');
      final session = await FFmpegKit.execute(
        '-hide_banner -nostats -i "$path" -vn -ac 1 -ar $rate '
        '-f s16le -y "${raw.path}"',
      );
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code) || !raw.existsSync()) return null;
      final bytes = raw.readAsBytesSync();
      final samples = bytes.lengthInBytes ~/ 2;
      if (samples < buckets) return null;
      final view = ByteData.sublistView(bytes);
      final out = List<double>.filled(buckets, 0);
      var peak = 0.0;
      for (var b = 0; b < buckets; b++) {
        final from = samples * b ~/ buckets;
        final to = samples * (b + 1) ~/ buckets;
        var sum = 0.0;
        for (var i = from; i < to; i++) {
          final v = view.getInt16(i * 2, Endian.little) / 32768.0;
          sum += v * v;
        }
        final rms = to > from ? math.sqrt(sum / (to - from)) : 0.0;
        out[b] = rms;
        if (rms > peak) peak = rms;
      }
      if (peak <= 0) return null;
      // Normalized, then compressed: a recitation sits well below its
      // own loudest moment nearly all the time, and a linear envelope
      // of one draws as a flat line with three spikes in it.
      return [for (final v in out) math.pow(v / peak, 0.6).toDouble()];
    } catch (e) {
      rlog('user audio: peaks failed ($e)');
      return null;
    } finally {
      try {
        if (raw != null && raw.existsSync()) raw.deleteSync();
      } catch (_) {}
    }
  }

  // ---- placing the verses ---------------------------------------------

  /// Where each ayah of [startAyah]..[endAyah] falls inside a recording
  /// [durationMs] long, given the silences found in it.
  ///
  /// Two signals, and neither is trusted alone:
  ///
  ///  * **Length.** How long a verse takes to recite tracks its letter
  ///    count closely — that is the model [ReelDuration] is built on —
  ///    so the verses' own text says what share of the recording each
  ///    of them should take. Stretched over the audible span, that
  ///    alone puts most boundaries within about a second of the truth,
  ///    for any voice, without listening to a note.
  ///
  ///  * **Silence.** The reciter's breath marks the real joint. But a
  ///    gap on its own says nothing about *which* joint it is: a long
  ///    verse pauses in the middle, a noisy recording swallows the
  ///    short pauses, and counting gaps off against verses breaks the
  ///    moment the two numbers disagree — which, on a real upload, is
  ///    most of the time.
  ///
  /// So the length model proposes and the silence corrects: each
  /// predicted boundary looks for a gap near itself and snaps to the
  /// middle of it, within a window scaled to the verses it separates.
  /// A boundary with no gap nearby keeps its predicted time, and a gap
  /// already claimed cannot be claimed twice — which is what keeps the
  /// result ascending and one-verse-per-slice however wrong the
  /// detection was.
  ///
  /// Pure: no I/O, no plugins, so all of it is testable off-device.
  static List<AyahTiming> plan({
    required List<Ayah> ayahs,
    required int startAyah,
    required int endAyah,
    required int durationMs,
    required List<SilenceGap> silences,
  }) {
    final n = endAyah - startAyah + 1;
    assert(n >= 1);

    // 1) The audible span. Lead-in and run-out silence belong to no
    //    verse, and opening the first card on two seconds of hiss is
    //    the most visible way to get this wrong.
    var from = 0;
    var to = durationMs;
    for (final g in silences) {
      if (g.startMs <= 250 && g.endMs > from) from = g.endMs;
      if (g.endMs >= durationMs - 250 && g.startMs < to) to = g.startMs;
    }
    // Hand a little of the silence back on each side: the breath taken
    // just before the first word belongs with it.
    from = (from - 120).clamp(0, durationMs);
    to = (to + 120).clamp(0, durationMs);
    if (to - from < n * minAyahMs) {
      from = 0;
      to = durationMs;
    }
    final span = to - from;

    if (n == 1) return [AyahTiming(startAyah, from, to)];

    // 2) Predict from the text: each verse takes the share of the span
    //    its own letters ask for.
    final weights = <int>[
      for (var a = startAyah; a <= endAyah; a++)
        math.max(1, ReelDuration.estimateMs(ayahs, startAyah: a, endAyah: a)),
    ];
    final total = weights.fold<int>(0, (s, w) => s + w);
    final predicted = <int>[from];
    var acc = 0;
    for (var i = 0; i < n - 1; i++) {
      acc += weights[i];
      predicted.add(from + (span * acc / total).round());
    }
    predicted.add(to);

    // 3) Correct with the breaths. Only a gap strictly inside the span
    //    can be a joint; the edges were already spent above.
    final interior = [
      for (final g in silences)
        if (g.startMs > from + minAyahMs && g.endMs < to - minAyahMs) g,
    ];
    final used = List<bool>.filled(interior.length, false);
    final marks = List<int>.from(predicted);
    for (var i = 1; i < n; i++) {
      final before = predicted[i] - predicted[i - 1];
      final after = predicted[i + 1] - predicted[i];
      final shorter = before < after ? before : after;
      // Reach far enough to fix a real mistake, never far enough to
      // step over a neighbouring verse.
      final window = (shorter * 0.45).round().clamp(250, 2500);
      final floor = marks[i - 1] + minAyahMs;
      final ceil = to - (n - i) * minAyahMs;
      var best = -1;
      var bestDistance = 1 << 30;
      for (var k = 0; k < interior.length; k++) {
        if (used[k]) continue;
        final mid = interior[k].midMs;
        final d = (mid - predicted[i]).abs();
        if (d > window || d >= bestDistance) continue;
        if (mid < floor || mid > ceil) continue;
        best = k;
        bestDistance = d;
      }
      if (best >= 0) {
        used[best] = true;
        marks[i] = interior[best].midMs;
      }
    }

    return timingsFrom(marks, startAyah, endMs: durationMs);
  }

  /// Ayah windows from [marks] — one more mark than there are verses,
  /// the first being the start of the run and the last its end.
  ///
  /// Pushes marks apart wherever an edit (or a snap) left two of them
  /// closer than a verse may be, so the table handed downstream is
  /// always strictly ascending. With [endMs] (the recording's length),
  /// pushing apart never carries the last mark past the end: the marks
  /// before it are pulled back instead.
  static List<AyahTiming> timingsFrom(
    List<int> marks,
    int startAyah, {
    int? endMs,
  }) {
    final m = List<int>.from(marks);
    void forward() {
      for (var i = 1; i < m.length; i++) {
        if (m[i] < m[i - 1] + minAyahMs) m[i] = m[i - 1] + minAyahMs;
      }
    }

    forward();
    if (endMs != null && m.isNotEmpty && m.last > endMs) {
      // Past the end of the file: hold the last mark there and pull
      // its neighbours back, then push forward once more in case the
      // file is too short to fit them all (ascending wins over length).
      m[m.length - 1] = endMs;
      for (var i = m.length - 2; i >= 0; i--) {
        if (m[i] > m[i + 1] - minAyahMs) m[i] = m[i + 1] - minAyahMs;
      }
      if (m.first < 0) m[0] = 0;
      forward();
    }
    return [
      for (var i = 0; i < m.length - 1; i++)
        AyahTiming(startAyah + i, m[i], m[i + 1]),
    ];
  }

  /// The marks behind a timing table — the inverse of [timingsFrom],
  /// for the screen that edits them.
  static List<int> marksOf(List<AyahTiming> timings) => [
        for (final t in timings) t.startMs,
        timings.last.endMs,
      ];
}
