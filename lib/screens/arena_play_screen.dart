import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/arena_challenge.dart';
import '../data/arena_engine.dart';
import '../data/arena_service.dart';
import '../data/surah_index.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/arena_fx.dart';
import '../widgets/glow_button.dart';
import '../widgets/illumination.dart';
import '../widgets/night_sky.dart';
import 'arena_result_screen.dart';

/// A round, being played.
///
/// One question at a time, a ring burning down beside it, and four
/// things to tap — or a tray of words to put back in order. A right
/// answer throws gold; a wrong one shakes and lights the right one so
/// the verse is learned either way.
class ArenaPlayScreen extends StatefulWidget {
  final ArenaSetup setup;
  final int seed;
  final ArenaMode mode;

  /// The player's name, as the round will be kept; empty when nameless.
  final String me;

  /// The code being answered, when there is one.
  final ArenaChallenge? challenge;

  /// Who sent it, when the link said.
  final String rival;

  const ArenaPlayScreen({
    super.key,
    required this.setup,
    required this.seed,
    required this.mode,
    this.me = '',
    this.challenge,
    this.rival = '',
  });

  @override
  State<ArenaPlayScreen> createState() => _ArenaPlayScreenState();
}

class _ArenaPlayScreenState extends State<ArenaPlayScreen>
    with SingleTickerProviderStateMixin {
  ArenaRound? _round;
  int _i = 0;
  final List<ArenaAnswer> _answers = [];
  int _combo = 0;

  bool _revealed = false;
  int _chosen = -1;
  bool _correct = false;
  int _gained = 0;
  bool _timedOut = false;
  List<int> _placed = const [];

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
    value: 1,
  );
  Timer? _advance;
  bool _finished = false;
  final _burst = BurstController();
  final _shake = ShakeController();
  final _glint = GlintController();

  ArenaQuestion get _q => _round!.questions[_i];
  int get _count => _round!.questions.length;
  int get _score => _answers.fold(0, (s, a) => s + a.points);

  @override
  void initState() {
    super.initState();
    _clock.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && !_revealed) _timeout();
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final corpus = await ArenaCorpus.load();
    if (!mounted) return;
    final round = ArenaRound.generate(corpus, widget.setup, widget.seed);
    if (round.questions.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _round = round);
    _start();
  }

  @override
  void dispose() {
    _advance?.cancel();
    _clock.dispose();
    _burst.dispose();
    _shake.dispose();
    _glint.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _revealed = false;
      _chosen = -1;
      _correct = false;
      _gained = 0;
      _timedOut = false;
      _placed = const [];
    });
    // The clock runs under reduced motion too: it is the round's
    // rule, not its decoration. The ring it drives simply moves less.
    _clock
      ..duration = Duration(seconds: _q.seconds)
      ..value = 1
      ..reverse(from: 1);
  }

  void _settle({required bool correct, required int chosen, Offset? at}) {
    if (_revealed) return;
    _clock.stop();
    final timeLeft = _clock.value.clamp(0.0, 1.0);
    _combo = correct ? _combo + 1 : 0;
    final points = ArenaScoring.points(
        correct: correct, timeLeft: timeLeft, combo: _combo);
    _answers.add(ArenaAnswer(
      chosen: chosen,
      correct: correct,
      timeLeft: timeLeft,
      points: points,
    ));
    setState(() {
      _revealed = true;
      _chosen = chosen;
      _correct = correct;
      _gained = points;
    });
    if (correct) {
      HapticFeedback.lightImpact();
      if (at != null) _burst.fire(at, scale: _combo >= 3 ? 1.3 : 1);
      if (_combo >= 3) _glint.fire();
    } else {
      HapticFeedback.heavyImpact();
      _shake.shake();
    }
    _advance = Timer(
      Duration(milliseconds: correct ? 1500 : 2100),
      _next,
    );
  }

  void _timeout() {
    if (!mounted || _round == null) return;
    setState(() => _timedOut = true);
    _settle(correct: false, chosen: -1);
  }

  void _answer(int i, Offset? at) => _settle(correct: i == _q.answer, chosen: i, at: at);

  void _place(int token, Offset? at) {
    if (_revealed || _placed.contains(token)) return;
    HapticFeedback.selectionClick();
    final next = [..._placed, token];
    setState(() => _placed = next);
    if (next.length == _q.tokens.length) {
      _settle(correct: _q.ordered(next), chosen: 0, at: at);
    }
  }

  void _unplace(int position) {
    if (_revealed) return;
    HapticFeedback.selectionClick();
    setState(() => _placed = _placed.sublist(0, position));
  }

  void _next() {
    _advance?.cancel();
    _advance = null;
    if (!mounted) return;
    if (_i + 1 >= _count) {
      _finish();
      return;
    }
    setState(() => _i++);
    _start();
  }

  void _finish() {
    // Filed once. The result replaces this screen's own route, not
    // whatever sits on top of it (a "leave round?" dialog would be the
    // one replaced, and the stale round under the result could file the
    // round a second time).
    if (_finished) return;
    _finished = true;
    final me = ModalRoute.of(context);
    final route = BloomRoute<void>(
      builder: (_) => ArenaResultScreen(
        round: _round!,
        result: ArenaResult(
          setup: widget.setup,
          seed: widget.seed,
          answers: List.unmodifiable(_answers),
        ),
        mode: widget.mode,
        me: widget.me,
        challenge: widget.challenge,
        rival: widget.rival,
        file: true,
      ),
    );
    final nav = Navigator.of(context);
    if (me != null && !me.isCurrent) {
      nav.replace(oldRoute: me, newRoute: route);
    } else {
      nav.pushReplacement(route);
    }
  }

  Future<void> _leave() async {
    final l = L10n.of(context);
    final wasRunning = _clock.isAnimating;
    _clock.stop();
    // The step to the next question waits for the answer too: left
    // running, the round would play on (and could end) behind it.
    final advancing = _advance != null;
    _advance?.cancel();
    _advance = null;
    final leave = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(l.arenaLeaveRound,
            style: Theme.of(d).textTheme.titleMedium, textAlign: TextAlign.center),
        content: Text(
          l.arenaLeaveNoKeep,
          textAlign: TextAlign.center,
          style: Theme.of(d).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          QuietButton(label: l.leave, onPressed: () => Navigator.of(d).pop(true)),
          QuietButton(label: l.stay, onPressed: () => Navigator.of(d).pop(false)),
        ],
      ),
    );
    if (!mounted) return;
    if (leave ?? false) {
      Navigator.of(context).pop();
    } else if (advancing) {
      _advance = Timer(const Duration(milliseconds: 600), _next);
    } else if (wasRunning && !_revealed) {
      _clock.reverse(from: _clock.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final round = _round;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const MeshBackdrop(alpha: 0.36, speed: 0.7, seed: 5),
            const IgnorePointer(child: Starfield(count: 60, seed: 4)),
            SafeArea(
              child: round == null
                  ? _Loading(l: l)
                  : GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _revealed ? _next : null,
                          child: Column(
                            children: [
                              _Top(
                                count: _count,
                                index: _i,
                                done: _i + (_revealed ? 1 : 0),
                                score: _score,
                                onClose: _leave,
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 420),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, a) => FadeTransition(
                                      opacity: a,
                                      child: SlideTransition(
                                        position: Tween(
                                          begin: const Offset(0, 0.04),
                                          end: Offset.zero,
                                        ).animate(a),
                                        child: child,
                                      ),
                                    ),
                                    layoutBuilder: (current, previous) => Stack(
                                      alignment: Alignment.topCenter,
                                      children: [...previous, if (current != null) current],
                                    ),
                                    child: KeyedSubtree(
                                      key: ValueKey('q$_i'),
                                      child: _question(l),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
            Positioned.fill(child: GoldBurst(controller: _burst)),
          ],
        ),
      ),
    );
  }

  Widget _question(L10n l) {
    final q = _q;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClockRow(
          clock: _clock,
          seconds: q.seconds,
          prompt: arenaPromptFor(l, q),
          streak: _combo,
          gained: _revealed ? _gained : 0,
          glint: _glint,
        ),
        const SizedBox(height: 14),
        Shaker(
          controller: _shake,
          child: ArenaQuestionCard(
            q: q,
            revealed: _revealed,
            correct: _correct,
            timedOut: _timedOut,
            placed: _placed,
            onUnplace: _unplace,
          ),
        ),
        const SizedBox(height: 14),
        if (q.game == ArenaGame.orderWords)
          _Tray(
            key: ValueKey('tray$_i'),
            q: q,
            placed: _placed,
            revealed: _revealed,
            onPlace: _place,
            onUndo: _placed.isEmpty ? null : () => _unplace(_placed.length - 1),
          )
        else
          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Rise(
                delay: Duration(milliseconds: 70 * i),
                child: ArenaOptionCard(
                  key: ValueKey('opt$_i-$i'),
                  option: q.options[i],
                  index: i,
                  state: !_revealed
                      ? ArenaOptionState.idle
                      : i == q.answer
                          ? ArenaOptionState.right
                          : i == _chosen
                              ? ArenaOptionState.wrong
                              : ArenaOptionState.dim,
                  onTap: (at) => _answer(i, at),
                ),
              ),
            ),
        if (_revealed) ...[
          const SizedBox(height: 6),
          _Verdict(
            correct: _correct,
            timedOut: _timedOut,
            reference: arenaReferenceOf(l, q),
          ),
        ],
      ],
    );
  }
}

