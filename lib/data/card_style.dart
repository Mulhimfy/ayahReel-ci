import 'package:flutter/painting.dart';

import 'verse_font.dart';

/// The design vocabulary of a card: its shape, its faces, the ways a
/// line of text can be finished, the borders it can wear, and the
/// grounds it can stand on when there is no photograph behind it.
///
/// ## Everything here is a fraction, never a pixel
///
/// A card is drawn at whatever width it is given — about 320pt in the
/// composer, 1080px in the file — and the two have to be the same
/// picture, because the composer *is* the proof of what will be
/// exported. So every measurement in a card is a fraction of its own
/// width: a text size of 0.08 is eight per cent of the card's width,
/// wherever it is drawn. Nothing in a saved card has a pixel in it,
/// which is also what lets the same card be re-shaped from square to
/// story without a single number being recomputed.

/// The three shapes a card is made in.
///
/// All three are 1080 across, so one export width serves them all and
/// the arithmetic below never changes; only the height moves. The
/// scenery library is entirely 1080x1920 (see [SceneCatalog]) —
/// upright, and taller than every one of these — so a photograph
/// always has more height than a card needs and the crop is a choice
/// rather than a compromise. Which part of it survives is the card's
/// own [CardBackground.focusY].
enum CardFormat {
  /// 1:1. The post that reads the same everywhere — feed, chat,
  /// anywhere a preview is square.
  square(1, 1),

  /// 4:5. The tallest a feed post is allowed to be, and so the most
  /// screen a card can take without becoming a story.
  portrait(4, 5),

  /// 9:16. A story or a reel cover, the same frame the app's reels are
  /// made in.
  story(9, 16);

  const CardFormat(this.wide, this.tall);

  final int wide;
  final int tall;

  /// Width over height.
  double get aspect => wide / tall;

  /// The width every card is exported at. The reels export at 1080
  /// too, which is what makes a story card and a reel cover the same
  /// size to the pixel.
  static const exportWidth = 1080.0;

  double get exportHeight => exportWidth / aspect;

  static CardFormat fromName(String? name) => CardFormat.values
      .firstWhere((f) => f.name == name, orElse: () => CardFormat.portrait);
}

/// A face a card's text can be set in.
///
/// Every one of them is a face the app already bundles for the verse
/// or the translation — see `lib/data/verse_font.dart`, which is
/// largely about why they are bundled rather than fetched — reached
/// here through one list instead of two, because a card does not know
/// whether the words on it are a verse, a hadith or the user's own
/// sentence. What it knows is the script they are written in.
///
/// The metrics are the ones derived from the files themselves, so a
/// card set in Cormorant and one set in Inter at the same nominal size
/// are the same size on the page.
enum CardFace {
  // ---- Arabic script --------------------------------------------
  uthmani(verse: VerseFace.uthmani),
  amiri(verse: VerseFace.amiri),
  scheherazade(verse: VerseFace.scheherazade),
  naskh(verse: VerseFace.naskh),
  lateef(verse: VerseFace.lateef),
  amiriText(verse: VerseFace.amiriText),
  kufi(verse: VerseFace.kufi),
  mada(verse: VerseFace.mada),
  notoSansArabic(verse: VerseFace.notoSansArabic),
  harmattan(verse: VerseFace.harmattan),
  plex(latin: TranslationFace.plex),
  nastaliq(latin: TranslationFace.nastaliq),
  markazi(latin: TranslationFace.markazi),
  cairo(display: DisplayFace.cairo),
  almarai(display: DisplayFace.almarai),
  changa(display: DisplayFace.changa),
  elMessiri(display: DisplayFace.elMessiri),
  reemKufi(display: DisplayFace.reemKufi),
  arefRuqaa(display: DisplayFace.arefRuqaa),
  qahiri(display: DisplayFace.qahiri),
  katibeh(latin: TranslationFace.katibeh),
  mirza(latin: TranslationFace.mirza),
  vazirmatn(display: DisplayFace.vazirmatn),

