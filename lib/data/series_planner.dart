import 'models.dart';
import 'reel_duration.dart';
import 'ruku_index.dart';

/// One reel of a series: a contiguous run of one surah's verses, and
/// roughly how long it will run.
class SeriesCut {
  final int startAyah;
  final int endAyah;

  /// Estimated length at the chosen voice's pace, from the verses'
  /// own text — see [ReelDuration]. Exact only once the audio is on
  /// the device, which is the preview's business, not the planner's.
  final int estimateMs;

  const SeriesCut({
    required this.startAyah,
    required this.endAyah,
    required this.estimateMs,
  });

  int get ayahCount => endAyah - startAyah + 1;

  @override
  bool operator ==(Object other) =>
      other is SeriesCut &&
      other.startAyah == startAyah &&
      other.endAyah == endAyah &&
      other.estimateMs == estimateMs;

  @override
  int get hashCode => Object.hash(startAyah, endAyah, estimateMs);

  @override
  String toString() => 'SeriesCut($startAyah-$endAyah ~${estimateMs}ms)';
}

/// Divides a whole surah into a series of reels.
///
/// The obvious way — four verses each, then the next four — is wrong
/// more often than it is right, because verses are not the unit a
/// surah is written in. A passage is: the story of the cave, the
/// argument with the disbelievers, the description of the garden. The
/// mushaf marks those passages itself — the ruku' — and a reel that
/// starts at the head of one and ends at the foot of one reads as a
/// complete thought, where one that cuts through the middle reads as a
/// sentence stopped halfway.
///
/// So the split is chosen, not dealt. Every way of cutting the surah
/// into the asked-for number of reels is scored on two things — how
/// evenly the reels come out, and how many of their edges land on a
/// passage boundary — and the cheapest is taken. Dynamic programming
/// makes that exact rather than greedy: the choice of where reel three
/// ends is made knowing what it does to reels four through seven.
///
/// The first reel always starts at ayah 1 and the last always ends at
/// the surah's last verse: a series is the whole surah, in order, and
/// nothing is skipped.
///
/// Pure — no I/O — so all of it is testable off-device.
abstract final class SeriesPlanner {
  /// What one reel of a series is aimed at, and what the suggested
  /// count is worked out from. Under the cap on purpose: the cap is a
  /// wall, and a plan that aims at the wall lands half its reels on
  /// the wrong side of it. Aimed at forty-five seconds, the reels
  /// come out between about half a minute and the minute.
  static const idealReelMs = 45 * 1000;

  /// The longest a reel of a series may run: a minute, the length the
  /// feeds this is posted to are built around. A hard cap, not a
  /// penalty — the planner would rather deal more reels than the days
  /// asked for than let one run over. The one exception is a single
  /// verse longer than this on its own (Al-Baqarah 282 is five
  /// minutes read): it cannot be cut, so it stands alone.
  static const maxCutMs = 60 * 1000;

  /// Under this a reel reads as a fragment. Pushed against, not
  /// forbidden: some surahs have verses of two words.
  static const shortReelMs = 20 * 1000;

  /// What a fragment costs, at nothing left of the reel at all.
  static const _shortWeight = 1.5;

  /// The price of an edge that falls inside a passage rather than
  /// between two, in the same units as the length cost — a squared
  /// relative deviation, so 0.55 is about the cost of a reel running
  /// three-quarters long. Enough that the planner will trade a fair
  /// amount of evenness for a clean cut, not so much that it will
  /// make one reel of three minutes and the next of ten seconds to
  /// get one.
  static const midPassagePenalty = 0.55;

  /// How many reels a surah naturally makes at [idealReelMs], at least
  /// one and never more than it has verses.
  static int suggestedReels(List<Ayah> ayahs, {double pace = 1.0}) {
    if (ayahs.isEmpty) return 1;
    final total = ReelDuration.estimateMs(
      ayahs,
      startAyah: 1,
      endAyah: ayahs.length,
      pace: pace,
    );
    final n = (total / idealReelMs).ceil();
    return n.clamp(1, ayahs.length);
  }

  /// Splits [surah] — its verses in [ayahs], first to last — into
  /// [reels] contiguous runs. Fewer than [reels] come back only when
  /// the surah has fewer verses than that; *more* come back when
  /// [reels] of them could not each stay under [maxCutMs], because the
  /// minute holds and the count gives.
  static List<SeriesCut> split({
    required int surah,
    required List<Ayah> ayahs,
    required int reels,
    double pace = 1.0,
  }) {
    final n = ayahs.length;
    if (n == 0) return const [];

    // Per-verse estimates and their prefix sums, so any run's length
    // is one subtraction.
    final ms = List<int>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      ms[i + 1] = ms[i] +
          ReelDuration.estimateMs(
            ayahs,
            startAyah: i + 1,
            endAyah: i + 1,
            pace: pace,
          );
    }
    // Never fewer reels than the cap needs. Any count from that one
    // up to the verse count can be dealt under the cap — a run that
    // fits can always be cut again — so the search below never comes
    // back empty-handed.
    final k = reels.clamp(1, n) < fewestUnderCap(ms)
        ? fewestUnderCap(ms)
        : reels.clamp(1, n);
    final total = ms[n];
    final target = total / k;

