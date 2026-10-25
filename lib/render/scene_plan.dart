import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/verse_lines.dart';
import '../state/creation_state.dart';

/// One scenery's turn on screen: which scene, from when to when, and
/// the verses it covers.
///
/// Times are absolute in the recording's clock — the same clock the
/// verse overlays are timed on — so the preview and the exporter place
/// a cut at the same millisecond without converting anything.
@immutable
class SceneCut {
  /// Index into the reel's scene list.
  final int scene;
  final int startMs;
  final int endMs;

  /// The verses on screen while this scene runs. Equal when a scene
  /// carries a single verse.
  final int firstAyah;
  final int lastAyah;

  const SceneCut({
    required this.scene,
    required this.startMs,
    required this.endMs,
    required this.firstAyah,
    required this.lastAyah,
  });

  int get durationMs => endMs - startMs;

  @override
  bool operator ==(Object other) =>
      other is SceneCut &&
      other.scene == scene &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.firstAyah == firstAyah &&
      other.lastAyah == lastAyah;

  @override
  int get hashCode => Object.hash(scene, startMs, endMs, firstAyah, lastAyah);

  @override
  String toString() => 'SceneCut($scene, $startMs-$endMs, '
      'ayahs $firstAyah-$lastAyah)';
}

/// Divides a reel between the sceneries chosen for it.
///
/// The single source of truth for where a cut lands: the live preview
/// switches scenery on this, the exporter builds its filter graph from
/// it, and the ribbon in the preview draws it. A cut that were computed
/// twice would eventually be computed two ways, and a preview that
/// disagrees with the file is the whole feature going wrong.
///
/// Pure — no I/O, no plugins — so all of it is testable off-device.
abstract final class ScenePlan {
  /// The shortest a scene may be. Below about this a cut stops reading
  /// as a change of scene and starts reading as a flicker, and the
  /// recitation — which is what the reel is actually for — is left
  /// competing with the pictures.
  static const minDwellMs = 2500;

  /// No reel takes more sceneries than this, whatever its length.
  ///
  /// The number that matters is [minDwellMs] — a reel's own length
  /// divided by it, which is what [maxScenes] actually computes. This
  /// is only the backstop above that, and it used to sit at 30: fine
  /// for a reel of a few verses, and plainly wrong for an hour, where
  /// thirty sceneries is two minutes each and the run stops reading as
  /// a run at all. A hundred is where the cost starts being real — one
  /// more input for the exporter to open per scene, and one more file
  /// to have on the device — and an hour still divides into it at
  /// thirty-six seconds a scene.
  static const sceneCeiling = 100;

  /// What one verse is worth in seconds before the recitation has been
  /// measured. The scenery screen can run before the audio is on the
  /// device; this is only ever used to size the picker's headroom, and
  /// the real timings settle it in the preview.
  static const _typicalAyahMs = 6000;

  /// How many sceneries this reel can hold.
  ///
  /// Long enough reels take more than one scene per verse — a two-verse
  /// reel can still run twenty seconds, and two pictures is not a
  /// choice — so the ceiling is the reel's own length divided by
  /// [minDwellMs]. A scene per verse is always allowed on top of that,
  /// however brisk the verses, because a verse is a natural unit and
  /// the app's own default must never be out of reach.
  static int maxScenes(int ayahCount, {int? segMs}) {
    final ms = segMs ?? ayahCount * _typicalAyahMs;
    final byTime = ms ~/ minDwellMs;
    final most = byTime > ayahCount ? byTime : ayahCount;
    return most.clamp(1, sceneCeiling);
  }

  /// What the picker suggests: a scene per verse.
  static int recommended(int ayahCount) => ayahCount;

