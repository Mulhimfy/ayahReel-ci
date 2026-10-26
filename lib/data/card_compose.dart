import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'card_deck.dart';
import 'card_style.dart';
import 'reel_effects.dart';
import 'scene_catalog.dart';

/// A designed starting point: everything about a card except the words
/// on it.
///
/// The composer never opens on a blank rectangle. A card made of a
/// verse is a typographic problem with a right answer — a face cut for
/// the script, a size that fills the frame without crowding it, a
/// ground the ink reads on, a rule to separate the verse from its
/// translation — and the user should be handed that answer and then
/// left free to disagree with it. These are the answers.
enum CardTemplate {
  /// The app's own night, a gilded rule, and the mushaf's face. What a
  /// verse card looks like when nobody has asked for anything.
  classic(
    paper: CardPaper.night,
    arabicFace: CardFace.uthmani,
    latinFace: CardFace.cormorant,
    frame: CardFrame.none,
    skin: CardSkin.rule,
  ),

  /// A photograph, darkened, with the type standing on it — the reel
  /// look, held still.
  scenery(
    paper: CardPaper.ink,
    arabicFace: CardFace.uthmani,
    latinFace: CardFace.spectral,
    frame: CardFrame.corners,
    skin: CardSkin.shadow,
    // A family with a bundled member, and that is the whole of why it
    // is this one: `sky` has sixteen sceneries in the catalog and not
    // one of them ships in the app, so [sceneFor] — which only ever
    // picks a bundled scenery — came back empty and this template, the
    // one whose entire idea is a photograph, opened on bare ink paper.
    sceneFamily: 'mountains',
    dim: 0.42,
  ),

  /// Ink on ivory, ruled like a printed page.
  page(
    paper: CardPaper.ivory,
    arabicFace: CardFace.scheherazade,
    latinFace: CardFace.sourceSerif,
    frame: CardFrame.double_,
    skin: CardSkin.none,
  ),

  /// Gold on a warm dark ground, sealed at the corners.
  gilded(
    paper: CardPaper.gilt,
    arabicFace: CardFace.amiri,
    latinFace: CardFace.cormorant,
    frame: CardFrame.khatam,
    skin: CardSkin.none,
  ),

  /// As little as a card can be and still be one: no frame, no rule,
  /// one weight of type, tracked wide.
  quiet(
    paper: CardPaper.ink,
    arabicFace: CardFace.naskh,
    latinFace: CardFace.inter,
    frame: CardFrame.none,
    skin: CardSkin.none,
    tracking: 0.06,
  ),

  /// Deep green, a mihrab across the top, and the words standing in
  /// the doorway.
  mihrab(
    paper: CardPaper.olive,
    arabicFace: CardFace.amiri,
    latinFace: CardFace.literata,
    frame: CardFrame.arch,
    skin: CardSkin.none,
  );

  const CardTemplate({
    required this.paper,
    required this.arabicFace,
    required this.latinFace,
    required this.frame,
    required this.skin,
    this.sceneFamily = '',
    this.dim = 0.3,
    this.tracking = 0,
  });

  final CardPaper paper;
  final CardFace arabicFace;
  final CardFace latinFace;
  final CardFrame frame;
  final CardSkin skin;

  /// A scenery family to open on — `sky`, `mountains`. Only a bundled
  /// scenery is ever chosen, so a template never waits on a download.
  final String sceneFamily;

  /// How far the photograph is darkened, when there is one.
  final double dim;

  final double tracking;

  /// The face for text in [arabicScript].
  CardFace faceFor({required bool arabicScript, bool quran = false}) {
    if (!arabicScript) return latinFace;
    // A hadith is not set in a Quran face: those are cut for the
    // mushaf's own orthography, and borrowing one for anything else
    // is a hand that does not belong to the words.
    return quran ? arabicFace : CardFace.arabicProse;
  }

  static CardTemplate fromName(String? name) => CardTemplate.values
      .firstWhere((t) => t.name == name, orElse: () => CardTemplate.classic);

