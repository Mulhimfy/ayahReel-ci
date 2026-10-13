import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'arena_challenge.dart';
import 'arena_engine.dart';
import 'whole_file.dart';

/// What the arena remembers between rounds: the bests, the rounds
/// played, and what the lobby was last set to. One file, no account,
/// no server.
///
/// Every round is free to play as often as wanted. A round is kept
/// whole — its seed, its games, every answer — so its picture can be
/// drawn again and shared again from the history, weeks later, exactly
/// as it was.
class ArenaState {
  /// Best score by [ArenaSetup.bestKey].
  final Map<String, int> best;

  /// Rounds finished, ever.
  final int played;

  /// Challenges sent and answered, ever.
  final int sent;
  final int answered;

  /// The last rounds, newest first.
  final List<ArenaRecord> history;

  /// What the lobby was last set to — scope, seconds, games, the
  /// player's name — so it opens where it was left; and the one-time
  /// notes that have been shown.
  final Map<String, String> prefs;

  const ArenaState({
    this.best = const {},
    this.played = 0,
    this.sent = 0,
    this.answered = 0,
    this.history = const [],
    this.prefs = const {},
  });

  ArenaState copyWith({
    Map<String, int>? best,
    int? played,
    int? sent,
    int? answered,
    List<ArenaRecord>? history,
    Map<String, String>? prefs,
  }) =>
      ArenaState(
        best: best ?? this.best,
        played: played ?? this.played,
        sent: sent ?? this.sent,
        answered: answered ?? this.answered,
        history: history ?? this.history,
        prefs: prefs ?? this.prefs,
      );

  int bestFor(ArenaSetup setup) => best[setup.bestKey] ?? 0;

  Map<String, dynamic> toJson() => {
        'best': best,
        'played': played,
        'sent': sent,
        'answered': answered,
        'history': [for (final r in history) r.toJson()],
        'prefs': prefs,
      };

  static ArenaState fromJson(Map<String, dynamic> j) => ArenaState(
        best: {
          for (final e in (j['best'] as Map<String, dynamic>? ?? {}).entries)
            e.key: e.value as int,
        },
        played: j['played'] as int? ?? 0,
        sent: j['sent'] as int? ?? 0,
        answered: j['answered'] as int? ?? 0,
        history: [
          for (final r in (j['history'] as List? ?? const []))
            ArenaRecord.fromJson(r as Map<String, dynamic>),
        ],
        prefs: {
          for (final e in (j['prefs'] as Map<String, dynamic>? ?? {}).entries)
            e.key: e.value as String,
        },
      );
}

/// How a round was played: alone, or against a code.
enum ArenaMode { solo, challenge }

/// One finished round, whole: enough to draw it again and share it
/// again. The questions are not stored — the seed makes them.
class ArenaRecord {
  /// Stable, for deleting: the moment it was filed, in milliseconds.
  final String id;
  final ArenaMode mode;
  final String scopeKey;
  final int seed;
  final Set<ArenaGame> games;
  final int seconds;
  final bool askMeanings;
  final List<ArenaAnswer> answers;
  final DateTime at;

  /// The player, as they were named at the time; empty when nameless.
  final String me;

  /// For a challenge: the other side.
  final String rival;
  final int rivalScore;
  final int rivalCorrect;

  /// For a challenge: the code that was played.
  final String code;

  /// The verses the round asked about, as (surah, ayah) in the order
  /// asked; a question about a surah's facts names no verse. Null for a
  /// round filed before rounds kept them, until [ArenaService.fillVerses]
  /// makes its questions again from the seed. They light the "Your
  /// verses" card beside the reels'.
  final List<(int, int)>? verses;

  const ArenaRecord({
    required this.id,
    required this.mode,
    required this.scopeKey,
    required this.seed,
    required this.games,
    required this.seconds,
    required this.askMeanings,
    required this.answers,
    required this.at,
    this.me = '',
    this.rival = '',
    this.rivalScore = 0,
    this.rivalCorrect = 0,
    this.code = '',
    this.verses,
  });

  /// The same round, its verses named.
  ArenaRecord withVerses(List<(int, int)> named) => ArenaRecord(
        id: id,
        mode: mode,
        scopeKey: scopeKey,
        seed: seed,
        games: games,
        seconds: seconds,
        askMeanings: askMeanings,
        answers: answers,
        at: at,
        me: me,
        rival: rival,
        rivalScore: rivalScore,
        rivalCorrect: rivalCorrect,
        code: code,
        verses: named,
      );