  /// The reel's scene timeline, in order and gapless: cut *i* ends
  /// exactly where cut *i+1* begins, the first starts at the segment's
  /// first millisecond and the last ends at its last.
  ///
  /// [sceneCount] is clamped into 1..[maxScenes] so a plan can always
  /// be drawn, whatever the picker was left holding. [weights] give
  /// scenes a bigger or smaller share of what they are competing for —
  /// verses when there are verses to spare, seconds when there are not;
  /// one weight per scene, all 1 for an even hand.
  ///
  /// [units] are what a scene per line counts: the verses, with every
  /// verse cut into lines standing as its parts (see [VerseUnit]). Read
  /// only by [ScenePacing.perLine]; without them that pacing is per
  /// verse.
  ///
  /// [anchors], one per scene, put a run the verses matched back on the
  /// verses it was matched for (see [SceneAnchor]); weights do not
  /// apply to it. Without them, or under [ScenePacing.even], the run is
  /// dealt out in order.
  static List<SceneCut> of({
    required int sceneCount,
    required Recitation recitation,
    required int startAyah,
    required int endAyah,
    ScenePacing pacing = ScenePacing.perAyah,
    List<int> weights = const [],
    List<VerseUnit>? units,
    List<SceneAnchor?> anchors = const [],
  }) {
    final slots = slotsFor(
      recitation: recitation,
      startAyah: startAyah,
      endAyah: endAyah,
      pacing: pacing,
      units: units,
    );
    final segMs = recitation.timing(endAyah).endMs -
        recitation.startOf(startAyah);
    if (pacing != ScenePacing.even &&
        _placeable(anchors, sceneCount, startAyah, endAyah)) {
      return _anchored([for (final a in anchors) a!], slots);
    }
    final n = sceneCount.clamp(1, maxScenes(slots.length, segMs: segMs));
    final w = _weightsFor(n, weights);
    return pacing == ScenePacing.even
        ? _even(n, w, recitation, startAyah, endAyah)
        : _perSlot(n, w, slots);
  }

  /// What a pacing deals scenes out over: a slot per verse, or — a scene
  /// per line — one per unit, so a verse cut into three lines is three
  /// slots.
  static List<({int startMs, int endMs, int ayah, int token})> slotsFor({
    required Recitation recitation,
    required int startAyah,
    required int endAyah,
    required ScenePacing pacing,
    List<VerseUnit>? units,
  }) {
    if (pacing == ScenePacing.perLine && units != null && units.isNotEmpty) {
      return [
        for (final u in units)
          (
            startMs: u.startMs,
            endMs: u.endMs,
            ayah: u.ayah,
            token: u.part?.tokenStart ?? 0,
          ),
      ];
    }
    return [
      for (var a = startAyah; a <= endAyah; a++)
        (
          // A reel that opens on the basmala has it on verse 1's scene.
          startMs: a == startAyah
              ? recitation.startOf(a)
              : recitation.timing(a).startMs,
          endMs: recitation.timing(a).endMs,
          ayah: a,
          token: 0,
        ),
    ];
  }

  /// The same plan, cut off at [endMs].
  ///
  /// The reel can be ended early — see the trim line under the preview
  /// ribbon — and everything that reads the timeline has to be cut with
  /// it: a scenery whose turn begins after the cut is not in the reel
  /// at all, and the one the cut falls inside ends there. Kept here,
  /// beside the plan itself, because the ribbon, the shortfall check
  /// and the exporter's filter graph must all see the same run.
  ///
  /// Never empty and never gapped: the first scenery is on screen
  /// whatever the cut is, so a cut at or before the reel's own start
  /// still leaves it a millisecond to be on screen for.
  static List<SceneCut> cutAt(List<SceneCut> cuts, int endMs) {
    if (cuts.isEmpty || cuts.last.endMs <= endMs) return cuts;
    final out = <SceneCut>[];
    for (final c in cuts) {
      if (c.startMs >= endMs && out.isNotEmpty) break;
      out.add(c.endMs <= endMs
          ? c
          : SceneCut(
              scene: c.scene,
              startMs: c.startMs,
              endMs: endMs > c.startMs ? endMs : c.startMs + 1,
              firstAyah: c.firstAyah,
              lastAyah: c.lastAyah,
            ));
    }
    return out;
  }

  /// Exactly [n] weights, every one of them at least 1: a shorter list
  /// (or none) is padded, a longer one cut. The plan is drawn from
  /// whatever the picker is holding, which can be a scene behind.
  static List<int> _weightsFor(int n, List<int> given) => [
        for (var i = 0; i < n; i++)
          i < given.length && given[i] > 0 ? given[i] : 1,
      ];

