import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'debug_log.dart';

/// One verse a search turned up.
class VerseHit {
  final int surah;
  final int ayah;

  /// The verse as the reel renders it: Uthmani, with its harakat.
  final String text;

  /// The translated line, when it is the translation that matched —
  /// empty for a hit found in the Arabic. A picker showing a hit found
  /// by an English word has to show the English: a list of Arabic a
  /// searcher cannot read is a list they cannot check.
  final String translation;

  const VerseHit(this.surah, this.ayah, this.text, {this.translation = ''});

  @override
  String toString() => 'VerseHit($surah:$ayah)';
}

/// Searching the Quran by the words of a verse, offline.
///
/// The whole text rides in assets/quran_search.json (see
/// tool/quran_search_index.py) and is read once, on the first search.
/// Matching is on letters alone: the Uthmani text is fully vowelled and
/// spelled the mushaf's way — `فِى` for في, `ٱلصَّلَوٰةَ` for الصلاة,
/// `ءَامَنُوا۟` for آمنوا — and nobody types it that way, so both the
/// verse and what was typed go through the same [normalize] first.
abstract final class QuranSearch {
  static const asset = 'assets/quran_search.json';

  /// Per surah (index 0 is surah 1): the verses' text, as rendered.
  static List<List<String>>? _text;

  /// The same, normalized once for matching.
  static List<List<String>>? _keys;

  /// The same again, spelled [loose]: what a search falls back to when
  /// the typed words don't meet the verse letter for letter.
  static List<List<String>>? _loose;

  static Future<void>? _loading;

  /// Starts reading the index, so the first letters typed into a field
  /// that searches are answered at once. Safe to call any number of
  /// times.
  static Future<void> warmUp() => _ensureLoaded();

  /// Whether the index is in memory, so [searchNow] can answer.
  static bool get isLoaded => _keys != null;

  /// Reads the index if it has not been read yet. Tests feed
  /// [loadFrom] the file instead.
  ///
  /// Parsed off the UI isolate: 1.35 MB of JSON and 6,236 verses
  /// normalized letter by letter stalled the screen for a second or
  /// more on a slow phone — the arena's lobby, opened from the day's
  /// quiz notification, froze on its way in.
  static Future<void> _ensureLoaded() => _loading ??= rootBundle
      .loadString(asset)
      .then((json) => compute(_parse, json))
      .then(_install);

  /// Loads the index from its JSON: `{"1": ["verse", ...], ...}`.
  @visibleForTesting
  static void loadFrom(String json) => _install(_parse(json));

  /// The verses, their normalized keys and their loose keys, out of the
  /// index's JSON.
  static (List<List<String>>, List<List<String>>, List<List<String>>) _parse(
      String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final text = List<List<String>>.generate(114, (_) => const []);
    for (final e in j.entries) {
      text[int.parse(e.key) - 1] = (e.value as List).cast<String>();
    }
    final keys = [
      for (final s in text) [for (final v in s) normalize(v)],
    ];
    return (
      text,
      keys,
      [
        for (final s in keys) [for (final k in s) loose(k)],
      ],
    );
  }

  static void _install(
      (List<List<String>>, List<List<String>>, List<List<String>>) index) {
    _text = index.$1;
    _keys = index.$2;
    _loose = index.$3;
    _loading = Future.value();
  }

