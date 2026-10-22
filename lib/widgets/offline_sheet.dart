import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fatiha_data.dart';
import '../data/models.dart';
import '../data/offline_pack.dart';
import '../l10n/l10n.dart';
import '../screens/reciter_screen.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';
import 'glow_button.dart';

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
    final voiceAll = OfflinePack.voiceBytes(p.voice, p.scope);
    final voiceLeft = have == null || have.voiceOf == 0
        ? voiceAll
        : (voiceAll * (1 - have.voice / have.voiceOf)).round();
    // Each row says its own size whether or not it is ticked, so the
    // choice is made knowing it.
    final stills = OfflinePack.scenesFor(
        OfflinePlan(voice: p.voice, stills: true, clips: false));
    final clips = OfflinePack.scenesFor(
        OfflinePlan(voice: p.voice, stills: false, clips: true));
    final stillsLeft = stills.fold(0, (a, s) => a + s.bytes);
    final clipsLeft = clips.fold(0, (a, s) => a + s.bytes);
    final stillCount = stills.length;
    final clipCount = clips.length;
    final total = textLeft +
        voiceLeft +
        (p.stills ? stillsLeft : 0) +
        (p.clips ? clipsLeft : 0);

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
                    sizeOf: (scope) =>
                        size(OfflinePack.voiceBytes(p.voice, scope)),
                    done: have != null &&
                        have.voiceOf > 0 &&
                        have.voice == have.voiceOf,
                    onScope: (s) => _set(p.copyWith(scope: s)),
                    onChange: busy ? null : _changeVoice,
                  ),
                  const _Gap(),
                  _Row(
                    icon: Icons.image_outlined,
                    title: l.offlineStills,
                    note: l.offlineScenesNote(stillCount, size(stillsLeft)),
                    done: stillCount == 0,
                    doneLabel: l.offlineOnPhone,
                    trailing: _Tick(on: p.stills),
                    onTap: busy ? null : () => _set(p.copyWith(stills: !p.stills)),
                  ),
                  const _Gap(),
                  _Row(
                    icon: Icons.movie_creation_outlined,
                    title: l.offlineClips,
                    note: l.offlineScenesNote(clipCount, size(clipsLeft)),
                    done: clipCount == 0,
                    doneLabel: l.offlineOnPhone,
                    trailing: _Tick(on: p.clips),
                    onTap: busy ? null : () => _set(p.copyWith(clips: !p.clips)),
                  ),
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

/// The voice: whose, and how much of it — none, Juz' 30, or the whole
/// Quran, each with its size.
class _VoiceRow extends StatelessWidget {
  final OfflinePlan plan;
  final bool busy;
  final bool done;
  final String Function(OfflineVoice scope) sizeOf;
  final ValueChanged<OfflineVoice> onScope;
  final VoidCallback? onChange;

  const _VoiceRow({
    required this.plan,
    required this.busy,
    required this.done,
    required this.sizeOf,
    required this.onScope,
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
                    label: l.offlineScope(s.name),
                    size: s == OfflineVoice.none ? null : sizeOf(s),
                    chosen: plan.scope == s,
                    onTap: busy ? null : () => onScope(s),
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

  const _ScopeChip({
    required this.label,
    required this.size,
    required this.chosen,
    required this.onTap,
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
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                      color: chosen
                          ? AppColors.goldBright
                          : AppColors.textPrimary)),
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
