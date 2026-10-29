import 'package:flutter/widgets.dart' show TextDirection;

/// The translation printed under a verse, and where it comes from.
///
/// Chosen in Settings, independently of the app's own language: the
/// person reading the interface in English is often not the person the
/// reel is being made for. The Arabic itself never changes — this only
/// ever picks the line beneath it.
///
/// Every edition here is one quran.com serves as a numbered resource,
/// which is the same endpoint the app has always used for English, so
/// adding one costs a request and nothing else.
///
/// ## What "verified" means for this list
///
/// An edition is only in this enum if all of the following were checked
/// against the live API, whole — not sampled:
///
///  1. It returns exactly 6236 verses, and its per-chapter counts match
///     the Hafs counts in [surahIndex] for all 114 surahs, so no verse
///     can ever be captioned with its neighbour's translation.
///  2. Every verse is non-empty once [QuranTextService.stripFootnoteMarkup]
///     has run, and no HTML survives that strip.
///  3. No stranded footnote digits are left glued to a word.
///  4. Every codepoint the edition uses is covered by the face the app
///     renders it in — checked against the font's cmap over the entire
///     edition, not a sample. A missing glyph is a tofu box in an
///     exported reel, which cannot be taken back.
///  5. Its invisible characters are known and handled. They are not the
///     same per edition — see [QuranTextService.normalizeSpaces].
///
/// The verification script is `tool/verify_translations.py`. Editions
/// that did not pass are named there with the reason, so nobody has to
/// re-derive why they were left out.
enum VerseTranslation {
  /// Saheeh International — what the app shipped with, and the default.
  /// Plain, close, and the most widely quoted English rendering.
  english(
    resourceId: 20,
    code: 'en',
    nativeName: 'English',
    englishName: 'English',
    translator: 'Saheeh International',
  ),

  /// Fatah Muhammad Jalandhari — the classic plain Urdu translation,
  /// printed in the subcontinent for a century. Chosen over Maududi's
  /// Tafheem, which is a commentary: its verses run long because they
  /// carry explanation, and a verse card has to hold the verse.
  urdu(
    resourceId: 234,
    code: 'ur',
    nativeName: 'اردو',
    englishName: 'Urdu',
    translator: 'فتح محمد جالندھری',
    rtl: true,
    arabicScript: true,
  ),

  /// The Indonesian Ministry of Religious Affairs' translation — the
  /// state edition, and the one an Indonesian reader will recognise.
  indonesian(
    resourceId: 33,
    code: 'id',
    nativeName: 'Bahasa Indonesia',
    englishName: 'Indonesian',
    translator: 'Kementerian Agama RI',
  ),

  /// Bubenheim & Elyas — published by the King Fahd Complex and the
  /// standard German rendering.
  german(
    resourceId: 27,
    code: 'de',
    nativeName: 'Deutsch',
    englishName: 'German',
    translator: 'Frank Bubenheim und Nadeem Elyas',
  );

  const VerseTranslation({
    required this.resourceId,
    required this.code,
    required this.nativeName,
    required this.englishName,
    required this.translator,
    this.rtl = false,
    this.arabicScript = false,
  });

  /// quran.com's resource id. This is the cache key as well as the URL
  /// segment — see [QuranTextService], where a surah cached under one
  /// edition must never be read back under another.
  final int resourceId;

  final String code;
  final String nativeName;
  final String englishName;

  /// Named on the settings row, under the language. Which hand a
  /// translation came from is the whole of what distinguishes one from
  /// another, so it is not a detail to leave off.
  final String translator;

  final bool rtl;

  /// Whether the translation needs an Arabic-capable face. Drives the
  /// font, and drops the italic — slanting joined script degrades it.
  final bool arabicScript;

  TextDirection get direction => rtl ? TextDirection.rtl : TextDirection.ltr;

  /// Falls back to the edition the app has always used, so a settings
  /// file naming an edition this build does not carry still opens.
  static VerseTranslation fromCode(String? code) => VerseTranslation.values
      .firstWhere((t) => t.code == code, orElse: () => VerseTranslation.english);

  /// The translation to start someone on, given the language they just
  /// chose for the app. Every app language except Arabic has a matching
  /// edition; Arabic hides the translation line entirely, so English is
  /// as good a resting value as any.
  static VerseTranslation forAppLang(String langCode) =>
      VerseTranslation.values.firstWhere((t) => t.code == langCode,
          orElse: () => VerseTranslation.english);
}
