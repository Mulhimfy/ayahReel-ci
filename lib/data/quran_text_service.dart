import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'debug_log.dart';
import 'download.dart';
import 'fatiha_data.dart';
import 'models.dart';
import 'settings_service.dart';
import 'trouble.dart';
import 'verse_translation.dart';

/// Fetches surah text (Uthmani Arabic + the chosen translation) from
/// quran.com on first use and caches it to disk forever after — each
/// surah is a one-time ~10-100KB download.
///
/// The translation is whichever edition Settings names; see
/// [VerseTranslation], which documents what every edition had to pass
/// before it could be offered. The Arabic is the same for all of them.
///
/// The Arabic is the King Fahd Complex's own QPC text, which is what
/// the bundled `UthmanicHafs.ttf` — the Complex's own face — is cut to
/// render. The previous source (alquran.cloud's Tanzil Uthmani) is a
/// different edition of the same recitation, and the face mis-set two
/// things in it: it dropped the mirrored iqlab meem into the body of
/// the letter (see [dropWrongSideIqlabMeem]) and, lacking the tatweel
/// the mushaf stretches a letter with, crowded the dagger alif against
/// it in 5,787 words. Both are spellings the QPC text simply has right.
///
/// Al-Fatiha is bundled, so the first-run experience never touches the
/// network for text.
abstract final class QuranTextService {
  static const _arabicEndpoint =
      'https://api.quran.com/api/v4/quran/verses/uthmani';

  /// quran.com serves translations per resource, separately from the
  /// Arabic, so a surah costs two requests.
  static const _translationBase =
      'https://api.quran.com/api/v4/quran/translations';

  /// Session cache, keyed by edition and then by surah. It has to be
  /// keyed by edition: the Arabic half is identical across them, but
  /// the translation is not, and a surah read back under the wrong key
  /// would caption every ayah in the language the reader just left.
  ///
  /// Al-Fatiha is bundled in every edition, so the promise that a
  /// first run never touches the network for text holds whichever
  /// language was chosen during onboarding.
  static final _memory = <int, Map<int, List<Ayah>>>{
    for (final t in VerseTranslation.values)
      t.resourceId: {1: fatihaIn(t)},
  };

  /// The edition Settings currently names.
  static VerseTranslation get edition => SettingsService.state.value.translation;

  static Map<int, List<Ayah>> _bucket(VerseTranslation t) =>
      _memory.putIfAbsent(t.resourceId, () => <int, List<Ayah>>{});

  /// Instant if bundled or already fetched this session, in the
  /// edition currently chosen.
  static List<Ayah>? cached(int surah) => _bucket(edition)[surah];

  /// Puts a surah's text in the session cache without a fetch.
  ///
  /// For tests of the screens that read text, which have no network
  /// and only Al-Fatiha bundled — and Al-Fatiha is seven verses, so
  /// anything about the length of a long selection is untestable
  /// through it. Pass null to put a seeded surah back.
  @visibleForTesting
  static void seed(int surah, List<Ayah>? ayahs, {VerseTranslation? into}) {
    final bucket = _bucket(into ?? edition);
    if (ayahs == null) {
      bucket.remove(surah);
    } else {
      bucket[surah] = ayahs;
    }
  }

