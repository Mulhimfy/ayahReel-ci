import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debug_log.dart';
import '../data/fatiha_data.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/reel_library.dart';
import '../data/series_library.dart';
import '../data/user_audio_service.dart';
import '../l10n/l10n.dart';
import '../state/creation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/illumination.dart';
import '../widgets/series_strip.dart';
import 'reel_player_screen.dart';
import 'series_intro_screen.dart';
import 'verses_screen.dart';

/// A planned series: its days across the top, the chosen day's reels
/// underneath, and from each reel the way into the wizard with the
/// verses already picked.
///
/// Nothing is rendered from here. A reel is made by going through the
/// same four screens every reel goes through — verses to adjust,
/// scenery to choose, the preview to watch — and it is the export at
/// the end of that which lights the day. A series is a plan, not a
/// batch job.
class SeriesScreen extends StatefulWidget {
  final String seriesId;

  /// The day to open on; otherwise the first unfinished one.
  final int? initialDay;

  const SeriesScreen({super.key, required this.seriesId, this.initialDay});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  ReelSeries? _series;
  int? _day;

  /// The surah's text, for the opening words on each reel's card.
  List<Ayah>? _ayahs;

  /// Finished reels by id, so a done card can open its video.
  Map<String, SavedReel> _saved = const {};

  @override
  void initState() {
    super.initState();
    _load();
    SeriesLibrary.revision.addListener(_load);
    ReelLibrary.revision.addListener(_loadSaved);
  }

  @override
  void dispose() {
    SeriesLibrary.revision.removeListener(_load);
    ReelLibrary.revision.removeListener(_loadSaved);
    super.dispose();
  }

  Future<void> _load() async {
    final s = await SeriesLibrary.byId(widget.seriesId);
    if (!mounted) return;
    if (s == null) {
      // Replaced by a new series, or gone: nothing is left to show, and
      // the page would spin for good. This page may not be the top one
      // (the new series sits over it), so it takes out its own route.
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
      return;
    }
    setState(() {
      _series = s;
      _day ??= widget.initialDay ?? s.nextDay ?? 1;
      if (_day! > s.days) _day = s.days;
    });
    _loadSaved();
    if (_ayahs == null) {
      try {
        final a = await QuranRepository.ayahsOf(s.surah);
        if (mounted) setState(() => _ayahs = a);
      } catch (_) {/* the cards just carry the range */}
    }
  }

  Future<void> _loadSaved() async {
    final reels = await ReelLibrary.load();
    if (mounted) setState(() => _saved = {for (final r in reels) r.id: r});
  }