  /// The template [slide] is standing on, by its ground and its frame,
  /// or null when it is on a mix that is none of them.
  ///
  /// Matched on paper and frame alone, and that pair is unique across
  /// all six. The faces are deliberately left out: somebody who
  /// changes only the face has still chosen the ground and the frame
  /// they are on, and a match that needed every ingredient would
  /// forget both the moment they did.
  ///
  /// This is what lets the composer remember a look now that the tab
  /// no longer asks for one up front.
  static CardTemplate? matching(CardSlide slide) {
    for (final t in CardTemplate.values) {
      if (t.paper == slide.background.paper && t.frame == slide.frame) {
        return t;
      }
    }
    return null;
  }
}

/// Turns words into a finished card, and finished cards into a deck.
///
/// The whole of the app's typographic judgement about cards lives here
/// rather than in the composer's widgets, for two reasons: the
/// composer is not the only caller — a verse handed over from the home
/// screen makes a card without anybody opening a panel — and because
/// every one of these decisions has to be testable without a screen.
abstract final class CardCompose {
  /// Widths everything is measured at. Any width would do — the model
  /// is fractions — but measuring at the export width means the sizes
  /// that come out are the sizes the file will actually be set in.
  static const _w = CardFormat.exportWidth;

  /// How much of the card's height the words may fill, before the
  /// margins the frame and the mark need. A card is mostly air; that
  /// is what makes it read as a card rather than as a screenshot.
  static const _textBox = 0.66;

  /// Gap between two stacked blocks, as a fraction of the card width.
  static const _gap = 0.052;

  /// Where the stack's centre sits. Slightly above the middle: the
  /// app's mark hangs at the bottom, and a block centred on the
  /// geometric middle reads as sitting low.
  static const _centre = 0.465;

  /// A card of [text], with an optional [translation] under it and an
  /// optional [reference] under that, set and placed.
  static CardSlide quote({
    required String id,
    required String text,
    String translation = '',
    String reference = '',
    required CardFormat format,
    CardTemplate template = CardTemplate.classic,
    CardBackground? background,
    ReelEffects effects = ReelEffects.off,
    CardSource source = CardSource.own,
    bool quran = false,
  }) {
    final bg = background ?? CardBackground(paper: template.paper);
    final ink = inkFor(bg, template);
    final accent = accentFor(bg, template);
    final skin = skinFor(bg, template);
    final rtl = CardTextBlock.rtlText(text);
    final blocks = <CardTextBlock>[];

    // The quotation. Sized to fill its share of the card, and the
    // share depends on what has to fit under it.
    final share = _textBox *
        (translation.isEmpty ? 1.0 : 0.62) *
        (reference.isEmpty ? 1.0 : 0.94);
    blocks.add(CardTextBlock(
      id: newId(),
      text: text,
      face: template.faceFor(arabicScript: rtl, quran: quran),
      // A starting size only: [fit] below sizes this one to fill its
      // share of the card, whatever it is set to here.
      size: 0.11,
      colourArgb: ink,
      x: 0.5,
      y: 0.5,
      width: 0.82,
      skin: skin,
      tracking: rtl ? 0 : template.tracking,
      rtl: rtl,
    ));

    if (translation.isNotEmpty) {
      final trtl = CardTextBlock.rtlText(translation);
      blocks.add(CardTextBlock(
        id: newId(),
        text: translation,
        face: template.faceFor(arabicScript: trtl),
        size: 0.042,
        colourArgb: _soften(ink),
        x: 0.5,
        y: 0.5,
        width: 0.78,
        skin: skin == CardSkin.rule ? CardSkin.none : skin,
        rtl: trtl,
      ));
    }

    if (reference.isNotEmpty) {
      blocks.add(CardTextBlock(
        id: newId(),
        text: reference,
        face: template.latinFace.arabicScript
            ? template.latinFace
            : CardFace.inter,
        size: 0.028,
        colourArgb: accent,
        x: 0.5,
        y: 0.5,
        width: 0.8,
        skin: skin == CardSkin.rule ? CardSkin.none : skin,
        tracking: 0.12,
        rtl: CardTextBlock.rtlText(reference),
      ));
    }

    final fitted = fit(blocks, format, share: share);
    return CardSlide(
      id: id,
      background: bg,
      effects: effects,
      frame: template.frame,
      frameArgb: accent,
      blocks: fitted,
      source: source,
    );
  }

