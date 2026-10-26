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

  static Future<void>? _loading;

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

  /// The verses and their normalized keys, out of the index's JSON.
  static (List<List<String>>, List<List<String>>) _parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final text = List<List<String>>.generate(114, (_) => const []);
    for (final e in j.entries) {
      text[int.parse(e.key) - 1] = (e.value as List).cast<String>();
    }
    return (
      text,
      [
        for (final s in text) [for (final v in s) normalize(v)],
      ],
    );
  }

  static void _install((List<List<String>>, List<List<String>>) index) {
    _text = index.$1;
    _keys = index.$2;
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
  static int letterCount(String s) =>
      RegExp('[ء-ي]').allMatches(normalize(s)).length;

  /// Verses whose letters contain [query]'s, in mushaf order, at most
  /// [limit] of them. Nothing for fewer than two letters: every verse
  /// has an alef.
  static Future<List<VerseHit>> search(String query, {int limit = 40}) async {
    final q = normalize(query);
    if (letterCount(q) < 2) return const [];
    await _ensureLoaded();
    final keys = _keys!, text = _text!;
    final hits = <VerseHit>[];
    for (var s = 0; s < keys.length && hits.length < limit; s++) {
      final ks = keys[s];
      for (var a = 0; a < ks.length && hits.length < limit; a++) {
        if (ks[a].contains(q)) hits.add(VerseHit(s + 1, a + 1, text[s][a]));
      }
    }
    return hits;
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
    _loading = null;
    _translationHits.clear();
  }
}
