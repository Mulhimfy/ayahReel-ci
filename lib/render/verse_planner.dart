import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/surah_slice.dart';
import '../data/verse_font.dart';
import '../data/verse_ink.dart';
import '../data/verse_lines.dart';
import '../data/verse_numbering.dart';
import '../data/verse_translation.dart';
import '../data/word_align_service.dart';
import '../state/creation_state.dart' show TextPreset;
import '../widgets/ayah_overlay.dart';
import '../widgets/verse_unit_card.dart';
import 'ayah_rasterizer.dart';

/// Everything a verse card's layout answers to — what a plan of cut
/// verses has to be made again for when any of it changes. Colours are
/// not in it: they move no line.
@immutable
class VerseLook {
  final double textScale;
  final TextPreset preset;
  final ReelTypography typography;
  final VerseTranslation edition;
  final VerseNumbering numbering;
  final bool showTranslation;
  final VerseInk ink;
  final int surah;

  const VerseLook({
    required this.textScale,
    required this.preset,
    required this.typography,
    required this.edition,
    required this.numbering,
    required this.showTranslation,
    required this.ink,
    required this.surah,
  });

  String get key => '${(textScale * 100).round()}_${preset.index}'
      '_${typography.key}_${edition.code}_${numbering.code}'
      '_${showTranslation ? 1 : 0}_${ink.isNone ? 0 : 1}_$surah';

