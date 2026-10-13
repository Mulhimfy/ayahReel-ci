import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'series_planner.dart';
import 'whole_file.dart';

/// One reel of a planned series, and whether it has been made yet.
class SeriesReel {
  /// Position in the series, 0-based, in reading order.
  final int index;

  /// The day it belongs to, 1-based.
  final int day;
  final int startAyah;
  final int endAyah;
  final int estimateMs;

  /// When the reel was exported — saved or shared — through the
  /// preview. Null until then.
  final DateTime? doneAt;

  /// The library entry the export produced, so the series can open
  /// the finished reel rather than only the recipe for it.
  final String? savedReelId;

  const SeriesReel({
    required this.index,
    required this.day,
    required this.startAyah,
    required this.endAyah,
    required this.estimateMs,
    this.doneAt,
    this.savedReelId,
  });

  bool get done => doneAt != null;
  int get ayahCount => endAyah - startAyah + 1;

  SeriesReel copyWith({
    int? startAyah,
    int? endAyah,
    int? estimateMs,
    DateTime? doneAt,
    String? savedReelId,
  }) =>
      SeriesReel(
        index: index,
        day: day,
        startAyah: startAyah ?? this.startAyah,
        endAyah: endAyah ?? this.endAyah,
        estimateMs: estimateMs ?? this.estimateMs,
        doneAt: doneAt ?? this.doneAt,
        savedReelId: savedReelId ?? this.savedReelId,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'day': day,
        'startAyah': startAyah,
        'endAyah': endAyah,
        'estimateMs': estimateMs,
        'doneAt': doneAt?.toIso8601String(),
        'savedReelId': savedReelId,
      };

  factory SeriesReel.fromJson(Map<String, dynamic> j) => SeriesReel(
        index: j['index'] as int,
        day: j['day'] as int,
        startAyah: j['startAyah'] as int,
        endAyah: j['endAyah'] as int,
        estimateMs: j['estimateMs'] as int? ?? 0,
        doneAt: j['doneAt'] == null
            ? null
            : DateTime.tryParse(j['doneAt'] as String),
        savedReelId: j['savedReelId'] as String?,
      );
}

/// A surah planned out over several days: the reels, the days they
/// fall on, and which of both are finished.
class ReelSeries {
  final String id;
  final int surah;
  final String reciterId;

  /// How many reels were asked for per day. The plan itself is in
  /// [reels]; this is kept for the summary line.
  final int perDay;

  /// The day the series was made — day 1. Today's day number is
  /// counted from it; see [todayIndex].
  final DateTime startedAt;
  final List<SeriesReel> reels;

  /// Days the user has marked finished by hand (a long press), on top
  /// of the ones whose reels are all done.
  final Set<int> manualDays;

  const ReelSeries({
    required this.id,
    required this.surah,
    required this.reciterId,
    required this.perDay,
    required this.startedAt,
    required this.reels,
    this.manualDays = const {},
  });

  /// How many days the plan spans.
  int get days => reels.isEmpty ? 0 : reels.last.day;

  List<SeriesReel> reelsOn(int day) =>
      reels.where((r) => r.day == day).toList();

  /// A day is done when as many of its reels as the user asked for a
  /// day have been exported, or when the user said so.
  ///
  /// A plan over fixed days can give a day more reels than that: each
  /// reel stays under a minute, so a long surah over a week comes to
  /// four or five a day. Those are a day's choice, not its homework —
  /// one asked for, one made, and the day is done (2026-10-11). The
  /// rest stay there for anyone who wants them.
  bool isDayDone(int day) {
    if (manualDays.contains(day)) return true;
    final on = reelsOn(day);
    if (on.isEmpty) return false;
    final want = perDay.clamp(1, on.length);
    return on.where((r) => r.done).length >= want;
  }

  int get daysDone => [for (var d = 1; d <= days; d++) d]
      .where(isDayDone)
      .length;

  bool get finished => days > 0 && daysDone == days;

  /// The calendar day the series is on: 1 on the day it was made, 2
  /// the next, clamped to the plan. The strip lights the day the user
  /// is *on* a little, so the next thing to do is never in doubt.
  int todayIndex(DateTime now) {
    // Calendar dates, compared in UTC: two local midnights are 23 hours
    // apart across the spring clock change, which inDays reads as 0.
    final a = DateTime.utc(startedAt.year, startedAt.month, startedAt.day);
    final b = DateTime.utc(now.year, now.month, now.day);
    final d = b.difference(a).inDays + 1;
    return d.clamp(1, days < 1 ? 1 : days);
  }

  /// The first day that still has work on it, or null when the
  /// series is finished.
  int? get nextDay {
    for (var d = 1; d <= days; d++) {
      if (!isDayDone(d)) return d;
    }
    return null;
  }

  ReelSeries copyWith({List<SeriesReel>? reels, Set<int>? manualDays}) =>
      ReelSeries(
        id: id,
        surah: surah,
        reciterId: reciterId,
        perDay: perDay,
        startedAt: startedAt,
        reels: reels ?? this.reels,
        manualDays: manualDays ?? this.manualDays,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'surah': surah,
        'reciterId': reciterId,
        'perDay': perDay,
        'startedAt': startedAt.toIso8601String(),
        'reels': [for (final r in reels) r.toJson()],
        'manualDays': manualDays.toList(),
      };

  factory ReelSeries.fromJson(Map<String, dynamic> j) => ReelSeries(
        id: j['id'] as String,
        surah: j['surah'] as int,
        reciterId: j['reciterId'] as String,
        perDay: j['perDay'] as int? ?? 1,
        startedAt: DateTime.parse(j['startedAt'] as String),
        reels: [
          for (final r in (j['reels'] as List))
            SeriesReel.fromJson(r as Map<String, dynamic>),
        ],
        manualDays: ((j['manualDays'] as List?) ?? const []).cast<int>().toSet(),
      );

