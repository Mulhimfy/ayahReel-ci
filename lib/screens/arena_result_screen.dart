import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/arena_challenge.dart';
import '../data/arena_engine.dart';
import '../data/arena_service.dart';
import '../data/arena_share_report.dart';
import '../data/debug_log.dart';
import '../data/instagram_share.dart';
import '../data/rewards_service.dart';
import '../data/settings_service.dart';
import '../data/share_origin.dart';
import '../data/surah_index.dart';
import '../l10n/l10n.dart';
import '../render/arena_story.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/arena_constellation.dart';
import '../widgets/arena_fx.dart';
import '../widgets/direct_share_button.dart';
import '../widgets/glow_button.dart';
import '../widgets/illumination.dart';
import '../widgets/name_dialog.dart';
import '../widgets/night_sky.dart';
import '../widgets/popover.dart';
import 'arena_play_screen.dart';
import 'arena_screen.dart';

/// The end of a round, and the beginning of the next person's.
///
/// The card the round makes, shown in a light frame exactly as it will
/// be shared — the round drawing itself in on it, and a small menu
/// under it for what it carries (score, name, surah or juz), every
/// choice landing on the picture as it is made. Under that the score
/// in one small line with its standing in one word, and — the reason
/// the screen exists — the code with the three things to do with it,
/// and two doors out: the story, straight into Instagram's composer
/// with the code on the clipboard, and the share sheet with the same
/// picture and the code in the message. Against a code, the two scores stand
/// either side of a hairline. The review of every question waits
/// folded behind a gold button, so the top is the whole of what a
/// glance takes in.
///
/// The same screen opens a round out of the history, which is why it
/// takes a result rather than making one, and files it only when told.
class ArenaResultScreen extends StatefulWidget {
  final ArenaRound round;
  final ArenaResult result;
  final ArenaMode mode;

  /// The player's name at the time, empty when nameless.
  final String me;

  /// The code that was answered, when one was.
  final ArenaChallenge? challenge;

  /// Who sent it, when the link said.
  final String rival;

  /// Whether this is the round's first showing, to be filed.
  final bool file;

  /// When it was played, for a round opened from the history.
  final DateTime? playedAt;

  const ArenaResultScreen({
    super.key,
    required this.round,
    required this.result,
    required this.mode,
    this.me = '',
    this.challenge,
    this.rival = '',
    this.file = true,
    this.playedAt,
  });

  @override
  State<ArenaResultScreen> createState() => _ArenaResultScreenState();
}

class _ArenaResultScreenState extends State<ArenaResultScreen> {
  final _burst = BurstController();
  bool _newBest = false;
  bool _storyBusy = false;
  bool _shareBusy = false;
  bool _review = false;

  /// Set for a moment after the story button copies the code, so the
  /// button itself says so before Instagram opens over it.
  bool _storyCopied = false;
  Timer? _copiedOff;

  /// The card on screen, for where the burst goes off.
  final _cardKey = GlobalKey();

  ArenaResult get _r => widget.result;
  ArenaChallenge? get _against => widget.challenge;

  /// The code this round makes: the same questions, and the score to
  /// beat.
  ArenaChallenge get _code => ArenaChallenge(
        setup: _r.setup.copyWith(count: ArenaChallenge.questions),
        seed: _r.seed,
        score: _r.score,
        correct: _r.correct,
      );

  late final List<ConstellationNode> _nodes =
      ConstellationNode.ofRound(widget.round.questions, _r.answers);

  String get _name =>
      widget.me.trim().isNotEmpty ? widget.me.trim() : SettingsService.state.value.name.trim();

  String _rivalName(L10n l) =>
      widget.rival.trim().isEmpty ? l.arenaTheCode : widget.rival.trim();

