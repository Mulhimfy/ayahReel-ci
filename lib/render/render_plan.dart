import 'package:flutter/foundation.dart';

/// One stretch of the reel showing one scenery, and what the exporter
/// needs to know to cut it in two without the picture jumping.
///
/// A still can be cut anywhere: every frame of it is the same frame. A
/// clip long enough to cover its whole turn can be cut anywhere too —
/// the second half simply seeks into it. A short clip is on its second
/// or third loop by then, so it can only be cut where a loop starts,
/// or the picture would jump back to the clip's first frame mid-scene.
@immutable
class PictureSpan {
  /// Absolute times in the recording's clock, like a scene cut's.
  final int startMs;
  final int endMs;

  /// A still (photo, gradient, flattened backdrop): no motion to lose.
  final bool isImage;

  /// The source clip's own length, or null when it could not be
  /// measured — which is the one case where nothing can be said about
  /// where a cut is safe.
  final int? sourceMs;

  /// How much of the source this span consumes: its own length, plus
  /// the crossfade it hands over on when it has one.
  final int needsMs;

  const PictureSpan({
    required this.startMs,
    required this.endMs,
    this.isImage = false,
    this.sourceMs,
    int? needsMs,
  }) : needsMs = needsMs ?? endMs - startMs;

  int get durationMs => endMs - startMs;

  /// Whether the clip runs out inside this span and starts again.
  bool get loops => !isImage && (sourceMs == null || sourceMs! < needsMs);

  /// Whether the source covers the span outright, so a cut anywhere in
  /// it is a plain seek.
  bool get covers => !isImage && sourceMs != null && sourceMs! >= needsMs;
}

/// One FFmpeg pass: the slice of the reel it draws, in the recording's
/// clock and in whole video frames.
///
/// Frames rather than seconds because the passes are joined end to end
/// afterwards: a pass half a frame short would pull every later frame
/// earlier, and forty of those would slide the verses off the voice.
@immutable
class RenderPass {
  final int startMs;
  final int endMs;

  /// Video frames before this pass, and in it. `-frames:v` is what the
  /// encode is bounded by, so these are exact.
  final int fromFrame;
  final int frames;

  const RenderPass({
    required this.startMs,
    required this.endMs,
    required this.fromFrame,
    required this.frames,
  });

  int get durationMs => endMs - startMs;

  @override
  bool operator ==(Object other) =>
      other is RenderPass &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.fromFrame == fromFrame &&
      other.frames == frames;

  @override
  int get hashCode => Object.hash(startMs, endMs, fromFrame, frames);

  @override
  String toString() => 'RenderPass($startMs-$endMs, $frames frames)';
}

/// Cuts a reel into the passes the exporter encodes it in.
///
/// The filter graph opens one input per verse card and holds a decoded
/// frame of every one of them for the whole encode, so its cost is the
/// number of cards, not the number of seconds. Ninety cards is a couple
/// of hundred megabytes and fine; an hour's worth would be several
/// gigabytes, and the process is killed long before that. So a long
/// reel is encoded a slice at a time, each slice holding only the cards
/// it shows, and the slices are joined with a stream copy — no second
/// encode, nothing re-compressed.
///
/// Reels up to the length this app used to cap at come back as a single
/// pass, which is the path they have always taken.
///
/// Pure — no I/O, no plugins — so all of it is testable off-device.
abstract final class RenderPlan {
  /// The exporter's frame rate. Everything the graph produces is
  /// normalised to it, so pass boundaries are counted in it.
  static const fps = 30;

  /// A reel no longer and no busier than this is encoded in one pass,
  /// exactly as it was before long reels existed.
  static const singlePassMaxMs = 120 * 1000;
  static const singlePassMaxClips = 130;

  /// What each pass of a long reel aims for. Shorter passes mean more
  /// FFmpeg launches; longer ones mean more cards held at once and a
  /// coarser progress bar.
  static const passTargetMs = 90 * 1000;
  static const passMinMs = 20 * 1000;

  /// Verse cards (with word highlighting, card *windows*) one pass may
  /// hold. Comfortably under what a 90-second reel already renders with
  /// highlighting on.
  static const clipsPerPass = 48;

  /// The most a pass may hold when the picture leaves nowhere safe to
  /// cut — a clip ffprobe could not measure, or one that loops on a
  /// stride longer than a pass. Cutting there restarts the scenery,
  /// which is a jump at one boundary; not cutting there is an encode
  /// the phone runs out of memory for and kills, which is no export at
  /// all. So there is a point past which the jump wins. It sits where
  /// today's busiest single-pass reel already sits.
  static const clipsHardMax = 130;

