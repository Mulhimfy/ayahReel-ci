import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'debug_log.dart';
import 'models.dart';
import 'qul_words.dart';
import 'quran_text_service.dart';
import 'recitation_service.dart';
import 'scene_catalog.dart';
import 'word_align_service.dart';

/// How much of a voice to keep on the phone.
enum OfflineVoice {
  /// None of it.
  none,

  /// The short surahs every reel-maker reaches for: Juz' 30, An-Naba'
  /// (78) to An-Nas (114).
  short,

  /// All 114 surahs.
  whole;

  List<int> get surahs => switch (this) {
        none => const [],
        short => [for (var s = 78; s <= 114; s++) s],
        whole => [for (var s = 1; s <= 114; s++) s],
      };
}

/// What to bring onto the phone so reels can be made with no network.
@immutable
class OfflinePlan {
  final Reciter voice;
  final OfflineVoice scope;

  /// The still sceneries: small, and most of what reels are made on.
  final bool stills;

  /// The moving ones: a few megabytes each.
  final bool clips;

  const OfflinePlan({
    required this.voice,
    this.scope = OfflineVoice.whole,
    this.stills = true,
    this.clips = false,
  });

  OfflinePlan copyWith({
    Reciter? voice,
    OfflineVoice? scope,
    bool? stills,
    bool? clips,
  }) =>
      OfflinePlan(
        voice: voice ?? this.voice,
        scope: scope ?? this.scope,
        stills: stills ?? this.stills,
        clips: clips ?? this.clips,
      );
}

/// Where a download for offline use has got to.
@immutable
class OfflineProgress {
  final OfflineStage stage;

  /// Across the whole run, 0..1.
  final double fraction;

  /// Files that could not be fetched, when it finished.
  final int missed;

  const OfflineProgress(this.stage, {this.fraction = 0, this.missed = 0});

  static const idle = OfflineProgress(OfflineStage.idle);

  bool get running => switch (stage) {
        OfflineStage.text ||
        OfflineStage.words ||
        OfflineStage.voice ||
        OfflineStage.scenes =>
          true,
        _ => false,
      };
}

enum OfflineStage {
  idle,
  text,
  words,
  voice,
  scenes,
  done,

  /// Stopped by the user; what came down stays.
  stopped,

  /// No connection: too many files in a row would not come.
  offline,

  /// The phone is full.
  full,
}

/// Brings what a reel needs from the network onto the phone, so reels
/// can be made with none: every surah's text in the translation chosen,
/// one voice (its short surahs or the whole Quran) with its word
/// timing, and the sceneries.
///
/// Built to be invisible while it runs. It is network and disk only —
/// nothing is decoded or encoded, so nothing here competes with the
/// app for the processor beyond measuring each verse's length once —
/// a few files at a time, with its progress told a few times a second
/// at most, on a notifier only the screens that show it listen to. It
/// goes on while the user does anything else in the app; stopped, or
/// cut off by the phone, it carries on from where it was the next time,
/// because every file already on the phone is skipped.
abstract final class OfflinePack {
  static final state = ValueNotifier<OfflineProgress>(OfflineProgress.idle);

  static bool _stop = false;

  /// Asks a run in progress to stop after the files in flight.
  static void stop() => _stop = true;

  /// How long the whole Quran runs, read at the pace the app's duration
  /// model is calibrated on (see `ReelDuration`), in seconds; and Juz'
  /// 30. Measured from the text the app ships (assets/quran_search.json).
  static const wholeSeconds = 82321;
  static const shortSeconds = 2907;

  /// About how many bytes [plan] brings down, for the sheet to say
  /// before anything is fetched: the voice at its bitrate and pace, the
  /// sceneries by their catalogued sizes. Only an estimate — what is on
  /// the phone already is subtracted by [missingBytes].
  static int voiceBytes(Reciter r, OfflineVoice scope) {
    final seconds = switch (scope) {
      OfflineVoice.none => 0,
      OfflineVoice.short => shortSeconds,
      OfflineVoice.whole => wholeSeconds,
    };
    return (seconds * r.pace * kbpsOf(r) * 1000 / 8).round();
  }