    // Where a passage begins, as the *verse index* (0-based) the
    // previous reel must end before to land on a boundary. Ayah 1 is
    // always a start and carries no information.
    final starts = <int>{
      for (final a in rukuStarts[surah] ?? const [1])
        if (a > 1 && a <= n) a - 1,
    };

    int lengthOf(int i, int j) => ms[j] - ms[i]; // verses i..j-1

    double cost(int i, int j) {
      final len = lengthOf(i, j);
      // Over the minute is not for sale, unless the reel is one verse
      // and there is nothing to cut.
      if (len > maxCutMs && j - i > 1) return double.infinity;
      final dev = (len - target) / (target <= 0 ? 1 : target);
      var c = dev * dev;
      // A curve rather than a step, so two reels a little short always
      // beat one reel much shorter to spare its neighbours.
      if (len < shortReelMs) {
        final under = (shortReelMs - len) / shortReelMs;
        c += _shortWeight * under * under;
      }
      // The last reel ends where the surah ends: that is a boundary
      // by definition.
      if (j != n && !starts.contains(j)) c += midPassagePenalty;
      return c;
    }

    // best[r][j]: cheapest way to cover verses 0..j-1 with r reels.
    const inf = double.infinity;
    final best = List.generate(k + 1, (_) => List<double>.filled(n + 1, inf));
    final from = List.generate(k + 1, (_) => List<int>.filled(n + 1, -1));
    best[0][0] = 0;
    for (var r = 1; r <= k; r++) {
      // Reel r can end no earlier than after r verses and must leave
      // at least k - r verses for the reels after it.
      for (var j = r; j <= n - (k - r); j++) {
        var bestCost = inf;
        var bestI = -1;
        for (var i = r - 1; i < j; i++) {
          final prev = best[r - 1][i];
          if (prev == inf) continue;
          final c = prev + cost(i, j);
          if (c < bestCost) {
            bestCost = c;
            bestI = i;
          }
        }
        best[r][j] = bestCost;
        from[r][j] = bestI;
      }
    }

    // Walk back from the end.
    final edges = <int>[n];
    var j = n;
    for (var r = k; r > 0; r--) {
      final i = from[r][j];
      if (i < 0) break; // unreachable: only when the surah is over the cap
      edges.add(i);
      j = i;
    }
    if (edges.last != 0) {
      // Cannot happen — see [fewestUnderCap] — but a series that
      // exists beats a crash if it ever does.
      return _even(ayahs, k, pace, ms);
    }
    final cuts = <SeriesCut>[];
    for (var e = edges.length - 1; e > 0; e--) {
      final i = edges[e], jj = edges[e - 1];
      cuts.add(SeriesCut(
        startAyah: i + 1,
        endAyah: jj,
        estimateMs: lengthOf(i, jj),
      ));
    }
    return cuts;
  }

  /// The fewest reels [ms] — prefix sums of per-verse estimates, as
  /// [split] builds them — can be dealt into with every reel of more
  /// than one verse under [maxCutMs]. Greedy from the front, which is
  /// exact for a contiguous deal under a cap.
  static int fewestUnderCap(List<int> ms) {
    final n = ms.length - 1;
    if (n <= 0) return 1;
    var count = 1;
    var start = 0;
    for (var i = 1; i <= n; i++) {
      if (ms[i] - ms[start] > maxCutMs && i - start > 1) {
        count++;
        start = i - 1;
      }
    }
    return count;
  }

  static List<SeriesCut> _even(
      List<Ayah> ayahs, int k, double pace, List<int> ms) {
    final n = ayahs.length;
    final cuts = <SeriesCut>[];
    final per = n ~/ k, spare = n % k;
    var a = 0;
    for (var i = 0; i < k; i++) {
      final len = per + (i < spare ? 1 : 0);
      cuts.add(SeriesCut(
        startAyah: a + 1,
        endAyah: a + len,
        estimateMs: ms[a + len] - ms[a],
      ));
      a += len;
    }
    return cuts;
  }

  /// Deals [cuts] out over exactly [days] days, as evenly as they go
  /// and in order — the earlier days carry the odd one. Fewer days
  /// come back only when there are fewer reels than that. This is
  /// what a chosen number of days means: seven days is seven days,
  /// however many reels the minute made of the surah.
  static List<List<SeriesCut>> overDays(List<SeriesCut> cuts, int days) {
    final n = cuts.length;
    if (n == 0) return const [];
    final d = days.clamp(1, n);
    final per = n ~/ d, spare = n % d;
    final out = <List<SeriesCut>>[];
    var at = 0;
    for (var i = 0; i < d; i++) {
      final len = per + (i < spare ? 1 : 0);
      out.add(cuts.sublist(at, at + len));
      at += len;
    }
    return out;
  }

  /// Deals [cuts] out over days, [perDay] to a day in order. The last
  /// day may be short when the surah ran out of verses before the
  /// days did.
  static List<List<SeriesCut>> byDay(List<SeriesCut> cuts, int perDay) {
    final p = perDay < 1 ? 1 : perDay;
    final days = <List<SeriesCut>>[];
    for (var i = 0; i < cuts.length; i += p) {
      days.add(cuts.sublist(i, i + p > cuts.length ? cuts.length : i + p));
    }
    return days;
  }
}
