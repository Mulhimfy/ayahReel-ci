import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/arena_challenge.dart';
import '../data/arena_engine.dart';
import '../data/arena_service.dart';
import '../data/settings_service.dart';
import '../data/surah_index.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/app_toast.dart';
import '../widgets/arena_fx.dart';
import '../widgets/arena_guide.dart';
import '../widgets/arena_history.dart';
import '../widgets/glow_button.dart';
import '../widgets/illumination.dart';
import '../widgets/night_sky.dart';
import '../widgets/surah_picker_sheet.dart';
import '../widgets/tanafus_button.dart' show markArenaSeen;
import 'arena_play_screen.dart';

/// 83:26, as the mushaf sets it — the verse over the arena's door.
const arenaVerse =
    'خِتَـٰمُهُۥ مِسْكٌ ۚ وَفِى ذَٰلِكَ فَلْيَتَنَافَسِ ٱلْمُتَنَـٰفِسُونَ';

/// The lobby's route while it is open. Every door (the shell's button,
/// a link, a notification, the Cards tab's portal) comes through
/// [openArena], so this keeps a second lobby from opening over the
/// first. Asked whether it is still in a navigator rather than kept as
/// a flag, which a route removed some other way would leave set.
Route<void>? _arenaRoute;

/// Opens the arena, rising out of a bloom at the top of the screen.
Future<void> openArena(BuildContext context) async {
  if (_arenaRoute?.isActive ?? false) return;
  unawaited(markArenaSeen());
  final route = BloomRoute<void>(builder: (_) => const ArenaScreen());
  _arenaRoute = route;
  await Navigator.of(context).push(route);
  if (identical(_arenaRoute, route)) _arenaRoute = null;
}

/// The setup the lobby remembers, read from the arena's prefs.
ArenaSetup rememberedArenaSetup(Map<String, String> p,
    {required bool askMeanings}) {
  final scope = ArenaScope.fromKey(p['scope'] ?? '') ?? const ArenaScope.juz(30);
  var seconds = int.tryParse(p['seconds'] ?? '') ?? ArenaSetup.defaultSeconds;
  if (!ArenaSetup.secondsOptions.contains(seconds)) {
    seconds = ArenaSetup.defaultSeconds;
  }
  final games = (p['games'] ?? '')
      .split(',')
      .where((g) => g.isNotEmpty)
      .map((g) => ArenaGame.values.firstWhere((x) => x.name == g,
          orElse: () => ArenaGame.missingWord))
      .toSet();
  return ArenaSetup(
    scope: scope,
    games: games.isEmpty ? {...ArenaGame.values} : games,
    seconds: seconds,
    count: ArenaChallenge.questions,
    askMeanings: askMeanings,
  );
}

/// The name of a scope in the reader's language.
String arenaScopeLabel(L10n l, ArenaScope scope) => switch (scope.kind) {
      ArenaScopeKind.quran => l.arenaWholeQuran,
      ArenaScopeKind.juz =>
        scope.value == 30 ? l.arenaJuzAmma : l.arenaJuz(scope.value),
      ArenaScopeKind.surah =>
        l.arenaSurah(surahIndex[scope.value - 1].nameEnglish),
    };