/// What a question asks, in the reader's language.
String arenaPromptFor(L10n l, ArenaQuestion q) {
  if (q.game != ArenaGame.surahFacts) return l.arenaPrompt(q.game);
  final name = surahIndex[q.surah - 1].nameEnglish;
  return switch (q.fact!) {
    ArenaFactKind.verseCount => l.arenaFactVerseCount(l.localizedSurahName(name)),
    ArenaFactKind.orderNumber => l.arenaFactOrderNumber(q.surah),
    ArenaFactKind.revelationPlace => l.arenaFactRevelation(l.localizedSurahName(name)),
    ArenaFactKind.comesAfter => l.arenaFactComesAfter(l.localizedSurahName(name)),
    ArenaFactKind.nameMeaning => l.arenaFactNameMeaning(q.meaning(l.lang.code)),
    ArenaFactKind.opensInJuz => l.arenaFactOpensInJuz(l.localizedSurahName(name)),
  };
}

/// Where a question's verse is — "Al-Baqarah · 255" — or its surah.
String arenaReferenceOf(L10n l, ArenaQuestion q) {
  final name = surahIndex[q.surah - 1].nameEnglish;
  if (q.ayah == 0) return l.arenaSurah(name);
  final ayah = q.game == ArenaGame.nextVerse ? q.ayah + 1 : q.ayah;
  return l.verseReference(name, ayah, ayah);
}