  // ---- Latin script ---------------------------------------------
  inter(latin: TranslationFace.inter),
  sourceSerif(latin: TranslationFace.sourceSerif),
  spectral(latin: TranslationFace.spectral),
  cormorant(latin: TranslationFace.cormorant),
  literata(latin: TranslationFace.literata),
  garamond(latin: TranslationFace.garamond),
  baskerville(latin: TranslationFace.baskerville),
  crimsonPro(latin: TranslationFace.crimsonPro),
  crimsonText(latin: TranslationFace.crimsonText),
  cardo(latin: TranslationFace.cardo),
  vollkorn(latin: TranslationFace.vollkorn),
  alegreya(latin: TranslationFace.alegreya),
  bitter(latin: TranslationFace.bitter),
  rokkitt(latin: TranslationFace.rokkitt),
  cormorantDisplay(latin: TranslationFace.cormorantDisplay),
  rasa(latin: TranslationFace.rasa),
  yrsa(latin: TranslationFace.yrsa),
  workSans(latin: TranslationFace.workSans),
  spaceGrotesk(latin: TranslationFace.spaceGrotesk),
  mulish(latin: TranslationFace.mulish),
  nunitoSans(latin: TranslationFace.nunitoSans),
  raleway(latin: TranslationFace.raleway),
  quicksand(latin: TranslationFace.quicksand),
  montserrat(latin: TranslationFace.montserrat),
  urbanist(latin: TranslationFace.urbanist),
  publicSans(latin: TranslationFace.publicSans),
  jakartaSans(latin: TranslationFace.jakartaSans),
  epilogue(latin: TranslationFace.epilogue),
  domine(latin: TranslationFace.domine),
  petrona(latin: TranslationFace.petrona),

  // ---- card only: see [DisplayFace] ------------------------------
  playfair(display: DisplayFace.playfair),
  marcellus(display: DisplayFace.marcellus),
  cinzel(display: DisplayFace.cinzel),
  gilda(display: DisplayFace.gilda),
  italiana(display: DisplayFace.italiana),
  tenorSans(display: DisplayFace.tenorSans),
  prata(display: DisplayFace.prata),
  bodoni(display: DisplayFace.bodoni),
  dmSerif(display: DisplayFace.dmSerif),
  josefin(display: DisplayFace.josefin),
  jost(display: DisplayFace.jost),
  outfit(display: DisplayFace.outfit);

  const CardFace({this.verse, this.latin, this.display})
      : assert(
            (verse == null ? 0 : 1) +
                    (latin == null ? 0 : 1) +
                    (display == null ? 0 : 1) ==
                1,
            'a card face comes from exactly one of the three lists');

  /// Exactly one of these is set; all three are forwarded to below.
  final VerseFace? verse;
  final TranslationFace? latin;
  final DisplayFace? display;

  String get family =>
      verse?.family ?? latin?.family ?? display!.family;
  double get sizeFactor =>
      verse?.sizeFactor ?? latin?.sizeFactor ?? display!.sizeFactor;
  double get height => verse?.height ?? latin?.height ?? display!.height;

  /// A display face leans on the same chain a translation face does:
  /// a serif for the marks it may not draw, then the Arabic-capable
  /// house face. Nothing a card can be typed with ends in a tofu box.
  List<String> get fallback =>
      verse?.fallback ??
      latin?.fallback ??
      const ['SourceSerif4', 'IBMPlexSansArabic'];
  String get label => verse?.label ?? latin?.label ?? display!.label;

  /// Whether the face is for joined script. The five Quran faces and
  /// the two Urdu ones are; the rest are not.
  bool get arabicScript =>
      verse != null ||
      (latin?.arabicScript ?? false) ||
      (display?.arabicScript ?? false);

  /// Whether the face was cut for the Quran's own text.
  ///
  /// Two of them were: the King Fahd Complex's own Hafs face, which
  /// the mushaf itself is set in, and Amiri's Quran cut. The rest are
  /// general Arabic faces — excellent ones, and several of them are
  /// used for Quran in print — but they were drawn for Arabic rather
  /// than for the mushaf's orthography and its marks.
  ///
  /// This is not the same question as "is it on the Arabic list":
  /// [arabicScript] answers that, and is what decides which faces a
  /// line is offered at all.
  bool get mushaf => this == CardFace.uthmani || this == CardFace.amiri;

  /// Set in the face itself in the picker. The Arabic faces spell the
  /// basmala's opening, the Latin ones their own name — a specimen
  /// has to be in the script it is a specimen of.
  String get specimen =>
      verse?.specimen ?? latin?.specimen ?? display!.label;

  /// Whether the app sets this face sloped. Inter alone, which is the
  /// look a translation has always had.
  bool get italic => latin?.italic ?? false;

  /// Whether this face is offered for a card and nowhere else — see
  /// [DisplayFace].
  bool get displayOnly => display != null;