  @override
  bool operator ==(Object other) => other is VerseLook && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Works out which verses of a reel are cut into lines, where, and when
/// each part comes on — see [VerseSplitter] and [PartTiming] for the two
/// halves of that, which are pure. This is the half that needs the
/// phone: laying the text out in the card's own face to know where its
/// lines break, and measuring each part's card.
///
/// Runs on the UI isolate, as everything that lays text out does. A
/// verse is only measured when it is long enough to need cutting, and
/// the frame is let through between verses.
abstract final class VersePlanner {
  static Future<VerseLinePlan> plan({
    required int lines,
    required List<Ayah> ayahs,
    required Recitation recitation,
    required int startAyah,
    required int endAyah,
    required VerseLook look,

    /// The voice's word timing, by verse; null when it has none.
    Map<int, List<WordSpan>>? words,

    /// The recording's loudness, asked for only when a verse needs
    /// cutting and the voice has no word timing.
    Future<List<double>?> Function()? loudness,
    bool Function()? keepGoing,
  }) async {
    if (lines <= VerseLines.whole) return VerseLinePlan.empty;
    final byAyah = <int, List<VersePart>>{};
    List<double>? env;
    double? quiet;
    var envAsked = false;
    final segStart = recitation.timing(startAyah).startMs;
    final segEnd = recitation.timing(endAyah).endMs;

    var whole = 0;
    for (var a = startAyah; a <= endAyah; a++) {
      if (keepGoing != null && !keepGoing()) break;
      if (a - 1 >= ayahs.length) break;
      final ayah = ayahs[a - 1];
      final tokens = VerseText.tokens(ayah.arabic);
      if (tokens.length < 2) continue;
      final spans = words?[a];
      final timed = spans == null || spans.isEmpty
          ? null
          : WordAlignService.tokenWindows(ayah.arabic, spans);
      bool fits(int s, int e) => linesOf(tokens, s, e, look, a) <= lines;

      final textCuts = VerseSplitter.split(
        tokens,
        fits,
        held: timed?.held ?? const {},
        // Without word timing a cut is timed by the reciter's breath,
        // which a phrase cut in two rarely has.
        plainCost: timed != null
            ? VerseSplitter.plainCutCost
            : VerseSplitter.plainCutCost * 1.6,
      );
      if (textCuts == null) continue;
      List<int> cuts = textCuts;

      final t = recitation.timing(a);
      List<int>? bounds;
      if (timed != null) {
        bounds = PartTiming.fromWords(
          cuts: cuts,
          times: timed.times,
          verseStartMs: t.startMs,
          verseEndMs: t.endMs,
        );
      } else if (loudness != null) {
        if (!envAsked) {
          envAsked = true;
          env = await loudness();
          final e = env;
          if (e != null && e.isNotEmpty) {
            final lo = (segStart ~/ 10).clamp(0, e.length);
            final hi = (segEnd ~/ 10).clamp(lo, e.length);
            quiet = SurahSlice.quietBelow(
                hi > lo ? e.sublist(lo, hi) : e);
          }
        }
        final e = env;
        final q = quiet;
        if (e != null && q != null) {
          final letters = [for (final k in tokens) VerseText.letters(k)];
          final p = PartTiming.pausesIn(e, q, t.startMs, t.endMs);
          final breaths = PartTiming.breathsIn(e, q, t.startMs, t.endMs);
          // Cut again, now that the breaths are known, preferring the
          // cuts the reciter can be heard to breathe at.
          final heard = p.voicedStart == null || p.voicedEnd == null
              ? const <int>{}
              : PartTiming.cutsAtBreaths(
                  letters: letters,
                  breaths: breaths,
                  voicedStartMs: p.voicedStart!,
                  voicedEndMs: p.voicedEnd!,
                );
          if (heard.isNotEmpty) {
            cuts = VerseSplitter.split(
                  tokens,
                  fits,
                  plainCost: VerseSplitter.plainCutCost * 1.6,
                  breaths: heard,
                ) ??
                cuts;
          }
          final placed = PartTiming.fromBreaths(
            cuts: cuts,
            letters: letters,
            verseStartMs: t.startMs,
            verseEndMs: t.endMs,
            breaths: breaths,
            env: e,
            voicedStartMs: p.voicedStart,
            voicedEndMs: p.voicedEnd,
          );
          // A voice timed everywhere else (the rare verse neither of
          // its tiers reaches) is cut only where every line change falls
          // on a breath: a guessed one, placed by its letters alone, can
          // put a line seconds off its words, and the verse is better
          // whole (the owner, 2026-10-27). A recording with no timing at
          // all, the user's own, is cut on its guesses as before.
          bounds = placed == null || (words != null && placed.guessed > 0)
              ? null
              : placed.bounds;
        }
      }
      // Neither timing could place the cuts: the verse is shown whole,
      // as it always was, and the lines control says some verses are.
      if (bounds == null) {
        whole++;
        continue;
      }

      final pieces = look.showTranslation
          ? TranslationSplit.forCuts(ayah.translation, tokens, cuts)
          : List.filled(cuts.length - 1, '');
      final fit = look.showTranslation
          ? pieces
              .map((p) => AyahOverlay.translationFit(p.length))
              .fold<double>(1, math.min)
          : 1.0;
      var parts = [
        for (var i = 0; i < cuts.length - 1; i++)
          VersePart(
            ayah: a,
            index: i,
            count: cuts.length - 1,
            tokenStart: cuts[i],
            tokenEnd: cuts[i + 1],
            startMs: bounds[i],
            endMs: bounds[i + 1],
            arabic: tokens.sublist(cuts[i], cuts[i + 1]).join(' '),
            translation: pieces[i],
            fit: fit,
          ),
      ];
      var tallest = 0.0;
      for (final p in parts) {
        tallest = math.max(tallest, AyahRasterizer.unitHeight(_card(ayah, p, look)));
      }
      parts = [for (final p in parts) p.withHeight(tallest.ceilToDouble())];
      byAyah[a] = parts;
      // Let a frame through: a reel of long verses is a few dozen
      // layouts, and none of them should be felt.
      await Future<void>.delayed(Duration.zero);
    }
    return VerseLinePlan(lines, byAyah, whole: whole);
  }

  static Widget _card(Ayah ayah, VersePart part, VerseLook look) =>
      VerseUnitCard(
        ayah: ayah,
        part: part,
        width: AyahRasterizer.exportWidth,
        textColor: Colors.white,
        textScale: look.textScale,
        preset: look.preset,
        onLight: false,
        translation: look.edition,
        numbering: look.numbering,
        showTranslation: look.showTranslation,
        surah: look.surah,
        verseFace: look.typography.verse,
        translationFace: look.typography.translation,
        ink: look.ink,
      );

