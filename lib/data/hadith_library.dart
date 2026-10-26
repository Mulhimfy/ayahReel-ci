import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'debug_log.dart';
import 'quran_search.dart';
import 'settings_service.dart';
import 'verse_translation.dart';

/// One hadith, as the card composer needs it.
@immutable
class Hadith {
  /// Row in the library — the identity a card stores, so a saved card
  /// can name where its words came from without keeping a copy of the
  /// whole library.
  final int index;

  /// Collection id: `bukhari`, `muslim`, `nawawi`, …
  final String collection;

  /// The hadith's number in that collection.
  final int number;

  /// The Arabic, with the transmission chain already stripped from the
  /// front — see `tool/fetch_hadith.py`.
  final String arabic;

  /// The translation in the reader's edition language, or in English
  /// where that language has none. Empty only when neither exists.
  final String translation;

  /// Which language [translation] is actually in, which is not always
  /// the one asked for.
  final String translationLang;

  /// "Sahih · al-Albani" and the like, for the collections that need
  /// grading. Empty for the two Sahihs and the two forties, which
  /// answer for themselves.
  final String grading;

  const Hadith({
    required this.index,
    required this.collection,
    required this.number,
    required this.arabic,
    required this.translation,
    required this.translationLang,
    required this.grading,
  });
}

/// The offline hadith library the card composer searches.
///
/// Six thousand hadith from the two Sahihs, the four Sunan, the
/// Muwatta and the two classical forties — every one of them short
/// enough to put on a card, and nothing graded weak. What is in the
/// file and why is written down in `tool/fetch_hadith.py`;
/// `tool/verify_hadith.py` is what keeps this and that honest.
///
/// ## What this costs, and when
///
/// Nothing at all until somebody opens the finder. The text is four
/// gzipped files, one per language, and this reads exactly two of
/// them: the Arabic, and the single translation the reader has chosen.
/// Both are inflated and parsed in a background isolate, so the tap
/// that opens the finder does not drop a frame — about 2 MB of asset
/// becomes about 16 MB of phone, once, for as long as the app is up.
///
/// A language the corpus has no edition for — German — reads in
/// English, and every result says which edition it is showing.
abstract final class HadithLibrary {
  static const dir = 'assets/hadith';

  static _Corpus? _corpus;
  static Future<void>? _loading;
  static String _lang = '';

  /// Whether a search can be answered right now, without waiting.
  static bool get isLoaded => _corpus != null;

  /// Collections in the library, in the order the browser shows them:
  /// what the collection is called, in English and in Arabic.
  static List<({String id, String en, String ar})> get collections =>
      _corpus?.collections ?? const [];

  /// Topic ids, for browsing rather than searching.
  static List<String> get topics => _corpus?.topics ?? const [];

  /// Who translated the edition being shown, for the credit line.
  static String get credit => _corpus?.credits[_lang] ?? '';

  /// The language the translations are actually in.
  static String get lang => _lang;

  /// How many hadith are loaded.
  static int get count => _corpus?.arabic.length ?? 0;

  /// The edition to read, for the language the reader has chosen. The
  /// corpus has no German, so a German reader reads the English —
  /// which is what [credit] then names.
  static String langFor(VerseTranslation t) =>
      const {'en', 'ur', 'id'}.contains(t.code) ? t.code : 'en';

  /// Reads the library if it is not already in memory, or if the
  /// reader has changed the edition since it was.
  ///
  /// Safe to call from a build — it hands back the same future while
  /// one is in flight — and safe to call again after a failure, which
  /// leaves nothing loaded and no future cached.
  static Future<void> load() {
    final want = langFor(SettingsService.state.value.translation);
    if (_corpus != null && _lang == want) return Future.value();
    if (_loading != null && _lang == want) return _loading!;
    final hadLang = _lang;
    _lang = want;
    return _loading = _read(want).then((c) {
      // A second load for another language may have landed first;
      // whichever finishes last for the language still wanted wins.
      if (_lang == want) _corpus = c;
    }).catchError((Object e, StackTrace s) {
      rlogError('hadith library', e, s);
      _loading = null;
      // The library already in memory stays, under the language it is
      // in: a failed switch to another edition leaves that one readable
      // rather than none, and the next call tries the switch again.
      if (_lang == want) _lang = hadLang;
    });
  }

  static Future<_Corpus> _read(String lang) async {
    Future<Uint8List> bytes(String name) async =>
        (await rootBundle.load('$dir/$name')).buffer.asUint8List();
    final meta = await rootBundle.loadString('$dir/meta.json');
    return compute(_parse, _Raw(
      meta: meta,
      arabic: await bytes('ar.json.gz'),
      translation: await bytes('$lang.json.gz'),
      // The fallback text for the tenth or so of the library the Urdu
      // and Indonesian editions do not carry. Not read when English is
      // the edition — it is already the translation — and never
      // indexed for search, which stays in the language asked for.
      english: lang == 'en' ? null : await bytes('en.json.gz'),
      lang: lang,
    ));
  }

