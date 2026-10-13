import 'package:flutter/foundation.dart';

import 'card_style.dart';
import 'dedication.dart';
import 'reel_effects.dart';

/// One block of words on a card.
///
/// Everything about where it sits and how big it is, is a fraction —
/// see the header of `card_style.dart`. [x] and [y] are the *centre*
/// of the block, as fractions of the card's width and height, and
/// [width] is how much of the card's width the lines may fill before
/// they wrap. A block is therefore the same block at 320pt and at
/// 1080px, and the same block again when the card is re-shaped from
/// square to story.
@immutable
class CardTextBlock {
  final String id;
  final String text;
  final CardFace face;

  /// Type size, as a fraction of the card's width. 0.08 is eight per
  /// cent of the width — about 86px on an exported card.
  final double size;

  final int colourArgb;
  final CardAlign align;

  /// Centre of the block, 0..1 across and down the card.
  final double x;
  final double y;

  /// How wide the lines may run, as a fraction of the card's width.
  final double width;

  /// Degrees, positive clockwise. Small angles only — see
  /// [maxRotation].
  final double rotation;

  final CardSkin skin;

  /// Multiplies the face's own line box. 1 is the face as its designer
  /// leaded it; the slider runs 0.8 to 1.6.
  final double lineHeight;

  /// Letter spacing as a fraction of the type size. Ignored for joined
  /// script, which must never be tracked.
  final double tracking;

  final double opacity;

  /// Whether the paragraph runs right to left. Set from the script of
  /// the text when a block is made, and left alone after: a user who
  /// has turned it is not to be overruled by a later edit.
  final bool rtl;

  const CardTextBlock({
    required this.id,
    required this.text,
    required this.face,
    required this.size,
    required this.colourArgb,
    this.align = CardAlign.middle,
    required this.x,
    required this.y,
    this.width = 0.8,
    this.rotation = 0,
    this.skin = CardSkin.shadow,
    this.lineHeight = 1,
    this.tracking = 0,
    this.opacity = 1,
    this.rtl = false,
  });

  /// How far a block may be turned. Past this a card stops reading as
  /// designed and starts reading as broken, and there is no verse that
  /// is improved by being on its side.
  static const maxRotation = 12.0;

  /// The range the size slider runs over. The floor is the smallest
  /// type that survives being posted to a feed and re-compressed; the
  /// ceiling is one word across the whole card.
  static const minSize = 0.022;
  static const maxSize = 0.20;

  CardTextBlock copyWith({
    String? text,
    CardFace? face,
    double? size,
    int? colourArgb,
    CardAlign? align,
    double? x,
    double? y,
    double? width,
    double? rotation,
    CardSkin? skin,
    double? lineHeight,
    double? tracking,
    double? opacity,
    bool? rtl,
  }) =>
      CardTextBlock(
        id: id,
        text: text ?? this.text,
        face: face ?? this.face,
        size: (size ?? this.size).clamp(minSize, maxSize),
        colourArgb: colourArgb ?? this.colourArgb,
        align: align ?? this.align,
        // A block is kept reachable: its centre may leave the card by
        // a little, so a line can hang off the edge on purpose, but
        // never so far that it cannot be caught and dragged back.
        x: (x ?? this.x).clamp(-0.15, 1.15),
        y: (y ?? this.y).clamp(-0.15, 1.15),
        width: (width ?? this.width).clamp(0.2, 1.0),
        rotation: (rotation ?? this.rotation).clamp(-maxRotation, maxRotation),
        skin: skin ?? this.skin,
        lineHeight: (lineHeight ?? this.lineHeight).clamp(0.8, 1.8),
        tracking: (tracking ?? this.tracking).clamp(-0.03, 0.3),
        opacity: (opacity ?? this.opacity).clamp(0.15, 1.0),
        rtl: rtl ?? this.rtl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'face': face.name,
        'size': size,
        'colour': colourArgb,
        'align': align.name,
        'x': x,
        'y': y,
        'width': width,
        if (rotation != 0) 'rotation': rotation,
        'skin': skin.name,
        if (lineHeight != 1) 'lineHeight': lineHeight,
        if (tracking != 0) 'tracking': tracking,
        if (opacity != 1) 'opacity': opacity,
        if (rtl) 'rtl': true,
      };