  /// How many lines tokens `[s, e)` of a verse take on its card at full
  /// size; the verse's last part carries the verse-end sign.
  static int linesOf(
      List<String> tokens, int s, int e, VerseLook look, int ayahNumber) {
    final style = AyahOverlay.verseLayoutStyle(
      width: AyahRasterizer.exportWidth,
      textScale: look.textScale,
      preset: look.preset,
      face: look.typography.verse,
      fit: 1,
    );
    final mark = e == tokens.length && look.numbering.showsMark
        ? AyahOverlay.endMarkLayoutSpan(
            width: AyahRasterizer.exportWidth,
            textScale: look.textScale,
            preset: look.preset,
            face: look.typography.verse,
            fit: 1,
            ayah: ayahNumber,
          )
        : null;
    final tp = TextPainter(
      text: TextSpan(style: style, children: [
        TextSpan(text: tokens.sublist(s, e).join(' ')),
        if (mark != null) mark,
      ]),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: AyahOverlay.lineWidth(AyahRasterizer.exportWidth));
    final n = tp.computeLineMetrics().length;
    tp.dispose();
    return n;
  }

  /// The text of every unit — whole verses, and the lines of the ones a
  /// plan would cut — [start]..[end] comes to, from the text alone: what
  /// the scenery screen counts a scene per line by, and lets each line
  /// choose its own scenery by, before any recitation is timed. A verse
  /// whose cuts end up untimeable is shown whole, so this is the most
  /// there will be.
  static List<String> estimateLines(List<Ayah> ayahs, int start, int end,
          int lines, VerseLook look) =>
      [for (final p in estimateParts(ayahs, start, end, lines, look)) p.text];

  /// [estimateLines], each with the verse it is from and the display
  /// token it starts on (0 for a verse shown whole): where a scenery
  /// chosen for a line belongs, whatever the lines come to later.
  static List<({int ayah, int token, String text})> estimateParts(
      List<Ayah> ayahs, int start, int end, int lines, VerseLook look) {
    final key = '$start-$end-$lines-${look.key}-${ayahs.length}';
    final hit = _estimates[key];
    if (hit != null) return hit;
    final out = <({int ayah, int token, String text})>[];
    for (var a = start; a <= end && a - 1 < ayahs.length; a++) {
      final text = ayahs[a - 1].arabic;
      final tokens = VerseText.tokens(text);
      final cuts = lines <= VerseLines.whole || tokens.length < 2
          ? null
          : VerseSplitter.split(
              tokens, (s, e) => linesOf(tokens, s, e, look, a) <= lines);
      if (cuts == null) {
        out.add((ayah: a, token: 0, text: text));
      } else {
        for (var i = 0; i < cuts.length - 1; i++) {
          out.add((
            ayah: a,
            token: cuts[i],
            text: tokens.sublist(cuts[i], cuts[i + 1]).join(' '),
          ));
        }
      }
    }
    if (_estimates.length > 32) _estimates.clear();
    return _estimates[key] = out;
  }

  /// How many of those units there are.
  static int estimateUnits(List<Ayah> ayahs, int start, int end, int lines,
          VerseLook look) =>
      lines <= VerseLines.whole
          ? end - start + 1
          : estimateParts(ayahs, start, end, lines, look).length;

  static final _estimates =
      <String, List<({int ayah, int token, String text})>>{};