  static Future<List<Ayah>> load(int surah) async {
    final t = edition;
    final inMemory = _bucket(t)[surah];
    if (inMemory != null) {
      rlog('text: memory hit $surah (${inMemory.length} ayahs)');
      return inMemory;
    }

    final file = await _cacheFile(surah, t);
    if (!file.existsSync() && t == VerseTranslation.english) {
      await _adoptLegacyEnglish(surah, file);
    }
    if (file.existsSync()) {
      try {
        final ayahs = _decode(surah, await file.readAsString());
        rlog('text: disk hit $surah/${t.code} (${ayahs.length} ayahs)');
        _bucket(t)[surah] = ayahs;
        return ayahs;
      } catch (e) {
        rlog('text: cache for $surah/${t.code} unreadable, refetching — $e');
      }
    }
    rlog('text: fetching surah $surah (${t.code}) from quran.com');

    final responses = await _fetchBoth(surah, t);
    rlog('text: $surah arabic HTTP ${responses[0].statusCode}, '
        'translation HTTP ${responses[1].statusCode}');
    final arabic = (jsonDecode(responses[0].body)
        as Map<String, dynamic>)['verses'] as List;
    final translated = (jsonDecode(responses[1].body)
        as Map<String, dynamic>)['translations'] as List;
    // The two endpoints are paired only by position, so a length that
    // doesn't line up would silently caption every ayah with its
    // neighbour's translation. Refuse it instead.
    if (arabic.length != translated.length || arabic.isEmpty) {
      throw TroubleException(
          Trouble.host,
          'surah $surah text and translation do not line up '
          '(${arabic.length} vs ${translated.length})');
    }

    final ayahs = <Ayah>[
      for (var i = 0; i < arabic.length; i++)
        () {
          final verse = arabic[i] as Map<String, dynamic>;
          final number = _ayahNumber(verse['verse_key'] as String);
          // Every surah's ayah 1 arrives with a leading space where the
          // Basmala sits in the mushaf — 110 of them. Centred verse text
          // would carry the offset straight onto the card.
          final text = (verse['text_uthmani'] as String).trim();
          return Ayah(
            number: number,
            // Circles come off first: a rosette standing as its own
            // token at the head of ayah 1 would push the Basmala out of
            // the first four words and hide it from the check below.
            arabic: stripLeadingBasmala(surah, number,
                stripCircleMarks(dropWrongSideIqlabMeem(text))),
            translation: normalizeSpaces(stripFootnoteMarkup(
                (translated[i] as Map<String, dynamic>)['text'] as String)),
          );
        }(),
    ];

    await file.writeAsString(jsonEncode([
      for (final a in ayahs)
        {'n': a.number, 'ar': a.arabic, 'en': a.translation},
    ]));
    await _deleteLegacyCache(surah, t);
    rlog('text: surah $surah (${t.code}) fetched (${ayahs.length} ayahs)');
    _bucket(t)[surah] = ayahs;
    return ayahs;
  }

  /// The Arabic and the translation of [surah], both answered 200.
  ///
  /// Tried [Download.attempts] times, [Download.backoff] apart. It was
  /// asked once: a moment without signal on the way into the preview —
  /// a lift, a hand-over from Wi-Fi to the mobile network — and the
  /// preview said to check the connection, and never got as far as the
  /// recitation, though a second later the network was back. A server
  /// that refuses outright is not asked again (see [Download.isFinal]);
  /// that is not the network.
  static Future<List<http.Response>> _fetchBoth(
      int surah, VerseTranslation t) async {
    final urls = [
      Uri.parse('$_arabicEndpoint?chapter_number=$surah'),
      Uri.parse('$_translationBase/${t.resourceId}?chapter_number=$surah'),
    ];
    Object? last;
    final client = http.Client();
    try {
      for (var attempt = 1; attempt <= Download.attempts; attempt++) {
        try {
          final responses = await Future.wait(
              [for (final u in urls) Download.get(client, u)]);
          for (final res in responses) {
            if (res.statusCode != 200) {
              throw BadStatus(res.statusCode, 'surah $surah text');
            }
          }
          return responses;
        } catch (e) {
          if (Download.isFinal(e)) rethrow;
          last = e;
          rlog('text: try $attempt/${Download.attempts} for surah $surah '
              'failed — $e');
          if (attempt < Download.attempts) {
            await Future<void>.delayed(Download.backoff(attempt));
          }
        }
      }
    } finally {
      client.close();
    }
    throw last!;
  }

  /// "2:255" -> 255.
  static int _ayahNumber(String verseKey) =>
      int.parse(verseKey.split(':').last);