  /// Sizes the first block to fill [share] of the card and stacks the
  /// blocks down the middle, centred as a group.
  ///
  /// Everything below the first keeps the size it was given — a
  /// translation and a reference are supporting lines and are set at
  /// fixed, small sizes on purpose — but all of them are shrunk
  /// together if the stack still does not fit, which is what keeps a
  /// long passage inside the card instead of off the bottom of it.
  static List<CardTextBlock> fit(
    List<CardTextBlock> blocks,
    CardFormat format, {
    double share = _textBox,
    double centre = _centre,
    bool fill = true,
  }) {
    if (blocks.isEmpty) return blocks;
    final cardH = _w / format.aspect;
    final first = fill
        ? blocks.first
            .copyWith(size: sizeToFill(blocks.first, format, share: share))
        : blocks.first;
    var out = [first, ...blocks.skip(1)];

    // Everything together, shrunk in step until the whole stack fits
    // inside the text box. Ten passes of 4% is a third off, which is
    // more than any real card needs and terminates whatever happens.
    for (var pass = 0; pass < 10; pass++) {
      final heights = [for (final b in out) heightOf(b, format)];
      final total = heights.fold<double>(0, (a, h) => a + h) +
          _gap * _w * (out.length - 1);
      if (total <= _textBox * cardH || out.first.size <= CardTextBlock.minSize) {
        return _stack(out, heights, total, cardH, centre);
      }
      out = [for (final b in out) b.copyWith(size: b.size * 0.96)];
    }
    final heights = [for (final b in out) heightOf(b, format)];
    final total = heights.fold<double>(0, (a, h) => a + h) +
        _gap * _w * (out.length - 1);
    return _stack(out, heights, total, cardH, centre);
  }

  static List<CardTextBlock> _stack(List<CardTextBlock> blocks,
      List<double> heights, double total, double cardH, double centre) {
    var y = centre * cardH - total / 2;
    final out = <CardTextBlock>[];
    for (var i = 0; i < blocks.length; i++) {
      out.add(blocks[i].copyWith(y: (y + heights[i] / 2) / cardH));
      y += heights[i] + _gap * _w;
    }
    return out;
  }

