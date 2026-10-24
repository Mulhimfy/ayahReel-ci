import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fatiha_data.dart';
import '../data/models.dart';
import '../data/offline_pack.dart';
import '../data/scene_catalog.dart';
import '../data/surah_index.dart';
import '../l10n/l10n.dart';
import '../screens/reciter_screen.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'glow_button.dart';
import 'surah_picker_sheet.dart';

/// Opens the offline download as the app's standard bottom sheet.
Future<void> showOfflineSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const OfflineSheet(),
  );
}

/// Everything a reel needs from the network, brought onto the phone in
/// one tap: the verses, a voice, the sceneries — each with what it
/// costs in space, and what is already there said as much.
///
/// The download is [OfflinePack]'s, not the sheet's: the sheet can be
/// closed and the app used while it runs, and opening it again shows
/// where it has got to.
class OfflineSheet extends StatefulWidget {
  const OfflineSheet({super.key});

  /// A size as the sheet writes it: megabytes, or gigabytes from 1000 MB.
  static String sizeLabel(int bytes) => _OfflineSheetState.size(bytes);

  /// The voice it opens on: the one the last reel was made with, or the
  /// app's first when there is none yet (or it was the user's own).
  static Reciter defaultVoice() {
    final r = creationState.reciter;
    return r == null || r.isUserAudio ? reciters.first : r;
  }

  @override
  State<OfflineSheet> createState() => _OfflineSheetState();
}

class _OfflineSheetState extends State<OfflineSheet> {
  late OfflinePlan _plan = OfflinePlan(voice: OfflineSheet.defaultVoice());
  ({int text, int voice, int voiceOf, int scenes, int scenesOf})? _have;

  @override
  void initState() {
    super.initState();
    OfflinePack.state.addListener(_onProgress);
    _measure();
  }

  @override
  void dispose() {
    OfflinePack.state.removeListener(_onProgress);
    super.dispose();
  }

  OfflineStage _last = OfflinePack.state.value.stage;

  /// A run that ends is measured again, so the rows say what is there.
  void _onProgress() {
    final stage = OfflinePack.state.value.stage;
    if (stage != _last && !OfflinePack.state.value.running) _measure();
    _last = stage;
  }

  Future<void> _measure() async {
    final plan = _plan;
    try {
      final have = await OfflinePack.status(plan);
      if (mounted && identical(plan, _plan)) setState(() => _have = have);
    } catch (_) {/* the rows show estimates without it */}
  }

  void _set(OfflinePlan p) {
    HapticFeedback.selectionClick();
    setState(() {
      _plan = p;
      _have = null;
    });
    _measure();
  }

  /// A surah of the voice: the picker, its unrecorded surahs shut.
  Future<void> _pickSurah() async {
    HapticFeedback.selectionClick();
    final pick = await showSurahPicker(context,
        unavailable: _plan.voice.missingSurahs);
    if (pick != null && mounted) {
      _set(_plan.copyWith(scope: OfflineVoice.surah, surah: pick.number));
    }
  }