  /// Loads from already-read bytes — the door tests come in through,
  /// since a test host has files rather than an asset bundle.
  @visibleForTesting
  static Future<void> loadFrom({
    required String meta,
    required Uint8List arabic,
    required Uint8List translation,
    Uint8List? english,
    String lang = 'en',
  }) async {
    _lang = lang;
    _corpus = await compute(_parse, _Raw(
      meta: meta,
      arabic: arabic,
      translation: translation,
      english: english,
      lang: lang,
    ));
    _loading = Future.value();
  }

  @visibleForTesting
  static void resetForTest() {
    _corpus = null;
    _loading = null;
    _lang = '';
  }

  /// The hadith at [index], or null if the library is not loaded or
  /// the index is from a build with a different library.
  static Hadith? at(int index) {
    final c = _corpus;
    if (c == null || index < 0 || index >= c.arabic.length) return null;
    return Hadith(
      index: index,
      collection: c.collections[c.collection[index]].id,
      number: c.number[index],
      arabic: c.arabic[index],
      translation: c.translation[index].isEmpty
          ? c.english[index]
          : c.translation[index],
      translationLang: c.translation[index].isEmpty ? 'en' : c.lang,
      grading: c.grading[index],
    );
  }

  /// Hadith whose words contain [query]'s, best first, at most [limit].
  ///
  /// The query decides which side is searched: anything with an Arabic
  /// letter in it is matched against the Arabic, normalized the way
  /// [QuranSearch] normalizes a verse — the hadith are vowelled and
  /// nobody types them that way. Anything else is matched against the
  /// translation, folded to plain lowercase letters.
  ///
  /// Ranking, in order: the collections that answer for themselves
  /// first, then the shortest text — a hadith that fits on a card
  /// before one that does not.
  static List<Hadith> search(String query, {int limit = 40}) {
    final c = _corpus;
    if (c == null) return const [];
    final arabicQuery = _hasArabic(query);
    final q = arabicQuery ? QuranSearch.normalize(query) : _fold(query);
    if (q.length < 2) return const [];
    final keys = arabicQuery ? c.arabicKey : c.transKey;
    final hits = <int>[];
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].contains(q)) hits.add(i);
    }
    return _rank(c, hits, limit);
  }

  /// Hadith filed under [topic], best first. Browsing, for somebody
  /// who has not come with a phrase in mind.
  static List<Hadith> byTopic(String topic, {int limit = 60}) {
    final c = _corpus;
    if (c == null) return const [];
    final bit = c.topics.indexOf(topic);
    if (bit < 0) return const [];
    final mask = 1 << bit;
    final hits = <int>[];
    for (var i = 0; i < c.topicBits.length; i++) {
      if (c.topicBits[i] & mask != 0) hits.add(i);
    }
    return _rank(c, hits, limit);
  }

  static List<Hadith> _rank(_Corpus c, List<int> hits, int limit) {
    hits.sort((a, b) {
      final ra = c.rank[c.collection[a]].compareTo(c.rank[c.collection[b]]);
      if (ra != 0) return ra;
      return c.arabic[a].length.compareTo(c.arabic[b].length);
    });
    return [
      for (final i in hits.take(limit)) at(i)!,
    ];
  }

  static bool _hasArabic(String s) =>
      s.runes.any((c) => c >= 0x0600 && c <= 0x06FF);

  /// Letters and digits, lowercased, everything else a space — so
  /// "Sa`id", "Sa'id" and "Said" are one word, and a search for
  /// "prophet said" still finds "Prophet (ﷺ) said".
  static String _fold(String s) {
    final b = StringBuffer();
    var space = true;
    for (final r in s.toLowerCase().runes) {
      final letter = (r >= 0x61 && r <= 0x7A) || (r >= 0x30 && r <= 0x39);
      if (letter) {
        b.writeCharCode(r);
        space = false;
      } else if (r >= 0xC0 && r < 0x250) {
        // Latin letters with marks, folded to their base where the
        // fold is a single letter; anything else becomes a space.
        final plain = _accents[r];
        if (plain != null) {
          b.write(plain);
          space = false;
        } else if (!space) {
          b.write(' ');
          space = true;
        }
      } else if (!space) {
        b.write(' ');
        space = true;
      }
    }
    return b.toString().trim();
  }

  static const _accents = <int, String>{
    0xE0: 'a', 0xE1: 'a', 0xE2: 'a', 0xE3: 'a', 0xE4: 'a', 0xE5: 'a',
    0xE7: 'c', 0xE8: 'e', 0xE9: 'e', 0xEA: 'e', 0xEB: 'e', 0xEC: 'i',
    0xED: 'i', 0xEE: 'i', 0xEF: 'i', 0xF1: 'n', 0xF2: 'o', 0xF3: 'o',
    0xF4: 'o', 0xF5: 'o', 0xF6: 'o', 0xF9: 'u', 0xFA: 'u', 0xFB: 'u',
    0xFC: 'u', 0xFD: 'y', 0x101: 'a', 0x12B: 'i', 0x16B: 'u',
  };

  /// The part of a hadith worth quoting: what the Prophet ﷺ said,
  /// where the edition marks it, and the whole text where it does not.
  ///
  /// These editions put the saying itself in quotation marks — `"…"`
  /// in the Arabic, `"…"` or `'…'` in the English — with the chain and
  /// the narrator outside them. A card usually wants what is inside,
  /// so the finder offers that first; the whole is always one tap away.
  static String quotable(String text) {
    for (final pair in const [('"', '"'), ('«', '»'), ('“', '”')]) {
      final start = text.indexOf(pair.$1);
      if (start < 0) continue;
      final end = text.lastIndexOf(pair.$2);
      if (end <= start + 8) continue;
      final inner = text.substring(start + 1, end).trim();
      if (inner.length >= 12) return inner;
    }
    return text;
  }
}

