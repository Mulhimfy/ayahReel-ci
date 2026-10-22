import 'surah_index.dart';
import 'verse_font.dart';
import 'verse_translation.dart';

/// Whether a reel's verse card says which verse it is, and how.
///
/// Two independent pieces, offered as one choice:
///
///  * the mark — the numbered end-of-verse sign a printed mushaf sets
///    after every ayah, drawn at the end of the Arabic line;
///  * the reference — a small "Al-Baqarah 2:255" under the
///    translation, for the viewer who wants to find the verse again.
///
/// Off by default: the card has always been the verse and nothing
/// else, and a reel that suddenly carried numbers after an update
/// would be a change nobody asked for. Anyone who wants them turns
/// them on in Settings.
enum VerseNumbering {
  off('off'),
  mark('mark'),
  reference('ref'),
  both('both');

  const VerseNumbering(this.code);

  /// What Settings stores and the render cache key carries. Short and
  /// stable: renaming a value must not change either.
  final String code;

  bool get showsMark => this == mark || this == both;
  bool get showsReference => this == reference || this == both;

  static VerseNumbering fromCode(String? code) => VerseNumbering.values
      .firstWhere((v) => v.code == code, orElse: () => VerseNumbering.off);
}

/// Arabic-Indic digits: 255 -> '٢٥٥'. The Arabic line is always
/// numbered this way, whatever language the app is in, because that is
/// how the mushaf numbers it.
String arabicIndicDigits(int n) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return n
      .toString()
      .split('')
      .map((d) => digits[d.codeUnitAt(0) - 0x30])
      .join();
}

/// The numbered end-of-verse sign, as text, and the face that draws it.
///
/// Every verse face draws the sign from its own glyphs, so it matches
/// the letters beside it — but the faces disagree on how it is asked
/// for, and that was checked by rendering each one rather than by
/// reading cmaps:
///
///  * KFGQPC Hafs draws its Arabic-Indic digits *as* the sign — a bare
///    ٢٥٥ comes out circled — and puts a second, empty circle beside
///    it if U+06DD is sent as well.
///  * The rest enclose the digits that follow U+06DD (END OF AYAH),
///    which is the Unicode way of asking.
///  * Mada and IBM Plex Sans Arabic, at every weight bundled, carry
///    U+06DD but do not enclose: they draw an empty rosette next to
///    plain digits. They borrow Noto Sans Arabic's sign, the nearest
///    sans to them — its ExtraLight's under Mada Light, whose strokes
///    are nearer that weight. (Noto Sans draws one rosette at Regular,
///    Black and the narrow cuts alike, so Plex Bold needs no heavier
///    one.) Every face added beside them was shaped with ۝ and one,
///    two and three digits, and encloses all three.
({String text, VerseFace face}) ayahEndMark(VerseFace face, int ayah) {
  final digits = arabicIndicDigits(ayah);
  if (face == VerseFace.uthmani) return (text: digits, face: face);
  final drawnIn = switch (face) {
    VerseFace.mada || VerseFace.plex || VerseFace.plexBold =>
      VerseFace.notoSansArabic,
    VerseFace.madaLight => VerseFace.notoSansExtraLight,
    _ => face,
  };
  return (text: '۝$digits', face: drawnIn);
}

/// The reference line — the surah by name, then the verse — in the
/// script of the translation printed above it, since that is who the
/// line is for: "Al-Baqarah 2:255" under English, German or Indonesian,
/// and "البقرة ٢٥٥" under Urdu.
///
/// Empty when the surah is unknown, which is how a card that was never
/// told one draws no reference rather than a wrong one.
String verseReferenceLine(
    int surah, int ayah, VerseTranslation edition) {
  if (surah < 1 || surah > surahIndex.length) return '';
  final info = surahIndex[surah - 1];
  return edition.arabicScript
      ? '${info.nameArabic} ${arabicIndicDigits(ayah)}'
      : '${info.nameEnglish} $surah:$ayah';
}
