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

      final cuts = VerseSplitter.split(
        tokens,
        (s, e) => linesOf(tokens, s, e, look, a) <= lines,
        held: timed?.held ?? const {},
        // Without word timing a cut is timed by the reciter's breath,
        // which a phrase cut in two rarely has.
        plainCost: timed != null
            ? VerseSplitter.plainCutCost
            : VerseSplitter.plainCutCost * 1.6,
      );
      if (cuts == null) continue;

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
          final p = PartTiming.pausesIn(e, q, t.startMs, t.endMs);
          bounds = PartTiming.fromPauses(
            cuts: cuts,
            letters: [for (final k in tokens) VerseText.letters(k)],
            verseStartMs: t.startMs,
            verseEndMs: t.endMs,
            pauses: p.pauses,
            voicedStartMs: p.voicedStart,
            voicedEndMs: p.voicedEnd,
          );
        }
      }
      // Neither timing could place the cuts: the verse is shown whole,
      // as it always was, rather than changing mid-word.
      if (bounds == null) continue;

      final total = tokens.fold<int>(0, (n, k) => n + VerseText.letters(k));
      var before = 0;
      final shares = <double>[];
      for (var c = 1; c < cuts.length - 1; c++) {
        for (var k = cuts[c - 1]; k < cuts[c]; k++) {
          before += VerseText.letters(tokens[k]);
        }
        shares.add(total == 0 ? c / (cuts.length - 1) : before / total);
      }
      final pieces = look.showTranslation
          ? TranslationSplit.split(ayah.translation, shares)
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
    return VerseLinePlan(lines, byAyah);
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
      int lines, VerseLook look) {
    final key = '$start-$end-$lines-${look.key}-${ayahs.length}';
    final hit = _estimates[key];
    if (hit != null) return hit;
    final out = <String>[];
    for (var a = start; a <= end && a - 1 < ayahs.length; a++) {
      final text = ayahs[a - 1].arabic;
      final tokens = VerseText.tokens(text);
      final cuts = lines <= VerseLines.whole || tokens.length < 2
          ? null
          : VerseSplitter.split(
              tokens, (s, e) => linesOf(tokens, s, e, look, a) <= lines);
      if (cuts == null) {
        out.add(text);
      } else {
        for (var i = 0; i < cuts.length - 1; i++) {
          out.add(tokens.sublist(cuts[i], cuts[i + 1]).join(' '));
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
          : estimateLines(ayahs, start, end, lines, look).length;

  static final _estimates = <String, List<String>>{};

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