  @override
  void initState() {
    super.initState();
    if (widget.file) unawaited(_file());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        _burst.fire(_cardHeart(), scale: 1.5);
        HapticFeedback.mediumImpact();
      });
    });
  }

  Future<void> _file() async {
    // A rematch is played in the challenge's mode — free, with a code
    // to send back — but nobody stands on the other side yet, so it is
    // filed as a round of one's own rather than as a win over nobody.
    final mode = widget.mode == ArenaMode.challenge && _against == null
        ? ArenaMode.solo
        : widget.mode;
    final best = await ArenaService.record(
      _r,
      mode: mode,
      me: _name,
      rival: widget.rival,
      rivalScore: _against?.score ?? 0,
      rivalCorrect: _against?.correct ?? 0,
      code: _against?.code ?? '',
      verses: ArenaRecord.versesOf(widget.round, _r.asked),
    );
    if (mounted && best) setState(() => _newBest = true);
  }

  /// Where the round sits on the card on screen: the burst goes off
  /// from its heart. The middle of the screen's top half when the card
  /// is not laid out (yet).
  Offset _cardHeart() {
    final box = _cardKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(
          Offset(box.size.width / 2, box.size.height * 0.56));
    }
    final size = MediaQuery.sizeOf(context);
    return Offset(size.width / 2, size.height * 0.32);
  }

  @override
  void dispose() {
    _burst.dispose();
    _copiedOff?.cancel();
    super.dispose();
  }

  void _say(String s, [ToastTone tone = ToastTone.info]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(toast(s, tone: tone));
  }

  /// The name as the card carries it: none when its menu leaves it off.
  String get _cardName =>
      SettingsService.state.value.arenaCardName ? _name : '';

  String _message(L10n l) => l.arenaShareMessage(
        name: _cardName,
        score: _r.score,
        correct: _r.correct,
        asked: _r.asked,
        scope: arenaScopeLabel(l, _r.setup.scope),
        code: _code.code,
        showScore: SettingsService.state.value.arenaCardScore,
      );

  /// The card as its menu has it at the moment of sharing — the same
  /// picture the frame on screen shows.
  Future<File> _card(L10n l) {
    final s = SettingsService.state.value;
    return ArenaStory.render(
      l: l,
      nodes: _nodes,
      seed: _r.seed,
      name: _cardName,
      score: _r.score,
      correct: _r.correct,
      asked: _r.asked,
      scope: arenaScopeLabel(l, _r.setup.scope),
      tier: _r.tier,
      rival: _against == null ? null : _rivalName(l),
      rivalScore: _against?.score,
      showScore: s.arenaCardScore,
      showScope: s.arenaCardScope,
    );
  }

  /// Tells the inbox a share was tapped, and through which door: who
  /// shared (new or not, how many reels), the round, the card as it
  /// goes, and the shares before it. See [ArenaShareReport]. On the tap,
  /// behind it — never in the way of the share.
  void _report(ArenaShareDoor door) {
    final s = SettingsService.state.value;
    unawaited(ArenaShareReport.tapped(ArenaShareFacts(
      door: door,
      result: _r,
      mode: widget.mode,
      scope: arenaScopeLabel(L10n.en, _r.setup.scope),
      rivalScore: _against?.score,
      cardScore: s.arenaCardScore,
      cardScope: s.arenaCardScope,
      cardName: s.arenaCardName && _name.isNotEmpty,
      nameSet: _name.isNotEmpty,
      playedAt: widget.playedAt,
    )));
  }

  /// A challenge went out: the app's own share reward is earned the
  /// way any invitation earns it.
  Future<void> _sent() async {
    unawaited(ArenaService.sent());
    unawaited(RewardsService.recordAppShared());
    _say(L10n.current.arenaChallengeSent, ToastTone.done);
  }

  Future<void> _toStory(BuildContext buttonContext) async {
    if (_storyBusy || _storyCopied) return;
    final l = L10n.of(context);
    final origin = shareOriginOf(buttonContext);
    HapticFeedback.selectionClick();
    _report(ArenaShareDoor.instagramStory);
    setState(() => _storyBusy = true);
    try {
      final card = await _card(l);
      // The picture carries no code — nobody can copy one off a story —
      // so it goes to the clipboard, to be pasted on as a sticker. The
      // button says so itself, and holds still a beat for it to be
      // read, before Instagram opens over the screen.
      await Clipboard.setData(ClipboardData(text: _code.code));
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _copiedOff?.cancel();
      setState(() {
        _storyBusy = false;
        _storyCopied = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 950));
      if (!mounted) return;
      final handed = await InstagramShare.shareStory(card);
      _copiedOff = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _storyCopied = false);
      });
      if (handed) {
        unawaited(ArenaService.sent());
        unawaited(RewardsService.recordAppShared());
        return;
      }
      _say(l.instagramUnavailable, ToastTone.problem);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(card.path, mimeType: 'image/png')],
        text: _message(l),
        sharePositionOrigin: origin,
      ));
      if (result.status != ShareResultStatus.dismissed) await _sent();
    } catch (e, s) {
      rlogError('arena story', e, s);
      _say(l.shareFailed(e), ToastTone.problem);
    } finally {
      if (mounted) setState(() => _storyBusy = false);
    }
  }

  Future<void> _shareCard(BuildContext buttonContext) async {
    if (_shareBusy) return;
    final l = L10n.of(context);
    final origin = shareOriginOf(buttonContext);
    HapticFeedback.selectionClick();
    _report(ArenaShareDoor.shareCard);
    setState(() => _shareBusy = true);
    try {
      final card = await _card(l);
      if (!mounted) return;
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(card.path, mimeType: 'image/png')],
        text: _message(l),
        sharePositionOrigin: origin,
      ));
      if (result.status != ShareResultStatus.dismissed) await _sent();
    } catch (e, s) {
      rlogError('arena share', e, s);
      _say(l.shareFailed(e), ToastTone.problem);
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  Future<void> _copy() async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: _code.code));
    _say(L10n.current.arenaCodeCopied, ToastTone.done);
  }

  /// The same setup again, on a new seed — after a challenge, a fresh
  /// round to send back.
  void _again() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(BloomRoute(
      builder: (_) => ArenaPlayScreen(
        setup: _r.setup.copyWith(count: ArenaChallenge.questions),
        seed: ArenaRound.newSeed(),
        mode: widget.mode,
        me: widget.me,
      ),
    ));
  }

  void _replay(int i) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(BloomRoute(
      builder: (_) => ArenaReplayScreen(
        question: widget.round.questions[i],
        answer: _r.answers[i],
        index: i,
        count: _r.asked,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final r = _r;
    final against = _against;
    // The card is the scene: the whole width of a phone, edge to edge.
    // On a tablet it stops at a tall phone's width rather than run a
    // screen and a half high.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = math.min(screenWidth, 480.0);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MeshBackdrop(alpha: 0.5, speed: 0.6, seed: 8),
          const IgnorePointer(child: Starfield(count: 90, seed: 9)),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                  sliver: SliverToBoxAdapter(
                    child: _TopRow(
                      title: widget.playedAt == null
                          ? l.arenaRoundOver
                          : l.formatDate(widget.playedAt!),
                    ),
                  ),
                ),
                // The card, as it will go, and no frame around it: the
                // whole width, its night running into the page's, the
                // round drawing itself in on it. Out of the page's
                // margins for that. The small menu of what it carries
                // sits in its faded foot, by the card's own edge.
                SliverToBoxAdapter(
                  child: Rise(
                    child: Stack(
                      children: [
                        _CardPreview(
                          key: _cardKey,
                          width: cardWidth,
                          fadeSides: cardWidth < screenWidth,
                          nodes: _nodes,
                          result: r,
                          name: () => _name,
                          rival: against == null ? null : _rivalName(l),
                          rivalScore: against?.score,
                        ),
                        PositionedDirectional(
                          end: (screenWidth - cardWidth) / 2 + 22,
                          bottom: 2,
                          child: _CardMenuChip(
                            scope: r.setup.scope.kind,
                            name: () => _name,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 140),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Rise(
                        delay: const Duration(milliseconds: 200),
                        child: Column(
                          children: [
                            // The number and its word are the card's
                            // own, at the head of the scene; here only
                            // when its menu leaves them off it.
                            ValueListenableBuilder<AppSettings>(
                              valueListenable: SettingsService.state,
                              builder: (context, s, _) => s.arenaCardScore
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _ScoreLine(
                                        score: r.score,
                                        tier: l.arenaTierName(r.tier),
                                      ),
                                    ),
                            ),
                            Text(
                              '${l.arenaRightOf(r.correct, r.asked)} · '
                              '${arenaScopeLabel(l, r.setup.scope)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppColors.textSecondary),
                            ),
                            if (r.bestRun >= 3) ...[
                              const SizedBox(height: 5),
                              Text(l.arenaBestRun(r.bestRun),
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.gold)),
                            ],
                            if (_newBest) ...[
                              const SizedBox(height: 12),
                              Glint(
                                every: const Duration(seconds: 4),
                                child: ClipPath(
                                  clipper: const CartoucheClipper(),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(22, 6, 22, 6),
                                    color: AppColors.gold.withValues(alpha: 0.3),
                                    child: Text(l.arenaNewBest,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                            color: AppColors.goldBright)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (against != null) ...[
                        const SizedBox(height: 22),
                        Rise(
                          delay: const Duration(milliseconds: 260),
                          child: _Versus(
                            me: _name.isEmpty ? l.arenaYou : _name,
                            score: r.score,
                            rival: _rivalName(l),
                            rivalScore: against.score,
                            verdict: r.score > against.score
                                ? l.arenaYouBeat(_rivalName(l))
                                : r.score == against.score
                                    ? l.arenaLevelWith(_rivalName(l))
                                    : l.arenaStillLeads(_rivalName(l)),
                            lit: r.score >= against.score,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Rise(
                        delay: const Duration(milliseconds: 320),
                        child: Column(
                          children: [
                            _CodePlate(code: _code.code, onCopy: _copy),
                            const SizedBox(height: 12),
                            const _Steps(),
                            const SizedBox(height: 16),
                            Builder(
                              builder: (bc) => DirectShareButton(
                                label: _storyCopied
                                    ? l.arenaYourCodeCopied
                                    : l.sendToInstagramStory,
                                icon: _storyCopied
                                    ? Icons.check_rounded
                                    : Icons.auto_awesome_rounded,
                                colors: instagramMesh,
                                height: 52,
                                busy: _storyBusy,
                                onPressed: () => _toStory(bc),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Builder(
                              builder: (bc) => GlowButton(
                                label: l.arenaShareCard,
                                icon: Icons.ios_share_rounded,
                                breathe: true,
                                height: 54,
                                busy: _shareBusy,
                                onPressed: () => _shareCard(bc),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ReviewButton(
                              open: _review,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _review = !_review);
                              },
                            ),
                            const SizedBox(height: 2),
                            QuietButton(
                              label: against != null
                                  ? l.arenaRematch
                                  : l.arenaPlayAgain,
                              icon: Icons.replay_rounded,
                              onPressed: _again,
                            ),
                            const SizedBox(height: 16),
                            const _SharePitch(),
                          ],
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _review
                            ? Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: _Review(
                                  round: widget.round,
                                  result: r,
                                  onOpen: _replay,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(child: GoldBurst(controller: _burst, count: 64)),
        ],
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  final String title;
  const _TopRow({required this.title});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      children: [
        A11yTap(
          label: MaterialLocalizations.of(context).closeButtonLabel,
          onTap: () => Navigator.of(context).pop(),
          child: Pressable(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface.withValues(alpha: 0.6),
                border: Border.all(color: AppColors.stroke),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textPrimary),
            ),
          ),
        ),
        const Spacer(),
        Text(title,
            style: TextStyle(
                fontSize: 11.5,
                letterSpacing: l.arabicScript ? 0 : 1.8,
                color: AppColors.gold,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        const SizedBox(width: 38),
      ],
    );
  }
}

/// The score in one line under the round: the number counting up and
/// its one word beside it. Small on purpose — the picture is the
/// constellation; this is its caption.
class _ScoreLine extends StatelessWidget {
  final int score;
  final String tier;
  const _ScoreLine({required this.score, required this.tier});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Semantics(
      label: '${l.arenaScore} $score, $tier',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF2CE), Color(0xFFEEC96B), Color(0xFFC9973B)],
            ).createShader(rect),
            child: CountUp(
              value: score,
              duration: const Duration(milliseconds: 1600),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            tier.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: l.arabicScript ? 0 : 2,
              color: AppColors.goldBright,
            ),
          ),
        ],
      ),
    );
  }
}

/// The card exactly as the share buttons will send it, before it goes:
/// the very widget the picture is rasterized from, the whole width of
/// the screen and framed by nothing — its top and foot fade into the
/// page — and redrawn the moment its menu changes what it carries.
///
/// The round draws itself in on it as it did at the top of this screen
/// before; the rasterized picture keeps the still one.
class _CardPreview extends StatelessWidget {
  final double width;

  /// Whether the card is narrower than the screen, so its sides fade
  /// into the page as its top and foot do. On a phone it runs edge to
  /// edge and has no sides to show.
  final bool fadeSides;
  final List<ConstellationNode> nodes;
  final ArenaResult result;
  final String Function() name;
  final String? rival;
  final int? rivalScore;

  const _CardPreview({
    super.key,
    required this.width,
    required this.fadeSides,
    required this.nodes,
    required this.result,
    required this.name,
    required this.rival,
    required this.rivalScore,
  });

  /// Opaque in the middle, nothing at the ends: as a mask, the card
  /// melting into what is behind it over its first and last [edge].
  static Shader _fade(Rect rect, {required bool across, double edge = 0.07}) =>
      LinearGradient(
        begin: across ? Alignment.centerLeft : Alignment.topCenter,
        end: across ? Alignment.centerRight : Alignment.bottomCenter,
        colors: const [
          Color(0x00FFFFFF),
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(rect);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final height = width * ArenaStory.height / ArenaStory.width;
    // The picture is laid out at its own 1080 wide, text scale and
    // all, so what is on screen is what is sent.
    Widget card = MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: FittedBox(
        fit: BoxFit.cover,
        child: ValueListenableBuilder<AppSettings>(
          valueListenable: SettingsService.state,
          builder: (context, s, _) => ArenaStoryCard(
            l: l,
            nodes: nodes,
            seed: result.seed,
            name: s.arenaCardName ? name() : '',
            score: result.score,
            correct: result.correct,
            asked: result.asked,
            scope: arenaScopeLabel(l, result.setup.scope),
            tier: result.tier,
            rival: rival,
            rivalScore: rivalScore,
            showScore: s.arenaCardScore,
            showScope: s.arenaCardScope,
            constellation: ConstellationReveal(nodes: nodes, seed: result.seed),
          ),
        ),
      ),
    );
    // No frame, no corners, no shadow under it: the card's top and foot
    // fade out, and the page is the card's night going on.
    card = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => _fade(rect, across: false),
      child: card,
    );
    if (fadeSides) {
      card = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => _fade(rect, across: true, edge: 0.1),
        child: card,
      );
    }
    // Heard as a picture — and, while the card carries the score, as
    // the score too: the line under it that said so gives way to it.
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, child) => Semantics(
        container: true,
        image: true,
        label: s.arenaCardScore
            ? '${l.a11yArenaCardPreview}. ${l.arenaScore} ${result.score}'
                '${l.comma} ${l.arenaTierName(result.tier)}'
            : l.a11yArenaCardPreview,
        excludeSemantics: true,
        child: child,
      ),
      child: Center(
        child: SizedBox(width: width, height: height, child: card),
      ),
    );
  }
}

/// The one control for what the card carries: a small pill in the
/// card's faded foot, by its corner, that opens a menu of three — the score, the name, the
/// surah or juz — each switched on the spot, the card above changing
/// with it. The pill says how many of the three are on.
class _CardMenuChip extends StatelessWidget {
  final ArenaScopeKind scope;
  final String Function() name;
  const _CardMenuChip({required this.scope, required this.name});

  void _open(BuildContext context) {
    showPopover<void>(
      context,
      builder: (_) => _CardMenu(scope: scope, name: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) {
        final hasName = name().isNotEmpty;
        final on = [
          s.arenaCardScore,
          if (hasName) s.arenaCardName,
          s.arenaCardScope,
        ].where((b) => b).length;
        final of = hasName ? 3 : 2;
        return A11yTap(
          label: l.arenaCardMenu,
          hint: l.arenaCardMenuHint(on, of),
          onTap: () => _open(context),
          child: Pressable(
            onTap: () => _open(context),
            child: Container(
              height: 32,
              padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.35), width: 0.9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune_rounded,
                      size: 14, color: AppColors.goldBright),
                  const SizedBox(width: 6),
                  Text(
                    l.arenaCardMenu,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: l.arabicScript ? 0 : 0.2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // How many of the three are on, as dots.
                  for (var i = 0; i < of; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 4.5,
                        height: 4.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < on
                              ? AppColors.goldBright
                              : AppColors.textSecondary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The menu itself: three rows, each a word and a gold check that
/// lights and goes out in place. Nobody is asked to confirm; the card
/// behind is the confirmation. Without a name to carry, the name row
/// offers to add one.
class _CardMenu extends StatelessWidget {
  final ArenaScopeKind scope;
  final String Function() name;
  const _CardMenu({required this.scope, required this.name});

  Future<void> _addName(BuildContext context) async {
    HapticFeedback.selectionClick();
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => const NameDialog(initial: ''),
    );
    if (picked == null || picked.isEmpty) return;
    await SettingsService.update(SettingsService.state.value
        .copyWith(name: picked, arenaCardName: true));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.state,
      builder: (context, s, _) {
        // Read at the tap, not at the build: two quick taps must not
        // undo each other through a menu drawn before the first landed.
        void flip(AppSettings Function(AppSettings now) change) {
          HapticFeedback.selectionClick();
          SettingsService.update(change(SettingsService.state.value));
        }

        final hasName = name().isNotEmpty;
        return Container(
          width: 228,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xF51A2029),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuRow(
                label: l.arenaCardScore,
                on: s.arenaCardScore,
                onTap: () => flip(
                    (v) => v.copyWith(arenaCardScore: !v.arenaCardScore)),
              ),
              _MenuRow(
                label: hasName ? l.arenaCardName : l.arenaAddName,
                on: hasName ? s.arenaCardName : null,
                onTap: hasName
                    ? () => flip(
                        (v) => v.copyWith(arenaCardName: !v.arenaCardName))
                    : () => _addName(context),
              ),
              _MenuRow(
                label: l.arenaCardScope(scope),
                on: s.arenaCardScope,
                onTap: () => flip(
                    (v) => v.copyWith(arenaCardScope: !v.arenaCardScope)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One line of the card's menu. [on] null makes it an action rather
/// than a switch — a plus where the check would be.
class _MenuRow extends StatelessWidget {
  final String label;
  final bool? on;
  final VoidCallback onTap;
  const _MenuRow({required this.label, required this.on, required this.onTap});

  static const _ease = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final lit = on ?? false;
    return A11yTap(
      label: label,
      toggled: on,
      button: on == null,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 11, 14, 11),
          child: Row(
            children: [
              Expanded(
                // From the theme, so the face is the app's: an
                // animated style replaces the one around it whole.
                child: AnimatedDefaultTextStyle(
                  duration: _ease,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: on == null
                            ? AppColors.goldBright
                            : lit
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                      ),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              if (on == null)
                const Icon(Icons.add_rounded,
                    size: 18, color: AppColors.goldBright)
              else
                AnimatedContainer(
                  duration: _ease,
                  curve: Curves.easeOutBack,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: lit ? AppColors.gold : Colors.transparent,
                    border: Border.all(
                      color: lit
                          ? AppColors.goldBright
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                      width: 1.4,
                    ),
                    boxShadow: lit
                        ? [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.45),
                              blurRadius: 10,
                            ),
                          ]
                        : const [],
                  ),
                  child: AnimatedScale(
                    duration: _ease,
                    curve: Curves.easeOutBack,
                    scale: lit ? 1 : 0,
                    child: const Icon(Icons.check_rounded,
                        size: 13, color: Color(0xFF14100A)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What to do with the code, in three glances: copy it, share it, see
/// who beats it on the same ten.
class _Steps extends StatelessWidget {
  const _Steps();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget step(IconData icon, String text) => Expanded(
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.10),
                  border:
                      Border.all(color: AppColors.gold.withValues(alpha: 0.38)),
                ),
                child: Icon(icon, size: 14, color: AppColors.goldBright),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                    fontSize: 11, height: 1.25, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
    final arrow = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Icon(Icons.chevron_right_rounded,
          size: 18, color: AppColors.gold.withValues(alpha: 0.6)),
    );
    return Semantics(
      label: '${l.arenaStepCopy}${l.comma} ${l.arenaStepShare}${l.comma} '
          '${l.arenaStepCompare}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          step(Icons.copy_rounded, l.arenaStepCopy),
          arrow,
          step(Icons.send_rounded, l.arenaStepShare),
          arrow,
          step(Icons.leaderboard_rounded, l.arenaStepCompare),
        ],
      ),
    );
  }
}

/// Why the code is worth sending, under the buttons: a card of three
/// short lines, each a different pull (the owner's ask, 2026-10-26) —
/// it is fair and it is theirs too (the same ten questions, in the same
/// order: the code is the seed, see ArenaRound.generate), it is a
/// friendly contest (the score is the one to beat), and it is a good
/// deed passed on (the hadith of the one who guides to good).
class _SharePitch extends StatelessWidget {
  const _SharePitch();

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget row(IconData icon, String text, {String? source}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.12),
                  border:
                      Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: Icon(icon, size: 13, color: AppColors.goldBright),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: text),
                    if (source != null)
                      TextSpan(
                        text: '  $source',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.gold.withValues(alpha: 0.85),
                        ),
                      ),
                  ]),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gold.withValues(alpha: 0.10),
            AppColors.surface.withValues(alpha: 0.6),
          ],
        ),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.arenaPitchTitle,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: AppColors.goldBright,
            ),
          ),
          row(Icons.copy_rounded, l.arenaPitchSame),
          row(Icons.leaderboard_rounded, l.arenaPitchBeat),
          row(Icons.auto_awesome_rounded, l.arenaPitchReward,
              source: l.arenaPitchRewardSource),
        ],
      ),
    );
  }
}

/// The review's door: a gold line of a button, its chevron turning
/// over when the review is open.
class _ReviewButton extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;
  const _ReviewButton({required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final label = open ? l.arenaHideReview : l.arenaShowReview;
    return A11yTap(
      label: label,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: Glint(
          every: const Duration(milliseconds: 6200),
          strength: 0.5,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [
                AppColors.gold.withValues(alpha: 0.08),
                AppColors.gold.withValues(alpha: 0.18),
                AppColors.gold.withValues(alpha: 0.08),
              ]),
              border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.62), width: 1.1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fact_check_rounded,
                    size: 18, color: AppColors.goldBright),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.goldBright)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more_rounded,
                      size: 20, color: AppColors.goldBright),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two scores either side of a hairline, the higher one lit, and one
/// line saying how they stand.
class _Versus extends StatelessWidget {
  final String me;
  final int score;
  final String rival;
  final int rivalScore;
  final String verdict;
  final bool lit;
  const _Versus({
    required this.me,
    required this.score,
    required this.rival,
    required this.rivalScore,
    required this.verdict,
    required this.lit,
  });

  @override
  Widget build(BuildContext context) {
    Widget side(String who, int n, bool bright) => Expanded(
          child: Column(
            children: [
              Text(who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 3),
              Text('$n',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: bright ? AppColors.goldBright : AppColors.textPrimary,
                  )),
            ],
          ),
        );
    return Column(
      children: [
        Row(
          children: [
            side(me, score, score >= rivalScore),
            Container(
              width: 1.2,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.gold.withValues(alpha: 0),
                    AppColors.gold.withValues(alpha: 0.7),
                    AppColors.gold.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            side(rival, rivalScore, rivalScore >= score),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          verdict,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: lit ? AppColors.goldBright : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// The code, in a cartouche, with a tap that copies it.
class _CodePlate extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;
  const _CodePlate({required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return A11yTap(
      label: '${l.arenaYourCode} $code',
      hint: MaterialLocalizations.of(context).copyButtonLabel,
      onTap: onCopy,
      child: Pressable(
        onTap: onCopy,
        child: Glint(
          every: const Duration(milliseconds: 4800),
          child: ClipPath(
            clipper: const CartoucheClipper(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(30, 10, 30, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.10),
                    AppColors.gold.withValues(alpha: 0.26),
                    AppColors.gold.withValues(alpha: 0.10),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Text(l.arenaYourCode,
                      style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: l.arabicScript ? 0 : 1.6,
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GildedText(
                          code,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.copy_rounded,
                            size: 15, color: AppColors.gold),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every question, with what was answered and what was right.
class _Review extends StatelessWidget {
  final ArenaRound round;
  final ArenaResult result;
  final ValueChanged<int> onOpen;
  const _Review({required this.round, required this.result, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionRule(title: l.arenaReview),
        const SizedBox(height: 12),
        for (var i = 0; i < result.answers.length && i < round.questions.length; i++)
          Rise(
            delay: Duration(milliseconds: 40 * i),
            from: 8,
            child: _ReviewRow(
              q: round.questions[i],
              answer: result.answers[i],
              onTap: () => onOpen(i),
            ),
          ),
      ],
    );
  }
}

/// One option as a line of text, for the review.
String arenaOptionLabel(L10n l, ArenaOption o) => switch (o) {
      VerseOption(:final text) => text,
      SurahOption(:final surah) => l.arabicScript
          ? surahIndex[surah - 1].nameArabic
          : '${surahIndex[surah - 1].nameEnglish} · ${surahIndex[surah - 1].nameArabic}',
      NumberOption(:final number) => '$number',
      PlaceOption(:final makkah) => makkah ? l.arenaMakkah : l.arenaMadinah,
      JuzOption(:final juz) => l.arenaJuz(juz),
    };

class _ReviewRow extends StatelessWidget {
  final ArenaQuestion q;
  final ArenaAnswer answer;
  final VoidCallback onTap;
  const _ReviewRow({required this.q, required this.answer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final ok = answer.correct;
    final option = q.correctOption;
    final String right = switch (q.game) {
      ArenaGame.orderWords => [for (final i in q.order) q.tokens[i]].join(' '),
      ArenaGame.missingWord => q.tokens[q.blank],
      _ => option is SurahOption ? '' : arenaOptionLabel(l, option!),
    };
    final arabic = q.game != ArenaGame.surahFacts;
    final surahAnswer = q.game == ArenaGame.surahFacts && option is SurahOption
        ? option.surah
        : q.game == ArenaGame.whichSurah
            ? q.surah
            : null;
    // What was tapped instead, when there was a tap and it is a thing
    // that can be shown: not for ordering, which keeps no sequence.
    final chosen = !ok &&
            q.game != ArenaGame.orderWords &&
            answer.chosen >= 0 &&
            answer.chosen < q.options.length
        ? q.options[answer.chosen]
        : null;
    final chosenSurah = chosen is SurahOption ? chosen.surah : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: A11yTap(
        label: '${arenaPromptFor(l, q)}. ${ok ? l.arenaRight : l.arenaNotThis}.',
        hint: l.a11yShowsQuestion,
        onTap: onTap,
        child: Pressable(
          onTap: onTap,
          scale: 0.985,
          child: TouchLight(
            radius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.66),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: ok
                        ? AppColors.gold.withValues(alpha: 0.35)
                        : ArenaPalette.wrong.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 18, color: ok ? AppColors.goldBright : ArenaPalette.wrong),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l.arenaGameName(q.game)} · ${arenaReferenceOf(l, q)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                        if (!ok) ...[
                          const SizedBox(height: 6),
                          _Chosen(
                            answer: answer,
                            chosen: chosen,
                            chosenSurah: chosenSurah,
                          ),
                        ],
                        const SizedBox(height: 5),
                        if (surahAnswer != null)
                          SurahNameText(
                            surah: surahAnswer,
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.textPrimary),
                          )
                        else
                          Text(
                            right,
                            textDirection: arabic ? TextDirection.rtl : null,
                            textAlign: arabic ? TextAlign.right : null,
                            style: arabic
                                ? AppTheme.quran(size: 17, color: AppColors.textPrimary)
                                    .copyWith(height: 1.8)
                                : const TextStyle(
                                    fontSize: 14, color: AppColors.textPrimary),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '+${answer.points}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ok ? AppColors.goldBright : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// What was tapped instead, struck through: the label in the reader's
/// face, the Quran's words in the mushaf's own, so neither is set in a
/// face that cannot draw it.
class _Chosen extends StatelessWidget {
  final ArenaAnswer answer;
  final ArenaOption? chosen;
  final int? chosenSurah;
  const _Chosen({required this.answer, this.chosen, this.chosenSurah});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final ink = ArenaPalette.wrong.withValues(alpha: 0.9);
    final line = ArenaPalette.wrong.withValues(alpha: 0.6);
    final label = TextStyle(fontSize: 12, color: ink);
    final struck = TextStyle(
      fontSize: 12,
      color: ink,
      decoration: TextDecoration.lineThrough,
      decorationColor: line,
    );
    final c = chosen;
    final String what;
    TextStyle style = struck;
    // No option chosen (in a round kept from when rounds had a clock,
    // one that ran out): only that it wasn't this.
    if (answer.chosen < 0 || c == null) {
      return Text(l.arenaNotThis, style: label);
    } else if (chosenSurah != null) {
      what = l.arabicScript
          ? surahIndex[chosenSurah! - 1].nameArabic
          : surahIndex[chosenSurah! - 1].nameEnglish;
    } else {
      what = arenaOptionLabel(l, c);
      if (c is VerseOption) {
        style = AppTheme.quran(size: 15, color: ink).copyWith(
          height: 1.4,
          decoration: TextDecoration.lineThrough,
          decorationColor: line,
        );
      }
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '${l.arenaYourAnswer}: ', style: label),
        TextSpan(text: what, style: style),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
