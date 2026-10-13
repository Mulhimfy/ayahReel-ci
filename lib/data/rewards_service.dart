import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'reel_library.dart';
import 'whole_file.dart';

/// Lightweight local rewards: points for creating and sharing reels,
/// a daily streak, and badges for the milestones along the way. No
/// accounts, no server — the reward is the habit itself.
class RewardsState {
  final int points;
  final int streakDays;
  final DateTime? lastCreated;

  /// Reels finished, ever. What the reel badges are counted from.
  final int reelsMade;

  /// Whether the home-screen widget has been placed at least once.
  /// Once true, stays true: a badge is not taken back.
  final bool widgetPlaced;

  const RewardsState({
    required this.points,
    required this.streakDays,
    required this.lastCreated,
    this.reelsMade = 0,
    this.widgetPlaced = false,
  });

  RewardsState copyWith({
    int? points,
    int? streakDays,
    DateTime? lastCreated,
    int? reelsMade,
    bool? widgetPlaced,
  }) =>
      RewardsState(
        points: points ?? this.points,
        streakDays: streakDays ?? this.streakDays,
        lastCreated: lastCreated ?? this.lastCreated,
        reelsMade: reelsMade ?? this.reelsMade,
        widgetPlaced: widgetPlaced ?? this.widgetPlaced,
      );

  /// The badges this state has earned, in the order they are shown.
  List<RewardBadge> get badges => [
        for (final b in RewardBadge.all)
          if (b.earnedBy(this)) b,
      ];
}

/// One badge: earned once, kept forever, and never a number the user
/// has to guard — a streak can break, a badge cannot.
class RewardBadge {
  /// Stable id, also the key the strings are looked up by.
  final String id;

  /// For a reel badge, how many reels it takes; null for the rest.
  final int? reels;

  const RewardBadge._(this.id, {this.reels});

  /// Earned by placing the verse widget on the home screen.
  static const widget = RewardBadge._('widget');

  /// The reel milestones: the first one, then the round numbers.
  static const reelMilestones = [1, 5, 10, 25, 50, 100];

  static final List<RewardBadge> all = [
    for (final n in reelMilestones) RewardBadge._('reels$n', reels: n),
    widget,
  ];

  bool earnedBy(RewardsState s) {
    final n = reels;
    if (n != null) return s.reelsMade >= n;
    return s.widgetPlaced;
  }

  /// For an unearned reel badge, how many more reels it wants.
  int reelsToGo(RewardsState s) {
    final n = reels;
    if (n == null) return 0;
    return (n - s.reelsMade).clamp(0, n);
  }

  @override
  bool operator ==(Object other) => other is RewardBadge && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RewardBadge($id)';
}

abstract final class RewardsService {
  static const pointsPerReel = 10;
  static const pointsPerShare = 5;

  /// Placing the widget is worth more than a share and less than two
  /// reels: a one-off, and the one thing here that keeps paying back.
  static const pointsForWidget = 15;

  /// UI listens to this for the home pill; updated on every award.
  static final ValueNotifier<RewardsState> state = ValueNotifier(
      const RewardsState(points: 0, streakDays: 0, lastCreated: null));

  static bool _loaded = false;

  /// Last time the user earned points for sharing the app itself —
  /// that reward is capped at once per calendar day.
  static DateTime? _lastAppShare;

  /// For tests: a file to use instead of the app's own, and the reel
  /// count to backfill from instead of reading the library.
  @visibleForTesting
  static File? fileOverride;
  @visibleForTesting
  static Future<int> Function()? reelCountOverride;

  static Future<void>? _loading;