  /// The bitrate a voice is served at, from its folder's name where it
  /// says (`Alafasy_128kbps`), else the 128 most hosts serve.
  static int kbpsOf(Reciter r) {
    final source = r.source;
    if (source is AyahFiles) {
      final m = RegExp(r'(\d+)kbps', caseSensitive: false)
          .firstMatch(source.folder);
      if (m != null) return int.parse(m.group(1)!);
    }
    return 128;
  }

  /// The sceneries [plan] asks for that are not on the phone yet.
  static List<Scene> scenesFor(OfflinePlan plan) => [
        for (final s in SceneCatalog.all)
          if (!s.bundled &&
              (s.isVideo ? plan.clips : plan.stills) &&
              !SceneCatalog.isReadySync(s))
            s,
      ];

  static int sceneBytes({required bool clips}) => [
        for (final s in SceneCatalog.all)
          if (!s.bundled && s.isVideo == clips) s.bytes,
      ].fold(0, (a, b) => a + b);

  /// The text of every surah, both halves: a few megabytes.
  static const textBytes = 4 * 1000 * 1000;

  static Future<void>? _running;

  /// Runs [plan]. A second call while one runs joins it.
  static Future<void> run(OfflinePlan plan) =>
      _running ??= _run(plan).whenComplete(() => _running = null);

  /// Files that failed in a row before the run is called offline.
  static const _offlineAfter = 6;

  static Future<void> _run(OfflinePlan plan) async {
    _stop = false;
    var missed = 0;
    var inARow = 0;
    final surahs = plan.scope.surahs
        .where((s) => plan.voice.hasSurah(s))
        .toList(growable: false);
    final scenes = scenesFor(plan);
    final qul = QulWords.sourceOf(plan.voice);
    final align = WordAlignService.alignedByQuranAlign(plan.voice);
    // The run's steps, each worth one; a surah of audio is worth more,
    // as it is most of the bytes.
    const voiceWeight = 6.0;
    final total = 114 +
        (qul != null ? surahs.length : 0) +
        (align ? 1 : 0) +
        surahs.length * voiceWeight +
        scenes.length;
    var done = 0.0;
    var told = DateTime.fromMillisecondsSinceEpoch(0);

    void tell(OfflineStage stage, {bool now = false}) {
      final t = DateTime.now();
      // A few times a second at most: the sheet's bar does not need
      // every file, and a notifier per file would rebuild it hundreds of
      // times a minute.
      if (!now && t.difference(told) < const Duration(milliseconds: 250)) {
        return;
      }
      told = t;
      state.value = OfflineProgress(stage,
          fraction: total == 0 ? 1 : (done / total).clamp(0.0, 1.0));
    }

    /// One file or step: run, counted, and judged. Answers false when the
    /// run has to end (the user stopped it, the network or the disk is
    /// gone), having said why.
    Future<bool> step(OfflineStage stage, Future<void> Function() job,
        {double worth = 1}) async {
      if (_stop) {
        state.value = OfflineProgress(OfflineStage.stopped,
            fraction: done / total, missed: missed);
        return false;
      }
      try {
        await job();
        inARow = 0;
      } on FileSystemException catch (e) {
        rlog('offline: disk — $e');
        if (_isFull(e)) {
          state.value = OfflineProgress(OfflineStage.full,
              fraction: done / total, missed: missed);
          return false;
        }
        missed++;
      } catch (e) {
        missed++;
        inARow++;
        rlog('offline: ${stage.name} failed — $e');
        if (inARow >= _offlineAfter) {
          state.value = OfflineProgress(OfflineStage.offline,
              fraction: done / total, missed: missed);
          return false;
        }
      }
      done += worth;
      tell(stage);
      return true;
    }

    rlog('offline: ${plan.voice.id} ${plan.scope.name}, '
        '${scenes.length} sceneries');
    tell(OfflineStage.text, now: true);

    // 1 · the text, in the translation chosen. Two at a time.
    for (var s = 1; s <= 114; s += 2) {
      final ok = await Future.wait([
        for (var k = s; k <= s + 1 && k <= 114; k++)
          step(OfflineStage.text, () async {
            if (!await QuranTextService.isOnDisk(k)) {
              await QuranTextService.load(k);
            }
          }),
      ]);
      if (ok.contains(false)) return;
    }

    // 2 · the word timing that follows the voice.
    if (align || qul != null) tell(OfflineStage.words, now: true);
    if (align &&
        !await step(OfflineStage.words, () async {
          // One file serves every surah of every such voice.
          await WordAlignService.load(plan.voice, 1);
        })) {
      return;
    }
    if (qul != null) {
      for (final s in surahs) {
        if (!await step(OfflineStage.words, () async {
          await QulWords.versesOf(qul, s);
        })) {
          return;
        }
      }
    }

    // 3 · the voice, a surah at a time.
    tell(OfflineStage.voice, now: true);
    for (final s in surahs) {
      final before = done;
      final ok = await step(OfflineStage.voice, () async {
        if (await RecitationService.isOffline(plan.voice, s)) return;
        await RecitationService.keepOffline(
          plan.voice,
          s,
          cancelled: () => _stop,
          onProgress: (p) {
            done = before + p * voiceWeight;
            tell(OfflineStage.voice);
          },
        );
      }, worth: 0);
      done = before + voiceWeight;
      if (!ok) return;
    }

    // 4 · the sceneries, stills first. Three at a time.
    tell(OfflineStage.scenes, now: true);
    for (var i = 0; i < scenes.length; i += 3) {
      final ok = await Future.wait([
        for (var k = i; k < scenes.length && k < i + 3; k++)
          step(OfflineStage.scenes, () async {
            final f = await SceneCatalog.download(scenes[k]);
            if (f == null) throw StateError('${scenes[k].id} did not come');
          }),
      ]);
      if (ok.contains(false)) return;
    }

    state.value = OfflineProgress(OfflineStage.done, fraction: 1, missed: missed);
    rlog('offline: done, $missed missed');
  }