  /// A juz of the voice: thirty numbers in a grid.
  Future<void> _pickJuz() async {
    HapticFeedback.selectionClick();
    final juz = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _JuzGrid(
        chosen: _plan.scope == OfflineVoice.juz ? _plan.juz : null,
      ),
    );
    if (juz != null && mounted) {
      _set(_plan.copyWith(scope: OfflineVoice.juz, juz: juz));
    }
  }

  Future<void> _changeVoice() async {
    HapticFeedback.selectionClick();
    final picked = await Navigator.of(context).push<Reciter>(
      MaterialPageRoute(
        builder: (_) => ReciterScreen(
          initialReciterId: _plan.voice.id,
          onContinue: (ctx, r) => Navigator.of(ctx).pop(r),
        ),
      ),
    );
    if (picked != null && mounted && !picked.isUserAudio) {
      _set(_plan.copyWith(voice: picked));
    }
  }

  void _start() {
    HapticFeedback.mediumImpact();
    unawaited(OfflinePack.run(_plan));
  }

  static String size(int bytes) {
    if (bytes <= 0) return '0 MB';
    const mb = 1000 * 1000;
    if (bytes < 1000 * mb) return '${(bytes / mb).ceil()} MB';
    return '${(bytes / (1000 * mb)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final p = _plan;
    final have = _have;

    // What is still to come, by part.
    final textLeft = have == null || have.text < 114 ? OfflinePack.textBytes : 0;
    final voiceAll = OfflinePack.voiceBytes(p.voice, p.surahs);
    final voiceLeft = have == null || have.voiceOf == 0
        ? voiceAll
        : (voiceAll * (1 - have.voice / have.voiceOf)).round();
    // Each row says its own size whether or not it is ticked, so the
    // choice is made knowing it.
    final stills = OfflinePack.scenesFor(
        p.copyWith(stills: true, clips: false));
    final clips = OfflinePack.scenesFor(
        p.copyWith(stills: false, clips: true));
    final stillsLeft = stills.fold(0, (a, s) => a + s.bytes);
    final clipsLeft = clips.fold(0, (a, s) => a + s.bytes);
    final stillCount = stills.length;
    final clipCount = clips.length;
    final total = textLeft +
        voiceLeft +
        (p.sceneTab != null && p.stills ? stillsLeft : 0) +
        (p.sceneTab != null && p.clips ? clipsLeft : 0);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: ValueListenableBuilder<OfflineProgress>(
            valueListenable: OfflinePack.state,
            builder: (context, run, _) {
              final busy = run.running;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.stroke,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  A11yHeader(child: Text(l.offlineTitle, style: t.titleMedium)),
                  const SizedBox(height: 4),
                  Text(l.offlineBody,
                      style: t.bodySmall?.copyWith(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 14),
                  _Row(
                    icon: Icons.menu_book_rounded,
                    title: l.offlineText,
                    note: l.offlineTextNote(size(OfflinePack.textBytes)),
                    done: have != null && have.text == 114,
                    doneLabel: l.offlineOnPhone,
                    trailing: const _Tick(on: true),
                  ),
                  const _Gap(),
                  _VoiceRow(
                    plan: p,
                    busy: busy,
                    sizeOf: (scope) => size(OfflinePack.voiceBytes(
                        p.voice,
                        OfflinePack.surahsFor(scope,
                            surah: p.surah, juz: p.juz))),
                    done: have != null &&
                        have.voiceOf > 0 &&
                        have.voice == have.voiceOf,
                    onScope: (s) => _set(p.copyWith(scope: s)),
                    onSurah: _pickSurah,
                    onJuz: _pickJuz,
                    onChange: busy ? null : _changeVoice,
                  ),
                  const _Gap(),
                  _SceneShelves(
                    chosen: p.sceneTab,
                    busy: busy,
                    onPick: (tab) => _set(tab == null
                        ? p.copyWith(clearSceneTab: true)
                        : p.copyWith(sceneTab: tab)),
                  ),
                  if (p.sceneTab != null) ...[
                    const _Gap(),
                    _Row(
                      icon: Icons.image_outlined,
                      title: l.offlineStills,
                      note: l.offlineScenesNote(stillCount, size(stillsLeft)),
                      done: stillCount == 0,
                      doneLabel: l.offlineOnPhone,
                      trailing: _Tick(on: p.stills),
                      onTap: busy
                          ? null
                          : () => _set(p.copyWith(stills: !p.stills)),
                    ),
                    const _Gap(),
                    _Row(
                      icon: Icons.movie_creation_outlined,
                      title: l.offlineClips,
                      note: l.offlineScenesNote(clipCount, size(clipsLeft)),
                      done: clipCount == 0,
                      doneLabel: l.offlineOnPhone,
                      trailing: _Tick(on: p.clips),
                      onTap: busy
                          ? null
                          : () => _set(p.copyWith(clips: !p.clips)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (busy) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: run.fraction <= 0 ? null : run.fraction,
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceRaised,
                        color: AppColors.gold,
                        semanticsLabel: l.offlineTitle,
                        semanticsValue: '${(run.fraction * 100).round()}%',
                      ),
                    ),
                    const SizedBox(height: 8),
                    A11yLive(
                      child: Text(
                        l.offlineRunning((run.fraction * 100).floor()),
                        textAlign: TextAlign.center,
                        style: t.bodySmall?.copyWith(
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 10),
                    QuietButton(
                      label: l.offlineStop,
                      icon: Icons.pause_rounded,
                      dense: true,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        OfflinePack.stop();
                      },
                    ),
                  ] else ...[
                    if (_message(l, run) case final m?) ...[
                      A11yLive(
                        child: Text(
                          m,
                          textAlign: TextAlign.center,
                          style: t.bodySmall?.copyWith(
                            fontSize: 12.5,
                            height: 1.4,
                            color: run.stage == OfflineStage.done &&
                                    run.missed == 0
                                ? AppColors.goldBright
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      l.offlineTotal(size(total)),
                      textAlign: TextAlign.center,
                      style: t.bodySmall?.copyWith(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    GlowButton(
                      label: l.offlineStart,
                      icon: Icons.download_rounded,
                      height: 48,
                      onPressed: total <= 0 ? null : _start,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// What the last run came to, when there is something to say.
  static String? _message(L10n l, OfflineProgress run) => switch (run.stage) {
        OfflineStage.done =>
          run.missed > 0 ? l.offlineMissed(run.missed) : l.offlineDone,
        OfflineStage.stopped => l.offlineStopped,
        OfflineStage.offline => l.offlineNoNet,
        OfflineStage.full => l.offlineFull,
        _ => null,
      };
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 8);
}

/// One part of the download: what it is, what it costs, and whether it
/// is in.
class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;
  final bool done;
  final String doneLabel;
  final Widget trailing;
  final VoidCallback? onTap;

  const _Row({
    required this.icon,
    required this.title,
    required this.note,
    required this.done,
    required this.doneLabel,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      child: Material(
        color: AppColors.surfaceRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            child: Row(
              children: [
                Icon(icon, size: 19, color: AppColors.gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: t.bodyMedium?.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(done ? doneLabel : note,
                          style: t.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: done
                                  ? AppColors.goldBright
                                  : AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round tick: filled gold when the part is in the download.
class _Tick extends StatelessWidget {
  final bool on;

  const _Tick({required this.on});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? AppColors.gold : Colors.transparent,
          border: Border.all(
              color: on ? AppColors.gold : AppColors.stroke, width: 1.4),
        ),
        child: on
            ? const Icon(Icons.check_rounded,
                size: 15, color: Color(0xFF14100A))
            : null,
      );
}

/// The voice: whose, and how much of it — none, Juz' 30, one surah or
/// one juz, each with its size. One at a time: a surah or a juz is a few
/// minutes' download, where the whole Quran was an evening's.
class _VoiceRow extends StatelessWidget {
  final OfflinePlan plan;
  final bool busy;
  final bool done;
  final String Function(OfflineVoice scope) sizeOf;
  final ValueChanged<OfflineVoice> onScope;
  final VoidCallback onSurah;
  final VoidCallback onJuz;
  final VoidCallback? onChange;

  const _VoiceRow({
    required this.plan,
    required this.busy,
    required this.done,
    required this.sizeOf,
    required this.onScope,
    required this.onSurah,
    required this.onJuz,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded,
                  size: 19, color: AppColors.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.reciterName(plan.voice) +
                          (l.recordingNote(plan.voice) == null
                              ? ''
                              : ' · ${l.recordingNote(plan.voice)}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    if (done) ...[
                      const SizedBox(height: 2),
                      Text(l.offlineOnPhone,
                          style: t.bodySmall?.copyWith(
                              fontSize: 11.5, color: AppColors.goldBright)),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: onChange,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.goldBright,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(l.offlineChangeVoice),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final s in OfflineVoice.values) ...[
                if (s != OfflineVoice.values.first) const SizedBox(width: 6),
                Expanded(
                  child: _ScopeChip(
                    label: switch (s) {
                      OfflineVoice.surah when plan.scope == s =>
                        l.localizedSurahName(
                            surahIndex[plan.surah - 1].nameEnglish),
                      OfflineVoice.juz when plan.scope == s =>
                        l.offlineJuzNumber(plan.juz),
                      _ => l.offlineScope(s.name),
                    },
                    size: s == OfflineVoice.none ||
                            ((s == OfflineVoice.surah ||
                                    s == OfflineVoice.juz) &&
                                plan.scope != s)
                        ? null
                        : sizeOf(s),
                    more: s == OfflineVoice.surah || s == OfflineVoice.juz,
                    chosen: plan.scope == s,
                    onTap: busy
                        ? null
                        : switch (s) {
                            OfflineVoice.surah => onSurah,
                            OfflineVoice.juz => onJuz,
                            _ => () => onScope(s),
                          },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String label;
  final String? size;
  final bool chosen;
  final VoidCallback? onTap;

  /// Opens a choice of its own: a small chevron says so.
  final bool more;

  const _ScopeChip({
    required this.label,
    required this.size,
    required this.chosen,
    required this.onTap,
    this.more = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: chosen,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: chosen
                ? AppColors.gold.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: chosen ? AppColors.gold : AppColors.stroke),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                chosen ? FontWeight.w600 : FontWeight.w400,
                            color: chosen
                                ? AppColors.goldBright
                                : AppColors.textPrimary)),
                  ),
                  if (more)
                    Icon(Icons.expand_more_rounded,
                        size: 14,
                        color: chosen
                            ? AppColors.goldBright
                            : AppColors.textSecondary),
                ],
              ),
              if (size != null)
                Text(size!,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shelves of sceneries, one to bring down at a time: Sky,
/// Mountains, Water… each with how many it holds, or none.
class _SceneShelves extends StatelessWidget {
  final String? chosen;
  final bool busy;
  final ValueChanged<String?> onPick;

  const _SceneShelves({
    required this.chosen,
    required this.busy,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final tabs = SceneCatalog.tabs;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 0, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.landscape_outlined,
                  size: 19, color: AppColors.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l.offlineScenes,
                    style: t.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(end: 14),
              children: [
                _ShelfChip(
                  label: l.offlineScope('none'),
                  chosen: chosen == null,
                  onTap: busy ? null : () => onPick(null),
                ),
                for (final tab in tabs)
                  _ShelfChip(
                    label: '${l.sceneTab(tab)} · '
                        '${SceneCatalog.inTab(tab).where((s) => !s.bundled).length}',
                    chosen: chosen == tab,
                    onTap: busy ? null : () => onPick(tab),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfChip extends StatelessWidget {
  final String label;
  final bool chosen;
  final VoidCallback? onTap;

  const _ShelfChip({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Semantics(
        button: true,
        selected: chosen,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: chosen
                  ? AppColors.gold.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                  color: chosen ? AppColors.gold : AppColors.stroke),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                color: chosen ? AppColors.goldBright : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The thirty juz, to pick one.
class _JuzGrid extends StatelessWidget {
  final int? chosen;

  const _JuzGrid({required this.chosen});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.stroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            A11yHeader(
              child: Text(l.offlinePickJuz,
                  textAlign: TextAlign.center, style: t.titleMedium),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var j = 1; j <= 30; j++)
                  Semantics(
                    button: true,
                    selected: chosen == j,
                    label: l.offlineJuzNumber(j),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(j),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: chosen == j
                              ? AppColors.gold.withValues(alpha: 0.18)
                              : AppColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: chosen == j
                                  ? AppColors.gold
                                  : AppColors.stroke),
                        ),
                        child: Text(
                          '$j',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: chosen == j
                                ? AppColors.goldBright
                                : AppColors.textPrimary,
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
    );
  }
}