/// Tanafus's lobby: how you play, where, what is asked, how long a
/// question has, and the rounds already played.
///
/// Every choice is on one page and every one of them is remembered,
/// so the second visit is a look and a tap. A code — pasted, typed, or
/// arriving through a link — takes over the page the moment it is
/// recognised, because a friend's dare is the reason most people will
/// ever open this screen.
class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  ArenaMode _mode = ArenaMode.solo;
  ArenaScope _scope = const ArenaScope.juz(30);
  Set<ArenaGame> _games = {...ArenaGame.values};
  int _seconds = ArenaSetup.defaultSeconds;
  final _code = TextEditingController();
  ArenaChallenge? _challenge;
  String _sender = '';

  /// The code [_sender] came with. A different code typed or pasted
  /// over it is someone else's, and drops the name.
  String? _senderCode;
  ArenaCorpus? _corpus;
  Set<ArenaGame>? _feasible;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCode);
    ArenaService.pendingCode.addListener(_takePending);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await ArenaService.init();
    if (!mounted) return;
    final p = ArenaService.state.value.prefs;
    final kept = rememberedArenaSetup(p, askMeanings: true);
    setState(() {
      _scope = kept.scope;
      _seconds = kept.seconds;
      _games = kept.games;
    });
    _takePending();
    // The one-time note, before anything else asks for attention —
    // unless a friend's code is already on the page, which explains
    // itself better than any note.
    if (p['intro'] != '1' && _challenge == null) {
      unawaited(ArenaService.remember({'intro': '1'}));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showArenaIntro(context);
      });
    }
    final corpus = await ArenaCorpus.load();
    if (!mounted) return;
    setState(() {
      _corpus = corpus;
      _feasible = corpus.feasible(_scope);
    });
  }

  /// A code the app was opened with: onto the page, and into the
  /// field, with the sender's name over it.
  void _takePending() {
    final code = ArenaService.pendingCode.value;
    if (code == null || !mounted) return;
    ArenaService.pendingCode.value = null;
    setState(() {
      _mode = ArenaMode.challenge;
      _sender = ArenaService.pendingSender;
      _senderCode =
          ArenaChallenge.parse(ArenaChallenge.find(code) ?? code)?.code;
      _code.text = code;
    });
  }

  void _onCode() {
    final c =
        ArenaChallenge.parse(ArenaChallenge.find(_code.text) ?? _code.text);
    if (c?.code == _challenge?.code) return;
    setState(() {
      _challenge = c;
      if (c != null && c.code != _senderCode) _sender = '';
    });
    if (c != null) HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    ArenaService.pendingCode.removeListener(_takePending);
    _code.removeListener(_onCode);
    _code.dispose();
    super.dispose();
  }

  L10n get _l => L10n.of(context);

  ArenaSetup get _setup => ArenaSetup(
        scope: _scope,
        games: _games,
        seconds: _seconds,
        count: ArenaChallenge.questions,
        askMeanings: !_l.ar,
      );

  void _setScope(ArenaScope s) {
    HapticFeedback.selectionClick();
    setState(() {
      _scope = s;
      _feasible = _corpus?.feasible(s);
    });
  }

  Future<void> _pickJuz() async {
    HapticFeedback.selectionClick();
    final juz = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _JuzSheet(selected: _scope.isJuz ? _scope.value : 0),
    );
    if (juz != null) _setScope(ArenaScope.juz(juz));
  }

  Future<void> _pickSurah() async {
    final pick = await showSurahPicker(context);
    if (pick != null) _setScope(ArenaScope.surah(pick.number));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    final found = ArenaChallenge.find(text);
    if (found != null) {
      _code.text = found;
    } else if (mounted) {
      _say(_l.arenaBadCode);
    }
  }

  /// The "?": how a round works. Words only — the way in is this page.
  void _openGuide() => showArenaGuide(context);

  void _say(String s, [ToastTone tone = ToastTone.problem]) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(toast(s, tone: tone));
  }

  Future<void> _begin() async {
    if (_starting || _corpus == null) return;
    final l = _l;
    HapticFeedback.mediumImpact();
    setState(() => _starting = true);
    try {
      unawaited(ArenaService.remember({
        'scope': _scope.key,
        'seconds': '$_seconds',
        'games': _games.map((g) => g.name).join(','),
      }));
      final me = SettingsService.state.value.name.trim();
      switch (_mode) {
        case ArenaMode.solo:
          await Navigator.of(context).push(BloomRoute(
            builder: (_) => ArenaPlayScreen(
              setup: _setup,
              seed: ArenaRound.newSeed(),
              mode: ArenaMode.solo,
              me: me,
            ),
          ));
        case ArenaMode.challenge:
          final c = _challenge;
          if (c == null) {
            _say(l.arenaBadCode);
            return;
          }
          await Navigator.of(context).push(BloomRoute(
            builder: (_) => ArenaPlayScreen(
              // The sender's setup exactly as the code carries it: one
              // flag changed here (meanings off for an Arabic reader)
              // changes the dice from the first surah-facts question on,
              // and the two would be scored on different rounds. A
              // meaning question then reads in English, as it would for
              // any reader whose language has no meanings.
              setup: c.setup,
              seed: c.seed,
              mode: ArenaMode.challenge,
              me: me,
              challenge: c,
              rival: _sender,
            ),
          ));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MeshBackdrop(alpha: 0.42, speed: 0.8, seed: 3),
          const IgnorePointer(child: Starfield(count: 70, seed: 11)),
          SafeArea(
            bottom: false,
            child: ValueListenableBuilder<ArenaState>(
              valueListenable: ArenaService.state,
              builder: (context, s, _) => CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _TopBar(onHelp: _openGuide)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Rise(
                            delay: const Duration(milliseconds: 40),
                            child: _Hero(l: l, t: t)),
                        const SizedBox(height: 18),
                        Rise(
                          delay: const Duration(milliseconds: 120),
                          child: _Section(
                            title: l.arenaModeTitle,
                            child: _ModeRow(
                              mode: _mode,
                              onSelect: (m) {
                                HapticFeedback.selectionClick();
                                setState(() => _mode = m);
                              },
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.only(
                                top: _mode == ArenaMode.solo ? 0 : 10),
                            child: _modeDetail(l),
                          ),
                        ),
                        if (_mode == ArenaMode.solo) ...[
                          const SizedBox(height: 16),
                          Rise(
                            delay: const Duration(milliseconds: 180),
                            child: _Section(
                              title: l.arenaScopeTitle,
                              child: _ScopeRow(
                                scope: _scope,
                                onScope: _setScope,
                                onJuz: _pickJuz,
                                onSurah: _pickSurah,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Rise(
                            delay: const Duration(milliseconds: 240),
                            child: _Section(
                              title: l.arenaGamesTitle,
                              child: _feasible == null
                                  ? const GlareBlock(height: 92)
                                  : _GameChips(
                                      games: _games,
                                      feasible: _feasible!,
                                      onToggle: (g) {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          final next = {..._games};
                                          if (next.contains(g)) {
                                            if (next.length > 1) {
                                              next.remove(g);
                                            }
                                          } else {
                                            next.add(g);
                                          }
                                          _games = next;
                                        });
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Rise(
                            delay: const Duration(milliseconds: 300),
                            child: _Section(
                              title: l.arenaSecondsTitle,
                              child: _SecondsRow(
                                seconds: _seconds,
                                onSelect: (v) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _seconds = v);
                                },
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Rise(
                          delay: const Duration(milliseconds: 340),
                          child: _cta(l),
                        ),
                        const SizedBox(height: 26),
                        Rise(
                          delay: const Duration(milliseconds: 400),
                          child: _Section(
                            title: l.arenaRecent,
                            trailing: s.bestFor(_setup) > 0
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                        '${l.arenaYourBest} · ${s.bestFor(_setup)}',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.goldBright,
                                            fontWeight: FontWeight.w700)),
                                  )
                                : null,
                            child: const ArenaHistoryStrip(),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeDetail(L10n l) {
    switch (_mode) {
      case ArenaMode.solo:
        // The door says it all; nothing under it.
        return const SizedBox(key: ValueKey('solo'), width: double.infinity);
      case ArenaMode.challenge:
        final c = _challenge;
        return _GlassCard(
          key: const ValueKey('challenge'),
          gold: c != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c == null
                    ? l.arenaHaveCode
                    : _sender.isEmpty
                        ? l.arenaCodeFromSomeone
                        : l.arenaCodeFrom(_sender),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c == null
                        ? AppColors.textSecondary
                        : AppColors.goldBright),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _CodeField(controller: _code, valid: c != null)),
                const SizedBox(width: 8),
                A11yTap(
                  label: MaterialLocalizations.of(context).pasteButtonLabel,
                  onTap: _paste,
                  child: Pressable(
                    onTap: _paste,
                    child: Container(
                      width: 44,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.stroke),
                      ),
                      child: const Icon(Icons.content_paste_rounded,
                          size: 18, color: AppColors.gold),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              if (c != null)
                Row(children: [
                  const SealGlyph(size: 8, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l.arenaCodeToBeat(c.score)} · '
                      '${arenaScopeLabel(l, c.setup.scope)} · '
                      '${l.arenaSecondsValue(c.setup.seconds)}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textPrimary,
                          height: 1.4),
                    ),
                  ),
                ])
              else
                Text(l.arenaChallengeHint,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4)),
            ],
          ),
        );
    }
  }

  Widget _cta(L10n l) {
    final loading = _corpus == null;
    final label = switch (_mode) {
      ArenaMode.solo => l.arenaBegin,
      ArenaMode.challenge => l.arenaPlayCode,
    };
    final enabled = !loading &&
        (_mode == ArenaMode.solo || _challenge != null);
    return GlowButton(
      label: loading ? l.arenaOpening : label,
      icon: Icons.play_arrow_rounded,
      breathe: enabled,
      busy: _starting,
      height: 52,
      onPressed: enabled ? _begin : null,
    );
  }
}

// ---------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final VoidCallback onHelp;
  const _TopBar({required this.onHelp});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        children: [
          A11yTap(
            label: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).maybePop(),
            child: Pressable(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface.withValues(alpha: 0.6),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_forward_ios_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  size: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const Spacer(),
          const TanafusMark(size: 15, glow: false),
          const SizedBox(width: 8),
          A11yHeader(
            child: Sheen(
              strength: 0.5,
              child: GildedText(
                l.arenaTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: l.arabicScript ? 0 : 2.2,
                ),
              ),
            ),
          ),
          const Spacer(),
          // How a round works, and where the code goes after it.
          A11yTap(
            label: l.arenaGuideTitle,
            onTap: onHelp,
            child: Pressable(
              onTap: onHelp,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.10),
                  border:
                      Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                ),
                child: const Text(
                  '?',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.goldBright,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The verse over the door, on glass, with the aurora showing through,
/// and the pitch under it.
class _Hero extends StatelessWidget {
  final L10n l;
  final TextTheme t;
  const _Hero({required this.l, required this.t});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        GlassPane(
          radius: BorderRadius.circular(24),
          tint: const Color(0x8C161B22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              children: [
                Sheen(
                  period: const Duration(milliseconds: 6000),
                  strength: 0.45,
                  child: GildedText(
                    arenaVerse,
                    textAlign: TextAlign.center,
                    style: AppTheme.quran(size: 21).copyWith(height: 1.8),
                  ),
                ),
                if (l.arenaVerseLine.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.arenaVerseLine,
                    textAlign: TextAlign.center,
                    style: AppTheme.translation(
                      size: 12.5,
                      arabic: l.arabicScript,
                      color: AppColors.textPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  l.verseReference('Al-Mutaffifin', 26, 26),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: l.arabicScript ? 0 : 1.6,
                    color: AppColors.gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Row(children: [
                  Expanded(child: OrnamentHairline(towardsEnd: false)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: SealGlyph(size: 8, color: AppColors.gold),
                  ),
                  Expanded(child: OrnamentHairline(towardsEnd: true)),
                ]),
                const SizedBox(height: 12),
                const ArenaPitch(compact: true),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: IlluminatedBorder(
              radius: BorderRadius.circular(24), sealSize: 8),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(title: title, trailing: trailing),
        const SizedBox(height: 9),
        child,
      ],
    );
  }
}

/// A heading with the rule running from its last word to the margin.
///
/// The app's [SectionRule] shares its row between the words and the
/// rule, which is right for a one-word heading and cuts a question
/// like "Where do you compete?" in half; here the words take what
/// they need and the rule takes the rest.
class _Heading extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _Heading({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      header: true,
      child: Row(
        children: [
          Flexible(
            flex: 0,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(fontSize: 15, letterSpacing: 0.1),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: OrnamentHairline(towardsEnd: true)),
          const SizedBox(width: 8),
          const SealGlyph(size: 7, color: Color(0x99D4A947)),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}

/// A pane of glass with a soft border, the body every choice on the
/// page is written on.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final bool gold;
  const _GlassCard({super.key, required this.child, this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: gold
                ? AppColors.gold.withValues(alpha: 0.5)
                : AppColors.stroke),
      ),
      child: child,
    );
  }
}

/// Play now, or beat a code: two doors, the open one lit.
class _ModeRow extends StatelessWidget {
  final ArenaMode mode;
  final ValueChanged<ArenaMode> onSelect;
  const _ModeRow({required this.mode, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget door(ArenaMode m, IconData icon, String label, String hint) {
      final on = m == mode;
      return Expanded(
        child: A11yTap(
          label: label,
          hint: hint,
          selected: on,
          onTap: () => onSelect(m),
          child: Pressable(
            onTap: () => onSelect(m),
            child: TouchLight(
              radius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: on
                      ? AppColors.gold.withValues(alpha: 0.13)
                      : AppColors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: on
                        ? AppColors.gold.withValues(alpha: 0.7)
                        : AppColors.stroke,
                    width: on ? 1.2 : 1,
                  ),
                  boxShadow: [
                    if (on)
                      BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.22),
                          blurRadius: 18),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon,
                        size: 19,
                        color:
                            on ? AppColors.goldBright : AppColors.textSecondary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
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

    return Row(
      children: [
        door(ArenaMode.solo, Icons.play_arrow_rounded, l.arenaSolo,
            l.arenaSoloHint),
        const SizedBox(width: 10),
        door(ArenaMode.challenge, Icons.bolt_rounded, l.arenaChallenge,
            l.arenaChallengeHint),
      ],
    );
  }
}

/// Where a code goes. Uppercased and grouped as it is typed, and gold
/// the moment it is a code.
class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final bool valid;
  const _CodeField({required this.controller, required this.valid});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      inputFormatters: [LengthLimitingTextInputFormatter(40)],
      style: TextStyle(
        fontSize: 17,
        letterSpacing: 2.2,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: valid ? AppColors.goldBright : AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'XXXX-XXXX-XXXX',
        hintStyle: TextStyle(
          letterSpacing: 2.2,
          color: AppColors.textSecondary.withValues(alpha: 0.6),
          fontSize: 15,
        ),
        isDense: true,
        filled: true,
        fillColor: AppColors.bg.withValues(alpha: 0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        suffixIcon: valid
            ? const Icon(Icons.verified_rounded,
                color: AppColors.goldBright, size: 20)
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: valid
                  ? AppColors.gold.withValues(alpha: 0.7)
                  : AppColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.gold.withValues(alpha: 0.85)),
        ),
      ),
    );
  }
}

/// The whole Quran, a juz, or a surah: three pills, the two pickers
/// wearing what they hold.
class _ScopeRow extends StatelessWidget {
  final ArenaScope scope;
  final ValueChanged<ArenaScope> onScope;
  final VoidCallback onJuz;
  final VoidCallback onSurah;

  const _ScopeRow({
    required this.scope,
    required this.onScope,
    required this.onJuz,
    required this.onSurah,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      children: [
        Expanded(
          child: _Pill(
            label: l.arenaWholeQuran,
            on: scope.isQuran,
            onTap: () => onScope(const ArenaScope.quran()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Pill(
            label: scope.isJuz ? arenaScopeLabel(l, scope) : l.arenaPickJuz,
            on: scope.isJuz,
            trailing: Icons.expand_more_rounded,
            onTap: onJuz,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Pill(
            label: scope.isSurah
                ? l.localizedSurahName(surahIndex[scope.value - 1].nameEnglish)
                : l.arenaPickSurah,
            on: scope.isSurah,
            trailing: Icons.expand_more_rounded,
            onTap: onSurah,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool on;
  final bool dim;
  final IconData? leading;
  final IconData? trailing;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.on,
    required this.onTap,
    this.dim = false,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      label: label,
      selected: on,
      enabled: !dim,
      onTap: onTap,
      child: Pressable(
        onTap: dim ? null : onTap,
        scale: 0.95,
        child: Opacity(
          opacity: dim ? 0.38 : 1,
          child: TouchLight(
            radius: BorderRadius.circular(30),
            enabled: !dim,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(leading != null ? 10 : 12, 8,
                  trailing != null ? 7 : 12, 8),
              decoration: BoxDecoration(
                color: on
                    ? AppColors.gold.withValues(alpha: 0.16)
                    : AppColors.surface.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: on
                      ? AppColors.gold.withValues(alpha: 0.75)
                      : AppColors.stroke,
                ),
                boxShadow: [
                  if (on)
                    BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.2),
                        blurRadius: 14),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    Icon(leading,
                        size: 15,
                        color:
                            on ? AppColors.goldBright : AppColors.textSecondary),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        color: on ? AppColors.goldBright : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 2),
                    Icon(trailing,
                        size: 16,
                        color:
                            on ? AppColors.goldBright : AppColors.textSecondary),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameChips extends StatelessWidget {
  final Set<ArenaGame> games;
  final Set<ArenaGame> feasible;
  final ValueChanged<ArenaGame> onToggle;
  const _GameChips(
      {required this.games, required this.feasible, required this.onToggle});

  static const _icons = {
    ArenaGame.completeVerse: Icons.more_horiz_rounded,
    ArenaGame.missingWord: Icons.crop_free_rounded,
    ArenaGame.whichSurah: Icons.menu_book_rounded,
    ArenaGame.nextVerse: Icons.arrow_downward_rounded,
    ArenaGame.orderWords: Icons.swap_horiz_rounded,
    ArenaGame.surahFacts: Icons.auto_awesome_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in ArenaGame.values)
          _Pill(
            label: l.arenaGameName(g),
            leading: _icons[g],
            on: games.contains(g) && feasible.contains(g),
            dim: !feasible.contains(g),
            onTap: () => onToggle(g),
          ),
      ],
    );
  }
}

/// How long a question has: four pills, the chosen one lit.
class _SecondsRow extends StatelessWidget {
  final int seconds;
  final ValueChanged<int> onSelect;
  const _SecondsRow({required this.seconds, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Row(
      children: [
        for (final v in ArenaSetup.secondsOptions) ...[
          if (v != ArenaSetup.secondsOptions.first) const SizedBox(width: 8),
          Expanded(
            child: _Pill(
              label: l.arenaSecondsValue(v),
              on: v == seconds,
              onTap: () => onSelect(v),
            ),
          ),
        ],
      ],
    );
  }
}

/// Thirty cartouches, one per juz.
class _JuzSheet extends StatelessWidget {
  final int selected;
  const _JuzSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D2537), Color(0xFF131A28)],
          ),
          border: Border(
              top: BorderSide(
                  color: AppColors.gold.withValues(alpha: 0.3), width: 0.9)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.stroke,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                A11yHeader(
                  child: Text(l.arenaPickJuz,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.55,
                  children: [
                    for (var j = 1; j <= 30; j++)
                      A11yTap(
                        label: l.arenaJuz(j),
                        selected: j == selected,
                        onTap: () => Navigator.of(context).pop(j),
                        child: Pressable(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).pop(j);
                          },
                          scale: 0.92,
                          child: ClipPath(
                            clipper: const CartoucheClipper(),
                            child: Container(
                              alignment: Alignment.center,
                              color: j == selected
                                  ? AppColors.gold.withValues(alpha: 0.22)
                                  : AppColors.surface.withValues(alpha: 0.85),
                              child: Text(
                                '$j',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: j == selected
                                      ? AppColors.goldBright
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