  /// Letters only, spelled the plain way, so a verse and a search for
  /// it come out the same string.
  static String normalize(String s) {
    final b = StringBuffer();
    var prev = 0;
    for (final c in s.runes) {
      // Waw carrying a small alef is a long a written the old way:
      // الصلوٰة is الصلاة, الزكوٰة is الزكاة, الحيوٰة is الحياة.
      if (c == 0x0670 && prev == 0x0648) {
        final str = b.toString();
        b
          ..clear()
          ..write(str.substring(0, str.length - 1))
          ..write('ا');
        prev = 0x0627;
        continue;
      }
      // Harakat, tanween, shadda, sukun, pause marks, tatweel, and the
      // rest of the marks: not letters. The small waw and yehs
      // (U+06E5..06E7) are letters written small, and fall through
      // to be spelled full-size below.
      final smallLetter = c >= 0x06E5 && c <= 0x06E7;
      if ((c >= 0x064B && c <= 0x065F) ||
          (c >= 0x06D6 && c <= 0x06ED && !smallLetter) ||
          c == 0x0670 ||
          c == 0x0640 ||
          c == 0x0653 ||
          c == 0x0654 ||
          c == 0x0655) {
        continue;
      }
      var out = c;
      switch (c) {
        case 0x0671 || 0x0623 || 0x0625 || 0x0622: // ٱ أ إ آ
          out = 0x0627; // ا
        case 0x0649: // ى
          out = 0x064A; // ي
        case 0x0624: // ؤ
          out = 0x0648; // و
        case 0x0626: // ئ
          out = 0x064A; // ي
        case 0x06E7 || 0x06E6: // small yeh: إِبْرَٰهِـۧمَ
          out = 0x064A; // ي
        case 0x06E5: // small waw
          out = 0x0648; // و
        // Urdu and Persian keyboards type their own yeh, kaf and heh:
        // سدیس is السديس, کناکری is الكناكري.
        case 0x06CC || 0x06D2: // ی ے
          out = 0x064A; // ي
        case 0x06A9: // ک
          out = 0x0643; // ك
        case 0x06C1 || 0x06D5 || 0x06C0: // ہ ە ۀ
          out = 0x0647; // ه
        case 0x06C3: // ۃ
          out = 0x0629; // ة
      }
      // A standalone hamza before an alef is how the mushaf writes
      // آ (ءَامَنُوا); the alef alone is what gets typed.
      if (out == 0x0627 && prev == 0x0621) {
        final str = b.toString();
        b
          ..clear()
          ..write(str.substring(0, str.length - 1));
      }
      b.writeCharCode(out);
      prev = out;
    }
    // Inside a word, alef goes. The mushaf writes the long a of
    // الصالحات, إبراهيم and الرحمن as a small alef over the letter —
    // or not at all — and people type it as a full alef, or not, by
    // habit; with no rule that tells the two apart, the letter that
    // both sides can agree on is none. A word's first alef stays: it
    // is the ال, the أ of أذكركم, the آ of آمنوا.
    final plain = b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final out = StringBuffer();
    var atStart = true;
    for (final c in plain.runes) {
      if (c == 0x0627 && !atStart) continue;
      out.writeCharCode(c);
      atStart = c == 0x20;
    }
    return out.toString();
  }

  /// Arabic letters in [s], after [normalize].
  static int letterCount(String s) => _letters(normalize(s));

  static int _letters(String normalized) =>
      RegExp('[ء-ي]').allMatches(normalized).length;

  /// A [normalize]d string with no spaces, no alef and no hamza at all,
  /// and ة read as ه.
  ///
  /// The mushaf joins what people type apart — يَٰٓأَيُّهَا is يا أيها,
  /// يَٰقَوْمِ is يا قوم, يَٰبُنَىَّ is يا بني — and writes or leaves out
  /// an alef where a typist does the opposite; people end a word in ه
  /// for ة, write شئ for شيء, and seat a hamza wherever their keyboard
  /// put it. None of that is what they meant, so none of it is matched
  /// on. It also means every letter typed on the way to a phrase finds
  /// the verses the phrase does: results narrow as the words are typed,
  /// they never blink out halfway and come back.
  static String loose(String normalized) {
    final b = StringBuffer();
    for (final c in normalized.codeUnits) {
      if (c < 0x0621 || c > 0x064A) continue; // spaces, digits, marks
      if (c == 0x0627 || c == 0x0621) continue; // ا ء
      b.writeCharCode(c == 0x0629 ? 0x0647 : c); // ة → ه
    }
    return b.toString();
  }

  /// Letters people swap for one another because they sound alike, or
  /// alike enough in their own dialect: ض and ظ, ذ and ز, س ص and ث,
  /// ت and ط, ه and ح. Folded only in the forgiving pass of [searchNow],
  /// never in what the strict passes match.
  static final List<int> _fold = () {
    final t = List<int>.generate(0x100, (i) => 0x0600 + i);
    void same(String letters) {
      final cs = letters.codeUnits;
      for (final c in cs) {
        t[c - 0x0600] = cs.first;
      }
    }

    same('ضظ');
    same('زذ');
    same('سصث');
    same('تط');
    same('هح');
    return t;
  }();

  static int _folded(int c) =>
      c >= 0x0600 && c < 0x0700 ? _fold[c - 0x0600] : c;

  /// How many letters a query of [letters] loose letters may get wrong
  /// and still find its verse: none up to four (a short word with one
  /// letter changed is another word), then one, two, three.
  static int _typos(int letters) => letters <= 4
      ? 0
      : letters <= 8
          ? 1
          : letters <= 14
              ? 2
              : 3;

  /// Below this many verses found as typed, the forgiving pass runs
  /// too: a query that already finds plenty is spelled right.
  static const _fewHits = 20;

