import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/verse_follow.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../data/verse_lines.dart';
import '../data/verse_motion.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
import '../state/creation_state.dart' show TextPreset;
import 'ayah_overlay.dart';
import 'measure_height.dart';
import 'verse_flourish.dart';
import 'verse_unit_card.dart';

/// The verse on the live preview: whichever unit — a whole verse, or one
/// line of a long one — the recitation is on, drawn with its motion.
///
/// Everything it shows comes from the same numbers the export is built
/// from: the units ([VerseUnit]), the words' state ([VerseFollow]), the
/// arrival's curves ([VerseMotion]) and the thread and the light
/// ([VerseFlourish], from the card's own layout). The card itself is
/// [VerseUnitCard], the widget the exporter rasterizes.
///
/// Laid out with no system text scaling and no inherited text style,
/// as the exporter lays the card out: a phone set to large text would
/// otherwise preview a bigger verse than it saves.
class VerseStage extends StatefulWidget {
  /// Where the recitation is, in the recording's clock.
  final ValueListenable<int> clock;
  final List<VerseUnit> units;
  final List<Ayah> ayahs;
  final Recitation recitation;
  final VerseMotion motion;

  /// The voice's word windows, whenever it has them (the trail and the
  /// unveil follow these), and whether the word highlight is on.
  final Map<int, List<HighlightSpan>>? words;
  final bool highlight;

  /// Each verse's tokens' recited windows, for the thread and the light.
  final Map<int, List<(int, int)?>>? wordTimes;

  final double width;
  final Color textColor;
  final Color accent;
  final VerseInk ink;
  final VerseInk accentInk;
  final double textScale;
  final TextPreset preset;
  final bool onLight;
  final VerseTranslation translation;
  final VerseNumbering numbering;
  final bool showTranslation;
  final int surah;
  final VerseFace verseFace;
  final TranslationFace translationFace;

  /// The card's laid-out height, as [MeasureHeight] reports it.
  final ValueChanged<double> onHeight;

  const VerseStage({
    super.key,
    required this.clock,
    required this.units,
    required this.ayahs,
    required this.recitation,
    required this.motion,
    required this.words,
    required this.highlight,
    required this.wordTimes,
    required this.width,
    required this.textColor,
    required this.accent,
    required this.ink,
    required this.accentInk,
    required this.textScale,
    required this.preset,
    required this.onLight,
    required this.translation,
    required this.numbering,
    required this.showTranslation,
    required this.surah,
    required this.verseFace,
    required this.translationFace,
    required this.onHeight,
  });

  @override
  State<VerseStage> createState() => _VerseStageState();
}

class _VerseStageState extends State<VerseStage> {
  final _windows = <int, List<FollowWindow>>{};
  final _times = <int, List<(int, int)?>?>{};
  int _unit = 0;
  String _window = '';

  bool get _animates =>
      widget.motion.moves || widget.motion.thread || widget.motion.light;

  @override
  void initState() {
    super.initState();
    widget.clock.addListener(_onClock);
    _sync(widget.clock.value);
  }

  @override
  void didUpdateWidget(covariant VerseStage old) {
    super.didUpdateWidget(old);
    if (!identical(old.clock, widget.clock)) {
      old.clock.removeListener(_onClock);
      widget.clock.addListener(_onClock);
    }
    if (!identical(old.units, widget.units) ||
        !identical(old.words, widget.words) ||
        !identical(old.wordTimes, widget.wordTimes) ||
        old.highlight != widget.highlight ||
        old.motion != widget.motion) {
      _windows.clear();
      _times.clear();
    }
    _sync(widget.clock.value);
  }

  @override
  void dispose() {
    widget.clock.removeListener(_onClock);
    super.dispose();
  }

  /// Rebuilds on every tick only while something moves; otherwise only
  /// when the unit or its words' state changes.
  void _onClock() {
    final changed = _sync(widget.clock.value);
    if ((changed || _animates) && mounted) setState(() {});
  }

  bool _sync(int ms) {
    if (widget.units.isEmpty) return false;
    final i = VerseUnit.indexAt(widget.units, ms);
    final w = VerseFollow.at(_windowsOf(i), ms).key;
    final changed = i != _unit || w != _window;
    _unit = i;
    _window = w;
    return changed;
  }

  List<FollowWindow> _windowsOf(int i) => _windows[i] ??= () {
        final u = widget.units[i];
        return VerseFollow.of(
          unit: u,
          verseStartMs: widget.recitation.timing(u.ayah).startMs,
          spans: widget.words?[u.ayah],
          highlight: widget.highlight,
          trail: widget.motion.trail,
          unveil: widget.motion.unveil,
        );
      }();

  List<(int, int)?>? _timesOf(int i) => _times.putIfAbsent(i, () {
        final u = widget.units[i];
        return u.timesIn(widget.wordTimes?[u.ayah],
            widget.recitation.timing(u.ayah).startMs);
      });

  @override
  Widget build(BuildContext context) {
    if (widget.units.isEmpty) return const SizedBox.shrink();
    final ms = widget.clock.value;
    final i = VerseUnit.indexAt(widget.units, ms);
    final u = widget.units[i];
    final ayah = widget.ayahs[u.ayah - 1];
    final w = VerseFollow.at(_windowsOf(i), ms);
    final into = (ms - u.startMs).clamp(0, u.durationMs);
    final m = widget.motion;
    final s = widget.width / 1080;

    Widget card = VerseUnitCard(
      ayah: ayah,
      part: u.part,
      width: widget.width,
      textColor: widget.textColor,
      textScale: widget.textScale,
      preset: widget.preset,
      onLight: widget.onLight,
      translation: widget.translation,
      numbering: widget.numbering,
      showTranslation: widget.showTranslation,
      surah: widget.surah,
      verseFace: widget.verseFace,
      translationFace: widget.translationFace,
      accent: widget.accent,
      ink: widget.ink,
      accentInk: widget.accentInk,
      highlightTokens: w.lit,
      dimFrom: w.dimFrom,
    );
    if (m.thread || m.light) {
      final fit = u.part?.fit ??
          AyahOverlay.fitFor(ayah, showTranslation: widget.showTranslation);
      card = VerseFlourish(
        arabic: VerseUnitCard.textOf(ayah, u.part).arabic,
        scale: s,
        ts: s *
            widget.textScale *
            fit *
            (widget.preset == TextPreset.minimal ? 0.85 : 1.0),
        ms: into,
        unitMs: u.durationMs,
        motion: m,
        times: _timesOf(i),
        accent: widget.accent,
        lightTint: AyahOverlay.lightTintOf(widget.accent, widget.accentInk),
        child: card,
      );
    }
    if (m.moves) {
      card = Transform.translate(
        offset: Offset(0, m.offsetAt(into, u.durationMs) * s),
        child: Opacity(
          opacity: m.alphaAt(into, u.durationMs),
          child: RepaintBoundary(child: card),
        ),
      );
      card = KeyedSubtree(key: ValueKey(i), child: card);
    } else {
      // A reel with no motion keeps the preview's crossfade between
      // verses, as it always had.
      card = AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(key: ValueKey(i), child: card),
      );
    }
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: DefaultTextStyle(
        style: const TextStyle(),
        child: MeasureHeight(onChange: widget.onHeight, child: card),
      ),
    );
  }
}
