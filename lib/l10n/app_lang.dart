import 'package:flutter/widgets.dart' show TextDirection;

/// The languages the app's own interface can be shown in.
///
/// Separate from [VerseTranslation]: this is the chrome — buttons,
/// headings, notifications — and it is chosen independently of the
/// translation printed under a verse. Somebody reading the app in
/// English may well want the verse in Urdu, and the reverse is just
/// as common.
///
/// The Quran's own text is never in this list. It is Arabic, always.
enum AppLang {
  en('en', 'English', 'English'),
  ar('ar', 'العربية', 'Arabic'),
  ur('ur', 'اردو', 'Urdu'),
  id('id', 'Bahasa Indonesia', 'Indonesian'),
  de('de', 'Deutsch', 'German');

  const AppLang(this.code, this.nativeName, this.englishName);

  /// The BCP-47 code, which is also what [Locale] is built from and
  /// what the settings file stores.
  final String code;

  /// What the language calls itself — what a language picker must show,
  /// because somebody who only reads Urdu cannot find "Urdu" in a list
  /// written in English.
  final String nativeName;

  /// The English name, for the second line of that same row.
  final String englishName;

  /// Arabic and Urdu are written right to left; the whole app mirrors.
  bool get rtl => this == AppLang.ar || this == AppLang.ur;

  TextDirection get direction => rtl ? TextDirection.rtl : TextDirection.ltr;

  /// True for the languages set in Arabic script.
  ///
  /// Two typographic rules hang off this and neither is about
  /// direction, which is why it is not spelled [rtl]: joined script
  /// must not be letter-spaced — the tracking pulls the joins apart —
  /// and it has no case, so a label the Latin languages set in capitals
  /// has to stay as it is written.
  bool get arabicScript => this == AppLang.ar || this == AppLang.ur;

  /// Falls back to English for anything unrecognised, so a settings
  /// file written by a newer build can never strand the app on a
  /// language this one cannot render.
  static AppLang fromCode(String? code) => AppLang.values
      .firstWhere((l) => l.code == code, orElse: () => AppLang.en);
}