  /// Verses whose letters contain [query]'s, at most [limit] of them.
  /// Nothing for fewer than two letters: every verse has an alef.
  static Future<List<VerseHit>> search(String query, {int limit = 100}) async {
    if (letterCount(query) < 2) return const [];
    await _ensureLoaded();
    return searchNow(query, limit: limit)!;
  }

  /// [search], answered on the spot — or null while the index is still
  /// being read. A field that searches as it is typed into shows each
  /// keystroke's verses in the frame that keystroke draws, instead of a
  /// frame of nothing between one answer and the next.
  ///
  /// Every verse is tried three ways, and the order is how sure the
  /// match is:
  ///
  ///  1. the words as typed, after [normalize];
  ///  2. the words [loose]: the spaces, alefs and hamzas the mushaf and
  ///     a keyboard never agree on;
  ///  3. when those found fewer than twenty: the loose letters again,
  ///     sound-alike letters as one and a few letters wrong, missing or
  ///     extra — the closest first.
  ///
  /// Within 1 and 2, a match that starts where a word starts comes
  /// before one in the middle of a word: يا بني is يَٰبَنِىٓ before it
  /// is إِلَىٰ بَنِىٓ, and يا ايها is يَٰٓأَيُّهَا before it is the
  /// middle of سَيِّئَةً. Otherwise mushaf order.
  static List<VerseHit>? searchNow(String query, {int limit = 100}) {
    final keys = _keys, looseKeys = _loose, text = _text;
    if (keys == null || looseKeys == null || text == null) return null;
    final q = normalize(query);
    if (_letters(q) < 2) return const [];
    final lq = loose(q);
    // ان or اء is two letters typed and one loose: too short to match
    // loosely without matching nearly every verse.
    final useLoose = lq.length >= 2;
    // exact at a word's start, loose at a word's start, exact inside a
    // word, loose inside a word.
    final tiers = List.generate(4, (_) => <VerseHit>[]);
    final found = <int>{};
    for (var s = 0; s < keys.length; s++) {
      final ks = keys[s], ls = looseKeys[s];
      for (var a = 0; a < ks.length; a++) {
        final int tier;
        if (ks[a].contains(q)) {
          final atStart = useLoose
              ? _looseAtWordStart(ks[a], ls[a], lq)
              : ks[a].startsWith(q) || ks[a].contains(' $q');
          tier = atStart ? 0 : 2;
        } else if (useLoose && ls[a].contains(lq)) {
          tier = _looseAtWordStart(ks[a], ls[a], lq) ? 1 : 3;
        } else {
          continue;
        }
        found.add(s * 1000 + a);
        if (tiers[tier].length < limit) {
          tiers[tier].add(VerseHit(s + 1, a + 1, text[s][a]));
        }
      }
    }
    final hits = [for (final t in tiers) ...t];
    if (hits.length >= limit) return hits.sublist(0, limit);
    if (found.length >= _fewHits || lq.length < 3) return hits;
    // A phrase typed on from the end of one verse into the next —
    // والعصر ان الانسان لفي خسر, قل هو الله احد الله الصمد — is found
    // at the verse it starts in.
    if (lq.length >= 4) {
      for (var s = 0; s < looseKeys.length && hits.length < limit; s++) {
        final ls = looseKeys[s];
        for (var a = 0; a + 1 < ls.length && hits.length < limit; a++) {
          if (found.contains(s * 1000 + a)) continue;
          final head = ls[a];
          final joined = StringBuffer(head);
          for (var n = a + 1;
              n < ls.length && joined.length < head.length + lq.length;
              n++) {
            joined.write(ls[n]);
          }
          // Starting inside this verse and running past its end: one
          // that fits inside it was found above.
          final from = head.length - lq.length + 1;
          final i = joined.toString().indexOf(lq, from < 0 ? 0 : from);
          if (i < 0 || i >= head.length) continue;
          found.add(s * 1000 + a);
          hits.add(VerseHit(s + 1, a + 1, text[s][a]));
        }
      }
    }
    final pattern = lq.length > 62 ? lq.substring(0, 62) : lq;
    final k = _typos(pattern.length);
    final peq = _letterMasks(pattern);
    final close = <(int, int, int)>[]; // (typos, surah index, ayah index)
    for (var s = 0; s < looseKeys.length; s++) {
      final ls = looseKeys[s];
      for (var a = 0; a < ls.length; a++) {
        if (found.contains(s * 1000 + a)) continue;
        final d = _closest(peq, pattern.length, ls[a], k);
        if (d <= k) close.add((d, s, a));
      }
    }
    close.sort((x, y) => x.$1 != y.$1
        ? x.$1 - y.$1
        : x.$2 != y.$2
            ? x.$2 - y.$2
            : x.$3 - y.$3);
    for (final (_, s, a) in close) {
      if (hits.length >= limit) break;
      hits.add(VerseHit(s + 1, a + 1, text[s][a]));
    }
    return hits;
  }

