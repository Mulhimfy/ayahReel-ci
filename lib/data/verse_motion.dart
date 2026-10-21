import 'package:flutter/foundation.dart';

/// How each verse, or each part of a long one, comes on and goes off.
enum VerseArrival {
  /// Straight on, straight off: the original behaviour.
  none,

  /// Fades in as its recitation begins, and out as the reciter finishes
  /// it.
  fade,

  /// Fades in rising a little into place, and fades out as it settles.
  rise,
}

/// What the verse text does while it is recited, beyond the lit word.
///
/// Everything here has to be drawn the same twice: live in the preview,
/// and by FFmpeg in the export. So nothing in it is something FFmpeg
/// would have to redraw the type for on every frame: the arrival is the
/// card's own alpha and position, the thread and the light are small
/// pictures moved and cropped over the card, and the trail and the
/// unveil are the word-by-word cards the word highlight already makes.
/// The timing of all of it comes from one place — [VerseMotion]'s
/// curves and [RowProgress] — which both sides read.
@immutable
class VerseMotion {
  final VerseArrival arrival;

  /// A thread of gold drawn under the words as they are recited,
  /// reaching each word's end as the reciter does.
  final bool thread;

  /// A band of light that passes through the letters with the
  /// recitation.
  final bool light;

  /// Words stay lit once recited, so the line fills with gold as it is
  /// read. Needs a voice with word timing.
  final bool trail;

  /// Words wait faint until the reciter reaches them. Needs a voice with
  /// word timing.
  final bool unveil;

  const VerseMotion({
    this.arrival = VerseArrival.none,
    this.thread = false,
    this.light = false,
    this.trail = false,
    this.unveil = false,
  });

  static const none = VerseMotion();

  bool get isNone =>
      arrival == VerseArrival.none && !thread && !light && !trail && !unveil;

  /// Whether any of it changes the verse cards themselves, which only a
  /// voice with word timing can drive.
  bool get followsWords => trail || unveil;

  /// Whether the card's own alpha or place is animated.
  bool get moves => arrival != VerseArrival.none;

  /// Short and stable: what the render's cache key carries. Empty for
  /// [none], so every reel cached before motion existed keeps its key.
  String get key {
    if (isNone) return '';
    return 'm${arrival.index}${thread ? 't' : ''}${light ? 'l' : ''}'
        '${trail ? 'g' : ''}${unveil ? 'u' : ''}';
  }

  VerseMotion copyWith({
    VerseArrival? arrival,
    bool? thread,
    bool? light,
    bool? trail,
    bool? unveil,
  }) =>
      VerseMotion(
        arrival: arrival ?? this.arrival,
        thread: thread ?? this.thread,
        light: light ?? this.light,
        trail: trail ?? this.trail,
        unveil: unveil ?? this.unveil,
      );

  /// What the preview and the export actually run, for a voice that
  /// has word timing or not: the trail and the unveil need it.
  VerseMotion forVoice({required bool hasWords}) =>
      hasWords ? this : copyWith(trail: false, unveil: false);

  Map<String, dynamic> toJson() => {
        'arrival': arrival.name,
        if (thread) 'thread': true,
        if (light) 'light': true,
        if (trail) 'trail': true,
        if (unveil) 'unveil': true,
      };