/// The three files as they come off the bundle, on their way to the
/// isolate that inflates them.
@immutable
class _Raw {
  final String meta;
  final Uint8List arabic;
  final Uint8List translation;

  /// Only when [lang] is not English; see [HadithLibrary._read].
  final Uint8List? english;
  final String lang;
  const _Raw({
    required this.meta,
    required this.arabic,
    required this.translation,
    required this.english,
    required this.lang,
  });
}

/// The library in memory: parallel lists, indexed by row.
///
/// Lists rather than a list of objects, and parallel rather than
/// nested, because this crosses an isolate boundary — primitives and
/// lists of them are what travel cheaply — and because a search only
/// ever touches the two key lists.
class _Corpus {
  final List<({String id, String en, String ar})> collections;
  final List<String> topics;
  final Map<String, String> credits;
  final String lang;

  final List<int> collection;
  final List<int> number;
  final List<int> topicBits;
  final List<String> grading;
  final List<String> arabic;
  final List<String> translation;
  final List<String> english;
  final List<String> arabicKey;
  final List<String> transKey;

  /// Sort order of each collection, by index — the Sahihs and the two
  /// forties first. Precomputed because it is read inside a sort.
  final List<int> rank;

  _Corpus({
    required this.collections,
    required this.topics,
    required this.credits,
    required this.lang,
    required this.collection,
    required this.number,
    required this.topicBits,
    required this.grading,
    required this.arabic,
    required this.translation,
    required this.english,
    required this.arabicKey,
    required this.transKey,
    required this.rank,
  });
}

/// The order results come back in: what a card is most likely to want
/// to quote, first.
const _collectionRank = <String, int>{
  'nawawi': 0, 'qudsi': 0, 'bukhari': 1, 'muslim': 1,
  'malik': 2, 'abudawud': 3, 'tirmidhi': 3, 'nasai': 3, 'ibnmajah': 3,
};

/// Runs in a background isolate: inflate, decode, and build the match
/// keys. All of it together is a few hundred milliseconds, once.
_Corpus _parse(_Raw raw) {
  final meta = jsonDecode(raw.meta) as Map<String, dynamic>;
  final collections = [
    for (final c in meta['collections'] as List)
      (
        id: (c as Map)['id'] as String,
        en: c['en'] as String,
        ar: c['ar'] as String,
      ),
  ];
  final arabic = (jsonDecode(utf8.decode(gzip.decode(raw.arabic))) as List)
      .cast<String>();
  final translation =
      (jsonDecode(utf8.decode(gzip.decode(raw.translation))) as List)
          .cast<String>();
  final rows = meta['rows'] as List;
  final n = rows.length;
  final collection = List<int>.filled(n, 0);
  final number = List<int>.filled(n, 0);
  final bits = List<int>.filled(n, 0);
  final grading = List<String>.filled(n, '');
  for (var i = 0; i < n; i++) {
    final r = rows[i] as List;
    collection[i] = r[0] as int;
    number[i] = r[1] as int;
    bits[i] = r[2] as int;
    grading[i] = r.length > 3 ? r[3] as String : '';
  }
  // The fallback text, for the tenth of the library the Urdu and
  // Indonesian editions do not carry. When English is the edition it
  // is the same list rather than a second copy of it.
  final english = raw.english == null
      ? translation
      : (jsonDecode(utf8.decode(gzip.decode(raw.english!))) as List)
          .cast<String>();
  return _Corpus(
    collections: collections,
    topics: (meta['topics'] as List).cast<String>(),
    credits: (meta['editions'] as Map).cast<String, String>(),
    lang: raw.lang,
    collection: collection,
    number: number,
    topicBits: bits,
    grading: grading,
    arabic: arabic,
    translation: translation,
    english: english,
    arabicKey: [for (final t in arabic) QuranSearch.normalize(t)],
    transKey: [for (final t in translation) HadithLibrary._fold(t)],
    rank: [
      for (final c in collections) _collectionRank[c.id] ?? 4,
    ],
  );
}
