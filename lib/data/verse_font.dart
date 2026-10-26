import 'package:flutter/foundation.dart';

import 'verse_translation.dart';

/// The faces a reel's typography is set in.
///
/// Bundled, not fetched. Everything else the app draws takes its face
/// from google_fonts, which resolves over the network and falls back
/// silently when it cannot — fine for a button, wrong for a verse: the
/// exporter rasterizes the card and burns it into an mp4 the user
/// cannot take back, and a face that had not landed yet would be baked
/// in as the fallback. So every face a reel can be typeset in ships
/// inside the app, which also means the picker can *show* them all on
/// a cold install with no network at all.
///
/// Each face carries two numbers derived from its own metrics rather
/// than guessed:
///
///  * [sizeFactor] normalises optical size. Two faces at the same
///    point size are not the same size on the page — the ink of a
///    letter fills anything from half to three quarters of the em —
///    so every face is scaled to set the verse at the size the
///    default sets it. Derived from the mean ink height of five
///    letters that carry the script's height (ا ل م ب س), against the
///    same measurement of the default face.
///  * [height] is the line box, as a multiple of the (already scaled)
///    size. Never below the face's own declared line height, which is
///    where the marks of one line start landing on the line above;
///    otherwise the app's own rhythm — line advance over ink height,
///    2.92 for the verse and 2.75 for the translation — carried over
///    from the default.
///
/// `tool/verify_fonts.py` re-derives both from the files on every run
/// and fails if a number here has drifted from the face it describes.
/// It also checks, over all 6236 verses and every translation edition,
/// that each face can actually set what it is offered for: a missing
/// glyph is a tofu box in an exported reel.
@immutable
class _Face {
  /// The family as declared in pubspec.yaml.
  final String family;
  final double sizeFactor;
  final double height;

  const _Face(this.family, this.sizeFactor, this.height);
}

/// A face the Quran's own line can be set in. Every one of them covers
/// the Uthmani text whole — checked against the cmap, not sampled — and
/// attaches its marks through GPOS, so a shadda and its vowel stack
/// rather than collide.
///
/// Ordered by hand, so the picker reads as a type specimen: the mushaf
/// faces, then the naskhs, the kufis, the sans and the display face,
/// each weight beside the face it is a weight of. Only [name] is
/// stored, so the order can change; a name cannot.
enum VerseFace {
  /// KFGQPC Uthmanic Hafs: the mushaf's own face, and the default.
  /// What the app has always set the verse in.
  uthmani(
    _Face('HafsUthmani', 1.00, 1.90),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Uthmani',
  ),

  /// Amiri Quran — the classical naskh of the Bulaq tradition, cut for
  /// Quranic text. Rounder and more calligraphic than the mushaf face,
  /// and it asks for the tallest line box here: its marks stack high.
  amiri(
    _Face('AmiriQuran', 0.90, 2.45),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Amiri',
  ),

  /// Scheherazade New — SIL's wide, unhurried naskh. The most generous
  /// counters of the five, which is what makes it read at a glance on
  /// a phone held at arm's length.
  scheherazade(
    _Face('ScheherazadeNew', 0.88, 2.16),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Scheherazade',
  ),

  /// Noto Naskh Arabic — even, modern, low contrast. The quietest of
  /// them against a busy scenery.
  naskh(
    _Face('NotoNaskhArabic', 0.94, 2.03),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Naskh',
  ),

  /// Noto Naskh Arabic Bold — the same even hand with the weight to
  /// hold its own over bright footage, where the regular thins first.
  naskhBold(
    _Face('NotoNaskhArabicBold', 0.90, 2.11),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Naskh Bold',
  ),

  /// Amiri's text cut, beside its Quran cut above. The same hand, set
  /// with ordinary marks rather than the raised ones a mushaf needs —
  /// which is a quieter, tighter page, and a line box half a unit
  /// shorter for it.
  amiriText(
    _Face('Amiri', 0.90, 2.10),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Amiri Text',
  ),

  /// Amiri Bold — the Bulaq naskh set heavy, the way a printed book
  /// sets its headings. Tighter still than the text cut.
  amiriBold(
    _Face('AmiriBold', 0.87, 2.17),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Amiri Bold',
  ),

  /// Lateef — a fine, light hand with a small body, which is why it
  /// takes the largest size factor of the five. Delicate on a still,
  /// and the one to avoid over moving water.
  lateef(
    _Face('Lateef', 1.29, 1.47),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Lateef',
  ),

  /// Lateef Bold — the same small, open hand with enough ink in it to
  /// survive the moving water the regular cut is warned off above.
  lateefBold(
    _Face('LateefBold', 1.20, 1.59),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Lateef Bold',
  ),