  /// Deals [total] whole units out over [weights], proportionally, with
  /// every share at least one.
  ///
  /// Largest remainder: hand out the floors, then the leftovers to
  /// whoever was rounded down hardest. Which is what stops seven verses
  /// over three scenes coming out 2, 2, 2 with one verse unaccounted
  /// for.
  static List<int> _deal(int total, List<int> weights) {
    final n = weights.length;
    if (n >= total) return List.filled(n, 1);
    final sum = weights.reduce((a, b) => a + b);
    final shares = List.filled(n, 0);
    final remainders = <({int at, double by})>[];
    var handed = 0;
    for (var i = 0; i < n; i++) {
      final exact = total * weights[i] / sum;
      // Never below one: a scene with no verse at all is a scene that
      // never appears, and the picker showed the user otherwise.
      final floor = exact.floor() < 1 ? 1 : exact.floor();
      shares[i] = floor;
      handed += floor;
      remainders.add((at: i, by: exact - exact.floor()));
    }
    // Over-handed by the min-one floor: take back from the biggest,
    // never below one.
    while (handed > total) {
      var biggest = 0;
      for (var i = 1; i < n; i++) {
        if (shares[i] > shares[biggest]) biggest = i;
      }
      if (shares[biggest] <= 1) break;
      shares[biggest]--;
      handed--;
    }
    remainders.sort((a, b) => b.by.compareTo(a.by));
    for (var i = 0; handed < total; i++, handed++) {
      shares[remainders[i % n].at]++;
    }
    return shares;
  }

  /// Cuts on slot boundaries: a verse's, or with a scene per line, a
  /// line's.
  ///
  /// Up to one scene per slot, the slots are dealt out over the scenes
  /// by weight, so a 7-verse reel over 3 even scenes runs 3, 2, 2
  /// rather than leaving one scene holding three times what its
  /// neighbours do.
  ///
  /// Past one scene per slot there are no slots left to deal, so the
  /// scenes queue up inside a slot instead and share its window between
  /// them — by weight again. Every slot boundary is still a cut; there
  /// are simply cuts between them too.
  static List<SceneCut> _perSlot(
    int n,
    List<int> weights,
    List<({int startMs, int endMs, int ayah, int token})> slots,
  ) {
    final count = slots.length;
    if (n <= count) {
      final runs = _deal(count, weights);
      final cuts = <SceneCut>[];
      var at = 0;
      for (var i = 0; i < n; i++) {
        final last = at + runs[i] - 1;
        cuts.add(SceneCut(
          scene: i,
          startMs: slots[at].startMs,
          endMs: slots[last].endMs,
          firstAyah: slots[at].ayah,
          lastAyah: slots[last].ayah,
        ));
        at = last + 1;
      }
      return cuts;
    }
    // More scenes than slots: every slot takes at least one, and the
    // spare scenes go to the slots at the front — the opening of a
    // passage is where a second picture is worth most.
    final per = n ~/ count;
    final spare = n % count;
    final cuts = <SceneCut>[];
    var scene = 0;
    for (var k = 0; k < count; k++) {
      final take = per + (k < spare ? 1 : 0);
      final slot = slots[k];
      final mine = weights.sublist(scene, scene + take);
      final slices = _slice(slot.startMs, slot.endMs, mine);
      for (var j = 0; j < take; j++) {
        cuts.add(SceneCut(
          scene: scene + j,
          startMs: slices[j],
          endMs: slices[j + 1],
          firstAyah: slot.ayah,
          lastAyah: slot.ayah,
        ));
      }
      scene += take;
    }
    return cuts;
  }

  /// Whether [anchors] can place a run of [count] sceneries: one each,
  /// inside the reel's verses, in reel order. A run picked by hand has
  /// none, and a run matched for other verses is dealt out as one.
  static bool _placeable(
      List<SceneAnchor?> anchors, int count, int startAyah, int endAyah) {
    if (count < 2 || anchors.length != count) return false;
    SceneAnchor? before;
    for (final a in anchors) {
      if (a == null || a.ayah < startAyah || a.ayah > endAyah) return false;
      if (before != null && a.compareTo(before) <= 0) return false;
      before = a;
    }
    return true;
  }

