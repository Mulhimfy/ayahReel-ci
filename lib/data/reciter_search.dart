import 'models.dart';
import 'quran_search.dart';

/// Finding a voice in the reciter list by what someone types.
///
/// Names are written a dozen ways. The same reciter is Ad-Dussary,
/// Al-Dosari and Aldossary; Ash-Shuraym and Al-Shuraim; Al-Thubaiti and
/// Al-Toubayti — and whichever one the list chose, somebody will type
/// another. So a Latin query is matched twice: as typed, letters and
/// digits only, and as its consonant skeleton, which is what those
/// spellings share (dsr, shrm, tbt). The article is spelled so many ways
/// (al, el, ad, ash…) that on its own, beside a name, it is not matched
/// at all, and a name typed with it glued on (Aldossary) is also tried
/// without it. Arabic goes through [QuranSearch.normalize], so hamza seats,
/// alef forms and marks don't matter, and spaces are dropped, so
/// عبد الرحمن is عبدالرحمن.
///
/// Every word of the query has to match something about the voice —
/// its name in either script, or its style line in English or in the
/// language on screen — so "husary mujawwad" finds one voice, not two.
///
/// Pure: no Flutter, no I/O.
abstract final class ReciterSearch {
  /// The voices in [all] that [query] finds, in list order. [styleOf]
  /// is the style line as shown on screen, so a query in the app's
  /// language matches it too.
  static List<Reciter> filter(
    Iterable<Reciter> all,
    String query, {
    String Function(Reciter r)? styleOf,
  }) {
    final words = query.trim().split(RegExp(r'[\s\-]+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.length > 1) {
      words.removeWhere((w) => _articles.contains(latinKey(w)));
    }
    if (words.isEmpty) return all.toList();
    return [
      for (final r in all)
        if (words.every((w) => _matches(r, w, styleOf))) r,
    ];
  }

  static bool _matches(
      Reciter r, String word, String Function(Reciter r)? styleOf) {
    final fields = [r.name, r.style, if (styleOf != null) styleOf(r)];
    if (_arabic.hasMatch(word)) {
      final q = arabicKey(word);
      if (q.isEmpty) return true;
      return [r.arabicName, ...fields].any((f) => arabicKey(f).contains(q));
    }
    final q = latinKey(word);
    if (q.isEmpty) return true;
    final forms = [
      q,
      for (final a in const ['al', 'el'])
        if (q.startsWith(a) && q.length - a.length >= 3) q.substring(a.length),
    ];
    return forms.any((q) {
      final bone = skeleton(q);
      return fields.any((f) =>
          latinKey(f).contains(q) ||
          // Three consonants at least: "al" or "ab" would be in half
          // the list.
          (bone.length >= 3 && skeleton(f).contains(bone)));
    });
  }

  static final _arabic = RegExp('[؀-ۿ]');

  static const _articles = {
    'al', 'el', 'ad', 'adh', 'an', 'ar', 'as', 'ash', 'at', 'ath', 'az', //
  };

  /// Lower-case Latin letters and digits only, accents dropped:
  /// "Al-Hudhaify" is "alhudhaify", "Qāri" is "qari".
  static String latinKey(String s) {
    final b = StringBuffer();
    for (final c in s.toLowerCase().runes) {
      final base = _unaccent[c] ?? c;
      if ((base >= 0x61 && base <= 0x7A) || (base >= 0x30 && base <= 0x39)) {
        b.writeCharCode(base);
      }
    }
    return b.toString();
  }

  /// The consonants of [s], doubled ones once, with the letters that
  /// transliterations swap for one another made one: "Dussary" and
  /// "Dosari" are both "dsr"; "Hudhaify" and "Huthaifi" are both "htf",
  /// as ذ and ث are written either way.
  static String skeleton(String s) {
    final k = latinKey(s)
        .replaceAll('q', 'k')
        .replaceAll('ph', 'f')
        .replaceAll(RegExp('[dt]h'), 't')
        .replaceAll(RegExp('[aeiouyw0-9]'), '');
    final b = StringBuffer();
    var prev = -1;
    for (final c in k.runes) {
      if (c != prev) b.writeCharCode(c);
      prev = c;
    }
    return b.toString();
  }

  /// Arabic letters as [QuranSearch.normalize] spells them, with teh
  /// marbuta read as heh (سلامة / سلامه), and with no spaces and no alef
  /// at all. The normalizer keeps a word's first alef and drops the
  /// rest, so عبد الباري and عبدالباري would otherwise differ by the
  /// alef of ال — and whether ال was typed at all shouldn't matter.
  static String arabicKey(String s) => QuranSearch.normalize(s)
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[^ء-ي]|ا'), '');

  static const _unaccent = {
    0xE0: 0x61, 0xE1: 0x61, 0xE2: 0x61, 0xE4: 0x61, 0x101: 0x61, //
    0xE8: 0x65, 0xE9: 0x65, 0xEA: 0x65, 0xEB: 0x65, 0x113: 0x65,
    0xEC: 0x69, 0xED: 0x69, 0xEE: 0x69, 0xEF: 0x69, 0x12B: 0x69,
    0xF2: 0x6F, 0xF3: 0x6F, 0xF4: 0x6F, 0xF6: 0x6F, 0x14D: 0x6F,
    0xF9: 0x75, 0xFA: 0x75, 0xFB: 0x75, 0xFC: 0x75, 0x16B: 0x75,
    0x1E0D: 0x64, 0x1E25: 0x68, 0x1E63: 0x73, 0x1E6D: 0x74, 0x1E93: 0x7A,
  };
}
