import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debug_log.dart';
import '../data/listen/listen_model.dart';
import '../data/listen/listen_service.dart';
import '../data/listen/listen_words.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/user_audio_service.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/glow_button.dart';
import '../widgets/step_dots.dart';
import 'align_screen.dart';
import 'background_screen.dart';
import 'verses_screen.dart';

/// The step an upload goes through instead of choosing its verses: AyahReel
/// Listen hears the recording, finds the surah and verses and times every
/// word, and the reel is made from what it heard. The user can still look
/// at the timing, pick another place with the same words, or choose the
/// verses themselves.
class ListenScreen extends StatefulWidget {
  final UserAudio audio;

  const ListenScreen({super.key, required this.audio});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

enum _Phase { preparing, ask, working, found, nothing, failed }

class _ListenScreenState extends State<ListenScreen> {
  _Phase _phase = _Phase.preparing;
  ListenStage _stage = ListenStage.model;
  double _share = 0;
  int _modelMb = 0;
  bool _offline = false;
  bool _alive = true;
  int _lastPaint = 0;

  ListenOutcome? _outcome;

  /// The passage the reel will be made of: one found, or an alternative
  /// of it the user picked (surah, first, last) with its own timing.
  ListenFound? _chosen;
  (int, int, int)? _alt;
  Map<int, List<int>>? _altTiming;
  bool _retiming = false;
  String _firstWords = '';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }

  Future<void> _prepare() async {
    final local = await ListenModel.local();
    if (!mounted) return;
    if (local != null) {
      unawaited(_run());
      return;
    }
    final m = await ListenModel.manifest();
    if (!mounted) return;
    if (m == null) {
      setState(() {
        _phase = _Phase.failed;
        _offline = true;
      });
      return;
    }
    setState(() {
      _modelMb = (m.bytes / 1e6).round();
      _phase = _Phase.ask;
    });
  }