  /// Every scenery from the slot its anchor falls in — the verse, or
  /// the line holding the word its line started on when it was matched
  /// — to the next scenery's.
  ///
  /// A slot no scenery is anchored in stays with the one before it: the
  /// verse of a scenery that could not be fetched, a line the estimate
  /// did not have. The slots ahead of the first anchor (the basmala's
  /// card) open on the first. Sceneries anchored in one slot — lines
  /// matched one by one, a verse now shown whole — share it evenly.
  /// Every scenery is on screen, each on its own verse.
  static List<SceneCut> _anchored(
    List<SceneAnchor> anchors,
    List<({int startMs, int endMs, int ayah, int token})> slots,
  ) {
    bool atOrBefore(({int startMs, int endMs, int ayah, int token}) s,
            SceneAnchor a) =>
        s.ayah < a.ayah || (s.ayah == a.ayah && s.token <= a.token);
    final own = [for (final _ in slots) <int>[]];
    var k = 0;
    for (var i = 0; i < anchors.length; i++) {
      while (k + 1 < slots.length && atOrBefore(slots[k + 1], anchors[i])) {
        k++;
      }
      own[k].add(i);
    }
    final cuts = <SceneCut>[];
    var scene = 0;
    var from = slots.first.startMs;
    var firstAyah = slots.first.ayah;
    var lastAyah = firstAyah;
    void close(int at) {
      cuts.add(SceneCut(
        scene: scene,
        startMs: from,
        endMs: at,
        firstAyah: firstAyah,
        lastAyah: lastAyah,
      ));
    }

    for (var j = 0; j < slots.length; j++) {
      final slot = slots[j];
      final mine = own[j];
      if (mine.isNotEmpty) {
        final edges =
            _slice(slot.startMs, slot.endMs, [for (final _ in mine) 1]);
        for (var m = 0; m < mine.length; m++) {
          // The first scenery has held the reel since its start.
          if (mine[m] == 0) continue;
          close(edges[m]);
          scene = mine[m];
          from = edges[m];
          firstAyah = slot.ayah;
          lastAyah = slot.ayah;
        }
      }
      lastAyah = slot.ayah;
    }
    close(slots.last.endMs);
    return cuts;
  }

  /// Boundaries dividing [from]..[to] by [weights] — one more value
  /// than there are weights, first [from] and last [to].
  ///
  /// Walks the boundaries rather than adding a rounded length
  /// repeatedly, so the slices tile the span exactly whatever the
  /// weights do to the arithmetic.
  static List<int> _slice(int from, int to, List<int> weights) {
    final sum = weights.reduce((a, b) => a + b);
    final span = to - from;
    final edges = <int>[from];
    var run = 0;
    for (var i = 0; i < weights.length - 1; i++) {
      run += weights[i];
      edges.add(from + (span * run / sum).round());
    }
    edges.add(to);
    return edges;
  }

  /// Slices of the reel by weight — equal ones unless a scene was
  /// given more room — wherever they land.
  static List<SceneCut> _even(
    int n,
    List<int> weights,
    Recitation rec,
    int startAyah,
    int endAyah,
  ) {
    final segStart = rec.startOf(startAyah);
    final segEnd = rec.timing(endAyah).endMs;
    final edges = _slice(segStart, segEnd, weights);
    final cuts = <SceneCut>[];
    for (var i = 0; i < n; i++) {
      final from = edges[i];
      final to = edges[i + 1];
      cuts.add(SceneCut(
        scene: i,
        startMs: from,
        endMs: to,
        firstAyah: _ayahAt(rec, from, startAyah, endAyah),
        // The last millisecond of the slice belongs to the slice; the
        // verse showing then is the one it ends on.
        lastAyah: _ayahAt(rec, to - 1, startAyah, endAyah),
      ));
    }
    return cuts;
  }

  /// Which verse is on screen at [ms], clamped to the chosen range.
  static int _ayahAt(Recitation rec, int ms, int startAyah, int endAyah) {
    for (var a = startAyah; a <= endAyah; a++) {
      if (ms < rec.timing(a).endMs) return a;
    }
    return endAyah;
  }

  /// How long a crossfade may actually run for this plan, in
  /// milliseconds — 0 meaning a straight cut.
  ///
  /// A blend costs both scenes half of itself, so it can never take
  /// more than half of the shortest scene in the reel; a blend shorter
  /// than a few frames reads as a stutter rather than a fade, so below
  /// that it becomes the cut it already looks like. The preview and the
  /// exporter both ask this, so a reel never fades on screen and cuts
  /// in the file.
  static int fadeMsFor(List<SceneCut> cuts, SceneTransition transition) {
    if (transition != SceneTransition.fade || cuts.length < 2) return 0;
    var shortest = cuts.first.durationMs;
    for (final c in cuts) {
      if (c.durationMs < shortest) shortest = c.durationMs;
    }
    final ms = sceneFadeMs < shortest ~/ 2 ? sceneFadeMs : shortest ~/ 2;
    return ms < 120 ? 0 : ms;
  }

  /// The cut playing at [ms], or the last one when the position has
  /// run past the end. Never null: a plan always covers its segment.
  static int indexAt(List<SceneCut> cuts, int ms) {
    for (var i = 0; i < cuts.length; i++) {
      if (ms < cuts[i].endMs) return i;
    }
    return cuts.length - 1;
  }
}