  /// The verses [round] asked, of the [asked] it got to.
  static List<(int, int)> versesOf(ArenaRound round, int asked) => [
        for (final q in round.questions.take(asked))
          if (q.ayah > 0) (q.surah, q.ayah),
      ];

  int get score => answers.fold(0, (s, a) => s + a.points);
  int get correct => answers.where((a) => a.correct).length;
  int get asked => answers.length;

  bool get won => mode == ArenaMode.challenge && score > rivalScore;
  bool get drew => mode == ArenaMode.challenge && score == rivalScore;

  /// The setup the round was played on.
  ArenaSetup get setup => ArenaSetup(
        scope: ArenaScope.fromKey(scopeKey) ?? const ArenaScope.quran(),
        games: games.isEmpty ? {ArenaGame.missingWord} : games,
        seconds: seconds,
        count: ArenaChallenge.questions,
        askMeanings: askMeanings,
      );

  /// The round's result, as the result screen reads it.
  ArenaResult get result =>
      ArenaResult(setup: setup, seed: seed, answers: answers);

  /// The challenge that was answered, when one was.
  ArenaChallenge? get challenge => mode == ArenaMode.challenge
      ? ArenaChallenge(
          setup: setup,
          seed: seed,
          score: rivalScore,
          correct: rivalCorrect,
        )
      : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode.name,
        'scope': scopeKey,
        'seed': seed,
        'games': [for (final g in games) g.name],
        'seconds': seconds,
        'meanings': askMeanings,
        'answers': [for (final a in answers) a.toJson()],
        'at': at.toIso8601String(),
        'me': me,
        'rival': rival,
        'rivalScore': rivalScore,
        'rivalCorrect': rivalCorrect,
        'code': code,
        // Flat, surah then ayah: ten pairs a round, thirty rounds kept.
        if (verses != null) 'v': [for (final (s, a) in verses!) ...[s, a]],
      };

  static List<(int, int)>? _versesFrom(Object? raw) {
    if (raw is! List) return null;
    return [
      for (var i = 0; i + 1 < raw.length; i += 2)
        if (raw[i] is int && raw[i + 1] is int)
          (raw[i] as int, raw[i + 1] as int),
    ];
  }

  static ArenaRecord fromJson(Map<String, dynamic> j) => ArenaRecord(
        id: j['id'] as String? ?? (j['at'] as String? ?? ''),
        mode: ArenaMode.values.firstWhere((m) => m.name == j['mode'],
            orElse: () => ArenaMode.solo),
        scopeKey: j['scope'] as String? ?? 'q',
        seed: j['seed'] as int? ?? 0,
        games: {
          for (final g in (j['games'] as List? ?? const []))
            for (final v in ArenaGame.values)
              if (v.name == g) v,
        },
        seconds: j['seconds'] as int? ?? ArenaSetup.defaultSeconds,
        askMeanings: j['meanings'] as bool? ?? true,
        answers: [
          for (final a in (j['answers'] as List? ?? const []))
            ArenaAnswer.fromJson(a as Map<String, dynamic>),
        ],
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2026),
        me: j['me'] as String? ?? '',
        rival: j['rival'] as String? ?? '',
        rivalScore: j['rivalScore'] as int? ?? 0,
        rivalCorrect: j['rivalCorrect'] as int? ?? 0,
        code: j['code'] as String? ?? '',
        verses: _versesFrom(j['v']),
      );
}

abstract final class ArenaService {
  /// How many rounds the history keeps.
  static const historyLength = 30;

  static final ValueNotifier<ArenaState> state =
      ValueNotifier(const ArenaState());

  /// A challenge the app was opened with — a link, or a code pasted
  /// somewhere the arena can see it — waiting for the arena to take
  /// it. The arena clears it when it does.
  static final ValueNotifier<String?> pendingCode = ValueNotifier(null);

  /// Who sent [pendingCode], when the link said.
  static String pendingSender = '';

  static Future<void>? _loading;