  /// The faces offered for a given script, Quran faces first.
  static List<CardFace> forScript({required bool arabicScript}) => [
        for (final f in CardFace.values)
          if (f.arabicScript == arabicScript) f
      ];

  /// What a script starts on before anybody has chosen.
  static CardFace defaultFor({required bool arabicScript}) =>
      arabicScript ? CardFace.uthmani : CardFace.cormorant;

  /// The face for a line of Arabic that is *not* Quran — a hadith, a
  /// name, a phrase. Naskh rather than the mushaf face: the mushaf
  /// face is cut for the Quran's own orthography and setting anything
  /// else in it is a borrowed hand.
  static const arabicProse = CardFace.naskh;

  static CardFace fromName(String? name) => CardFace.values
      .firstWhere((f) => f.name == name, orElse: () => CardFace.cormorant);

  /// The style this face sets [size] pixels of text in. [size] is
  /// already in pixels — the card's width times the block's fraction —
  /// and is scaled here by the face's own optical factor, exactly as
  /// [AppTheme.quran] scales a verse.
  TextStyle style({
    required double size,
    required Color color,
    double lineHeight = 1,
    double tracking = 0,
    List<Shadow> shadows = const [],
  }) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size * sizeFactor,
        height: height * lineHeight,
        // Joined script is never tracked: the letter spacing pulls the
        // joins apart and the word stops being one word.
        letterSpacing: arabicScript ? null : tracking * size,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color,
        shadows: shadows,
      );
}

