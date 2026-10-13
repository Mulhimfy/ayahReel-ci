import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/debug_log.dart';
import '../data/models.dart';
import '../data/quran_repository.dart';
import '../data/series_library.dart';
import '../data/series_planner.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/glow_button.dart';
import '../widgets/illumination.dart';
import '../widgets/surah_picker_sheet.dart';
import 'reciter_screen.dart';
import 'series_screen.dart';

/// The four decisions a series is made of, on one page: how many days,
/// how many reels a day, which surah, whose voice — and, once the
/// surah's text has been read, what those add up to, said plainly
/// above the button that commits to it.
class SeriesSetupScreen extends StatefulWidget {
  const SeriesSetupScreen({super.key});

  @override
  State<SeriesSetupScreen> createState() => _SeriesSetupScreenState();
}

class _SeriesSetupScreenState extends State<SeriesSetupScreen> {
  /// The day presets. 0 stands for "let the surah decide".
  static const _dayOptions = [3, 7, 10, 14, 30, 0];
  static const _perDayOptions = [1, 2, 3];

  int _days = 7;
  int _perDay = 1;
  SurahInfo? _surah;
  Reciter? _reciter;

  /// The chosen surah's verses, once read. Null while loading, or
  /// when nothing is chosen yet.
  List<Ayah>? _ayahs;
  bool _loadingText = false;
  bool _textFailed = false;
  bool _planning = false;