  factory CardTextBlock.fromJson(Map<String, dynamic> j) => CardTextBlock(
        id: j['id'] as String? ?? newId(),
        text: j['text'] as String? ?? '',
        face: CardFace.fromName(j['face'] as String?),
        size: _num(j['size'], 0.07),
        colourArgb: j['colour'] as int? ?? 0xFFFFFFFF,
        align: CardAlign.fromName(j['align'] as String?),
        x: _num(j['x'], 0.5),
        y: _num(j['y'], 0.5),
        width: _num(j['width'], 0.8),
        rotation: _num(j['rotation'], 0),
        skin: CardSkin.fromName(j['skin'] as String?),
        lineHeight: _num(j['lineHeight'], 1),
        tracking: _num(j['tracking'], 0),
        opacity: _num(j['opacity'], 1),
        rtl: j['rtl'] as bool? ?? false,
      );

  /// True when [text] is written in a script that runs right to left.
  /// Decided on the letters themselves rather than on the app's
  /// language: a card written in English by somebody reading the app
  /// in Arabic is still an English card.
  static bool rtlText(String text) {
    for (final c in text.runes) {
      // Arabic, Hebrew, Syriac, Thaana and the Arabic supplements.
      if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) ||
          (c >= 0xFE70 && c <= 0xFEFF)) {
        return true;
      }
      if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) return false;
    }
    return false;
  }
}

/// What stands behind the words: a paper, a scenery from the app's own
/// library, or a photograph the user brought in.
///
/// The scenery library is shared with the reels, whole and by id — see
/// [SceneCatalog]. A scenery added to the catalog appears in both
/// places on the same build, because there is only one catalog and
/// neither side keeps a list of its own.
@immutable
class CardBackground {
  /// The ground under everything. Shown as the card's own background
  /// when there is no picture, and behind a picture while it decodes.
  final CardPaper paper;

  /// Catalog scenery id, or empty.
  final String sceneId;

  /// A photograph the user picked, or empty.
  final String filePath;

  /// Which part of the picture the card keeps, 0..1. The library is
  /// entirely upright 9:16 and every card is squarer than that, so
  /// [focusY] is the one that matters: 0 keeps the top of the
  /// photograph, 1 the bottom, 0.5 the middle.
  final double focusX;
  final double focusY;

  /// 1 fills the card; above that the picture is pushed in closer.
  final double zoom;

  /// How much black is laid over the picture, 0..1 — the card's own
  /// version of the reels' legibility scrim.
  final double dim;

  /// How far the picture is thrown out of focus, 0..1. A blurred
  /// photograph is the oldest trick there is for making type readable
  /// over one, and the only one that keeps its colour.
  final double blur;

  const CardBackground({
    this.paper = CardPaper.night,
    this.sceneId = '',
    this.filePath = '',
    this.focusX = 0.5,
    this.focusY = 0.5,
    this.zoom = 1,
    this.dim = 0.28,
    this.blur = 0,
  });

  bool get hasPicture => sceneId.isNotEmpty || filePath.isNotEmpty;

  /// True when the card's own ground shows — which is when the ink
  /// colour has to answer to the paper rather than to a photograph.
  bool get isPaper => !hasPicture;

  CardBackground copyWith({
    CardPaper? paper,
    String? sceneId,
    String? filePath,
    double? focusX,
    double? focusY,
    double? zoom,
    double? dim,
    double? blur,
  }) =>
      CardBackground(
        paper: paper ?? this.paper,
        sceneId: sceneId ?? this.sceneId,
        filePath: filePath ?? this.filePath,
        focusX: (focusX ?? this.focusX).clamp(0.0, 1.0),
        focusY: (focusY ?? this.focusY).clamp(0.0, 1.0),
        zoom: (zoom ?? this.zoom).clamp(1.0, 2.5),
        dim: (dim ?? this.dim).clamp(0.0, 0.92),
        blur: (blur ?? this.blur).clamp(0.0, 1.0),
      );

  /// Clears the picture and stands the card on [paper] instead.
  CardBackground onPaper(CardPaper paper) => CardBackground(
        paper: paper,
        focusX: focusX,
        focusY: focusY,
        zoom: zoom,
        dim: dim,
        blur: blur,
      );

  Map<String, dynamic> toJson() => {
        'paper': paper.name,
        if (sceneId.isNotEmpty) 'scene': sceneId,
        if (filePath.isNotEmpty) 'file': filePath,
        'focusX': focusX,
        'focusY': focusY,
        if (zoom != 1) 'zoom': zoom,
        'dim': dim,
        if (blur != 0) 'blur': blur,
      };