  factory VerseMotion.fromJson(Map<String, dynamic>? j) {
    if (j == null) return none;
    var arrival = VerseArrival.none;
    for (final a in VerseArrival.values) {
      if (a.name == j['arrival']) arrival = a;
    }
    return VerseMotion(
      arrival: arrival,
      thread: j['thread'] == true,
      light: j['light'] == true,
      trail: j['trail'] == true,
      unveil: j['unveil'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VerseMotion &&
      other.arrival == arrival &&
      other.thread == thread &&
      other.light == light &&
      other.trail == trail &&
      other.unveil == unveil;

  @override
  int get hashCode => Object.hash(arrival, thread, light, trail, unveil);

  @override
  String toString() => 'VerseMotion($key)';

  // ---- timing, shared by the preview and the export ------------------

  /// How long a card takes to come on and to go off, at most.
  static const fadeInMs = 320;
  static const riseInMs = 460;
  static const outMs = 260;

  /// How far a rising card travels, and how far it lifts as it leaves,
  /// in export pixels (1080 wide).
  static const risePx = 36.0;
  static const liftPx = 10.0;

  /// The arrival's and the departure's lengths for a unit [unitMs]
  /// long: never more than a third of it coming on and a quarter going
  /// off, so a short part is never all fade.
  ({int inMs, int outMs}) windowsFor(int unitMs) {
    if (!moves || unitMs <= 0) return (inMs: 0, outMs: 0);
    final want = arrival == VerseArrival.rise ? riseInMs : fadeInMs;
    final i = want < unitMs ~/ 3 ? want : unitMs ~/ 3;
    final o = outMs < unitMs ~/ 4 ? outMs : unitMs ~/ 4;
    return (inMs: i, outMs: o);
  }

  /// The card's opacity [ms] into a unit [unitMs] long. Linear, because
  /// FFmpeg's fade is.
  double alphaAt(int ms, int unitMs) {
    final w = windowsFor(unitMs);
    var a = 1.0;
    if (w.inMs > 0 && ms < w.inMs) a = (ms / w.inMs).clamp(0.0, 1.0);
    final tail = unitMs - w.outMs;
    if (w.outMs > 0 && ms > tail) {
      a = a * ((unitMs - ms) / w.outMs).clamp(0.0, 1.0);
    }
    return a;
  }

  /// How far below its place the card is drawn, in export pixels, [ms]
  /// into a unit [unitMs] long (negative is above). Ease-out cubic on
  /// the way in, ease-in on the way out.
  double offsetAt(int ms, int unitMs) {
    if (arrival != VerseArrival.rise) return 0;
    final w = windowsFor(unitMs);
    if (w.inMs > 0 && ms < w.inMs) {
      final p = 1 - (ms / w.inMs).clamp(0.0, 1.0);
      return risePx * p * p * p;
    }
    final tail = unitMs - w.outMs;
    if (w.outMs > 0 && ms > tail) {
      final p = ((ms - tail) / w.outMs).clamp(0.0, 1.0);
      return -liftPx * p * p;
    }
    return 0;
  }

  /// [offsetAt] as an FFmpeg expression in [t] (seconds, unit-relative):
  /// the same curve, for the overlay's y.
  String offsetExpr(String t, int unitMs) {
    if (arrival != VerseArrival.rise) return '0';
    final w = windowsFor(unitMs);
    final parts = <String>[];
    if (w.inMs > 0) {
      final d = (w.inMs / 1000).toStringAsFixed(3);
      parts.add('if(lt($t,$d),${risePx.toStringAsFixed(1)}*pow(1-$t/$d,3),0)');
    }
    if (w.outMs > 0) {
      final tail = ((unitMs - w.outMs) / 1000).toStringAsFixed(3);
      final d = (w.outMs / 1000).toStringAsFixed(3);
      parts.add('if(gt($t,$tail),-${liftPx.toStringAsFixed(1)}'
          '*pow(min(1,($t-$tail)/$d),2),0)');
    }
    return parts.isEmpty ? '0' : parts.join('+');
  }
}

/// The designed looks the style step offers, each a whole [VerseMotion].
enum MotionPreset {
  still(VerseMotion.none),
  breathe(VerseMotion(arrival: VerseArrival.fade)),
  rise(VerseMotion(arrival: VerseArrival.rise)),
  thread(VerseMotion(arrival: VerseArrival.fade, thread: true)),
  light(VerseMotion(arrival: VerseArrival.fade, light: true)),
  unveil(VerseMotion(arrival: VerseArrival.fade, unveil: true)),
  gilded(VerseMotion(arrival: VerseArrival.rise, trail: true, thread: true));

  const MotionPreset(this.motion);
  final VerseMotion motion;

  /// Whether it shows anything more than its arrival without word
  /// timing.
  bool get needsWords => motion.followsWords;

  static MotionPreset? of(VerseMotion m) {
    for (final p in values) {
      if (p.motion == m) return p;
    }
    return null;
  }
}

/// How far along one line of a verse the recitation is, as the thread
/// and the light draw it: pixels from the line's right edge (the text
/// runs right to left), against milliseconds into the unit.
///
/// Piecewise linear through [points]: before the first, nothing; after
/// the last, the whole line. With word timing there are two points a
/// word — at its first sound the progress is at the word's right edge,
/// at its last at its left — so the thread reaches each word's end
/// exactly as the reciter does. Without, the line is crossed at an even
/// pace over its share of the unit.
@immutable
class RowProgress {
  /// (ms into the unit, pixels from the right edge), ascending in time
  /// and never going back.
  final List<(int, double)> points;

  /// The line's width in pixels: where the progress ends.
  final double width;

  const RowProgress(this.points, this.width);

  int get startMs => points.isEmpty ? 0 : points.first.$1;
  int get endMs => points.isEmpty ? 0 : points.last.$1;

  double at(int ms) {
    if (points.isEmpty) return 0;
    if (ms <= points.first.$1) return points.first.$2;
    for (var i = 1; i < points.length; i++) {
      final (t1, p1) = points[i];
      if (ms < t1) {
        final (t0, p0) = points[i - 1];
        if (t1 <= t0) return p1;
        return p0 + (p1 - p0) * (ms - t0) / (t1 - t0);
      }
    }
    return points.last.$2;
  }

  /// The same function as an FFmpeg expression in [t] (seconds, unit
  /// time — whatever the caller's clock is, passed as an expression).
  String expr(String t) {
    if (points.isEmpty) return '0';
    String s(int ms) => (ms / 1000).toStringAsFixed(3);
    String p(double v) => v.toStringAsFixed(1);
    final b = StringBuffer();
    var open = 0;
    b.write('if(lt($t,${s(points.first.$1)}),${p(points.first.$2)},');
    open++;
    for (var i = 1; i < points.length; i++) {
      final (t0, p0) = points[i - 1];
      final (t1, p1) = points[i];
      if (t1 <= t0) continue;
      final slope = (p1 - p0) / ((t1 - t0) / 1000);
      b.write('if(lt($t,${s(t1)}),'
          '${p(p0)}+${slope.toStringAsFixed(3)}*($t-${s(t0)}),');
      open++;
    }
    b.write(p(points.last.$2));
    for (var i = 0; i < open; i++) {
      b.write(')');
    }
    return b.toString();
  }

  /// A line crossed at an even pace from [fromMs] to [toMs].
  factory RowProgress.even(int fromMs, int toMs, double width) =>
      RowProgress([(fromMs, 0), (toMs > fromMs ? toMs : fromMs + 1, width)],
          width);

  /// A line crossed word by word: [words] are each word's (start, end)
  /// in ms into the unit, and its (right, left) edge as pixels from the
  /// line's right edge, in reading order.
  factory RowProgress.words(
      List<({int startMs, int endMs, double from, double to})> words,
      double width) {
    final pts = <(int, double)>[];
    var lastT = -1 << 30;
    var lastP = 0.0;
    void add(int t, double v) {
      if (t < lastT) t = lastT;
      if (v < lastP) v = lastP;
      if (t == lastT && pts.isNotEmpty) {
        pts[pts.length - 1] = (t, v);
      } else {
        pts.add((t, v));
      }
      lastT = t;
      lastP = v;
    }

    for (final w in words) {
      add(w.startMs, w.from);
      add(w.endMs > w.startMs ? w.endMs : w.startMs + 1, w.to);
    }
    if (pts.isEmpty) return RowProgress(const [], width);
    // The last word reaches the line's far end.
    if (pts.last.$2 < width) {
      pts[pts.length - 1] = (pts.last.$1, width);
    }
    return RowProgress(pts, width);
  }
}