  /// Harmattan — SIL’s light naskh, drawn for West African Arabic — simple shapes and a short line.
  harmattan(
    _Face('Harmattan', 1.09, 1.75),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Harmattan',
  ),

  /// Harmattan Bold — the West African hand, heavier: plain, sturdy
  /// letters that read from across a room.
  harmattanBold(
    _Face('HarmattanBold', 1.05, 1.81),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Harmattan Bold',
  ),

  /// Noto Kufi Arabic — the one face on this list that is not a naskh.
  /// Kufi is the hand of an inscription: geometric, unmodulated, and
  /// built for a wall rather than a page. On a card it reads as
  /// architecture, which is exactly why it is here and exactly why it
  /// is not the default.
  kufi(
    _Face('NotoKufiArabic', 0.82, 2.31),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Kufi',
  ),

  /// Noto Kufi Arabic Thin — the inscription drawn with a hairline.
  /// Architectural and quiet; at its best over dark, still scenery.
  kufiThin(
    _Face('NotoKufiArabicThin', 0.84, 2.25),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Kufi Thin',
  ),

  /// Noto Kufi Arabic Bold — the kufi at poster weight: square, loud,
  /// and made for a title card.
  kufiBold(
    _Face('NotoKufiArabicBold', 0.81, 2.34),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Kufi Bold',
  ),

  /// Noto Sans Arabic — Noto’s own sans: low contrast, even colour, and complete.
  notoSansArabic(
    _Face('NotoSansArabic', 0.88, 2.15),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Noto Sans Arabic',
  ),

  /// Noto Sans Arabic ExtraLight — the sans reduced to a thread.
  /// Elegant over an open sky; lost over leaves.
  notoSansExtraLight(
    _Face('NotoSansArabicExtraLight', 0.90, 2.11),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Sans ExtraLight',
  ),

  /// Noto Sans Arabic Black — the heaviest face on the list. A
  /// headline rather than a page, and the last to give way to footage.
  notoSansBlack(
    _Face('NotoSansArabicBlack', 0.79, 2.40),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Sans Black',
  ),

  /// Noto Sans Arabic ExtraCondensed — the same sans drawn narrow and
  /// tall, which sets a long verse in fewer lines than anything here.
  notoSansNarrow(
    _Face('NotoSansArabicExtraCondensed', 0.89, 2.13),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Sans Narrow',
  ),

  /// Its bold: narrow and heavy, the look of a film title.
  notoSansNarrowBold(
    _Face('NotoSansArabicExtraCondensedBold', 0.83, 2.30),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Narrow Bold',
  ),

  /// IBM Plex Sans Arabic — the app's own Urdu face, and a verse face
  /// too: a sans with the pen still in it, thick and thin where Noto's
  /// sans is even.
  plex(
    _Face('IBMPlexSansArabic', 0.92, 2.07),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'IBM Plex',
  ),

  /// IBM Plex Sans Arabic Bold — the same, with a caption's weight.
  plexBold(
    _Face('IBMPlexSansArabicBold', 0.87, 2.17),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'IBM Plex Bold',
  ),

  /// Mada — a modern Arabic sans that carries every Quranic mark — the plainest ground a verse can stand on.
  mada(
    _Face('Mada', 1.12, 1.70),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Mada',
  ),

  /// Mada Light — as plain as Mada, with less ink: the quietest sans
  /// here.
  madaLight(
    _Face('MadaLight', 1.14, 1.66),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Mada Light',
  ),

  /// Estedad — a Persian sans on geometric lines: round bowls, flat
  /// terminals, a wide set. The most contemporary face on the list.
  estedad(
    _Face('Estedad', 0.92, 2.06),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Estedad',
  ),

  /// Estedad Black — the same geometry at full weight: round, heavy,
  /// and friendly rather than loud.
  estedadBlack(
    _Face('EstedadBlack', 0.85, 2.24),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Estedad Black',
  ),

  /// Jomhuria — a Persian display hand: dark, compact, dramatic, with
  /// short ascenders and a small body. A poster, not a page — and the
  /// only face here drawn for a headline rather than for text.
  jomhuria(
    _Face('Jomhuria', 1.38, 1.38),
    specimen: 'بِسْمِ ٱللَّهِ',
    label: 'Jomhuria',
  );

  const VerseFace(this._face, {required this.specimen, required this.label});

  final _Face _face;

  /// What the picker sets in the face itself. The same phrase for
  /// every one of them, so the card shows the difference and nothing
  /// else.
  final String specimen;

  /// The face's own name, in the UI's font.
  final String label;