  /// quran.com marks translator footnotes inline as
  /// `<sup foot_note=195935>1</sup>` — 1,903 of them across the Quran.
  /// The app has nowhere to show a footnote, and the bare digit left
  /// behind reads as part of the sentence ("...conscious of Allah1 -"),
  /// so the whole tag goes.
  @visibleForTesting
  static String stripFootnoteMarkup(String text) => text
      .replaceAll(RegExp(r'<sup\b[^>]*>.*?</sup>', dotAll: true), '')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'  +'), ' ')
      .trim();

  /// Flattens the invisible characters the translation editions carry.
  ///
  /// The English edition has none, which is why nothing here existed
  /// until other languages were added. The three that were added each
  /// carry their own, and every one of them shows on a verse card:
  ///
  ///  * `U+00AD` SOFT HYPHEN — 17 of them across 7 verses of the
  ///    Indonesian, and clustered: 2:119 reads
  ///    `(pertang\u00ad\u00ad\u00adgung\u00ad\u00ad jawaban)`. It is a
  ///    hyphenation hint for justified print. Shapers are free to draw
  ///    it as a real hyphen at a line end, and Inter has no glyph for
  ///    it at all, so it goes entirely rather than becoming a space.
  ///  * `U+000D`/`U+000A` — a hard line break sitting mid-clause in
  ///    4:140 of the German (`mit ihnen\r\n(zusammen)`). Left alone it
  ///    breaks the line there on every card, in the middle of a
  ///    sentence, for ever.
  ///  * `U+00A0` NO-BREAK SPACE — twice in the Urdu, used as an
  ///    ordinary word space (27:7, 9:52). It reads correctly but binds
  ///    the two words together, so a card can only break the line
  ///    somewhere worse.
  ///
  /// Zero-width joiner and non-joiner are deliberately left alone:
  /// they are not decoration in Arabic script, they choose whether
  /// letters join, and dropping them would misspell Urdu words. None
  /// of the offered editions uses them today, but a future one may.
  ///
  /// Verified by `tool/verify_translations.py`, which fails the build
  /// of this list if an edition carries an invisible this does not
  /// handle.
  @visibleForTesting
  static String normalizeSpaces(String text) {
    const softHyphen = 0x00AD, zeroWidthSpace = 0x200B, bom = 0xFEFF;
    const nbsp = 0x00A0, narrowNbsp = 0x202F, lineSep = 0x2028;
    const paraSep = 0x2029, nextLine = 0x0085;
    final out = StringBuffer();
    for (final c in text.runes) {
      if (c == softHyphen || c == zeroWidthSpace || c == bom) continue;
      final isBreak = c == 0x0A || c == 0x0D || c == 0x09 ||
          c == lineSep || c == paraSep || c == nextLine;
      if (isBreak || c == nbsp || c == narrowNbsp) {
        out.write(' ');
        continue;
      }
      out.writeCharCode(c);
    }
    return out.toString().replaceAll(RegExp(r'  +'), ' ').trim();
  }

  static List<Ayah> _decode(int surah, String json) {
    final raw = jsonDecode(json) as List;
    return [
      for (final e in raw.cast<Map<String, dynamic>>())
        Ayah(
          number: e['n'] as int,
          // Also applied here so caches written before the fix load
          // correctly — stripping an already-clean ayah is a no-op.
          // This is what clears the circles out of surahs already on
          // disk, without making anyone re-download a word.
          arabic: stripLeadingBasmala(surah, e['n'] as int,
              stripCircleMarks(dropWrongSideIqlabMeem(e['ar'] as String))),
          // Also normalized here, so caches written before the
          // normalizer load clean without anyone re-downloading.
          translation: normalizeSpaces(e['en'] as String),
        ),
    ];
  }

  /// The source text glues the Basmala onto ayah 1 of every surah.
  /// In the mushaf it is only part of an ayah in Al-Fatiha (and
  /// At-Tawbah opens without one), so everywhere else it must not be
  /// displayed as verse text. Matched letters-only, so any diacritic
  /// or encoding variant of the Basmala is caught.
  @visibleForTesting
  static String stripLeadingBasmala(int surah, int ayah, String text) {
    if (ayah != 1 || surah == 1 || surah == 9) return text;
    final words = text.split(' ');
    if (words.length < 5) return text;
    if (_letters(words.take(4).join(' ')) != 'بسم الله الرحمن الرحيم') {
      return text;
    }
    return words.skip(4).join(' ');
  }

  /// The mushaf's circles. None of them is a letter, and none of them
  /// survives onto a card.
  ///
  /// The round zero (U+06DF) sits over a letter that is written but not
  /// pronounced — the silent alif of `ءَامَنُوا۟`, `صَلُّوا۟`, `وَسَلِّمُوا۟` — and
  /// its upright twin (U+06E0) says the same of a letter skipped only
  /// when the reader carries straight on. At verse size they are
  /// hairlines in print; blown up to fill a reel they read as bright
  /// white beads strung through the line, and that is what they were
  /// reported as.
  ///
  /// The rosette (U+06DE) is not part of a verse at all: it marks where
  /// a rub' el hizb begins, and the source serves it as its own
  /// space-separated token — 30 across the six surahs sampled — so it
  /// would land mid-card as a large bright circle with a space either
  /// side. The space it leaves behind is closed up with it.
  ///
  /// This is a deliberate departure from the printed KFGQPC text, which
  /// sets all three. The letters, their harakat and the pause marks are
  /// untouched; what goes is only the annotation a listener following a
  /// recitation is never reading anyway.
  @visibleForTesting
  static String stripCircleMarks(String text) {
    const roundedZero = 0x06DF, uprightZero = 0x06E0;
    const rubElHizb = 0x06DE, endOfAyah = 0x06DD;
    final out = StringBuffer();
    for (final c in text.runes) {
      if (c == roundedZero ||
          c == uprightZero ||
          c == rubElHizb ||
          c == endOfAyah) {
        continue;
      }
      out.writeCharCode(c);
    }
    return out.toString().replaceAll(RegExp(r'  +'), ' ').trim();
  }

  /// The iqlab meem — the little meem that says "pronounce this tanween
  /// as an m" — is written on the same side as the tanween it belongs
  /// to: below for kasratan (U+06ED), above for fathatan and dammatan
  /// (U+06E2). The mushaf only ever prints it that way, and the bundled
  /// KFGQPC Hafs face only knows how to position it that way.
  ///
  /// The source text also carries the mirrored spellings — a *low* meem
  /// under fathatan/dammatan, a *high* meem over kasratan — as a reading
  /// annotation the mushaf itself does not print. The face has outlines
  /// for both codepoints, so nothing falls through to the Amiri
  /// fallback; it simply has no anchor for the combination and drops the
  /// meem straight into the body of the letter, where it reads as a tiny
  /// glyph smudged behind the word (هُدًۭى, خَيْرٌۭ, شَىْءٍۢ …).
  ///
  /// Dropping just the mirrored pair leaves exactly the 609 meems the
  /// King Fahd Complex mushaf prints, in exactly its places.
  @visibleForTesting
  static String dropWrongSideIqlabMeem(String text) {
    const lowMeem = 0x06ED, highMeem = 0x06E2;
    const fathatan = 0x064B, dammatan = 0x064C, kasratan = 0x064D;
    final out = StringBuffer();
    var prev = 0;
    for (final c in text.runes) {
      final mirrored = (c == lowMeem && (prev == fathatan || prev == dammatan)) ||
          (c == highMeem && prev == kasratan);
      if (!mirrored) out.writeCharCode(c);
      prev = c;
    }
    return out.toString();
  }

  static String _letters(String s) {
    final b = StringBuffer();
    for (final c in s.runes) {
      if (c >= 0x064B && c <= 0x065F) continue; // harakat
      if (c == 0x0670 || c == 0x0640 || c == 0x0653) continue; // dagger alif, tatweel, madda
      b.write(String.fromCharCode(c == 0x0671 ? 0x0627 : c)); // ٱ → ا
    }
    return b.toString();
  }

  static Future<Directory> _cacheDir() async {
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/quran_text');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// `_qpc` in the name is what makes an upgrading user re-fetch: the
  /// Tanzil caches they already hold are a different edition, and
  /// re-reading them would keep the old spellings on screen forever.
  /// The edition is part of the name, not just `_qpc`. Without it a
  /// surah cached in one translation would be read straight back in
  /// another — the Arabic would look right and every translation line
  /// would be the language the reader had just switched away from.
  static Future<File> _cacheFile(int surah, VerseTranslation t) async =>
      File('${(await _cacheDir()).path}/surah_${surah}_qpc_${t.code}.json');

  /// The single-edition `_qpc` cache from before translations could be
  /// chosen, renamed to the English edition's name — which is what it
  /// holds: Saheeh International beside the same Arabic. Read, not
  /// thrown away, so a surah an upgrading user already had still opens
  /// offline instead of failing to load; [_decode] cleans it up the way
  /// it does every cache written before a fix.
  static Future<void> _adoptLegacyEnglish(int surah, File into) async {
    try {
      final old = File('${(await _cacheDir()).path}/surah_${surah}_qpc.json');
      if (old.existsSync()) {
        await old.rename(into.path);
        rlog('text: surah $surah cache from before editions kept as en');
      }
    } catch (_) {/* fetched instead */}
  }

  /// Caches from before this file's naming scheme, dropped once their
  /// replacement is safely on disk so an old copy isn't left taking up
  /// room: the Tanzil-era one, and — once the English edition has its
  /// own file — the single-edition `_qpc` one that held it before
  /// translations could be chosen. Fetching another edition leaves that
  /// one alone: it is the English text, still wanted if the reader
  /// switches back.
  static Future<void> _deleteLegacyCache(int surah, VerseTranslation t) async {
    try {
      final dir = (await _cacheDir()).path;
      for (final name in [
        'surah_$surah.json',
        if (t == VerseTranslation.english) 'surah_${surah}_qpc.json',
      ]) {
        final old = File('$dir/$name');
        if (old.existsSync()) old.deleteSync();
      }
    } catch (_) {/* cosmetic cleanup: never fail a load over it */}
  }
}