  Future<void> _pickSurah() async {
    final picked = await showSurahPicker(context,
        unavailable: _reciter?.missingSurahs ?? const {});
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _surah = picked.surah;
      _ayahs = QuranRepository.ayahsIfCached(picked.number);
      _textFailed = false;
    });
    if (_ayahs != null) return;
    setState(() => _loadingText = true);
    try {
      final ayahs = await QuranRepository.ayahsOf(picked.number);
      if (mounted && _surah?.number == picked.number) {
        setState(() => _ayahs = ayahs);
      }
    } catch (e, s) {
      rlogError('series: surah text', e, s);
      if (mounted && _surah?.number == picked.number) {
        setState(() => _textFailed = true);
      }
    } finally {
      if (mounted) setState(() => _loadingText = false);
    }
  }

  void _pickVoice() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReciterScreen(
          initialReciterId: _reciter?.id,
          surah: _surah?.number,
          onContinue: (ctx, r) {
            setState(() => _reciter = r);
            Navigator.of(ctx).pop();
          },
        ),
      ),
    );
  }

  /// How many reels the days asked for come to, before the surah has
  /// its say.
  int _reelsAsked(List<Ayah> ayahs) =>
      (_days == 0 ? 1 : _days * _perDay).clamp(1, ayahs.length);

  /// How many reels the current choices make, over these verses.
  ///
  /// Never fewer than the surah needs under a minute a reel. Seven
  /// days of Al-Baqarah used to mean seven reels of seven minutes:
  /// the day count was taken as the reel count, and the reel's own
  /// length — the minute the feeds it goes to are built around — was
  /// never consulted. Now the minute holds *and* the days hold: the
  /// extra reels go onto the days the user chose, more to a day,
  /// which is what the summary line under the questions reads back.
  int _reelCount(List<Ayah> ayahs) {
    final pace = _reciter?.pace ?? 1.0;
    final needed = SeriesPlanner.suggestedReels(ayahs, pace: pace);
    final n = _days == 0 ? needed : max(_days * _perDay, needed);
    return n.clamp(1, ayahs.length);
  }

  List<SeriesCut>? _preview() {
    final ayahs = _ayahs;
    final surah = _surah;
    if (ayahs == null || surah == null) return null;
    return SeriesPlanner.split(
      surah: surah.number,
      ayahs: ayahs,
      reels: _reelCount(ayahs),
      pace: _reciter?.pace ?? 1.0,
    );
  }

  bool get _ready =>
      _surah != null && _reciter != null && _ayahs != null && !_planning;

  Future<void> _plan() async {
    final cuts = _preview();
    final surah = _surah;
    final reciter = _reciter;
    if (cuts == null || surah == null || reciter == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _planning = true);
    final series = ReelSeries.plan(
      surah: surah.number,
      reciterId: reciter.id,
      perDay: _days == 0 ? 1 : _perDay,
      days: _days == 0 ? null : _days,
      cuts: cuts,
    );
    await SeriesLibrary.add(series);
    rlog('series: planned ${surah.number} over ${series.days} days, '
        '${series.reels.length} reels, voice ${reciter.id}');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SeriesScreen(seriesId: series.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final t = Theme.of(context).textTheme;
    final cuts = _preview();
    final ayahs = _ayahs;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textSecondary),
        title: Text(l.seriesTitle, style: t.titleMedium),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                children: [
                  _Question(
                    label: l.howManyDays,
                    note: _days == 0 ? l.autoDaysBody : null,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in _dayOptions)
                          _Chip(
                            label: d == 0 ? l.autoDays : l.daysCount(d),
                            selected: _days == d,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _days = d);
                            },
                          ),
                      ],
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _days == 0
                        ? const SizedBox(width: double.infinity)
                        : _Question(
                            label: l.reelsADay,
                            child: Wrap(
                              spacing: 8,
                              children: [
                                for (final p in _perDayOptions)
                                  _Chip(
                                    label: l.reelsCount(p),
                                    selected: _perDay == p,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _perDay = p);
                                    },
                                  ),
                              ],
                            ),
                          ),
                  ),
                  _Question(
                    label: l.whichSurah,
                    child: _Selector(
                      icon: Icons.menu_book_rounded,
                      title: _surah == null
                          ? l.chooseASurah
                          : l.surahTitle(_surah!),
                      subtitle: _surah == null
                          ? null
                          : l.versesCount(_surah!.ayahCount),
                      trailing: _surah != null && !l.usesArabicNames
                          ? Text(_surah!.nameArabic,
                              style: AppTheme.quran(
                                  size: 18, color: AppColors.textPrimary))
                          : null,
                      chosen: _surah != null,
                      onTap: _pickSurah,
                      hint: l.a11yOpensSurahPicker,
                    ),
                  ),
                  _Question(
                    label: l.whoseVoice,
                    child: _Selector(
                      icon: Icons.graphic_eq_rounded,
                      title: _reciter == null
                          ? l.chooseAVoice
                          : l.reciterName(_reciter!),
                      subtitle:
                          _reciter == null ? null : l.reciterStyle(_reciter!),
                      trailing: _reciter != null && !l.usesArabicNames
                          ? Text(_reciter!.arabicName,
                              style: AppTheme.quran(
                                  size: 15, color: AppColors.textSecondary))
                          : null,
                      chosen: _reciter != null,
                      onTap: _pickVoice,
                      hint: l.a11yOpensVoicePicker,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // What the choices come to, once there is a surah to
                  // count. Gold, because it is the one line on the
                  // page that says what will happen.
                  // Live: it is the one line that says what the
                  // choices above add up to, and it changes as they do.
                  A11yLive(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _summary(l, t, cuts, ayahs),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlowButton(
                    label: l.planTheSeries,
                    icon: Icons.auto_awesome_rounded,
                    busy: _planning,
                    onPressed: _ready ? _plan : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(
      L10n l, TextTheme t, List<SeriesCut>? cuts, List<Ayah>? ayahs) {
    if (_loadingText) {
      return _SummaryLine(
        key: const ValueKey('loading'),
        icon: Icons.hourglass_top_rounded,
        text: l.seriesLoadingSurah,
      );
    }
    if (_textFailed) {
      return _SummaryLine(
        key: const ValueKey('failed'),
        icon: Icons.cloud_off_rounded,
        text: l.surahLoadError.replaceAll('\n', ' '),
        action: QuietButton(
          label: l.tryAgain,
          dense: true,
          icon: Icons.refresh_rounded,
          onPressed: () {
            final s = _surah;
            if (s == null) return;
            setState(() => _surah = null);
            _surah = s;
            _pickSurahAgain(s);
          },
        ),
      );
    }
    if (cuts == null || ayahs == null) {
      return const SizedBox(key: ValueKey('none'), height: 0);
    }
    final byDay = _days == 0
        ? SeriesPlanner.byDay(cuts, 1)
        : SeriesPlanner.overDays(cuts, _days);
    final days = byDay.length;
    final each = cuts.fold<int>(0, (a, c) => a + c.estimateMs) ~/ cuts.length;
    final wanted = _days == 0 ? cuts.length : _days * _perDay;
    final short = wanted > ayahs.length;
    // The minute cap asked for more reels than the days did: say how
    // many a day that makes, because the reels-a-day chip still reads
    // the number the user tapped.
    final stretched = _days != 0 && cuts.length > _reelsAsked(ayahs);
    final mostADay = byDay.fold<int>(0, (a, d) => d.length > a ? d.length : a);
    return Column(
      key: ValueKey('summary-${cuts.length}-$days-$each'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine(
          icon: Icons.auto_awesome_rounded,
          text: l.seriesSummary(cuts.length, days, each),
        ),
        if (stretched) ...[
          const SizedBox(height: 4),
          Text(
            l.seriesUnderAMinute(mostADay),
            style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        if (short) ...[
          const SizedBox(height: 4),
          Text(
            l.seriesShortSurah(ayahs.length),
            style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  /// Retries the text for a surah that failed to load, without asking
  /// the user to pick it again.
  Future<void> _pickSurahAgain(SurahInfo s) async {
    setState(() {
      _surah = s;
      _textFailed = false;
      _loadingText = true;
    });
    try {
      final ayahs = await QuranRepository.ayahsOf(s.number);
      if (mounted && _surah?.number == s.number) {
        setState(() => _ayahs = ayahs);
      }
    } catch (_) {
      if (mounted) setState(() => _textFailed = true);
    } finally {
      if (mounted) setState(() => _loadingText = false);
    }
  }
}

/// One of the page's questions: a small gold caption and the control.
class _Question extends StatelessWidget {
  final String label;
  final Widget child;
  final String? note;

  const _Question({required this.label, this.note, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SealGlyph(size: 7, color: Color(0x99D4A947)),
              const SizedBox(width: 8),
              // A heading, read in its own case: capitals are for the
              // eye, and some readers spell an all-caps word out.
              Semantics(
                container: true,
                header: true,
                label: label,
                excludeSemantics: true,
                child: Text(
                  l.arabicScript ? label : label.toUpperCase(),
                  style: t.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: l.arabicScript ? 0 : 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!, style: t.bodySmall?.copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return A11yTap(
      selected: selected,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.stroke,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.12),
                blurRadius: 14,
              ),
          ],
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color:
                    selected ? AppColors.goldBright : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
        ),
      ),
      ),
    );
  }
}

/// A row that opens a picker, and shows what it picked.
class _Selector extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool chosen;
  final VoidCallback onTap;

  /// What a screen reader says a double tap opens.
  final String? hint;

  const _Selector({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.chosen,
    required this.onTap,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      hint: hint,
      child: Material(
      color: chosen ? AppColors.surfaceRaised : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: chosen ? AppColors.gold : AppColors.stroke,
              width: chosen ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen
                      ? AppColors.gold
                      : AppColors.gold.withValues(alpha: 0.12),
                ),
                child: Icon(icon,
                    size: 19,
                    color: chosen ? const Color(0xFF14100A) : AppColors.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: t.titleMedium?.copyWith(
                          fontSize: 15.5,
                          color: chosen
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        )),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: t.bodyMedium?.copyWith(fontSize: 12.5)),
                  ],
                ),
              ),
              // The Arabic name beside an English row is the same name
              // again, so it is left to the eye.
              if (trailing != null) ...[
                ExcludeSemantics(child: trailing!),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.unfold_more_rounded,
                  size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _SummaryLine({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: AppColors.gold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.gold.withValues(alpha: 0.92),
                ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}
