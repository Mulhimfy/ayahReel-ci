import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ayahreel_listen/ayahreel_listen.dart' as engine;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../debug_log.dart';
import 'listen_model.dart';
import 'listen_service.dart';

/// A word the live recitation has reached.
@immutable
class LiveWordHeard {
  final int surah, ayah, position;
  final int startMs;
  const LiveWordHeard(this.surah, this.ayah, this.position, this.startMs);
}

/// What the screen shows while someone recites.
@immutable
class LiveView {
  /// Where the reciter is: (surah, ayah), null until the tracker is sure.
  final (int, int)? place;

  /// Positions heard so far in each verse of the current surah.
  final Map<int, Set<int>> heard;

  /// The last word placed, as (ayah, position).
  final (int, int)? last;
  final int elapsedMs;

  /// Loudness of the microphone just now, 0..1.
  final double level;

  const LiveView({
    this.place,
    this.heard = const {},
    this.last,
    this.elapsedMs = 0,
    this.level = 0,
  });
}

/// AyahReel Listen following a recitation as it happens: the microphone's
/// sound is written to a file (the reel's audio, afterwards) and, every
/// [hopMs], the model runs over the last [windowS] seconds; the frames with
/// [lookS] of sound after them go to the tracker (package ayahreel_listen,
/// LiveTracker), which runs in an isolate of its own and answers with the
/// words it placed.
class ListenLive {
  static const _channel = MethodChannel('ayahreel/listen');
  static const sr = 16000;

  final int hopMs;
  final double windowS;
  final double lookS;

  ListenLive({this.hopMs = 800, this.windowS = 5.0, this.lookS = 1.0});

  final view = ValueNotifier(const LiveView());

  final _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  RandomAccessFile? _wav;
  File? _wavFile;
  final _recent = <Float32List>[];
  int _recentSamples = 0;
  int _samples = 0;
  int _committed = 0;
  Timer? _timer;
  bool _busy = false;
  bool _running = false;
  double _level = 0;
  ListenManifest? _m;

  Isolate? _iso;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  Completer<void>? _ready;
  int? _surah;
  final _heard = <int, Set<int>>{};
  (int, int)? _last;
  (int, int)? _place;

  bool get running => _running;

  /// Whether the microphone may be used (asks the first time).
  Future<bool> permitted() => _rec.hasPermission();