  /// Into the wizard, at the verses, with this reel's range selected
  /// and the series' own voice already chosen.
  Future<void> _make(SeriesReel reel) async {
    final s = _series;
    if (s == null) return;
    var reciter = reciters.firstWhere(
      (r) => r.id == s.reciterId,
      orElse: () => reciters.first,
    );
    // A series planned on the user's own recording keeps it, as long as
    // that recording is still the one on the phone.
    if (UserAudioService.isUserId(s.reciterId)) {
      final a = await UserAudioService.restore();
      if (!mounted) return;
      if (a != null && a.id == s.reciterId) {
        reciter = UserAudioService.reciterFor(a);
      }
    }
    HapticFeedback.selectionClick();
    creationState
      ..startNewReel()
      ..selectReciter(reciter)
      ..selectSurah(s.surah)
      ..selectRange(reel.startAyah, reel.endAyah)
      ..setSeriesTarget(SeriesTarget(s.id, reel.index));
    rlog('series: making reel ${reel.index} of ${s.id} '
        '(${s.surah}:${reel.startAyah}-${reel.endAyah})');
    QuranRepository.prefetchRecitation(reciter, s.surah,
        startAyah: reel.startAyah, endAyah: reel.endAyah);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VersesScreen(preselect: true)),
    );
  }

  void _openSaved(SavedReel r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReelPlayerScreen(reel: r)),
    );
  }

  Future<void> _toggleDay(int day) async {
    final s = _series;
    if (s == null) return;
    final l = L10n.of(context);
    final before = s.isDayDone(day);
    final after = await SeriesLibrary.toggleDay(s.id, day);
    if (!mounted || after == null) return;
    if (after.isDayDone(day) && !before) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(after.finished ? l.seriesFinished : l.seriesReelDone(day)),
          duration: const Duration(seconds: 2),
        ));
    }
  }

  /// Into the planner, from here: the same door the home tab opens.
  void _addSeries() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SeriesIntroScreen()),
    );
  }

  Future<void> _delete() async {
    final s = _series;
    if (s == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = L10n.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.surfaceRaised,
          title: Text(l.deleteSeriesTitle),
          content: Text(l.deleteSeriesBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.delete,
                  style: const TextStyle(color: Color(0xFFE57373))),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await SeriesLibrary.remove(s.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final s = _series;
    final surahName =
        s == null ? '' : QuranRepository.surahInfo(s.surah).nameEnglish;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: s == null
            ? null
            : Text(l.seriesHeading(surahName, s.days), style: t.titleMedium),
        actions: [
          PopupMenuButton<String>(
            tooltip: l.a11ySeriesOptions,
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textSecondary),
            color: AppColors.surfaceRaised,
            onSelected: (v) => v == 'add' ? _addSeries() : _delete(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'add', child: Text(l.newSeries)),
              PopupMenuItem(value: 'delete', child: Text(l.delete)),
            ],
          ),
        ],
      ),
      body: s == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 10),
                    child: Row(
                      children: [
                        const SealGlyph(size: 8),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.finished
                                ? l.seriesFinished
                                : l.seriesProgress(s.daysDone, s.days),
                            style: t.bodyMedium?.copyWith(
                              color: s.finished
                                  ? AppColors.goldBright
                                  : AppColors.textSecondary,
                              fontWeight: s.finished
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Text(
                          l.localizedReciterName(_reciterName(s)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  SeriesStrip(
                    series: s,
                    selectedDay: _day,
                    onTapDay: (d) => setState(() => _day = d),
                    onLongPressDay: _toggleDay,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
                    child: Text(
                      l.holdADayToMark,
                      style: t.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 6, 24, 8),
                    child: Row(
                      children: [
                        Expanded(child: OrnamentHairline(towardsEnd: true)),
                        SizedBox(width: 8),
                        SealGlyph(size: 7, color: Color(0x99D4A947)),
                      ],
                    ),
                  ),
                  Expanded(child: _dayList(s, l, t)),
                ],
              ),
            ),
    );
  }

  String _reciterName(ReelSeries s) {
    if (UserAudioService.isUserId(s.reciterId)) {
      return L10n.of(context).yourRecitation;
    }
    for (final r in reciters) {
      if (r.id == s.reciterId) return r.name;
    }
    return s.reciterId;
  }

  Widget _dayList(ReelSeries s, L10n l, TextTheme t) {
    final day = _day ?? 1;
    final reels = s.reelsOn(day);
    final today = s.todayIndex(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      children: [
        Row(
          children: [
            A11yHeader(child: Text(l.dayN(day), style: t.titleMedium)),
            if (day == today && !s.isDayDone(day)) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.5)),
                ),
                child: Text(
                  l.nextUp,
                  style: t.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: AppColors.goldBright,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (s.isDayDone(day))
              Row(
                children: [
                  const SealGlyph(size: 9),
                  const SizedBox(width: 5),
                  Text(l.doneLabel,
                      style: t.bodySmall?.copyWith(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < reels.length; i++) ...[
          _ReelCard(
            reel: reels[i],
            ordinal: i + 1,
            opening: _opening(reels[i]),
            saved: reels[i].savedReelId == null
                ? null
                : _saved[reels[i].savedReelId!],
            onMake: () => _make(reels[i]),
            onOpen: _openSaved,
          ),
          if (i < reels.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// The first few words of the reel's first verse, so a card says
  /// what it is rather than only where it is.
  String? _opening(SeriesReel r) {
    final ayahs = _ayahs;
    if (ayahs == null || r.startAyah - 1 >= ayahs.length) return null;
    final words = ayahs[r.startAyah - 1].arabic.split(' ');
    final take = words.length > 7 ? 7 : words.length;
    final s = words.take(take).join(' ');
    return take < words.length ? '$s …' : s;
  }
}

/// One reel of the day: what it covers, how long it runs, and either
/// the way to make it or the reel that was made.
class _ReelCard extends StatelessWidget {
  final SeriesReel reel;
  final int ordinal;
  final String? opening;
  final SavedReel? saved;
  final VoidCallback onMake;
  final ValueChanged<SavedReel> onOpen;

  const _ReelCard({
    required this.reel,
    required this.ordinal,
    required this.opening,
    required this.saved,
    required this.onMake,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final done = reel.done;
    final open = saved != null ? () => onOpen(saved!) : null;
    // The card is a button — its verses, its length, its opening words
    // and whether it is done — and the pill inside it stays a button
    // of its own, since on a finished reel the two do different things.
    return Semantics(
      container: true,
      button: true,
      hint: done ? (open == null ? null : l.a11yPlaysReel) : null,
      child: Pressable(
      onTap: done ? open : onMake,
      scale: 0.985,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: done ? AppColors.surfaceRaised : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: done ? AppColors.gold.withValues(alpha: 0.55) : AppColors.stroke,
          ),
          boxShadow: [
            if (done)
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.10),
                blurRadius: 16,
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? AppColors.gold
                          : AppColors.gold.withValues(alpha: 0.10),
                    ),
                    child: done
                        ? const Icon(Icons.check_rounded,
                            size: 17, color: Color(0xFF14100A))
                        : Text(
                            '$ordinal',
                            style: t.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.gold,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.ayahRange(reel.startAyah, reel.endAyah),
                          style: t.titleMedium?.copyWith(fontSize: 15.5),
                        ),
                        Text(
                          '${l.versesCount(reel.ayahCount)} · '
                          '${l.reelLengthAbout(reel.estimateMs)}',
                          style: t.bodyMedium?.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (opening != null) ...[
                const SizedBox(height: 10),
                Text(
                  opening!,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.quran(
                    size: 16,
                    color: done ? AppColors.goldBright : AppColors.textPrimary,
                  ).copyWith(height: 1.5),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (done) ...[
                    Expanded(
                      child: Text(
                        saved == null
                            ? l.doneLabel
                            : '${l.doneLabel} · ${l.formatDate(reel.doneAt!)}',
                        style: t.bodySmall?.copyWith(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _Pill(
                      label: l.makeItAgain,
                      icon: Icons.refresh_rounded,
                      quiet: true,
                      onTap: onMake,
                    ),
                  ] else ...[
                    const Spacer(),
                    _Pill(
                      label: l.makeThisReel,
                      icon: Icons.arrow_forward_rounded,
                      quiet: false,
                      onTap: onMake,
                    ),
                  ],
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

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool quiet;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.icon,
    required this.quiet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: quiet
              ? null
              : const LinearGradient(
                  colors: [AppColors.goldBright, AppColors.gold],
                ),
          border: quiet ? Border.all(color: AppColors.stroke) : null,
          boxShadow: quiet
              ? null
              : [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.25),
                    blurRadius: 12,
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color:
                        quiet ? AppColors.textSecondary : const Color(0xFF14100A),
                  ),
            ),
            const SizedBox(width: 4),
            Icon(icon,
                size: 14,
                color: quiet ? AppColors.textSecondary : const Color(0xFF14100A)),
          ],
        ),
      ),
      ),
    );
  }
}