  /// For tests: a file to use instead of the app's own, and a clock.
  @visibleForTesting
  static File? fileOverride;
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  @visibleForTesting
  static void reset() {
    _loading = null;
    _filling = null;
    state.value = const ArenaState();
    pendingCode.value = null;
    pendingSender = '';
  }

  /// Reads arena.json once. Every caller waits for that one read: a
  /// second caller that went ahead while it was still running — the
  /// lobby, opened by a challenge link on a cold start — found empty
  /// defaults, and the first thing it saved wrote them over the file.
  static Future<void> init() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final f = await _file();
      if (f.existsSync()) {
        state.value = ArenaState.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {/* start fresh */}
  }

  /// Files a finished round. Returns whether it is a new best for its
  /// scope.
  static Future<bool> record(
    ArenaResult result, {
    required ArenaMode mode,
    String me = '',
    String rival = '',
    int rivalScore = 0,
    int rivalCorrect = 0,
    String code = '',
    List<(int, int)>? verses,
  }) async {
    await init();
    final s = state.value;
    final key = result.setup.bestKey;
    final isBest = result.score > (s.best[key] ?? 0);
    final at = now();
    final rec = ArenaRecord(
      id: '${at.millisecondsSinceEpoch}',
      mode: mode,
      scopeKey: result.setup.scope.key,
      seed: result.seed,
      games: result.setup.games,
      seconds: result.setup.seconds,
      askMeanings: result.setup.askMeanings,
      answers: result.answers,
      at: at,
      me: me,
      rival: rival,
      rivalScore: rivalScore,
      rivalCorrect: rivalCorrect,
      code: code,
      verses: verses,
    );
    state.value = s.copyWith(
      best: isBest ? {...s.best, key: result.score} : s.best,
      played: s.played + 1,
      answered: mode == ArenaMode.challenge ? s.answered + 1 : s.answered,
      history: [rec, ...s.history].take(historyLength).toList(),
    );
    await _persist();
    return isBest;
  }

  static Future<void>? _filling;

  /// Names the verses of the rounds filed before rounds kept them: the
  /// seed makes each round's questions again. Once a run, and nothing
  /// to do — not even the corpus to read — when every round has them.
  /// A corpus that can't be read leaves them for the next call.
  static Future<void> fillVerses() => _filling ??= () async {
        try {
          await init();
          if (!state.value.history.any((r) => r.verses == null)) return;
          final corpus = await ArenaCorpus.load();
          // A round that can't be made again names none, and is not
          // tried again.
          List<(int, int)> named(ArenaRecord r) {
            if (r.asked == 0) return const [];
            try {
              return ArenaRecord.versesOf(
                  ArenaRound.generate(corpus, r.setup, r.seed), r.asked);
            } catch (_) {
              return const [];
            }
          }

          // Read again after the wait: a round filed meanwhile stays.
          final s = state.value;
          state.value = s.copyWith(history: [
            for (final r in s.history)
              r.verses != null ? r : r.withVerses(named(r)),
          ]);
          await _persist();
        } catch (_) {
          _filling = null;
        }
      }();

  /// Takes a round out of the history.
  static Future<void> remove(String id) async {
    await init();
    final s = state.value;
    state.value = s.copyWith(
      history: [
        for (final r in s.history)
          if (r.id != id) r,
      ],
    );
    await _persist();
  }

  /// Counts a challenge sent.
  static Future<void> sent() async {
    await init();
    state.value = state.value.copyWith(sent: state.value.sent + 1);
    await _persist();
  }

  /// Keeps what the lobby is set to, and which notes have been shown.
  static Future<void> remember(Map<String, String> prefs) async {
    await init();
    state.value =
        state.value.copyWith(prefs: {...state.value.prefs, ...prefs});
    await _persist();
  }

  /// A link the app was opened with, or handed while open. Anything
  /// that is not a challenge is ignored.
  static void takeLink(String? link) {
    final code = ArenaChallenge.codeInLink(link);
    if (code == null) return;
    pendingSender = ArenaChallenge.senderInLink(link);
    pendingCode.value = code;
  }

  static Future<File> _file() async {
    final o = fileOverride;
    if (o != null) return o;
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/arena.json');
  }

  static Future<void> _persist() async {
    try {
      await writeWhole(await _file(), jsonEncode(state.value.toJson()));
    } catch (_) {/* best effort */}
  }
}