  String get family => _face.family;
  double get sizeFactor => _face.sizeFactor;
  double get height => _face.height;

  /// Behind every verse face, in order. Never reached in practice —
  /// every one of them covers the Uthmani text whole — and carried anyway,
  /// because the alternative to a fallback that never fires is a tofu
  /// box in a file somebody already shared.
  List<String> get fallback => const ['HafsUthmani', 'NotoNaskhArabic'];

  static VerseFace fromName(String? name) =>
      VerseFace.values.firstWhere((f) => f.name == name,
          orElse: () => VerseFace.uthmani);
}

/// A face the translation line can be set in.
///
/// Two lists in one enum, because a translation is set in one script
/// or the other and the choice belongs to the script rather than to
/// the reel: somebody reading Saheeh International in Cormorant still
/// wants Nastaliq the day they switch the edition to Urdu, and back
/// again when they switch it out. [CreationState] keeps one choice per
/// script for exactly that reason.
enum TranslationFace {
  // ---- Latin script: English, Indonesian, German -----------------

  /// Inter, italic — what the app has always set a translation in.
  inter(
    _Face('Inter', 1.00, 1.50),
    arabicScript: false,
    italic: true,
    label: 'Inter',
  ),

  /// Source Serif 4 — a text serif with a large eye, built to be read
  /// small. The closest thing here to a printed edition.
  sourceSerif(
    _Face('SourceSerif4', 1.11, 1.37),
    arabicScript: false,
    label: 'Source Serif',
  ),

  /// Spectral — a screen-first serif with long extenders; the most
  /// editorial of the four, and the one that best survives a scrim.
  spectral(
    _Face('Spectral', 1.21, 1.52),
    arabicScript: false,
    label: 'Spectral',
  ),

  /// Cormorant Garamond — a display Garamond, fine-stroked and
  /// small-bodied, which is why it is set nearly half again as large
  /// as Inter. The most beautiful line on the list and the first to
  /// disappear over bright footage.
  cormorant(
    _Face('CormorantGaramond', 1.41, 1.21),
    arabicScript: false,
    label: 'Cormorant',
  ),

  /// Literata — Google's book face: sturdy, warm, entirely unfussy.
  literata(
    _Face('Literata', 1.08, 1.49),
    arabicScript: false,
    label: 'Literata',
  ),

  /// EB Garamond — the Garamond that is actually a Garamond: a digital
  /// cut of Claude Garamont's own types. Small-bodied, so it is set a
  /// third again as large as Inter, and the most *printed*-looking
  /// line on the list.
  garamond(
    _Face('EBGaramond', 1.33, 1.30),
    arabicScript: false,
    label: 'EB Garamond',
  ),

  /// Libre Baskerville — Baskerville cut for screens: a large eye, open
  /// counters and enough weight to hold up over a photograph, which is
  /// where the finer serifs here give way first.
  baskerville(
    _Face('LibreBaskerville', 1.03, 1.46),
    arabicScript: false,
    label: 'Baskerville',
  ),