  /// A fresh series from a plan: over exactly [days] days when given,
  /// as evenly as the reels go, and otherwise [perDay] to a day.
  factory ReelSeries.plan({
    required int surah,
    required String reciterId,
    required int perDay,
    required List<SeriesCut> cuts,
    int? days,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final byDay = days == null
        ? SeriesPlanner.byDay(cuts, perDay)
        : SeriesPlanner.overDays(cuts, days);
    final reels = <SeriesReel>[];
    for (var d = 0; d < byDay.length; d++) {
      for (final c in byDay[d]) {
        reels.add(SeriesReel(
          index: reels.length,
          day: d + 1,
          startAyah: c.startAyah,
          endAyah: c.endAyah,
          estimateMs: c.estimateMs,
        ));
      }
    }
    return ReelSeries(
      id: at.millisecondsSinceEpoch.toString(),
      surah: surah,
      reciterId: reciterId,
      perDay: perDay,
      startedAt: at,
      reels: reels,
    );
  }
}

/// Where a series lives between launches: one JSON file, newest
/// first, in the app's support directory — the same arrangement the
/// reel library uses, for the same reason.
abstract final class SeriesLibrary {
  /// Bumped on every change so Home and the series screen refresh.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static List<ReelSeries>? _cache;

  /// For tests: a file to use instead of the app's own.
  @visibleForTesting
  static File? fileOverride;

  static Future<File> _file() async =>
      fileOverride ??
      File('${(await getApplicationSupportDirectory()).path}/series.json');

  static Future<List<ReelSeries>>? _loading;

  /// Newest first. One read for every caller that comes before it
  /// lands; and a change written while it was reading wins over what
  /// it read.
  static Future<List<ReelSeries>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final read = _loading ??= _read();
    try {
      final all = await read;
      return _cache ??= all;
    } finally {
      if (identical(_loading, read)) _loading = null;
    }
  }

  static Future<List<ReelSeries>> _read() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return [];
      final raw = jsonDecode(await f.readAsString()) as List;
      return [
        for (final e in raw) ReelSeries.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return []; // corrupt: start fresh rather than crash
    }
  }

  /// The series the home screen carries: the newest one still in
  /// progress, or null when there is none.
  static Future<ReelSeries?> active() async {
    for (final s in await load()) {
      if (!s.finished) return s;
    }
    return null;
  }

  static Future<ReelSeries?> byId(String id) async {
    for (final s in await load()) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Makes [s] the series — the only one. Planning a new series over
  /// an old one used to stack them, so deleting the new one brought
  /// the old one back from under it, weeks stale. A new plan is a
  /// decision to stop the old one; nothing of it is kept.
  static Future<void> add(ReelSeries s) async {
    await load(); // so a corrupt file is read once, not written over blind
    await _write([s]);
  }

  static Future<void> remove(String id) async {
    final all = await load();
    await _write(all.where((s) => s.id != id).toList());
  }

  /// Records that reel [index] of [seriesId] has been exported.
  static Future<ReelSeries?> markReelDone(
    String seriesId,
    int index, {
    String? savedReelId,
    DateTime? now,
  }) async {
    final all = await load();
    ReelSeries? updated;
    final next = [
      for (final s in all)
        if (s.id == seriesId)
          updated = s.copyWith(reels: [
            for (final r in s.reels)
              if (r.index == index)
                r.copyWith(
                  doneAt: now ?? DateTime.now(),
                  savedReelId: savedReelId,
                )
              else
                r,
          ])
        else
          s,
    ];
    if (updated == null) return null;
    await _write(next);
    return updated;
  }

  /// Moves reel [index] of [seriesId] to [startAyah]..[endAyah]: the
  /// user opened it and picked a different run, and the plan follows
  /// them rather than keeping the one it dealt. A no-op when nothing
  /// moved, so coming straight back through the wizard writes nothing.
  static Future<ReelSeries?> setReelRange(
    String seriesId,
    int index, {
    required int startAyah,
    required int endAyah,
    required int estimateMs,
  }) async {
    final all = await load();
    ReelSeries? updated;
    final next = <ReelSeries>[];
    for (final s in all) {
      if (s.id != seriesId) {
        next.add(s);
        continue;
      }
      final same = s.reels.any((r) =>
          r.index == index &&
          r.startAyah == startAyah &&
          r.endAyah == endAyah);
      if (same) return s;
      updated = s.copyWith(reels: [
        for (final r in s.reels)
          if (r.index == index)
            r.copyWith(
              startAyah: startAyah,
              endAyah: endAyah,
              estimateMs: estimateMs,
            )
          else
            r,
      ]);
      next.add(updated);
    }
    if (updated == null) return null;
    await _write(next);
    return updated;
  }

  /// A long press on a day: marks it done, or takes the mark back off
  /// a day the user marked themselves. A day whose reels are all
  /// exported stays done — there is nothing to take back.
  static Future<ReelSeries?> toggleDay(String seriesId, int day) async {
    final all = await load();
    ReelSeries? updated;
    final next = [
      for (final s in all)
        if (s.id == seriesId)
          updated = s.copyWith(
            manualDays: s.manualDays.contains(day)
                ? (s.manualDays.toSet()..remove(day))
                : (s.manualDays.toSet()..add(day)),
          )
        else
          s,
    ];
    if (updated == null) return null;
    await _write(next);
    return updated;
  }

  static Future<void> _write(List<ReelSeries> all) async {
    _cache = all;
    try {
      final f = await _file();
      await writeWhole(f, jsonEncode([for (final s in all) s.toJson()]));
    } catch (_) {/* best-effort, like every other store here */}
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    _cache = null;
    _loading = null;
  }
}