  /// Starts listening: the model must be on the phone (ListenModel).
  Future<void> start(File model) async {
    final m = await ListenModel.manifest();
    if (m == null) throw const ListenUnavailable('manifest');
    _m = m;
    await _channel.invokeMethod('load', {'path': model.path, 'threads': 2});
    await _spawn(m);
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/recitations');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _wavFile = File(
        '${dir.path}/recited_${DateTime.now().millisecondsSinceEpoch}.wav');
    _wav = await _wavFile!.open(mode: FileMode.write);
    await _wav!.writeFrom(_wavHeader(0));
    final stream = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sr,
      numChannels: 1,
    ));
    _running = true;
    _sub = stream.listen(_onPcm, onError: (Object e) {
      rlog('live: microphone error $e');
    });
    _timer = Timer.periodic(Duration(milliseconds: hopMs), (_) => _hop());
    rlog('live: started');
  }

  void _onPcm(Uint8List bytes) {
    if (!_running || bytes.isEmpty) return;
    final even = bytes.length & ~1;
    _wav?.writeFromSync(bytes, 0, even);
    final pcm = Int16List.sublistView(
        Uint8List.fromList(bytes.sublist(0, even)));
    final f = Float32List(pcm.length);
    var peak = 0.0;
    for (var i = 0; i < pcm.length; i++) {
      final v = pcm[i] / 32768.0;
      f[i] = v;
      final a = v < 0 ? -v : v;
      if (a > peak) peak = a;
    }
    _level = _level * 0.6 + peak * 0.4;
    _recent.add(f);
    _recentSamples += f.length;
    _samples += f.length;
    final keep = (windowS * sr).ceil() + sr;
    while (_recentSamples - _recent.first.length > keep) {
      _recentSamples -= _recent.removeAt(0).length;
    }
  }

  Future<void> _hop() async {
    if (_busy || !_running) return;
    final m = _m;
    if (m == null || _toWorker == null) return;
    _busy = true;
    try {
      final hop = m.hop;
      final end = _samples;
      final win = (windowS * sr).round();
      var lo = end - win < 0 ? 0 : end - win;
      lo = lo ~/ hop * hop;
      final wave = _tail(end - lo);
      if (wave.length < sr ~/ 2) return;
      final r = await _channel.invokeMapMethod<String, Object?>(
          'run', {'wave': wave});
      final lp = r!['logp'] as Float32List;
      final width = (r['width'] as num).toInt();
      final frames = (r['frames'] as num).toInt();
      final lastOk = (end - (lookS * sr).round()) ~/ hop;
      final first = _committed;
      final rows = <Float32List>[];
      for (var f = first; f < lastOk; f++) {
        final k = f - lo ~/ hop;
        if (k < 0 || k >= frames) continue;
        rows.add(Float32List.sublistView(lp, k * width, (k + 1) * width));
      }
      if (rows.isNotEmpty) {
        _committed = first + rows.length;
        final flat = Float32List(rows.length * width);
        for (var i = 0; i < rows.length; i++) {
          flat.setRange(i * width, (i + 1) * width, rows[i]);
        }
        _toWorker!.send({
          'rows': TransferableTypedData.fromList([flat]),
          'width': width,
          'now': end * 1000 ~/ sr,
        });
      }
      _publish();
    } catch (e) {
      rlog('live: hop failed ($e)');
    } finally {
      _busy = false;
    }
  }

  /// The last [n] samples heard.
  Float32List _tail(int n) {
    final out = Float32List(n);
    var at = n;
    for (var i = _recent.length - 1; i >= 0 && at > 0; i--) {
      final c = _recent[i];
      final take = c.length < at ? c.length : at;
      out.setRange(at - take, at, c, c.length - take);
      at -= take;
    }
    return out;
  }

  void _publish() {
    view.value = LiveView(
      place: _place,
      heard: {for (final e in _heard.entries) e.key: Set.of(e.value)},
      last: _last,
      elapsedMs: _samples * 1000 ~/ sr,
      level: _level.clamp(0.0, 1.0),
    );
  }

  Future<void> _spawn(ListenManifest m) async {
    final text = await ListenService.quranText();
    _fromWorker = ReceivePort();
    _ready = Completer<void>();
    _iso = await Isolate.spawn(_liveWorker, _fromWorker!.sendPort);
    _fromWorker!.listen((msg) {
      if (msg is SendPort) {
        _toWorker = msg;
        msg.send({'init': true, 'text': text, 'vocab': m.vocab, 'frameMs': m.frameMs});
      } else if (msg is Map && msg['ready'] == true) {
        _ready?.complete();
      } else if (msg is Map && msg['words'] is List) {
        for (final w in (msg['words'] as List).cast<List>()) {
          final s = w[0] as int, a = w[1] as int, p = w[2] as int;
          if (_surah != s) {
            _surah = s;
            _heard.clear();
          }
          _heard.putIfAbsent(a, () => <int>{}).add(p);
          _last = (a, p);
        }
        final pl = msg['place'];
        if (pl is List) _place = (pl[0] as int, pl[1] as int);
        _publish();
      }
    });
    await _ready!.future.timeout(const Duration(seconds: 20));
  }

  /// Stops listening. Returns the recording (a WAV file), or null when
  /// nothing was heard.
  Future<File?> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    try {
      await _rec.stop();
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    final wav = _wav;
    _wav = null;
    if (wav != null) {
      final dataBytes = await wav.length() - 44;
      await wav.setPosition(0);
      await wav.writeFrom(_wavHeader(dataBytes < 0 ? 0 : dataBytes));
      await wav.close();
    }
    unawaited(_channel.invokeMethod('unload').catchError((_) {}));
    _toWorker?.send('close');
    _fromWorker?.close();
    _iso?.kill(priority: Isolate.beforeNextEvent);
    _iso = null;
    final f = _wavFile;
    if (f == null || !f.existsSync() || f.lengthSync() <= 44 + sr) {
      try {
        f?.deleteSync();
      } catch (_) {}
      return null;
    }
    return f;
  }

  Future<void> dispose() async {
    if (_running) {
      final f = await stop();
      try {
        f?.deleteSync();
      } catch (_) {}
    }
    await _rec.dispose();
    view.dispose();
  }

  static Uint8List _wavHeader(int dataBytes) {
    final b = ByteData(44);
    void str(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataBytes, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, sr, Endian.little);
    b.setUint32(28, sr * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataBytes, Endian.little);
    return b.buffer.asUint8List();
  }
}

/// The tracker's isolate: built once (the Quran's index), then fed the
/// committed frames hop by hop.
void _liveWorker(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  engine.LiveTracker? tracker;
  inbox.listen((msg) {
    if (msg is Map && msg['init'] == true) {
      final text = (msg['text'] as List).cast<List<String>>();
      final vocab = (msg['vocab'] as List).cast<String>();
      final fm = (msg['frameMs'] as num).toDouble();
      tracker = engine.LiveTracker(
          engine.Spell(vocab, frameMs: fm), engine.QuranIndex(text));
      out.send({'ready': true});
    } else if (msg is Map && msg['rows'] != null) {
      final t = tracker;
      if (t == null) return;
      final flat = (msg['rows'] as TransferableTypedData)
          .materialize()
          .asFloat32List();
      final width = msg['width'] as int;
      final rows = <Float32List>[
        for (var i = 0; i + width <= flat.length; i += width)
          Float32List.sublistView(flat, i, i + width),
      ];
      final words = t.commit(rows, msg['now'] as int);
      final pl = t.place;
      out.send({
        'words': [
          for (final w in words) [w.surah, w.ayah, w.position, w.startMs],
        ],
        'place': pl == null ? null : [pl.$1, pl.$2],
      });
    } else if (msg == 'close') {
      inbox.close();
    }
  });
}