  /// Crimson Pro — a Garalde cut for long reading, with a small eye.
  crimsonPro(
    _Face('CrimsonPro', 1.30, 1.15),
    arabicScript: false,
    label: 'Crimson Pro',
  ),
  /// Crimson Text — the older, warmer cut of the same hand.
  crimsonText(
    _Face('CrimsonText', 1.28, 1.30),
    arabicScript: false,
    label: 'Crimson Text',
  ),
  /// Cardo — a Bembo revival, built for scholarship.
  cardo(
    _Face('Cardo', 1.24, 1.35),
    arabicScript: false,
    label: 'Cardo',
  ),
  /// Vollkorn — a sturdy German text face — "wholegrain".
  vollkorn(
    _Face('Vollkorn', 1.18, 1.39),
    arabicScript: false,
    label: 'Vollkorn',
  ),
  /// Alegreya — calligraphic, restless, designed for literature.
  alegreya(
    _Face('Alegreya', 1.18, 1.36),
    arabicScript: false,
    label: 'Alegreya',
  ),
  /// Bitter — a contemporary slab, square and steady.
  bitter(
    _Face('Bitter', 1.03, 1.46),
    arabicScript: false,
    label: 'Bitter',
  ),
  /// Rokkitt — a geometric slab with the smallest body here.
  rokkitt(
    _Face('Rokkitt', 1.38, 1.14),
    arabicScript: false,
    label: 'Rokkitt',
  ),
  /// Cormorant — the display Garamond the Garamond above is a text
  /// cut of: the same drawing, finer and less hinted.
  cormorantDisplay(
    _Face('Cormorant', 1.41, 1.21),
    arabicScript: false,
    label: 'Cormorant Display',
  ),
  /// Rasa — a Devanagari-companion serif, open and light.
  rasa(
    _Face('Rasa', 1.31, 1.22),
    arabicScript: false,
    label: 'Rasa',
  ),
  /// Yrsa — Rasa with more weight in the stems.
  yrsa(
    _Face('Yrsa', 1.31, 1.22),
    arabicScript: false,
    label: 'Yrsa',
  ),
  /// Work Sans — a grotesque cut for screens at middle sizes.
  workSans(
    _Face('WorkSans', 1.09, 1.37),
    arabicScript: false,
    label: 'Work Sans',
  ),
  /// Space Grotesk — a proportional cut of a monospace design.
  spaceGrotesk(
    _Face('SpaceGrotesk', 1.12, 1.34),
    arabicScript: false,
    label: 'Space Grotesk',
  ),
  /// Mulish — a minimal sans with round, even counters.
  mulish(
    _Face('Mulish', 1.09, 1.38),
    arabicScript: false,
    label: 'Mulish',
  ),
  /// Nunito Sans — the upright cut of a rounded family.
  nunitoSans(
    _Face('NunitoSans', 1.12, 1.36),
    arabicScript: false,
    label: 'Nunito Sans',
  ),
  /// Raleway — an elegant sans with a single-storey w.
  raleway(
    _Face('Raleway', 1.05, 1.43),
    arabicScript: false,
    label: 'Raleway',
  ),
  /// Quicksand — geometric and rounded at every terminal.
  quicksand(
    _Face('Quicksand', 1.05, 1.43),
    arabicScript: false,
    label: 'Quicksand',
  ),
  /// Montserrat — the urban signage of Buenos Aires, redrawn.
  montserrat(
    _Face('Montserrat', 1.04, 1.44),
    arabicScript: false,
    label: 'Montserrat',
  ),
  /// Urbanist — a low-contrast geometric sans.
  urbanist(
    _Face('Urbanist', 1.09, 1.38),
    arabicScript: false,
    label: 'Urbanist',
  ),
  /// Public Sans — the US government’s own neutral sans.
  publicSans(
    _Face('PublicSans', 1.06, 1.42),
    arabicScript: false,
    label: 'Public Sans',
  ),
  /// Jakarta Sans — a humanist sans from a city brand.
  jakartaSans(
    _Face('PlusJakartaSans', 1.02, 1.47),
    arabicScript: false,
    label: 'Jakarta Sans',
  ),
  /// Epilogue — a variable grotesque with a narrow set.
  epilogue(
    _Face('Epilogue', 1.03, 1.46),
    arabicScript: false,
    label: 'Epilogue',
  ),
  /// Domine — a body serif drawn to hold up at small sizes.
  domine(
    _Face('Domine', 1.01, 1.48),
    arabicScript: false,
    label: 'Domine',
  ),
  /// Petrona — a fine transitional serif with long extenders.
  petrona(
    _Face('Petrona', 1.23, 1.22),
    arabicScript: false,
    label: 'Petrona',
  ),

  // ---- Arabic script: Urdu ---------------------------------------

  /// IBM Plex Sans Arabic — the app's own, and what an Urdu
  /// translation has always been set in.
  plex(
    _Face('IBMPlexSansArabic', 1.00, 1.50),
    arabicScript: true,
    label: 'IBM Plex',
  ),

  /// Noto Nastaliq Urdu — the hand Urdu is actually printed in.
  /// Sloped, cascading, and nothing like a naskh: it needs two and a
  /// half times its own size as a line box, and is set a little
  /// smaller to pay for it.
  nastaliq(
    _Face('NotoNastaliqUrdu', 0.88, 2.50),
    arabicScript: true,
    label: 'Nastaliq',
  ),

  /// Noto Naskh Arabic, again — the same face the verse can be set
  /// in, which is what makes a reel typeset entirely in one hand
  /// possible.
  naskh(
    _Face('NotoNaskhArabic', 1.02, 1.70),
    arabicScript: true,
    label: 'Naskh',
  ),

  /// Scheherazade New, again, for the same reason.
  scheherazade(
    _Face('ScheherazadeNew', 0.96, 2.04),
    arabicScript: true,
    label: 'Scheherazade',
  ),

  /// Amiri's text cut, for the same reason: a reel typeset in one hand
  /// throughout, verse and translation.
  amiri(
    _Face('Amiri', 0.99, 1.76),
    arabicScript: true,
    label: 'Amiri',
  ),

