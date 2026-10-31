import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ayahreel_listen/ayahreel_listen.dart' as engine;
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../debug_log.dart';
import 'listen_model.dart';

/// One passage AyahReel Listen heard in a recording.
class ListenFound {
  final int surah;
  final int first;
  final int last;
  final double score;

  /// The app's compact word timing (`QulWords.encodeCompact`'s shape):
  /// ayah -> [from, to, p, s, e, ...], ms on the recording's own clock,
  /// in the order recited. Only verses whose words were found.
  final Map<int, List<int>> timing;

  /// Per verse: whether every word was heard, and how clearly (the mean
  /// log-probability of the path below the model's best, per frame:
  /// 0 is perfect, below -2 is doubtful).
  final Map<int, ({bool full, double conf, int words})> verses;

  /// Other places with the same (or nearly the same) words: (surah,
  /// first, last). A verse such as 55:13 has thirty twins.
  final List<(int, int, int)> alternatives;

  const ListenFound({
    required this.surah,
    required this.first,
    required this.last,
    required this.score,
    required this.timing,
    required this.verses,
    required this.alternatives,
  });

  /// Where the passage's words begin and end in the recording, ms.
  (int, int)? get spanMs {
    int? a, b;
    for (final v in timing.values) {
      if (a == null || v[0] < a) a = v[0];
      if (b == null || v[1] > b) b = v[1];
    }
    return a == null ? null : (a, b!);
  }
}

class ListenOutcome {
  final List<ListenFound> passages;

  /// The model's output, kept for timing another passage on the same
  /// recording (an alternative the user picks): frames x [width].
  final Float32List logp;
  final int width;
  final List<String> vocab;
  final double frameMs;

  /// Index of the passage that holds most of the recording.
  final int? best;
  final String model;
  final int audioMs;
  final int modelMs;
  final int engineMs;

  const ListenOutcome({
    required this.passages,
    required this.logp,
    required this.width,
    required this.vocab,
    required this.frameMs,
    required this.best,
    required this.model,
    required this.audioMs,
    required this.modelMs,
    required this.engineMs,
  });

  ListenFound? get main => best == null ? null : passages[best!];
}

/// Where a listen is: fetching the model, reading the audio, hearing it
/// (with the share done), finding the verses.
enum ListenStage { model, decode, hear, find }

typedef ListenProgress = void Function(ListenStage stage, double share);

/// AyahReel Listen on the phone: the model (ONNX Runtime, native, see
/// ListenBridge) turns the recording into letter probabilities, and the
/// engine (package ayahreel_listen, in a background isolate) finds the
/// verses and times every word.
abstract final class ListenService {
  static const _channel = MethodChannel('ayahreel/listen');

  static List<List<String>>? _text;

  /// The Quran as the app displays it (the same text the engine was
  /// built on), per surah, per verse.
  static Future<List<List<String>>> _quran() async {
    final held = _text;
    if (held != null) return held;
    final raw = await rootBundle.loadString('assets/quran_search.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return _text = [
      for (var s = 1; s <= 114; s++) (j['$s'] as List).cast<String>(),
    ];
  }

  static int get _threads {
    final n = Platform.numberOfProcessors;
    return n >= 8 ? 4 : (n >= 4 ? 2 : 1);
  }