  factory CardBackground.fromJson(Map<String, dynamic> j) => CardBackground(
        paper: CardPaper.fromName(j['paper'] as String?),
        sceneId: j['scene'] as String? ?? '',
        filePath: j['file'] as String? ?? '',
        focusX: _num(j['focusX'], 0.5),
        focusY: _num(j['focusY'], 0.5),
        zoom: _num(j['zoom'], 1),
        dim: _num(j['dim'], 0.28),
        blur: _num(j['blur'], 0),
      );
}

/// Where a card's words came from, so a saved card can say so and a
/// reader can look it up.
///
/// Kept as a reference rather than as a claim: a card that quotes
/// 2:286 says 2:286, and a card somebody typed themselves says
/// nothing at all. Nothing here is drawn unless the user asked for a
/// reference line — this is the card's provenance, not its design.
@immutable
class CardSource {
  /// `verse`, `hadith` or empty for the user's own words.
  final String kind;

  final int surah;
  final int startAyah;
  final int endAyah;

  /// Hadith collection id and number, when [kind] is `hadith`.
  final String collection;
  final int number;

  const CardSource({
    this.kind = '',
    this.surah = 0,
    this.startAyah = 0,
    this.endAyah = 0,
    this.collection = '',
    this.number = 0,
  });

  static const own = CardSource();

  const CardSource.verse(this.surah, this.startAyah, this.endAyah)
      : kind = 'verse',
        collection = '',
        number = 0;

  const CardSource.hadith(this.collection, this.number)
      : kind = 'hadith',
        surah = 0,
        startAyah = 0,
        endAyah = 0;

  bool get isVerse => kind == 'verse';
  bool get isHadith => kind == 'hadith';

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (isVerse) 'surah': surah,
        if (isVerse) 'start': startAyah,
        if (isVerse) 'end': endAyah,
        if (isHadith) 'collection': collection,
        if (isHadith) 'number': number,
      };

  factory CardSource.fromJson(Map<String, dynamic>? j) => j == null
      ? own
      : CardSource(
          kind: j['kind'] as String? ?? '',
          surah: j['surah'] as int? ?? 0,
          startAyah: j['start'] as int? ?? 0,
          endAyah: j['end'] as int? ?? 0,
          collection: j['collection'] as String? ?? '',
          number: j['number'] as int? ?? 0,
        );
}

/// One card.
@immutable
class CardSlide {
  final String id;
  final CardBackground background;

  /// The grade and the finish over the picture — the same value the
  /// reels carry, and the same arithmetic behind it. A card uses the
  /// look, the warmth, the vibrance, the vignette and the grain; the
  /// fade is a moving picture's business and is ignored here.
  final ReelEffects effects;

  final CardFrame frame;
  final int frameArgb;

  /// Bottom to top: the first block is drawn first.
  final List<CardTextBlock> blocks;

  final CardSource source;

  const CardSlide({
    required this.id,
    this.background = const CardBackground(),
    this.effects = ReelEffects.off,
    this.frame = CardFrame.none,
    this.frameArgb = 0xFFEEC96B,
    this.blocks = const [],
    this.source = CardSource.own,
  });

  CardSlide copyWith({
    CardBackground? background,
    ReelEffects? effects,
    CardFrame? frame,
    int? frameArgb,
    List<CardTextBlock>? blocks,
    CardSource? source,
  }) =>
      CardSlide(
        id: id,
        background: background ?? this.background,
        effects: effects ?? this.effects,
        frame: frame ?? this.frame,
        frameArgb: frameArgb ?? this.frameArgb,
        blocks: blocks ?? this.blocks,
        source: source ?? this.source,
      );

  /// The same slide with [block] put back where it was.
  CardSlide withBlock(CardTextBlock block) => copyWith(blocks: [
        for (final b in blocks) b.id == block.id ? block : b,
      ]);

  CardSlide withoutBlock(String id) =>
      copyWith(blocks: [for (final b in blocks) if (b.id != id) b]);