  /// Whether [lq] turns up in the loose key [ls] where one of the words
  /// of the normalized key [key] starts. Run only on verses that
  /// matched, so the word starts are counted then rather than stored.
  ///
  /// A word also starts after the و or ف fixed to its front, and after
  /// its ال: اقيموا الصلاة is the start of وَأَقِيمُوا۟ ٱلصَّلَوٰةَ, and
  /// صلاة the start of ٱلصَّلَوٰةَ.
  static bool _looseAtWordStart(String key, String ls, String lq) {
    final starts = <int>{};
    var pos = 0;
    for (final word in key.split(' ')) {
      final kept = loose(word);
      if (kept.isEmpty) continue;
      starts.add(pos);
      // Only a word long enough to carry them: إلى is not ال + ى.
      final c0 = kept.codeUnitAt(0);
      final conj = c0 == 0x0648 || c0 == 0x0641; // و ف
      if (kept.length >= 3 && (conj || word.startsWith('ال'))) {
        starts.add(pos + 1);
      }
      // و or ف, then the ل of an ال the normalizer left no alef in.
      if (kept.length >= 4 && conj && kept.codeUnitAt(1) == 0x0644) {
        starts.add(pos + 2);
      }
      pos += kept.length;
    }
    for (var i = ls.indexOf(lq); i >= 0; i = ls.indexOf(lq, i + 1)) {
      if (starts.contains(i)) return true;
    }
    return false;
  }

  /// Per Arabic letter (index: code unit − U+0600), the positions of
  /// [pattern] it may stand in for, sound-alikes folded together.
  static List<int> _letterMasks(String pattern) {
    final peq = List<int>.filled(0x100, 0);
    for (var i = 0; i < pattern.length; i++) {
      final c = _folded(pattern.codeUnitAt(i));
      if (c < 0x0600 || c >= 0x0700) continue;
      for (var x = 0; x < 0x100; x++) {
        if (_fold[x] == c) peq[x] |= 1 << i;
      }
    }
    return peq;
  }

  /// The fewest letters the [m]-letter pattern behind [peq] (see
  /// [_letterMasks]; m at most 62) gets wrong against any stretch of
  /// [verse]; anything over [k] comes back as k + 1. Myers' bit-parallel
  /// edit distance, one machine word per column, so the whole Quran
  /// takes milliseconds.
  static int _closest(List<int> peq, int m, String verse, int k) {
    final high = 1 << (m - 1);
    final mask = (1 << m) - 1;
    var pv = mask, mv = 0, score = m, best = m;
    for (var j = 0; j < verse.length; j++) {
      final c = verse.codeUnitAt(j);
      final eq = c >= 0x0600 && c < 0x0700 ? peq[c - 0x0600] : 0;
      final xv = eq | mv;
      final xh = ((((eq & pv) + pv) & mask) ^ pv) | eq;
      var ph = mv | (~(xh | pv) & mask);
      var mh = pv & xh;
      if ((ph & high) != 0) {
        score++;
      } else if ((mh & high) != 0) {
        score--;
      }
      // A match may start anywhere in the verse: nothing shifts in.
      ph = (ph << 1) & mask;
      mh = (mh << 1) & mask;
      pv = mh | (~(xv | ph) & mask);
      mv = ph & xv;
      if (score < best) {
        best = score;
        if (best == 0) return 0;
      }
    }
    return best > k ? k + 1 : best;
  }

  /// The one verse at [surah]:[ayah], or nothing if there is no such
  /// verse. What "2:255" typed into a search field means — somebody
  /// who knows the reference is not searching, they are navigating.
  static Future<List<VerseHit>> verse(int surah, int ayah) async {
    if (surah < 1 || surah > 114 || ayah < 1) return const [];
    await _ensureLoaded();
    final text = _text![surah - 1];
    if (ayah > text.length) return const [];
    return [VerseHit(surah, ayah, text[ayah - 1])];
  }

  /// The whole Quran, surah by surah (index 0 is surah 1), as the reel
  /// renders it — what the arena builds its questions from. Read once;
  /// the same list every call after that.
  static Future<List<List<String>>> all() async {
    await _ensureLoaded();
    return _text!;
  }