  /// What a pass holds on a phone that has already refused one encode
  /// for want of memory — see [VideoRenderer]'s retry. A third of the
  /// usual budget: the graph's cost is the cards it holds decoded, so
  /// cutting their number is the one lever that reliably moves it.
  /// Slower (more FFmpeg launches, one stream-copy join) and worth it,
  /// since the alternative on that phone is no reel at all.
  static const clipsPerPassLowMemory = 16;

  /// Half that again, for the smallest phones and for any phone that
  /// lost an export even on the low-memory plan. Each card costs 12 to
  /// 17 MB in the graph, on top of about 350 MB for the encode itself:
  /// eight is about 500 MB a pass, and halving it again would save
  /// little and add launches.
  static const clipsPerPassLeast = 8;

  /// The passes covering [segStartMs]..[segEndMs].
  ///
  /// [clips] are the overlay windows, in start order; a clip straddling
  /// a boundary is simply drawn by both passes. [spans] is the scenery
  /// timeline — one entry for a single-background reel — and decides
  /// where a boundary may fall at all.
  ///
  /// [maxClips] caps what one pass may hold, whatever the length: it is
  /// how a phone short of memory asks for the same reel in smaller
  /// pieces. It overrides every clip budget here, including the one
  /// that lets a pass run long where the picture gives it nowhere safe
  /// to cut. A cut part-way through a lap of a looping clip is then
  /// made safe instead: the next pass seeks into the lap and ends where
  /// it does (see [_lapEndFor]), so the scenery never jumps back to its
  /// first frame.
  static List<RenderPass> of({
    required int segStartMs,
    required int segEndMs,
    required List<PictureSpan> spans,
    required List<({int startMs, int endMs})> clips,
    int fadeMs = 0,
    int? maxClips,
  }) {
    final total = segEndMs - segStartMs;
    if (total <= 0) return const [];
    final perPass = maxClips ?? clipsPerPass;
    final hardMax = maxClips ?? clipsHardMax;
    if (total <= singlePassMaxMs &&
        clips.length <= (maxClips ?? singlePassMaxClips)) {
      return [_pass(segStartMs, segStartMs, segEndMs)];
    }
    final out = <RenderPass>[];
    var from = segStartMs;
    while (from < segEndMs) {
      final budget = _clipBudgetEnd(clips, from, perPass);
      final hardEnd = _clipBudgetEnd(clips, from, hardMax);
      final lapEnd = _lapEndFor(spans, from);
      var hi = from + passTargetMs;
      if (budget != null && budget < hi) hi = budget;
      if (lapEnd != null && lapEnd < hi) hi = lapEnd;
      if (hi >= segEndMs) {
        out.add(_pass(segStartMs, from, segEndMs));
        break;
      }
      var lo = from + passMinMs;
      if (lo > hi) lo = hi;
      var at = _boundary(spans, segEndMs, fadeMs, lo, hi, largest: true);
      // Nothing safe inside the budget: a pass that runs long is a
      // slower export, a pass that cuts where it must not is a picture
      // that jumps. So look past the budget for the first safe cut, and
      // only if there is none at all take the whole rest in one.
      at ??= _boundary(spans, segEndMs, fadeMs, hi + 1, segEndMs - 1,
          largest: false);
      // And past a point, no safe boundary within reach beats no export
      // at all: see [clipsHardMax].
      if (hardEnd != null && (at == null || at > hardEnd)) at = hardEnd;
      // A pass that opened part-way through a lap is over when the lap
      // is, wherever else it might have run to.
      if (lapEnd != null && (at == null || at > lapEnd)) at = lapEnd;
      // Snap back to a frame boundary: the passes are counted in
      // frames, and a boundary between two of them cannot be encoded.
      // Back rather than to the nearest, so a boundary chosen to keep
      // clear of something is never rounded onto it; the shift is under
      // a frame, which no loop point notices.
      final t = at == null
          ? null
          : _msOfFrame(segStartMs, _floorFrame(segStartMs, at));
      if (t == null || t <= from || t >= segEndMs) {
        out.add(_pass(segStartMs, from, segEndMs));
        break;
      }
      out.add(_pass(segStartMs, from, t));
      from = t;
    }
    return out;
  }

  static RenderPass _pass(int segStartMs, int from, int to) {
    final f0 = _frameOf(segStartMs, from);
    final f1 = _frameOf(segStartMs, to);
    return RenderPass(
      startMs: from,
      endMs: to,
      fromFrame: f0,
      frames: f1 - f0,
    );
  }

  static int _frameOf(int segStartMs, int ms) =>
      ((ms - segStartMs) * fps / 1000).round();

  static int _floorFrame(int segStartMs, int ms) =>
      ((ms - segStartMs) * fps / 1000).floor();