  /// Markazi Text — by Amiri's designer, cut for Persian and Urdu as
  /// much as for Arabic: a light, economical naskh that sets a long
  /// translation in fewer lines than anything else here.
  markazi(
    _Face('MarkaziText', 1.27, 1.20),
    arabicScript: true,
    label: 'Markazi',
  ),

  /// Noto Kufi Arabic, again — an inscription under a verse set in
  /// one. Only ever a pairing choice; nobody reads a paragraph in
  /// kufi.
  kufi(
    _Face('NotoKufiArabic', 0.90, 1.90),
    arabicScript: true,
    label: 'Kufi',
  ),

  /// Katibeh — a Persian display hand, sloped and calligraphic.
  katibeh(
    _Face('Katibeh', 1.07, 1.41),
    arabicScript: true,
    label: 'Katibeh',
  ),
  /// Mirza — a nastaliq-influenced text face, Persian in feel.
  mirza(
    _Face('Mirza', 1.18, 1.27),
    arabicScript: true,
    label: 'Mirza',
  );

  const TranslationFace(
    this._face, {
    required this.arabicScript,
    required this.label,
    this.italic = false,
  });

  final _Face _face;

  /// Which of the two lists this face is on.
  final bool arabicScript;

  /// Whether the line is set sloped. True for Inter alone, which is
  /// the look the app shipped with; joined script is never slanted,
  /// and the serif faces read better upright under a verse.
  final bool italic;

  final String label;

  String get family => _face.family;
  double get sizeFactor => _face.sizeFactor;
  double get height => _face.height;

  /// What the picker sets in the face. The Latin faces spell their own
  /// name, which is how a type specimen has always worked; the
  /// Arabic-script ones spell "Urdu", because the four of them differ
  /// far more than four Latin names would show.
  String get specimen => arabicScript ? 'اردو' : label;

  /// Behind the face, in order.
  ///
  /// Source Serif first: a translation carries the transliteration
  /// marks Saheeh International sets its names in — ḥ ṣ ṭ ẓ ḍ ā ī ū —
  /// and not every face on this list draws all of them. A face that
  /// does not gets them from a text serif of roughly its own colour,
  /// which is a joined word with one borrowed letter in it rather than
  /// a tofu box. Most of the list needs it for nothing at all; see
  /// `tool/verify_fonts.py`, which prints exactly how many codepoints
  /// each face leans on the fallback for.
  ///
  /// Then the Arabic-capable house face, for the ﷺ ligature Saheeh
  /// International writes 34 times and no Latin face carries — and,
  /// behind Nastaliq, for the one high hamza it does not (a
  /// non-joining letter, so the substitution stands alone and breaks
  /// no word).
  List<String> get fallback =>
      const ['SourceSerif4', 'IBMPlexSansArabic'];

  /// The faces offered for a line set in this script.
  static List<TranslationFace> forScript({required bool arabicScript}) => [
        for (final f in TranslationFace.values)
          if (f.arabicScript == arabicScript) f
      ];

  /// What a script starts on before anybody has chosen.
  static TranslationFace defaultFor({required bool arabicScript}) =>
      arabicScript ? TranslationFace.plex : TranslationFace.inter;

  /// The face for [t], given the two the user has chosen. Falls back
  /// to the script's default when a saved name is from a build that
  /// offered something this one does not.
  static TranslationFace fromName(String? name, {required bool arabicScript}) {
    for (final f in TranslationFace.values) {
      if (f.name == name && f.arabicScript == arabicScript) return f;
    }
    return defaultFor(arabicScript: arabicScript);
  }
}

/// The pair of faces one reel is typeset in, resolved for the edition
/// its translation is in.
///
/// A single value so the widget, the rasterizer, the recipe and the
/// render key all read the same thing — the cards are memoized on it,
/// and a face that reached the widget but not the key would serve a
/// stale PNG.
@immutable
class ReelTypography {
  final VerseFace verse;
  final TranslationFace translation;

  const ReelTypography({
    this.verse = VerseFace.uthmani,
    this.translation = TranslationFace.inter,
  });

  /// The pair for [edition], out of the choice held per script.
  factory ReelTypography.of({
    required VerseFace verse,
    required TranslationFace latin,
    required TranslationFace arabicScript,
    required VerseTranslation edition,
  }) =>
      ReelTypography(
        verse: verse,
        translation: edition.arabicScript ? arabicScript : latin,
      );

  /// Everything about the pair that changes a pixel, for a cache key.
  String get key => '${verse.name}.${translation.name}';

  @override
  bool operator ==(Object other) =>
      other is ReelTypography &&
      other.verse == verse &&
      other.translation == translation;

  @override
  int get hashCode => Object.hash(verse, translation);
}