  /// Reads the file once, for every caller. Each one waits for that
  /// read: a caller let through on the defaults while it was still
  /// running (the widget's first frame, at launch) would write 0
  /// points over the user's own.
  static Future<void> init() => _loading ??= _load();

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      state.value = RewardsState(
        points: j['points'] as int? ?? 0,
        streakDays: j['streak'] as int? ?? 0,
        lastCreated: j['last'] == null
            ? null
            : DateTime.tryParse(j['last'] as String),
        // Reels were not counted before the badges: a file without
        // the count is from then, and the library says how many.
        reelsMade: j['reels'] as int? ?? await _reelsInLibrary(),
        widgetPlaced: j['widget'] as bool? ?? false,
      );
      _lastAppShare = j['lastAppShare'] == null
          ? null
          : DateTime.tryParse(j['lastAppShare'] as String);
      // A missed day resets the streak display on launch.
      final last = state.value.lastCreated;
      if (last != null && _daysBetween(last, DateTime.now()) > 1) {
        state.value = state.value.copyWith(streakDays: 0);
        await _persist();
      }
    } catch (_) {/* start fresh */}
  }

  static Future<int> _reelsInLibrary() async {
    try {
      final count = reelCountOverride;
      if (count != null) return await count();
      return (await ReelLibrary.load()).length;
    } catch (_) {
      return 0;
    }
  }

  /// Call when a reel is exported (saved or shared). Advances the
  /// streak at most once per calendar day, counts the reel, and
  /// returns the badge that reel earned, if it earned one.
  static Future<RewardBadge?> recordReelCreated() async {
    await init();
    final now = DateTime.now();
    final s = state.value;
    final gap =
        s.lastCreated == null ? null : _daysBetween(s.lastCreated!, now);
    final streak = switch (gap) {
      null => 1, // first ever reel
      0 => s.streakDays == 0 ? 1 : s.streakDays, // same day: no change
      1 => s.streakDays + 1, // consecutive day
      _ => 1, // streak broken, start over
    };
    final next = s.copyWith(
      points: s.points + pointsPerReel,
      streakDays: streak,
      lastCreated: now,
      reelsMade: s.reelsMade + 1,
    );
    final earned = _newRewardBadge(s, next);
    state.value = next;
    await _persist();
    return earned;
  }

  /// Call when a card is made — saved to the gallery, shared, or sent
  /// to a story.
  ///
  /// Advances the streak exactly as a reel does, and for the reason
  /// the streak exists: the lever on a habit is how *often*, not how
  /// much, and a day somebody only had a minute is still a day they
  /// made something. Worth a share's points rather than a reel's — a
  /// card is a minute's work and a reel is an encode.
  ///
  /// Deliberately not counted in [RewardsState.reelsMade]: the reel
  /// badges count reels, and a badge that can be earned two ways is a
  /// badge that means neither.
  static Future<void> recordCardMade() async {
    await init();
    final now = DateTime.now();
    final s = state.value;
    final gap =
        s.lastCreated == null ? null : _daysBetween(s.lastCreated!, now);
    final streak = switch (gap) {
      null => 1,
      0 => s.streakDays == 0 ? 1 : s.streakDays,
      1 => s.streakDays + 1,
      _ => 1,
    };
    state.value = s.copyWith(
      points: s.points + pointsPerShare,
      streakDays: streak,
      lastCreated: now,
    );
    await _persist();
  }

  /// Call whenever the app learns the widget is on the home screen.
  /// Awards the badge and its points the first time only; returns
  /// whether this call was that time.
  static Future<bool> recordWidgetPlaced() async {
    await init();
    final s = state.value;
    if (s.widgetPlaced) return false;
    state.value = s.copyWith(
      points: s.points + pointsForWidget,
      widgetPlaced: true,
    );
    await _persist();
    return true;
  }

  static RewardBadge? _newRewardBadge(RewardsState before, RewardsState after) {
    for (final b in RewardBadge.all) {
      if (b.earnedBy(after) && !b.earnedBy(before)) return b;
    }
    return null;
  }

  /// Points for sharing the APP itself (Settings). Once per calendar
  /// day, so tapping share repeatedly can't farm points. Returns
  /// whether points were actually awarded.
  static Future<bool> recordAppShared() async {
    await init();
    final now = DateTime.now();
    if (_lastAppShare != null && _daysBetween(_lastAppShare!, now) == 0) {
      return false; // already earned today
    }
    _lastAppShare = now;
    final s = state.value;
    state.value = s.copyWith(points: s.points + pointsPerShare);
    await _persist();
    return true;
  }

  static Future<void> recordShared() async {
    await init();
    final s = state.value;
    state.value = s.copyWith(points: s.points + pointsPerShare);
    await _persist();
  }

  /// Calendar days from [a] to [b], read as dates in UTC: two local
  /// midnights are 23 hours apart across the spring clock change, which
  /// inDays reads as the same day.
  static int _daysBetween(DateTime a, DateTime b) {
    final da = DateTime.utc(a.year, a.month, a.day);
    final db = DateTime.utc(b.year, b.month, b.day);
    return db.difference(da).inDays;
  }

  static Future<void> _persist() async {
    try {
      final s = state.value;
      await writeWhole(await _file(), jsonEncode({
        'points': s.points,
        'streak': s.streakDays,
        'last': s.lastCreated?.toIso8601String(),
        'lastAppShare': _lastAppShare?.toIso8601String(),
        'reels': s.reelsMade,
        'widget': s.widgetPlaced,
      }));
    } catch (_) {/* rewards are best-effort */}
  }

  static Future<File> _file() async =>
      fileOverride ??
      File('${(await getApplicationSupportDirectory()).path}/rewards.json');

  @visibleForTesting
  static void resetForTest() {
    _loaded = false;
    _loading = null;
    _lastAppShare = null;
    state.value =
        const RewardsState(points: 0, streakDays: 0, lastCreated: null);
  }
}