  /// Hears the recording at [audioPath]. Throws [ListenUnavailable] when
  /// the model can't be had, and anything else when the audio can't be
  /// read. [keepGoing] returning false stops it (between windows).
  static Future<ListenOutcome> hearFile(
    String audioPath, {
    ListenProgress? onProgress,
    bool Function()? keepGoing,
  }) async {
    bool going() => keepGoing == null || keepGoing();
    final sw = Stopwatch()..start();
    final model = await ListenModel.ensure(
      onProgress: (s) => onProgress?.call(ListenStage.model, s),
      keepGoing: keepGoing,
    );
    final m = (await ListenModel.manifest())!;
    onProgress?.call(ListenStage.decode, 0);
    final tmp = await getTemporaryDirectory();
    final pcm = File('${tmp.path}/listen_${DateTime.now().microsecondsSinceEpoch}.s16');
    try {
      final session = await FFmpegKit.execute(
        '-hide_banner -nostats -i "$audioPath" -vn -ac 1 -ar 16000 '
        '-f s16le -y "${pcm.path}"',
      );
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code) || !pcm.existsSync()) {
        throw const FormatException('listen: the audio could not be read');
      }
      if (!going()) throw const ListenUnavailable('cancelled');
      final samples = pcm.lengthSync() ~/ 2;
      final audioMs = samples * 1000 ~/ 16000;
      await _channel.invokeMethod('load', {'path': model.path, 'threads': _threads});
      final t0 = sw.elapsedMilliseconds;
      final logp = await _logp(pcm, samples, m, (s) {
        onProgress?.call(ListenStage.hear, s);
      }, going);
      final modelMs = sw.elapsedMilliseconds - t0;
      unawaited(_channel.invokeMethod('unload').catchError((_) {}));
      if (!going()) throw const ListenUnavailable('cancelled');
      onProgress?.call(ListenStage.find, 0);
      final text = await _quran();
      final vocab = m.vocab;
      final width = vocab.length + 1;
      final frameMs = m.frameMs;
      final t1 = sw.elapsedMilliseconds;
      final found = await Isolate.run(
          () => _hear(logp, width, frameMs, vocab, text));
      final engineMs = sw.elapsedMilliseconds - t1;
      rlog('listen: ${(audioMs / 1000).toStringAsFixed(1)} s heard in '
          '${modelMs}ms + ${engineMs}ms: '
          '${found.$1.map((p) => '${p.surah}:${p.first}-${p.last}').join(' ')}');
      return ListenOutcome(
        passages: found.$1,
        logp: logp,
        width: width,
        vocab: vocab,
        frameMs: frameMs,
        best: found.$2,
        model: m.model,
        audioMs: audioMs,
        modelMs: modelMs,
        engineMs: engineMs,
      );
    } finally {
      try {
        if (pcm.existsSync()) pcm.deleteSync();
      } catch (_) {}
    }
  }

  /// [surah] [first]..[last] timed over the stretch of [outcome]'s
  /// recording that [heard] was found in: for an alternative the user
  /// picks (the same words elsewhere in the mushaf). Null when it can't
  /// be placed.
  static Future<Map<int, List<int>>?> retime(ListenOutcome outcome,
      ListenFound heard, int surah, int first, int last) async {
    final span = heard.spanMs;
    if (span == null) return null;
    final text = await _quran();
    final lp = outcome.logp, width = outcome.width, vocab = outcome.vocab;
    final fm = outcome.frameMs;
    final frames = lp.length ~/ width;
    var f0 = (span.$1 / fm).floor() - 25;
    var f1 = (span.$2 / fm).ceil() + 25;
    if (f0 < 0) f0 = 0;
    if (f1 > frames) f1 = frames;
    return Isolate.run(() {
      final q = engine.QuranIndex(text);
      final spell = engine.Spell(vocab, frameMs: fm);
      return engine.timeRange(engine.LogProbs(lp, width, frameMs: fm), spell, q,
          surah, first, last, f0, f1);
    });
  }

  /// Each verse's word count in the app's text (what the word light
  /// checks a verse's timing against).
  static Future<Map<int, int>> wordCounts(int surah, int first, int last) async {
    final text = await _quran();
    return {
      for (var a = first; a <= last; a++)
        a: engine.verseWords(text[surah - 1][a - 1]).length,
    };
  }

  /// A verse's text as the app displays it.
  static Future<String> verseText(int surah, int ayah) async =>
      (await _quran())[surah - 1][ayah - 1];

  /// The model over the whole recording: windows of [m.windowS] seconds
  /// overlapping [m.overlapS] either side, stitched at their middles
  /// (the engine's fc_server scheme), [m.hop] samples per frame.
  static Future<Float32List> _logp(File pcm, int samples, ListenManifest m,
      void Function(double) progress, bool Function() going) async {
    const sr = 16000;
    final win = m.windowS * sr, ov = m.overlapS * sr, hop = m.hop;
    final width = m.vocab.length + 1;
    final want = samples ~/ hop < 1 ? 1 : samples ~/ hop;
    final out = Float32List(want * width);
    var filled = 0;
    final raf = await pcm.open();
    try {
      var start = 0;
      do {
        if (!going()) throw const ListenUnavailable('cancelled');
        final lo = start - ov < 0 ? 0 : start - ov;
        final hi = start + win + ov > samples ? samples : start + win + ov;
        final wave = await _read(raf, lo, hi);
        final r = await _channel.invokeMapMethod<String, Object?>(
            'run', {'wave': wave});
        final lp = r!['logp'] as Float32List;
        final frames = (r['frames'] as num).toInt();
        final a = (start - lo) ~/ hop;
        final end = start + win > samples ? samples : start + win;
        var b = a + (end - start) ~/ hop;
        if (b > frames) b = frames;
        for (var t = a; t < b && filled < want; t++) {
          out.setRange(filled * width, (filled + 1) * width,
              Float32List.sublistView(lp, t * width, (t + 1) * width));
          filled++;
        }
        start += win;
        progress(start >= samples ? 1.0 : start / samples);
      } while (start < samples);
    } finally {
      await raf.close();
    }
    // A last frame or two the windows didn't reach: the last row again.
    for (; filled < want && filled > 0; filled++) {
      out.setRange(filled * width, (filled + 1) * width,
          Float32List.sublistView(out, (filled - 1) * width, filled * width));
    }
    return out;
  }

  static Future<Float32List> _read(RandomAccessFile raf, int from, int to) async {
    var n = to - from;
    // The model wants half a second at least.
    final size = n < 8000 ? 8000 : n;
    final bytes = Uint8List(n * 2);
    await raf.setPosition(from * 2);
    await raf.readInto(bytes);
    final pcm = Int16List.sublistView(bytes);
    final wave = Float32List(size);
    for (var i = 0; i < n; i++) {
      wave[i] = pcm[i] / 32768.0;
    }
    return wave;
  }
}

/// In the background isolate: the engine over the model's output.
(List<ListenFound>, int?) _hear(Float32List logp, int width, double frameMs,
    List<String> vocab, List<List<String>> text) {
  final q = engine.QuranIndex(text);
  final spell = engine.Spell(vocab, frameMs: frameMs);
  final r = engine.hear(engine.LogProbs(logp, width, frameMs: frameMs), spell, q);
  final out = <ListenFound>[];
  for (var i = 0; i < r.passages.length; i++) {
    final p = r.passages[i];
    final al = r.aligned[i];
    out.add(ListenFound(
      surah: p.surah,
      first: p.first,
      last: p.last,
      score: p.score,
      timing: r.timing[i],
      verses: {
        if (al != null)
          for (final e in al.verses.entries)
            e.key: (
              full: e.value.full,
              conf: e.value.conf,
              words: e.value.words,
            ),
      },
      alternatives: [
        for (final a in p.alternatives) (a.surah, a.first, a.last),
      ],
    ));
  }
  return (out, r.best);
}