/// A face offered on a card and nowhere else.
///
/// The verse and the translation lists are held to a hard rule: every
/// face on them sets every verse, or every edition, out of its own
/// cmap or out of the fallback stacked behind it, checked over all
/// 6236 verses by `tool/verify_fonts.py`. A display face cannot meet
/// that rule and is not asked to — these are for a headline, a name, a
/// reference, a line somebody wrote themselves, and several of them do
/// not draw the transliteration marks a translation needs at all.
///
/// So they live here instead of on those lists, which is the whole
/// distinction: a card is typed by the person holding it, and what it
/// says is not a claim about the Quran.
enum DisplayFace {
  /// Playfair — high-contrast Didone, for a line that announces itself.
  playfair('PlayfairDisplay', 1.06, 1.42, 'Playfair'),
  /// Marcellus — Roman inscriptional capitals, at text size.
  marcellus('Marcellus', 1.09, 1.37, 'Marcellus'),
  /// Cinzel — classical capitals throughout — there is no lower case.
  cinzel('Cinzel', 0.91, 1.65, 'Cinzel'),
  /// Gilda — a light display serif with fine bracketed serifs.
  gilda('GildaDisplay', 1.15, 1.30, 'Gilda'),
  /// Italiana — Italian Renaissance capitals, very high contrast.
  italiana('Italiana', 1.09, 1.37, 'Italiana'),
  /// Tenor Sans — a quiet display sans, wide and open.
  tenorSans('TenorSans', 1.09, 1.37, 'Tenor Sans'),
  /// Prata — a Didone with strong vertical stress.
  prata('Prata', 1.05, 1.42, 'Prata'),
  /// Bodoni — Bodoni proper: hairlines and flat serifs.
  bodoni('BodoniModa', 1.19, 1.52, 'Bodoni'),
  /// DM Serif — a modern display serif with a large eye.
  dmSerif('DMSerifDisplay', 1.13, 1.37, 'DM Serif'),
  /// Josefin — 1920s geometric, with a very small x-height.
  josefin('JosefinSans', 1.32, 1.14, 'Josefin'),
  /// Jost — a Futura in all but name.
  jost('Jost', 1.19, 1.45, 'Jost'),
  /// Outfit — a clean geometric sans with even weight.
  outfit('Outfit', 1.15, 1.31, 'Outfit'),
  /// Aref Ruqaa — the ruqʿah hand — everyday Arabic handwriting. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  arefRuqaa('ArefRuqaa', 1.03, 1.56,
      'Aref Ruqaa', arabicScript: true),
  /// Almarai — a clean corporate naskh. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  almarai('Almarai', 0.91, 1.65,
      'Almarai', arabicScript: true),
  /// Cairo — a modern kufi-influenced sans. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  cairo('Cairo', 0.90, 1.87,
      'Cairo', arabicScript: true),
  /// Changa — a display sans with condensed forms. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  changa('Changa', 0.96, 1.84,
      'Changa', arabicScript: true),
  /// El Messiri — a soft, contemporary naskh. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  elMessiri('ElMessiri', 0.95, 1.57,
      'El Messiri', arabicScript: true),
  /// Qahiri — a revival of the 1960s Cairo kufi. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  qahiri('Qahiri', 1.10, 1.37,
      'Qahiri', arabicScript: true),
  /// Reem Kufi — a Fatimid kufi with geometric joins. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  reemKufi('ReemKufi', 1.12, 1.50,
      'Reem Kufi', arabicScript: true),
  /// Vazirmatn — a neutral Persian sans, plain and legible. Offered on a card and not under
  /// a verse: it leaves a combining honorific to the fallback, and a
  /// mark drawn by one face over another's letters is not something to
  /// print in a translation.
  vazirmatn('Vazirmatn', 1.04, 1.56,
      'Vazirmatn', arabicScript: true);

  const DisplayFace(this.family, this.sizeFactor, this.height, this.label,
      {this.arabicScript = false});

  final String family;
  final double sizeFactor;
  final double height;
  final String label;

  /// Which of a card's two lists this face is offered on.
  final bool arabicScript;

  static DisplayFace? fromName(String? name) {
    for (final f in DisplayFace.values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// Where a block's lines sit against each other, and which edge of the
/// block they hang from.
///
/// Stored as a direction-free choice — start, middle, end — so a card
/// whose text is Arabic and one whose text is English mean the same
/// thing by "start", and neither has to be rewritten when the words
/// change script.
enum CardAlign {
  start,
  middle,
  end;

  TextAlign resolve({required bool rtl}) => switch (this) {
        CardAlign.start => rtl ? TextAlign.right : TextAlign.left,
        CardAlign.middle => TextAlign.center,
        CardAlign.end => rtl ? TextAlign.left : TextAlign.right,
      };

  static CardAlign fromName(String? name) => CardAlign.values
      .firstWhere((a) => a.name == name, orElse: () => CardAlign.middle);
}

/// How a block of text is finished so it reads against whatever is
/// behind it.
///
/// This is the one decision on a card that is not taste: white text on
/// a photograph is illegible about a third of the time, and the fix is
/// never "choose a different photograph". Each of these is a different
/// answer to the same problem, in ascending order of how much it
/// admits to solving one.
enum CardSkin {
  /// Nothing at all. For a card standing on a plain ground, where a
  /// shadow would only be a smudge.
  none,

  /// A soft drop shadow under the letters — the default over any
  /// photograph, and what the app's own reels have always used.
  shadow,

  /// A halo of the text's own colour, spread wide and low. Reads as
  /// light coming off the letters rather than as a shadow under them.
  glow,

  /// The text stands on its own translucent slab, shaped to the lines.
  /// The only one that works over a photograph with detail *behind the
  /// words themselves* — a crowd, a lattice, a city at night.
  plate,

  /// A short gilded rule under the block: the verse divider the reels
  /// draw, available to any line here.
  rule;

  static CardSkin fromName(String? name) => CardSkin.values
      .firstWhere((s) => s.name == name, orElse: () => CardSkin.shadow);
}

/// The border a card wears.
///
/// Drawn rather than borrowed: every one of these is built from the
/// same shapes the rest of the app is drawn with — the seal, the
/// cartouche, the arch — so a card looks like it came from this app
/// and not from a template pack.
enum CardFrame {
  none,

  /// One hairline, inset from the edge.
  hairline,

  /// Two rules, a heavy and a fine, the way a printed page is ruled.
  double_,

  /// A bracket at each corner with a smaller one inside it, and a
  /// diamond on the corner point.
  corners,

  /// A hairline with the app's eight-pointed seal set into each
  /// corner.
  khatam,

  /// A pointed arch across the top on two piers — a mihrab, standing
  /// the words in a doorway — with a finer arch inside it, capitals,
  /// and a seal for a keystone.
  arch,

  /// A translucent panel inset from the edge, lifted on a soft shadow,
  /// with a hairline around it: a card inside the card, which is what
  /// makes a busy photograph usable.
  panel,

  /// A gilded moulding, lit from the top left, mitred at the corners,
  /// a seal on every mitre.
  gilt,

  /// A slab of frosted glass on its own shadow, with a sheen across it.
  glass,

  /// A loose pile of three sheets, the two behind turned a little.
  layers,

  /// One rule of light, glowing, a seal burning at every corner.
  glow,

  /// A band of eight-pointed stars linked by turned squares.
  girih,

  /// A band of tiles: diamonds point to point, a dark one in each.
  zellige,

  /// The app's lattice cut into a band, as a mashrabiya frames a window.
  lattice,

  /// A double rule with a leaf and two buds flourishing in each corner.
  arabesque,

  /// An Ottoman cartouche: corners cut inward in quarter circles.
  cartouche,

  /// Small stars all round, a few haloed, a sparkle at each corner.
  stars;

  /// How far in from the edge the frame is drawn, as a fraction of the
  /// card's width.
  double get inset => switch (this) {
        CardFrame.none => 0,
        CardFrame.panel => 0.052,
        CardFrame.arch => 0.058,
        CardFrame.gilt || CardFrame.lattice => 0.03,
        CardFrame.girih || CardFrame.zellige => 0.034,
        CardFrame.arabesque => 0.045,
        CardFrame.cartouche || CardFrame.stars => 0.05,
        CardFrame.glow => 0.055,
        CardFrame.layers => 0.07,
        CardFrame.glass => 0.075,
        _ => 0.048,
      };

  /// Whether the frame darkens what is behind it, which is what
  /// decides whether text over it needs a skin of its own.
  bool get shades =>
      this == CardFrame.panel ||
      this == CardFrame.glass ||
      this == CardFrame.layers;

  static CardFrame fromName(String? name) => CardFrame.values
      .firstWhere((f) => f.name == name, orElse: () => CardFrame.none);
}

/// A ground for a card with no photograph behind it.
///
/// Eight papers, each a gradient and the two inks that read on it —
/// chosen together, so choosing a paper is one decision rather than
/// three. A card on paper costs no download, no decode and no scrim,
/// which is why the composer opens on one.
enum CardPaper {
  /// The app's own night. The card equivalent of the reels' default.
  night(0xFF0D1117, 0xFF1B222C, inkArgb: 0xFFF2EFE6, accentArgb: 0xFFEEC96B),

  /// Ink on ivory: a printed page, and the only ground here that a
  /// gold-on-dark verse should never be put on — which is why its ink
  /// is dark and its accent is the deeper gold.
  ivory(0xFFF8F3E9, 0xFFEDE2CE, inkArgb: 0xFF15181C, accentArgb: 0xFFD4A947, light: true),

  /// Warm, dry, unbleached — desert light on a page.
  sand(0xFFE9DAC0, 0xFFCDB894, inkArgb: 0xFF2C2113, accentArgb: 0xFF8A6A32, light: true),

  /// Deep green, the colour of a mosque carpet and of the cloth a
  /// mushaf is bound in.
  olive(0xFF16291F, 0xFF0A1510, inkArgb: 0xFFF2EFE6, accentArgb: 0xFFBFD4B4),

  /// Almost black, with the barest lift at the top. The quietest
  /// ground a gold line can sit on.
  ink(0xFF11141A, 0xFF000000, inkArgb: 0xFFEADFC8, accentArgb: 0xFFD4A947),

  /// Dusk over water.
  sea(0xFF0F2436, 0xFF06121C, inkArgb: 0xFFF2EFE6, accentArgb: 0xFF9CC7F5),

  /// The warm pale one — the matte look, for a gentle line.
  rose(0xFFF6E1DB, 0xFFE7C2BC, inkArgb: 0xFF4A2A28, accentArgb: 0xFFB56B5F, light: true),

  /// Gilt: a warm dark ground made of the accent itself.
  gilt(0xFF3A2C12, 0xFF17120A, inkArgb: 0xFFEEC96B, accentArgb: 0xFFF3E2B4);

  const CardPaper(this.topArgb, this.bottomArgb,
      {required this.inkArgb, required this.accentArgb, this.light = false});

  final int topArgb;
  final int bottomArgb;

  /// The text colour this paper was chosen with.
  final int inkArgb;

  /// The rule, the seal and the frame on this paper.
  final int accentArgb;

  /// Whether the paper is pale enough that white would disappear into
  /// it — which is what decides the ink of anything dropped onto it
  /// later, and whether the app's own mark is drawn dark or light.
  final bool light;

  List<Color> get colours => [Color(topArgb), Color(bottomArgb)];

  static CardPaper fromName(String? name) => CardPaper.values
      .firstWhere((p) => p.name == name, orElse: () => CardPaper.night);
}