  /// The largest size at which [block] still fits inside [share] of
  /// the card's height — and never so large that three words fill the
  /// card, which is what a two-word verse would otherwise do.
  static double sizeToFill(
    CardTextBlock block,
    CardFormat format, {
    double share = _textBox,
  }) {
    final limit = share * (_w / format.aspect);
    var lo = CardTextBlock.minSize;
    var hi = CardTextBlock.maxSize;
    // Twelve halvings of a 0.18-wide range settles to well under a
    // tenth of a per cent, which is finer than a pixel at export size.
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      if (heightOf(block.copyWith(size: mid), format) <= limit) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// How tall [block] lays out, in export pixels.
  static double heightOf(CardTextBlock block, CardFormat format) {
    final painter = TextPainter(
      text: TextSpan(
        text: block.text,
        style: block.face.style(
          size: block.size * _w,
          color: const Color(0xFF000000),
          lineHeight: block.lineHeight,
          tracking: block.tracking,
        ),
      ),
      textDirection: block.rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: block.align.resolve(rtl: block.rtl),
      // No cap: the fit is decided by the height that comes back, and
      // a limit here would hide exactly the overflow being measured.
      maxLines: null,
    )..layout(maxWidth: block.width * _w);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  /// The ink a card in this template, on this ground, is written in.
  static int inkFor(CardBackground background, CardTemplate template) =>
      background.hasPicture ? 0xFFFFFFFF : template.paper.inkArgb;

  /// The rule, the frame and the reference line.
  static int accentFor(CardBackground background, CardTemplate template) =>
      background.hasPicture ? 0xFFEEC96B : template.paper.accentArgb;

  /// A photograph needs the words lifted off it; a paper does not.
  static CardSkin skinFor(CardBackground background, CardTemplate template) =>
      background.hasPicture
          ? (template.skin == CardSkin.rule
              ? CardSkin.rule
              : CardSkin.shadow)
          : template.skin;

  /// The supporting line is set in the same ink, a shade quieter.
  static int _soften(int argb) =>
      (argb & 0x00FFFFFF) | (((argb >> 24 & 0xFF) * 0.82).round() << 24);

  /// A scenery for a new card to stand on, drawn at random, so every
  /// card opens on a different photograph rather than on the dark.
  ///
  /// Drawn from the ones that draw at once — bundled, or fetched
  /// before — because a new card never waits on a download: it would
  /// open dark behind a spinner, which is the thing this is here to
  /// end. Each draw also fetches one more still from the library in
  /// the background, so the pool grows toward the whole of it, a card
  /// at a time. Upright stills only: a card is a still, and a wide
  /// picture cropped to an upright card loses most of itself. Empty
  /// when the catalog is not in yet.
  static String drawScene({math.Random? random}) {
    final rng = random ?? _dice;
    final ready = <Scene>[];
    final waiting = <Scene>[];
    for (final s in SceneCatalog.all) {
      if (s.isVideo || s.wide) continue;
      (SceneCatalog.isReadySync(s) ? ready : waiting).add(s);
    }
    if (growPool) {
      unawaited(SceneCatalog.warmCache());
      if (waiting.isNotEmpty) {
        unawaited(SceneCatalog.download(waiting[rng.nextInt(waiting.length)]));
      }
    }
    if (ready.isEmpty) return '';
    return ready[rng.nextInt(ready.length)].id;
  }

  /// Whether a draw also fetches one more scenery. Off under test,
  /// where there is no network to fetch from.
  static bool growPool = !Platform.environment.containsKey('FLUTTER_TEST');

  /// The same, from the sceneries that draw with no network: bundled,
  /// or fetched before. What a new card falls back on when the one it
  /// drew could not be fetched.
  static String randomReadyScene({math.Random? random, String not = ''}) {
    final pool = [
      for (final s in SceneCatalog.all)
        if (!s.isVideo && !s.wide && s.id != not && SceneCatalog.isReadySync(s))
          s.id,
    ];
    if (pool.isEmpty) return '';
    return pool[(random ?? _dice).nextInt(pool.length)];
  }

  static final _dice = math.Random();

  /// A bundled scenery from [family], or none. Bundled only: a
  /// template that has to download before it can draw is not a
  /// starting point.
  static String sceneFor(String family) {
    if (family.isEmpty) return '';
    for (final s in SceneCatalog.all) {
      if (s.bundled && !s.isVideo && !s.wide && s.family == family) {
        return s.id;
      }
    }
    return '';
  }

  /// A deck of one card, ready to open the composer on.
  static CardDeck deck(CardSlide slide, {CardFormat? format}) => CardDeck(
        id: newId(),
        format: format ?? CardFormat.portrait,
        slides: [slide],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  /// The style of [source] carried onto [target] — the ground, the
  /// grade, the frame, and the look of every block that has a
  /// counterpart. What "apply to all" means.
  ///
  /// The ground means the whole ground, the photograph included. It
  /// used to mean the paper, the dim and the blur only, so the one
  /// thing a card is most transformed by — the scenery — was the one
  /// thing "apply to all" left behind: style a card onto a mountain,
  /// tap it, and the rest of the deck stayed on black paper with the
  /// right frame around it. Nobody reads that as "it worked". The crop
  /// travels with the picture too, since a picture framed one way and
  /// re-framed at random is not the card that was copied.
  ///
  /// Counterparts are matched by position, not by id: the blocks of a
  /// card built by [quote] are always quotation, translation,
  /// reference, in that order, so the second block of one card is the
  /// second block of another. A block with no counterpart keeps its
  /// own look and only its ground changes.
  static CardSlide carry(CardSlide source, CardSlide target) {
    final blocks = <CardTextBlock>[];
    for (var i = 0; i < target.blocks.length; i++) {
      final b = target.blocks[i];
      if (i >= source.blocks.length) {
        blocks.add(b);
        continue;
      }
      final s = source.blocks[i];
      blocks.add(b.copyWith(
        // The face follows only within a script: a translation set in
        // Cormorant must not put an Arabic line into a Latin face.
        face: s.face.arabicScript == b.face.arabicScript ? s.face : b.face,
        colourArgb: s.colourArgb,
        align: s.align,
        skin: s.skin,
        tracking: b.rtl ? b.tracking : s.tracking,
        lineHeight: s.lineHeight,
        opacity: s.opacity,
      ));
    }
    return target.copyWith(
      background: target.background.copyWith(
        paper: source.background.paper,
        sceneId: source.background.sceneId,
        filePath: source.background.filePath,
        focusX: source.background.focusX,
        focusY: source.background.focusY,
        zoom: source.background.zoom,
        dim: source.background.dim,
        blur: source.background.blur,
      ),
      effects: source.effects,
      frame: source.frame,
      frameArgb: source.frameArgb,
      blocks: blocks,
    );
  }

  /// The same card in another shape.
  ///
  /// Changing the shape of a card is the one operation that can ruin
  /// one, and the reason is arithmetic rather than taste: every
  /// position is a fraction of the card, so a block sitting a third of
  /// the way down a story lands a third of the way down a square —
  /// which is a different place entirely, because the two cards are
  /// the same width and nothing like the same height.
  ///
  /// So the vertical positions are carried in *width* units instead:
  /// a block that sat 120 units above the centre still sits 120 units
  /// above the centre, and a composition keeps its proportions
  /// whatever the card is cut to. What cannot be kept is anything that
  /// no longer fits, so after the move each block is shrunk until it
  /// does, and nudged back inside the card if the new shape pushed it
  /// out.
  static CardSlide reshape(CardSlide slide, CardFormat from, CardFormat to) {
    if (from == to) return slide;
    final oldH = 1 / from.aspect;
    final newH = 1 / to.aspect;
    final blocks = <CardTextBlock>[];
    for (final b in slide.blocks) {
      var moved = b.copyWith(y: 0.5 + (b.y - 0.5) * (oldH / newH));
      // A block taller than the card it is now on is a block nobody
      // can read. Shrinking is the only move that keeps the words.
      final limit = 0.94 * (_w / to.aspect);
      var height = heightOf(moved, to);
      for (var pass = 0; pass < 12 && height > limit; pass++) {
        moved = moved.copyWith(size: moved.size * 0.92);
        if (moved.size <= CardTextBlock.minSize) break;
        height = heightOf(moved, to);
      }
      // And one that has been carried off the card comes back on.
      final half = height / 2 / (_w / to.aspect);
      final y = moved.y.clamp(half * 0.6, 1 - half * 0.6);
      blocks.add(moved.copyWith(y: y));
    }
    return slide.copyWith(blocks: blocks);
  }

  /// Splits [text] into at most [max] cards' worth of lines, cutting
  /// on sentence ends where it can and on words where it cannot.
  ///
  /// What "turn this into a carousel" does to a paragraph somebody
  /// pasted in. The target is a card's worth of characters rather than
  /// a measured height, because the answer has to be the same before
  /// and after they change the face.
  static List<String> paginate(String text, {int max = CardDeck.maxSlides}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return const [];
    const perCard = 220;
    if (clean.length <= perCard) return [clean];
    final wanted = math.min(max, (clean.length / perCard).ceil());
    final target = clean.length / wanted;
    final out = <String>[];
    var start = 0;
    while (start < clean.length && out.length < wanted - 1) {
      final ideal = (start + target).round();
      final cut = _cutNear(clean, start, ideal);
      out.add(clean.substring(start, cut).trim());
      start = cut;
    }
    final rest = clean.substring(start).trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  /// The best place to end a card near [ideal]: a sentence end if one
  /// is close, otherwise a space, otherwise [ideal] itself.
  static int _cutNear(String s, int start, int ideal) {
    final window = ((ideal - start) * 0.45).round();
    final lo = math.max(start + 1, ideal - window);
    final hi = math.min(s.length, ideal + window);
    for (final marks in const ['.!?۔؟', ',;:،؛', ' ']) {
      var best = -1;
      for (var i = lo; i < hi; i++) {
        if (marks.contains(s[i]) && (best < 0 ||
            (i - ideal).abs() < (best - ideal).abs())) {
          best = i;
        }
      }
      if (best > start) return math.min(s.length, best + 1);
    }
    // No mark or space near: cut where asked, but never between the two
    // halves of an emoji.
    var cut = math.min(s.length, ideal);
    if (cut > start + 1 &&
        cut < s.length &&
        (s.codeUnitAt(cut) & 0xFC00) == 0xDC00) {
      cut--;
    }
    return cut;
  }
}
