import 'models.dart';

/// How long a selection of verses will run.
///
/// Exact once the recitation is on the device — its timing table is
/// built from the measured files, so there is nothing to estimate. The
/// interesting case is the other one: the verse picker runs before a
/// note of audio has been fetched, and until it could answer this, the
/// cap was left to the preview. A user could pick two hours of
/// Al-Baqarah, watch the download, and only then be told the reel had
/// been cut back to an hour — a decision taken on their behalf, three
/// screens after they made it.
///
/// So the picker estimates, and the estimate is good enough to hold a
/// cap with: recitation length tracks letter count closely, because
/// what a reciter is doing is pronouncing letters. The model is one
/// multiplication and one addition per verse —
///
///     ms ≈ [_perAyahMs] + [_perLetterMs] × letters
///
/// — where the constant per verse is the breath and pause at its end,
/// which does not scale with how long the verse is.
///
/// Calibrated against two things that agree: the bundled Al-Fatiha
/// timings (exact, measured with ffprobe) and the length of a complete
/// murattal recitation of the Quran over its letter count. Al-Fatiha
/// alone would set the rate about a fifth too slow — it is recited more
/// deliberately than the rest — so the constants sit between the two,
/// and land within roughly a fifth either way for a murattal voice.
///
/// That is a warning's worth of accuracy, not a timing table's, and
/// nothing downstream treats it as more: the preview re-checks against
/// the real recitation and still trims if it has to. What this buys is
/// that it almost never has to.
///
/// Pure — no I/O, no plugins — so all of it is testable off-device.
abstract final class ReelDuration {
  /// Milliseconds per Arabic letter, at a typical murattal pace.
  static const _perLetterMs = 230;

  /// The end of a verse, whatever its length: the reciter's breath and
  /// the gap before the next one.
  static const _perAyahMs = 1200;

  /// Estimated length of [startAyah]..[endAyah] (1-based, inclusive)
  /// read at [pace] — see [Reciter.pace].
  ///
  /// [ayahs] is the surah, in order from its first verse; verses the
  /// list does not reach are counted at the surah's own average rather
  /// than dropped, so a partially loaded surah cannot make a selection
  /// look shorter than it is.
  static int estimateMs(
    List<Ayah> ayahs, {
    required int startAyah,
    required int endAyah,
    double pace = 1.0,
  }) {
    if (ayahs.isEmpty || endAyah < startAyah) return 0;
    var ms = 0;
    var counted = 0;
    for (var n = startAyah; n <= endAyah; n++) {
      final i = n - 1;
      if (i < 0 || i >= ayahs.length) continue;
      ms += _perAyahMs + _perLetterMs * lettersIn(ayahs[i].arabic);
      counted++;
    }
    if (counted == 0) return 0;
    final asked = endAyah - startAyah + 1;
    // Whole verses missing from the list: charge them the average of
    // the ones that are there.
    final scaled = counted == asked ? ms : (ms / counted * asked).round();
    return (scaled * pace).round();
  }

  /// Letters in [arabic] — what the reciter actually pronounces.
  ///
  /// Vowel marks, the superscript alef, sukun, shadda and the waqf
  /// signs are all excluded: they change how a letter is said, not how
  /// many there are, and counting them would make a fully vocalized
  /// text (which the app's is) read as three times its own length.
  /// Tatweel is excluded for the same reason — it is a typographic
  /// stretch, silent by definition.
  static int lettersIn(String arabic) {
    var n = 0;
    for (final c in arabic.runes) {
      if (c == 0x0640) continue; // tatweel
      if ((c >= 0x0621 && c <= 0x063A) ||
          (c >= 0x0641 && c <= 0x064A) ||
          (c >= 0x066E && c <= 0x066F) ||
          (c >= 0x0671 && c <= 0x06D3)) {
        n++;
      }
    }
    return n;
  }
}