  /// [all], normalized: the same verses as letters alone, one string
  /// per verse, words still separated by single spaces — so a verse's
  /// words can be matched without normalizing the Quran a second time.
  static Future<List<List<String>>> allKeys() async {
    await _ensureLoaded();
    return _keys!;
  }

  /// Every verse of [surah], as the reel renders them — the Arabic
  /// alone, with no translation and no network.
  ///
  /// What the card composer's verse browser falls back to when the
  /// translation cannot be fetched: the whole Quran is already in the
  /// app for searching, so a phone with no connection can still read
  /// any surah and put any verse on a card. It just cannot print an
  /// English line under it.
  static Future<List<String>> surah(int surah) async {
    if (surah < 1 || surah > 114) return const [];
    await _ensureLoaded();
    return _text![surah - 1];
  }

  // ── searching the translation ──────────────────────────────────────

  /// Verses whose *translation* carries [query], in the edition
  /// [resourceId] names.
  ///
  /// Why this one is online when everything above it is not: the
  /// Arabic text is 1.3 MB and ships in the app, but a translation is
  /// another megabyte *per edition* and there are five of them, and
  /// the app already fetches the line under a verse from the same
  /// host. So a search of the translation is exactly as online as the
  /// translation itself is — nothing that used to work offline stops
  /// working, and somebody typing "mercy" gets verses instead of the
  /// nothing they got before.
  ///
  /// The Arabic on each hit comes off the bundled index rather than
  /// out of the response, so a verse found this way is the same string
  /// the app would have rendered had it been found by its Arabic. Only
  /// the reference is taken from the answer.
  ///
  /// Never throws: no network, a rate limit, a changed shape — all of
  /// them are an empty list, and the picker goes on showing surahs.
  static Future<List<VerseHit>> searchTranslation(
    String query, {
    required int resourceId,
    int limit = 40,
  }) async {
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Two letters of Arabic is a word; two of English is "of". Three
    // is where a translation search stops answering with the whole
    // Quran.
    if (q.length < 3) return const [];
    final key = '$resourceId|${q.toLowerCase()}';
    final had = _translationHits[key];
    if (had != null) return had;
    try {
      final uri = Uri.parse('$_searchEndpoint'
          '?q=${Uri.encodeQueryComponent(q)}'
          '&size=$limit&page=0&translations=$resourceId');
      // A client of its own is closed after: one per query, as the user
      // types, each held a connection open until it timed out.
      final client = clientForTest ?? http.Client();
      final http.Response res;
      try {
        res = await client.get(uri).timeout(const Duration(seconds: 12));
      } finally {
        if (clientForTest == null) client.close();
      }
      if (res.statusCode != 200) {
        rlog('translation search: HTTP ${res.statusCode}');
        return const [];
      }
      await _ensureLoaded();
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final results = ((j['search'] as Map?)?['results'] as List?) ?? const [];
      final out = <VerseHit>[];
      for (final r in results.cast<Map<String, dynamic>>()) {
        final parts = (r['verse_key'] as String? ?? '').split(':');
        if (parts.length != 2) continue;
        final s = int.tryParse(parts[0]);
        final a = int.tryParse(parts[1]);
        if (s == null || a == null || s < 1 || s > 114 || a < 1) continue;
        final verses = _text![s - 1];
        if (a > verses.length) continue;
        final line = ((r['translations'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map((t) => t['text'] as String? ?? '')
            .firstWhere((t) => t.isNotEmpty, orElse: () => '');
        out.add(VerseHit(s, a, verses[a - 1],
            translation: _stripHighlight(line)));
      }
      _translationHits[key] = out;
      return out;
    } catch (e) {
      rlog('translation search: $e');
      return const [];
    }
  }

  static const _searchEndpoint = 'https://api.quran.com/api/v4/search';

  /// Stands in for the network, so the shape of an answer can be
  /// tested without one. The parsing is the half of this that can be
  /// wrong quietly: a changed key name gives an empty list, which
  /// looks exactly like a word nothing matched.
  @visibleForTesting
  static http.Client? clientForTest;

  /// Answers already given, for this session. Retyping a word — or
  /// backspacing onto one — costs nothing, which matters when the
  /// field searches as you type.
  static final Map<String, List<VerseHit>> _translationHits = {};

  /// The API marks every match with `<em>`, and a footnote with a
  /// `<sup>`. Neither belongs in a list row.
  static String _stripHighlight(String s) => s
      .replaceAll(RegExp(r'<sup[^>]*>.*?</sup>', dotAll: true), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @visibleForTesting
  static void resetForTest() {
    _text = null;
    _keys = null;
    _loose = null;
    _loading = null;
    _translationHits.clear();
  }
}