/// A question as it was answered, to look at again from the review:
/// the same card and the same options, already revealed, with nothing
/// to tap but the way out.
class ArenaReplayScreen extends StatelessWidget {
  final ArenaQuestion question;
  final ArenaAnswer answer;
  final int index;
  final int count;

  const ArenaReplayScreen({
    super.key,
    required this.question,
    required this.answer,
    required this.index,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final q = question;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MeshBackdrop(alpha: 0.32, speed: 0.6, seed: 6),
          const IgnorePointer(child: Starfield(count: 50, seed: 4)),
          SafeArea(
            child: Column(
              children: [
                _Top(
                  count: count,
                  index: index,
                  done: count,
                  score: answer.points,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        A11yHeader(
                          child: Text(
                            arenaPromptFor(l, q),
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ArenaQuestionCard(
                          q: q,
                          revealed: true,
                          correct: answer.correct,
                          timedOut: answer.chosen < 0,
                          placed: q.game == ArenaGame.orderWords ? q.order : const [],
                          onUnplace: (_) {},
                        ),
                        const SizedBox(height: 14),
                        if (q.game != ArenaGame.orderWords)
                          for (var i = 0; i < q.options.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Rise(
                                delay: Duration(milliseconds: 60 * i),
                                child: ArenaOptionCard(
                                  option: q.options[i],
                                  index: i,
                                  state: i == q.answer
                                      ? ArenaOptionState.right
                                      : i == answer.chosen
                                          ? ArenaOptionState.wrong
                                          : ArenaOptionState.dim,
                                  onTap: (_) {},
                                ),
                              ),
                            ),
                        const SizedBox(height: 6),
                        _Verdict(
                          correct: answer.correct,
                          timedOut: answer.chosen < 0,
                          reference: arenaReferenceOf(l, q),
                          hint: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------

class _Loading extends StatelessWidget {
  final L10n l;
  const _Loading({required this.l});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 60, 18, 0),
      child: Column(
        children: [
          Text(l.arenaOpening,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 22),
          const GlareBlock(height: 150, radius: BorderRadius.all(Radius.circular(22))),
          const SizedBox(height: 14),
          for (var i = 0; i < 4; i++) ...[
            const GlareBlock(height: 58),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// The bar: close, the seals of the round, the score.
class _Top extends StatelessWidget {
  final int count;
  final int index;
  final int done;
  final int score;
  final VoidCallback onClose;

  const _Top({
    required this.count,
    required this.index,
    required this.done,
    required this.score,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 18, 4),
      child: Row(
        children: [
          A11yTap(
            label: MaterialLocalizations.of(context).closeButtonLabel,
            onTap: onClose,
            child: Pressable(
              onTap: onClose,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface.withValues(alpha: 0.6),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textPrimary),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: l.arenaQuestionOf(index + 1, count),
              excludeSemantics: true,
              child: Center(
                child: SealProgress(count: count, done: done, current: index),
              ),
            ),
          ),
          Semantics(
            label: '${l.arenaScore} $score',
            excludeSemantics: true,
            child: CountUp(
              value: score,
              duration: const Duration(milliseconds: 600),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.goldBright,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The ring, the prompt, and — when there is one — the run.
class _ClockRow extends StatelessWidget {
  final Animation<double> clock;
  final int seconds;
  final String prompt;
  final int streak;
  final int gained;
  final GlintController glint;

  const _ClockRow({
    required this.clock,
    required this.seconds,
    required this.prompt,
    required this.streak,
    required this.gained,
    required this.glint,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: clock,
          builder: (context, _) {
            final left = (clock.value * seconds).ceil();
            return Semantics(
              label: l.a11ySecondsLeft(left),
              liveRegion: true,
              excludeSemantics: true,
              child: TimerRing(
                remaining: clock,
                size: 62,
                stroke: 4.2,
                child: Text(
                  '$left',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: clock.value < 0.25 ? ArenaPalette.wrong : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              A11yHeader(
                child: Text(
                  prompt,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: streak >= 3
                        ? Glint(
                            key: ValueKey('streak$streak'),
                            controller: glint,
                            child: _Cartouche(
                              text: l.arenaStreak(streak),
                              strong: true,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.6), end: Offset.zero)
                            .animate(a),
                        child: child,
                      ),
                    ),
                    child: gained > 0
                        ? Text(
                            '+$gained',
                            key: ValueKey('gain$gained'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.goldBright,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small awarded label, cut as a cartouche.
class _Cartouche extends StatelessWidget {
  final String text;
  final bool strong;
  const _Cartouche({required this.text, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const CartoucheClipper(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        color: strong
            ? AppColors.gold.withValues(alpha: 0.28)
            : AppColors.surface.withValues(alpha: 0.8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: strong ? AppColors.goldBright : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The question itself: the verse, the stem, the verse with a hole in
/// it, the line being put in order, or the fact's subject.
class ArenaQuestionCard extends StatelessWidget {
  final ArenaQuestion q;
  final bool revealed;
  final bool correct;
  final bool timedOut;
  final List<int> placed;
  final ValueChanged<int> onUnplace;

  const ArenaQuestionCard({
    super.key,
    required this.q,
    required this.revealed,
    required this.correct,
    required this.timedOut,
    required this.placed,
    required this.onUnplace,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final radius = BorderRadius.circular(22);
    final Widget body;
    switch (q.game) {
      case ArenaGame.missingWord:
        body = _BlankVerse(q: q, revealed: revealed);
      case ArenaGame.orderWords:
        body = _OrderLine(q: q, placed: placed, revealed: revealed, correct: correct,
            onUnplace: onUnplace);
      case ArenaGame.surahFacts:
        final name = surahIndex[q.surah - 1];
        body = Column(
          children: [
            GildedText(
              q.fact == ArenaFactKind.orderNumber
                  ? '${q.surah}'
                  : q.fact == ArenaFactKind.nameMeaning
                      ? '“${q.meaning(l.lang.code)}”'
                      : l.arabicScript
                          ? name.nameArabic
                          : name.nameEnglish,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: q.fact == ArenaFactKind.orderNumber ? 46 : 28,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            if (q.fact != ArenaFactKind.orderNumber &&
                q.fact != ArenaFactKind.nameMeaning &&
                !l.arabicScript) ...[
              const SizedBox(height: 6),
              Text(name.nameArabic,
                  style: AppTheme.quran(size: 20, color: AppColors.textSecondary)),
            ],
          ],
        );
      case ArenaGame.completeVerse:
        // Asked: the stem and a gap. Answered: the whole verse, its
        // ending in gold — the verse is what is to be learned, not the
        // letter that was tapped.
        body = Text.rich(
          TextSpan(
            children: [
              TextSpan(text: q.text),
              const TextSpan(text: ' '),
              if (revealed)
                TextSpan(
                  text: (q.options[q.answer] as VerseOption).text,
                  style: const TextStyle(color: AppColors.goldBright),
                )
              else
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _Blank(revealed: false, wide: true),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: AppTheme.quran(size: 24).copyWith(height: 2.0),
        );
      case ArenaGame.whichSurah:
      case ArenaGame.nextVerse:
        body = Text(
          q.text,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: AppTheme.quran(size: 24).copyWith(height: 2.0),
        );
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        GlassPane(
          radius: radius,
          tint: const Color(0x99161B22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: SizedBox(width: double.infinity, child: body),
          ),
        ),
        Positioned.fill(
          child: IlluminatedBorder(
            radius: radius,
            sealSize: 7,
            color: revealed
                ? (correct ? AppColors.goldBright : ArenaPalette.wrong)
                : AppColors.gold,
          ),
        ),
      ],
    );
  }
}

/// A gap in a line of the Quran: a cartouche holding a mark that
/// breathes until the word is known, and the word once it is.
class _Blank extends StatefulWidget {
  final bool revealed;
  final String? text;
  final bool wide;
  const _Blank({required this.revealed, this.text, this.wide = false});

  @override
  State<_Blank> createState() => _BlankState();
}

class _BlankState extends State<_Blank> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = still ? 0.5 : Curves.easeInOut.transform(_c.value);
        final lit = widget.revealed ? 1.0 : 0.45 + 0.55 * v;
        return ClipPath(
          clipper: const CartoucheClipper(),
          child: Container(
            constraints: BoxConstraints(minWidth: widget.wide ? 96 : 64),
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
            color: AppColors.gold.withValues(alpha: 0.12 + 0.16 * lit),
            child: Text(
              widget.text ?? '؟',
              textAlign: TextAlign.center,
              style: AppTheme.quran(size: 24).copyWith(
                height: 1.6,
                color: AppColors.goldBright.withValues(alpha: 0.55 + 0.45 * lit),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The verse with one word missing, the hole where it was.
class _BlankVerse extends StatelessWidget {
  final ArenaQuestion q;
  final bool revealed;
  const _BlankVerse({required this.q, required this.revealed});

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.quran(size: 24).copyWith(height: 2.0);
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < q.tokens.length; i++) ...[
            if (i > 0) const TextSpan(text: ' '),
            if (i == q.blank)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _Blank(
                  revealed: revealed,
                  text: revealed ? q.tokens[i] : null,
                ),
              )
            else
              TextSpan(text: q.tokens[i]),
          ],
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      style: style,
    );
  }
}

/// The line being put back together: the words placed so far, on a
/// rule, and the whole verse in gold once it is right — or once it is
/// wrong, so it is learned anyway.
class _OrderLine extends StatelessWidget {
  final ArenaQuestion q;
  final List<int> placed;
  final bool revealed;
  final bool correct;
  final ValueChanged<int> onUnplace;

  const _OrderLine({
    required this.q,
    required this.placed,
    required this.revealed,
    required this.correct,
    required this.onUnplace,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final style = AppTheme.quran(size: 23).copyWith(height: 1.7);
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var p = 0; p < placed.length; p++)
                  A11yTap(
                    label: q.tokens[placed[p]],
                    hint: revealed ? null : l.arenaUndo,
                    onTap: () => onUnplace(p),
                    child: Pressable(
                      onTap: revealed ? null : () => onUnplace(p),
                      scale: 0.94,
                      child: _WordChip(
                        text: q.tokens[placed[p]],
                        style: style,
                        tone: revealed
                            ? (correct ? _Tone.right : _Tone.wrong)
                            : _Tone.placed,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const OrnamentHairline(towardsEnd: true),
        if (revealed && !correct) ...[
          const SizedBox(height: 14),
          Text(l.arenaTheAnswer,
              style: const TextStyle(
                  fontSize: 11, letterSpacing: 1.2, color: AppColors.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          GildedText(
            [for (final i in q.order) q.tokens[i]].join(' '),
            textAlign: TextAlign.center,
            style: style,
          ),
        ],
      ],
    );
  }
}

enum _Tone { tray, placed, right, wrong }

class _WordChip extends StatelessWidget {
  final String text;
  final TextStyle style;
  final _Tone tone;
  const _WordChip({required this.text, required this.style, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color edge, Color ink) = switch (tone) {
      _Tone.tray => (
          AppColors.surface.withValues(alpha: 0.85),
          AppColors.stroke,
          AppColors.textPrimary
        ),
      _Tone.placed => (
          AppColors.gold.withValues(alpha: 0.14),
          AppColors.gold.withValues(alpha: 0.6),
          AppColors.goldBright
        ),
      _Tone.right => (
          AppColors.gold.withValues(alpha: 0.28),
          AppColors.goldBright,
          AppColors.goldBright
        ),
      _Tone.wrong => (
          ArenaPalette.wrong.withValues(alpha: 0.16),
          ArenaPalette.wrong.withValues(alpha: 0.7),
          AppColors.textPrimary
        ),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: edge),
      ),
      child: Text(text, style: style.copyWith(color: ink), textDirection: TextDirection.rtl),
    );
  }
}

/// The words still to place.
class _Tray extends StatelessWidget {
  final ArenaQuestion q;
  final List<int> placed;
  final bool revealed;
  final void Function(int token, Offset? at) onPlace;
  final VoidCallback? onUndo;

  const _Tray({
    super.key,
    required this.q,
    required this.placed,
    required this.revealed,
    required this.onPlace,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final style = AppTheme.quran(size: 23).copyWith(height: 1.7);
    Offset? down;
    return Column(
      children: [
        Directionality(
          textDirection: TextDirection.rtl,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var t = 0; t < q.tokens.length; t++)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: placed.contains(t) ? 0.18 : 1,
                  child: A11yTap(
                    label: q.tokens[t],
                    hint: l.a11yPlacesWord,
                    enabled: !placed.contains(t) && !revealed,
                    onTap: () => onPlace(t, null),
                    child: Rise(
                      delay: Duration(milliseconds: 50 * t),
                      child: Listener(
                        key: ValueKey('word$t'),
                        // Where the finger came down, for the burst. The
                        // word itself waits for the tap, so a drag that
                        // starts on it scrolls a tall question instead.
                        onPointerDown: (e) => down = e.position,
                        child: Pressable(
                          onTap: placed.contains(t) || revealed
                              ? null
                              : () => onPlace(t, down),
                          scale: 0.92,
                          child: TouchLight(
                            radius: BorderRadius.circular(14),
                            child: _WordChip(text: q.tokens[t], style: style, tone: _Tone.tray),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!revealed)
          QuietButton(
            label: l.arenaUndo,
            icon: Icons.undo_rounded,
            dense: true,
            onPressed: onUndo,
          ),
      ],
    );
  }
}

enum ArenaOptionState { idle, right, wrong, dim }

/// One thing to tap.
class ArenaOptionCard extends StatelessWidget {
  final ArenaOption option;
  final int index;
  final ArenaOptionState state;
  final void Function(Offset? at) onTap;

  const ArenaOptionCard({
    super.key,
    required this.option,
    required this.index,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final radius = BorderRadius.circular(18);
    final arabic = option is VerseOption;
    Offset? down;
    final label = _label(l, option);
    final (Color fill, Color edge, double opacity) = switch (state) {
      ArenaOptionState.idle => (AppColors.surface.withValues(alpha: 0.74), AppColors.stroke, 1.0),
      ArenaOptionState.right => (
          AppColors.gold.withValues(alpha: 0.24),
          AppColors.goldBright,
          1.0
        ),
      ArenaOptionState.wrong => (
          ArenaPalette.wrong.withValues(alpha: 0.18),
          ArenaPalette.wrong.withValues(alpha: 0.85),
          1.0
        ),
      ArenaOptionState.dim => (AppColors.surface.withValues(alpha: 0.4), AppColors.stroke, 0.45),
    };
    return A11yTap(
      label: label,
      hint: state == ArenaOptionState.idle ? l.a11yAnswersWith : null,
      enabled: state == ArenaOptionState.idle,
      onTap: () => onTap(null),
      child: Listener(
        // Where the finger came down, for the burst. The answer waits for
        // the tap: options of a long verse run past the screen, and a drag
        // that starts on one has to scroll, not answer.
        onPointerDown: (e) => down = e.position,
        child: Pressable(
          onTap: state == ArenaOptionState.idle ? () => onTap(down) : null,
          scale: 0.975,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: opacity,
            child: TouchLight(
              radius: radius,
              enabled: state == ArenaOptionState.idle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: radius,
                  border: Border.all(
                      color: edge, width: state == ArenaOptionState.right ? 1.4 : 1),
                  boxShadow: [
                    if (state == ArenaOptionState.right)
                      BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.35), blurRadius: 22),
                  ],
                ),
                child: Row(
                  children: [
                    _Letter(index: index, state: state),
                    const SizedBox(width: 12),
                    Expanded(
                      child: arabic
                          ? Text(
                              label,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: AppTheme.quran(size: 20).copyWith(
                                height: 1.8,
                                color: state == ArenaOptionState.right
                                    ? AppColors.goldBright
                                    : AppColors.textPrimary,
                              ),
                            )
                          : option is SurahOption
                              ? SurahNameText(
                                  surah: (option as SurahOption).surah,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                    color: state == ArenaOptionState.right
                                        ? AppColors.goldBright
                                        : AppColors.textPrimary,
                                  ),
                                )
                              : Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: option is NumberOption ||
                                            option is JuzOption
                                        ? 18
                                        : 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                    color: state == ArenaOptionState.right
                                        ? AppColors.goldBright
                                        : AppColors.textPrimary,
                                  ),
                                ),
                    ),
                    if (state == ArenaOptionState.right)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check_rounded, size: 20, color: AppColors.goldBright),
                      ),
                    if (state == ArenaOptionState.wrong)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.close_rounded, size: 20, color: ArenaPalette.wrong),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _label(L10n l, ArenaOption o) => switch (o) {
        VerseOption(:final text) => text,
        SurahOption(:final surah) => l.arabicScript
            ? surahIndex[surah - 1].nameArabic
            : '${surahIndex[surah - 1].nameEnglish} · ${surahIndex[surah - 1].nameArabic}',
        NumberOption(:final number) => '$number',
        PlaceOption(:final makkah) => makkah ? l.arenaMakkah : l.arenaMadinah,
        JuzOption(:final juz) => l.arenaJuz(juz),
      };
}

/// The option's letter, in a small seal.
class _Letter extends StatelessWidget {
  final int index;
  final ArenaOptionState state;
  const _Letter({required this.index, required this.state});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final letters = l.arabicScript ? const ['أ', 'ب', 'ج', 'د'] : const ['A', 'B', 'C', 'D'];
    final lit = state == ArenaOptionState.right;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(30, 30),
            painter: _SealBadgePainter(
              lit ? AppColors.goldBright : AppColors.gold.withValues(alpha: 0.35),
              lit,
            ),
          ),
          Text(
            letters[index.clamp(0, 3)],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: lit ? const Color(0xFF14100A) : AppColors.gold,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SealBadgePainter extends CustomPainter {
  final Color color;
  final bool filled;
  const _SealBadgePainter(this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Khatam.star(size.center(Offset.zero), size.shortestSide / 2);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(covariant _SealBadgePainter old) =>
      old.color != color || old.filled != filled;
}

/// Right, not this one, or out of time — and where the verse is.
class _Verdict extends StatelessWidget {
  final bool correct;
  final bool timedOut;
  final String reference;
  final bool hint;
  const _Verdict({
    required this.correct,
    required this.timedOut,
    required this.reference,
    this.hint = true,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final word = correct
        ? l.arenaRight
        : timedOut
            ? l.arenaTimeUp
            : l.arenaNotThis;
    return A11yLive(
      child: Rise(
        from: 8,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 18, color: correct ? AppColors.goldBright : ArenaPalette.wrong),
                const SizedBox(width: 7),
                Text(word,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: correct ? AppColors.goldBright : ArenaPalette.wrong)),
                const SizedBox(width: 10),
                _Cartouche(text: reference),
              ],
            ),
            if (hint) ...[
              const SizedBox(height: 8),
              Text(l.arenaTapToContinue,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A surah's name as a line: the transliteration in the reader's own
/// face and the Arabic after it in the mushaf's — or the Arabic alone
/// for a reader of Arabic script. The UI face has no Arabic, and a
/// name that fell back to whatever the phone had was the one thing on
/// the screen not set on purpose.
class SurahNameText extends StatelessWidget {
  final int surah;
  final TextStyle style;
  final TextAlign? textAlign;
  const SurahNameText({
    super.key,
    required this.surah,
    required this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = surahIndex[surah - 1];
    final size = style.fontSize ?? 15;
    final ink = style.color ?? AppColors.textPrimary;
    final arabic = AppTheme.quran(size: size * 1.12, color: ink).copyWith(
      height: 1.5,
      fontWeight: FontWeight.w400,
    );
    if (l.arabicScript) {
      return Text(s.nameArabic, style: arabic, textAlign: textAlign);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: s.nameEnglish, style: style),
        TextSpan(text: '   ', style: style),
        TextSpan(
          text: s.nameArabic,
          style: arabic.copyWith(color: ink.withValues(alpha: 0.78)),
        ),
      ]),
      textAlign: textAlign,
    );
  }
}