  CardTextBlock? block(String? id) {
    if (id == null) return null;
    for (final b in blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// The words on this card, longest block first — what the library
  /// shows under its cover, and what names a deck that quotes nothing.
  String get caption {
    final texts = [for (final b in blocks) b.text.trim()]
      ..removeWhere((t) => t.isEmpty)
      ..sort((a, b) => b.length.compareTo(a.length));
    return texts.isEmpty ? '' : texts.first;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'background': background.toJson(),
        'effects': effects.toJson(),
        'frame': frame.name,
        'frameArgb': frameArgb,
        'blocks': [for (final b in blocks) b.toJson()],
        'source': source.toJson(),
      };

  factory CardSlide.fromJson(Map<String, dynamic> j) => CardSlide(
        id: j['id'] as String? ?? newId(),
        background: CardBackground.fromJson(
            (j['background'] as Map?)?.cast<String, dynamic>() ?? const {}),
        effects: ReelEffects.fromJson(
            (j['effects'] as Map?)?.cast<String, dynamic>()),
        frame: CardFrame.fromName(j['frame'] as String?),
        frameArgb: j['frameArgb'] as int? ?? 0xFFEEC96B,
        blocks: [
          for (final b in (j['blocks'] as List? ?? const []))
            CardTextBlock.fromJson((b as Map).cast<String, dynamic>()),
        ],
        source: CardSource.fromJson(
            (j['source'] as Map?)?.cast<String, dynamic>()),
      );
}

/// A card, or a run of them meant to be posted together.
///
/// One type for both: a single card is a deck of one, which is what
/// keeps the composer, the library and the export from each having a
/// one-card path and a many-card path that drift apart.
@immutable
class CardDeck {
  final String id;
  final CardFormat format;
  final List<CardSlide> slides;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Who the deck was made for, if anybody. On the deck rather than on
  /// each card: a carousel is one gift, and a dedication that differed
  /// between its cards would be a mistake somebody made rather than a
  /// thing anybody wants.
  final Dedication dedication;

  const CardDeck({
    required this.id,
    this.format = CardFormat.portrait,
    required this.slides,
    required this.createdAt,
    required this.updatedAt,
    this.dedication = Dedication.none,
  });

  /// How many cards one deck may hold. A carousel on either of the
  /// networks this app posts to stops at ten, and a deck that cannot
  /// be posted whole is a trap rather than a feature.
  static const maxSlides = 10;

  bool get isFull => slides.length >= maxSlides;

  CardDeck copyWith({
    CardFormat? format,
    List<CardSlide>? slides,
    DateTime? updatedAt,
    Dedication? dedication,
  }) =>
      CardDeck(
        id: id,
        format: format ?? this.format,
        slides: slides ?? this.slides,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        dedication: dedication ?? this.dedication,
      );

  CardDeck withSlide(CardSlide slide) => copyWith(slides: [
        for (final s in slides) s.id == slide.id ? slide : s,
      ]);

  CardSlide? slide(String id) {
    for (final s in slides) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The words this deck is known by in the library.
  String get caption {
    for (final s in slides) {
      final c = s.caption;
      if (c.isNotEmpty) return c;
    }
    return '';
  }

  /// What the deck quotes, if anything — the first slide that names a
  /// source.
  CardSource get source {
    for (final s in slides) {
      if (s.source.kind.isNotEmpty) return s.source;
    }
    return CardSource.own;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'format': format.name,
        'slides': [for (final s in slides) s.toJson()],
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (dedication.isNotEmpty) 'dedication': dedication.toJson(),
      };

  factory CardDeck.fromJson(Map<String, dynamic> j) {
    final slides = [
      for (final s in (j['slides'] as List? ?? const []))
        CardSlide.fromJson((s as Map).cast<String, dynamic>()),
    ];
    final created = DateTime.tryParse(j['createdAt'] as String? ?? '');
    return CardDeck(
      id: j['id'] as String? ?? newId(),
      format: CardFormat.fromName(j['format'] as String?),
      // A deck with no cards cannot be opened, so a file that somehow
      // holds none opens on an empty one rather than on a crash.
      slides: slides.isEmpty ? [CardSlide(id: newId())] : slides,
      createdAt: created ?? DateTime.now(),
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
          created ??
          DateTime.now(),
      dedication: Dedication.fromJson(
          (j['dedication'] as Map?)?.cast<String, dynamic>()),
    );
  }
}

/// Ids are only ever compared inside one deck, so the clock plus a
/// counter is enough and costs nothing.
int _seq = 0;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${(_seq++).toRadixString(36)}';

double _num(Object? v, double fallback) =>
    v is num ? v.toDouble() : fallback;