  static bool _isFull(FileSystemException e) {
    final code = e.osError?.errorCode;
    // ENOSPC on Android and iOS alike; the message, where a plugin
    // rewrapped it.
    return code == 28 ||
        (e.osError?.message.toLowerCase().contains('no space') ?? false) ||
        e.message.toLowerCase().contains('no space');
  }

  /// How much of [plan] is on the phone already: every surah's text, the
  /// voice's surahs, and the sceneries asked for. For the sheet to say
  /// "on your phone" rather than offer what is already there.
  static Future<({int text, int voice, int voiceOf, int scenes, int scenesOf})>
      status(OfflinePlan plan) async {
    var text = 0;
    for (var s = 1; s <= 114; s++) {
      if (await QuranTextService.isOnDisk(s)) text++;
    }
    final surahs =
        plan.scope.surahs.where((s) => plan.voice.hasSurah(s)).toList();
    var voice = 0;
    for (final s in surahs) {
      if (await RecitationService.isOffline(plan.voice, s, thorough: false)) {
        voice++;
      }
    }
    final asked = [
      for (final s in SceneCatalog.all)
        if (!s.bundled && (s.isVideo ? plan.clips : plan.stills)) s,
    ];
    final ready = asked.where(SceneCatalog.isReadySync).length;
    return (
      text: text,
      voice: voice,
      voiceOf: surahs.length,
      scenes: ready,
      scenesOf: asked.length,
    );
  }

  /// Forgets a finished or stopped run's last word, for a new one.
  @visibleForTesting
  static void debugReset() {
    _stop = false;
    _running = null;
    state.value = OfflineProgress.idle;
  }
}