  Future<void> _run() async {
    setState(() {
      _phase = _Phase.working;
      _stage = ListenStage.model;
      _share = 0;
      _offline = false;
    });
    try {
      final out = await ListenService.hearFile(
        widget.audio.audioPath,
        keepGoing: () => _alive,
        onProgress: (stage, share) {
          if (!mounted) return;
          // A few times a second is plenty for a progress ring, and a
          // download reports every chunk.
          final now = DateTime.now().millisecondsSinceEpoch;
          if (stage == _stage && share < 1 && now - _lastPaint < 120) return;
          _lastPaint = now;
          setState(() {
            _stage = stage;
            _share = share;
          });
        },
      );
      if (!mounted) return;
      final main = out.main;
      if (main == null) {
        setState(() {
          _outcome = out;
          _phase = _Phase.nothing;
        });
        return;
      }
      _firstWords = await ListenService.verseText(main.surah, main.first);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _outcome = out;
        _chosen = main;
        _phase = _Phase.found;
      });
    } on ListenUnavailable catch (e) {
      rlog('listen: unavailable ($e)');
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _offline = e.why == 'download' || e.why == 'manifest';
      });
    } catch (e, st) {
      rlogError('listen: failed', e, st);
      if (!mounted) return;
      setState(() => _phase = _Phase.failed);
    }
  }

  /// Where the reel's verses are: (surah, first, last).
  (int, int, int)? get _passage {
    final alt = _alt;
    if (alt != null) return alt;
    final c = _chosen;
    return c == null ? null : (c.surah, c.first, c.last);
  }

  Map<int, List<int>>? get _timing => _alt != null ? _altTiming : _chosen?.timing;

  Future<void> _pickPassage(ListenFound f) async {
    HapticFeedback.selectionClick();
    final words = await ListenService.verseText(f.surah, f.first);
    if (!mounted) return;
    setState(() {
      _chosen = f;
      _alt = null;
      _altTiming = null;
      _firstWords = words;
    });
  }

  Future<void> _pickAlternative((int, int, int) a) async {
    final out = _outcome, from = _chosen;
    if (out == null || from == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _alt = a;
      _altTiming = null;
      _retiming = true;
    });
    final t = await ListenService.retime(out, from, a.$1, a.$2, a.$3);
    final words = await ListenService.verseText(a.$1, a.$2);
    if (!mounted || _alt != a) return;
    setState(() {
      _altTiming = t;
      _retiming = false;
      _firstWords = words;
    });
  }

  /// The verses' windows in the recording, from where their words were
  /// heard: each verse's card comes up just before its first word.
  List<AyahTiming>? _windows() {
    final p = _passage, t = _timing;
    if (p == null || t == null) return null;
    final (_, first, last) = p;
    final dur = widget.audio.durationMs;
    final starts = <int>[], ends = <int>[];
    for (var a = first; a <= last; a++) {
      final v = t[a];
      if (v == null) return null;
      starts.add(v[0]);
      ends.add(v[1]);
    }
    final marks = <int>[(starts.first - 400).clamp(0, dur)];
    for (var i = 0; i + 1 < starts.length; i++) {
      final b = starts[i + 1] - 300;
      marks.add(b > ends[i] ? b : ends[i]);
    }
    marks.add((ends.last + 600).clamp(0, dur));
    return UserAudioService.timingsFrom(marks, first, endMs: dur);
  }

  Future<void> _use({required bool review}) async {
    final p = _passage, t = _timing, windows = _windows();
    if (p == null || t == null || windows == null) return;
    final (surah, first, last) = p;
    creationState.selectSurah(surah);
    creationState.selectRange(first, last);
    ListenWords.forget(widget.audio.id);
    ListenWords.register(widget.audio.id, surah, t,
        await ListenService.wordCounts(surah, first, last));
    if (!mounted) return;
    rlog('listen: reel from $surah:$first-$last'
        '${review ? ' (timing checked by hand)' : ''}');
    if (review) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AlignScreen(audio: widget.audio, heard: windows)));
      return;
    }
    UserAudioService.register(audio: widget.audio, surah: surah, timings: windows);
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BackgroundScreen()));
  }

  void _chooseMyself() {
    _alive = false;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const VersesScreen()))
        .then((_) => _alive = mounted);
  }

  // ---- build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: StepDots(current: WizardSteps.verses, total: WizardSteps.total),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: switch (_phase) {
            _Phase.preparing => const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.gold),
                ),
              ),
            _Phase.ask => _ask(t, l),
            _Phase.working => _working(t, l),
            _Phase.found => _found(t, l),
            _Phase.nothing => _message(t, l, l.listenNothing, retry: false),
            _Phase.failed => _message(
                t, l, _offline ? l.listenOffline : l.listenFailed,
                retry: true),
          },
        ),
      ),
    );
  }

  Widget _ask(TextTheme t, L10n l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        A11yHeader(child: Text(l.listenAskTitle, style: t.headlineMedium)),
        const SizedBox(height: 12),
        Text(l.listenAskBody(_modelMb), style: t.bodyMedium),
        const Spacer(),
        GlowButton(
          label: l.listenStart,
          icon: Icons.hearing_rounded,
          onPressed: _run,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _chooseMyself,
            child: Text(l.listenChooseMyself),
          ),
        ),
      ],
    );
  }

  Widget _working(TextTheme t, L10n l) {
    final line = switch (_stage) {
      ListenStage.model => l.listenStageModel(
          (_share * _modelMbOrGuess).round(), _modelMbOrGuess),
      ListenStage.decode => l.listenStageDecode,
      ListenStage.hear => l.listenStageHear((_share * 100).round()),
      ListenStage.find => l.listenStageFind,
    };
    final determinate =
        _stage == ListenStage.model || _stage == ListenStage.hear;
    return Column(
      children: [
        const Spacer(),
        SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: AppColors.gold,
            value: determinate ? _share.clamp(0.02, 1.0) : null,
          ),
        ),
        const SizedBox(height: 22),
        A11yLive(child: Text(line, style: t.titleMedium, textAlign: TextAlign.center)),
        const Spacer(),
        TextButton(onPressed: _chooseMyself, child: Text(l.listenChooseMyself)),
      ],
    );
  }

  int get _modelMbOrGuess => _modelMb > 0 ? _modelMb : 118;

  Widget _found(TextTheme t, L10n l) {
    final out = _outcome!;
    final p = _passage!;
    final info = QuranRepository.surahInfo(p.$1);
    final chosen = _chosen!;
    final alts = chosen.alternatives;
    final others = [
      for (final f in out.passages)
        if (!identical(f, chosen)) f,
    ];
    final ready = !_retiming && _timing != null && _windows() != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.listenHeard, style: t.bodyMedium),
        const SizedBox(height: 6),
        A11yHeader(
          child: Text('${info.nameEnglish} · ${info.nameArabic}',
              style: t.headlineMedium),
        ),
        const SizedBox(height: 2),
        Text(l.listenVerses(p.$2, p.$3),
            style: t.titleMedium?.copyWith(color: AppColors.gold)),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _firstWords,
                  textDirection: TextDirection.rtl,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'HafsUthmani',
                    fontSize: 24,
                    height: 1.9,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 16, color: AppColors.gold),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l.listenWordsLit, style: t.bodySmall)),
                ],
              ),
              if (alts.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(l.listenAlsoIn, style: t.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(t, (chosen.surah, chosen.first, chosen.last),
                        _alt == null, () {
                      setState(() {
                        _alt = null;
                        _altTiming = null;
                        _retiming = false;
                      });
                      ListenService.verseText(chosen.surah, chosen.first).then(
                          (w) => mounted ? setState(() => _firstWords = w) : null);
                    }),
                    for (final a in alts.take(40))
                      _chip(t, a, _alt == a, () => _pickAlternative(a)),
                  ],
                ),
              ],
              if (others.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(l.listenOtherParts, style: t.bodyMedium),
                const SizedBox(height: 8),
                for (final f in others)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${QuranRepository.surahInfo(f.surah).nameEnglish} '
                        '${f.first == f.last ? f.first : '${f.first}–${f.last}'}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickPassage(f),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlowButton(
          label: l.listenMakeReel,
          icon: Icons.arrow_forward_rounded,
          busy: _retiming,
          onPressed: ready ? () => _use(review: false) : null,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: ready ? () => _use(review: true) : null,
              child: Text(l.listenCheckTiming),
            ),
            TextButton(
              onPressed: _chooseMyself,
              child: Text(l.listenChooseMyself),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chip(TextTheme t, (int, int, int) a, bool on, VoidCallback onTap) {
    final name = QuranRepository.surahInfo(a.$1).nameEnglish;
    final verses = a.$2 == a.$3 ? '${a.$2}' : '${a.$2}–${a.$3}';
    return ChoiceChip(
      label: Text('$name $verses'),
      selected: on,
      onSelected: (_) => onTap(),
    );
  }

  Widget _message(TextTheme t, L10n l, String text, {required bool retry}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        A11yLive(child: Text(text, style: t.titleMedium)),
        const Spacer(),
        if (retry)
          GlowButton(
            label: l.listenTryAgain,
            icon: Icons.refresh_rounded,
            onPressed: () {
              _alive = true;
              _prepare();
            },
          ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _chooseMyself,
            child: Text(l.listenChooseMyself),
          ),
        ),
      ],
    );
  }
}