  static int _msOfFrame(int segStartMs, int frame) =>
      segStartMs + (frame * 1000 / fps).round();

  /// Where the lap ends that a pass starting at [from] opens in, when
  /// [from] falls part-way through a lap of a looping clip; null
  /// otherwise.
  ///
  /// Such a pass reads its clip by seeking into it rather than looping
  /// it — FFmpeg applies an input's seek again on every lap — so it has
  /// to be over before the clip runs out. A pass that starts on a lap
  /// can loop as far as it likes. Within a frame of a lap's start
  /// counts as on it: the clip read from its top is less than a frame
  /// off, which is where every boundary at a loop point already lands.
  static int? _lapEndFor(List<PictureSpan> spans, int from) {
    for (final s in spans) {
      if (from < s.startMs || from >= s.endMs) continue;
      final l = s.sourceMs;
      if (!s.loops || l == null || l <= 0) return null;
      final phase = (from - s.startMs) % l;
      const frame = 1000 ~/ fps + 1;
      if (phase < frame || l - phase < frame) return null;
      return from - phase + l;
    }
    return null;
  }

  /// Where a clip that loops is to be read from by a pass opening
  /// [into] ms into its turn and drawing [ms] of it: that far into its
  /// lap when the pass is over before the lap is, else from its top —
  /// which, by [_lapEndFor], is a pass that starts on a lap. A clip
  /// that covers the whole turn is the same rule with one lap. Zero for
  /// a still, or a clip that could not be measured.
  static int seekInto({
    required bool isImage,
    required int? sourceMs,
    required int into,
    required int ms,
  }) {
    if (isImage || into <= 0 || sourceMs == null || sourceMs <= 0) return 0;
    final phase = into % sourceMs;
    return phase > 0 && sourceMs >= phase + ms ? phase : 0;
  }

  /// Where a pass starting at [from] must end for it to hold no more
  /// than [limit] cards, or null when it never has to.
  static int? _clipBudgetEnd(
      List<({int startMs, int endMs})> clips, int from, int limit) {
    var count = 0;
    for (final c in clips) {
      if (c.endMs <= from) continue;
      count++;
      // A card starting exactly here belongs to the next pass, so
      // ending on it is what keeps the count at [limit].
      if (count > limit) return c.startMs;
    }
    return null;
  }

  /// The safest boundary in [lo]..[hi] — the largest or the smallest,
  /// depending on which side of the budget we are searching.
  ///
  /// Inside a span first: cutting there costs nothing. A span edge is a
  /// cut the plan already makes, so it is safe too — except when the
  /// scenes cross-fade into each other there, which a boundary would
  /// turn back into a hard cut. So edges are the fallback, taken only
  /// when no span will be cut open.
  static int? _boundary(
    List<PictureSpan> spans,
    int segEndMs,
    int fadeMs,
    int lo,
    int hi, {
    required bool largest,
  }) {
    if (lo > hi) return null;
    int? best;
    int? edge;
    void take(int? t, {required bool isEdge}) {
      if (t == null) return;
      if (isEdge && fadeMs > 0) {
        if (edge == null || (largest ? t > edge! : t < edge!)) edge = t;
      } else {
        if (best == null || (largest ? t > best! : t < best!)) best = t;
      }
    }

    for (final s in spans) {
      // Inside the span. A boundary within a crossfade of either end of
      // it lands in the middle of a blend.
      final guard = fadeMs > 0 ? fadeMs : 1;
      final ilo = lo > s.startMs + guard ? lo : s.startMs + guard;
      // And a boundary in the last crossfade of a span leaves the next
      // pass holding a sliver of a scene with a blend to play out of
      // it. There is always somewhere better.
      final iend = s.endMs - guard;
      final ihi = hi < iend ? hi : iend;
      if (ilo <= ihi) take(_inside(s, ilo, ihi, largest), isEdge: false);
      // The span's own end, where the next scenery takes over.
      final e = s.endMs;
      if (e < segEndMs && e >= lo && e <= hi) take(e, isEdge: true);
    }
    return best ?? edge;
  }

  /// A boundary inside one span, or null when the span offers none.
  static int? _inside(PictureSpan s, int lo, int hi, bool largest) {
    if (s.isImage || s.covers) return largest ? hi : lo;
    final l = s.sourceMs;
    if (l == null || l <= 0) return null; // unmeasurable: never cut here
    // Only where a loop starts.
    if (largest) {
      final k = (hi - s.startMs) ~/ l;
      final t = s.startMs + k * l;
      return k >= 1 && t >= lo ? t : null;
    }
    final k = ((lo - s.startMs) + l - 1) ~/ l;
    final t = s.startMs + k * l;
    return k >= 1 && t <= hi ? t : null;
  }
}