  /// [ayah] as if recited at an even pace — every letter as long as the
  /// next, a breath before each line — and cut the way [plan] cuts it
  /// from its text: what a demonstration plays to show what the line,
  /// the motion and the highlight choices do, with nothing recorded.
  ///
  /// The units to show in turn, the words' highlight windows and each
  /// token's recited window — both in the verse's own time, which
  /// starts at 0 — and how long the verse runs.
  static ({
    List<VerseUnit> units,
    List<HighlightSpan> spans,
    List<(int, int)?> times,
    int verseMs,
  }) demo({
    required Ayah ayah,
    required int lines,
    required VerseLook look,
    int msPerLetter = 78,
    int breathMs = 360,
  }) {
    final tokens = VerseText.tokens(ayah.arabic);
    final letters = [for (final t in tokens) VerseText.letters(t)];
    final cuts = (lines <= VerseLines.whole || tokens.length < 2
            ? null
            : VerseSplitter.split(tokens,
                (s, e) => linesOf(tokens, s, e, look, ayah.number) <= lines)) ??
        [0, tokens.length];
    final times = List<(int, int)?>.filled(tokens.length, null);
    final bounds = <int>[0];
    var t = 0;
    for (var c = 0; c < cuts.length - 1; c++) {
      t += breathMs;
      for (var k = cuts[c]; k < cuts[c + 1]; k++) {
        if (letters[k] == 0) {
          // A pause sign takes its word's window, as real timing does.
          if (k > 0) times[k] = times[k - 1];
          continue;
        }
        final len = letters[k] * msPerLetter;
        times[k] = (t, t + (len * 0.88).round());
        t += len;
      }
      bounds.add(t + (c == cuts.length - 2 ? breathMs : breathMs ~/ 2));
    }
    final verseMs = bounds.last;
    // Gap-filled to the next word, as the highlight's windows are.
    final words = [
      for (var k = 0; k < tokens.length; k++)
        if (letters[k] > 0) k,
    ];
    final spans = <HighlightSpan>[
      for (var i = 0; i < words.length; i++)
        HighlightSpan(
          times[words[i]]!.$1,
          i + 1 < words.length ? times[words[i + 1]]!.$1 : verseMs,
          words[i],
          i + 1 < words.length ? words[i + 1] : tokens.length,
        ),
    ];
    if (cuts.length <= 2) {
      return (
        units: [VerseUnit(ayah.number, null, 0, verseMs)],
        spans: spans,
        times: times,
        verseMs: verseMs,
      );
    }
    final pieces = look.showTranslation
        ? TranslationSplit.forCuts(ayah.translation, tokens, cuts)
        : List.filled(cuts.length - 1, '');
    final fit = look.showTranslation
        ? pieces
            .map((p) => AyahOverlay.translationFit(p.length))
            .fold<double>(1, math.min)
        : 1.0;
    var parts = [
      for (var i = 0; i < cuts.length - 1; i++)
        VersePart(
          ayah: ayah.number,
          index: i,
          count: cuts.length - 1,
          tokenStart: cuts[i],
          tokenEnd: cuts[i + 1],
          startMs: bounds[i],
          endMs: bounds[i + 1],
          arabic: tokens.sublist(cuts[i], cuts[i + 1]).join(' '),
          translation: pieces[i],
          fit: fit,
        ),
    ];
    var tallest = 0.0;
    for (final p in parts) {
      tallest =
          math.max(tallest, AyahRasterizer.unitHeight(_card(ayah, p, look)));
    }
    parts = [for (final p in parts) p.withHeight(tallest.ceilToDouble())];
    return (
      units: [for (final p in parts) VerseUnit(ayah.number, p, p.startMs, p.endMs)],
      spans: spans,
      times: times,
      verseMs: verseMs,
    );
  }

  /// Each verse's tokens' recited windows, from word timing: what the
  /// thread, the light and the follow cards are timed by.
  static Map<int, List<(int, int)?>> wordTimes(
      List<Ayah> ayahs, Map<int, List<WordSpan>> words, int start, int end) {
    final out = <int, List<(int, int)?>>{};
    for (var a = start; a <= end; a++) {
      final spans = words[a];
      if (spans == null || spans.isEmpty || a - 1 >= ayahs.length) continue;
      out[a] = WordAlignService.tokenWindows(ayahs[a - 1].arabic, spans).times;
    }
    return out;
  }
}
