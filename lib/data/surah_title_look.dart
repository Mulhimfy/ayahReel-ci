import 'package:flutter/foundation.dart';

import 'verse_ink.dart';

/// The face the surah's name is set in, with the Latin face the name in
/// capitals under it is paired with.
///
/// Every one is bundled (see pubspec.yaml), so a phone with no
/// connection exports the title it previews. [scale] and [height] even
/// the faces out: Jomhuria's letters sit small in their box, Katibeh's
/// flourishes run tall.
enum TitleFace {
  /// Ruqaa: the title the app has always set.
  ruqaa('ArefRuqaa', 'Cinzel', 1.0, 1.35),

  /// Naskh, as a printed mushaf heads its surahs.
  naskh('Amiri', 'CormorantGaramond', 0.92, 1.55),

  /// Kufi: square and modern.
  kufi('ReemKufi', 'Montserrat', 0.84, 1.42),

  /// A calligrapher's display hand.
  diwani('Katibeh', 'Marcellus', 1.2, 1.15),

  /// Heavy, for a title that has to carry across the room.
  bold('Jomhuria', 'Cinzel', 1.38, 1.0);

  const TitleFace(this.arabic, this.latin, this.scale, this.height);

  final String arabic;
  final String latin;
  final double scale;
  final double height;
}

/// What frames the name.
enum TitleFrame {
  /// Two rules either side, each ending in a diamond by the name: the
  /// title the app has always set.
  rules,

  /// The name alone.
  plain,

  /// The name inside a cartouche.
  cartouche,

  /// The name on a band with pointed ends, as a mushaf's surah heading.
  band,
}

/// How the surah's name is set on a reel: its face, its colour and its
/// frame.
///
/// The colour is either one of the luminous inks the verse can be
/// written in ([ink]) or a flat colour ([argb]); 0 is the house gold,
/// which takes its deeper shade on a pale band.
@immutable
class SurahTitleLook {
  final TitleFace face;
  final TitleFrame frame;
  final VerseInk ink;
  final int argb;

  const SurahTitleLook({
    this.face = TitleFace.ruqaa,
    this.frame = TitleFrame.rules,
    this.ink = VerseInk.none,
    this.argb = 0,
  });

  /// The title the app has always drawn.
  static const classic = SurahTitleLook();

  /// The flat colours offered beside the house gold and the inks.
  static const flats = [
    0xFFFFFFFF,
    0xFFF5ECD7,
    0xFFF4B6C2,
    0xFFA8E6CF,
    0xFFA7C7FF,
  ];

  bool get isClassic =>
      face == TitleFace.ruqaa &&
      frame == TitleFrame.rules &&
      ink == VerseInk.none &&
      argb == 0;

  /// Short and stable: what the title's PNG and the render's cache key
  /// carry. Empty for [classic], so every reel and title rendered before
  /// the look could change keeps its name.
  String get code => isClassic
      ? ''
      : '${face.index}${frame.index}'
          '${ink == VerseInk.none ? '' : 'i${ink.index}'}'
          '${argb == 0 ? '' : 'c${argb.toRadixString(16)}'}';

  SurahTitleLook copyWith({
    TitleFace? face,
    TitleFrame? frame,
    VerseInk? ink,
    int? argb,
  }) =>
      SurahTitleLook(
        face: face ?? this.face,
        frame: frame ?? this.frame,
        ink: ink ?? this.ink,
        argb: argb ?? this.argb,
      );

  /// A flat colour: the ink comes off.
  SurahTitleLook withFlat(int argb) =>
      SurahTitleLook(face: face, frame: frame, argb: argb);

  /// An ink: the flat colour goes back to the gold underneath it.
  SurahTitleLook withInk(VerseInk ink) =>
      SurahTitleLook(face: face, frame: frame, ink: ink);

  Map<String, dynamic> toJson() => {
        'face': face.name,
        'frame': frame.name,
        if (ink != VerseInk.none) 'ink': ink.name,
        if (argb != 0) 'argb': argb,
      };

  /// Anything unreadable falls back to the part of [classic] it stood
  /// for, so a newer build's look never fails an older reel's recipe.
  static SurahTitleLook fromJson(Object? j) {
    if (j is! Map) return classic;
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return fallback;
    }

    final argb = j['argb'];
    return SurahTitleLook(
      face: pick(TitleFace.values, j['face'], TitleFace.ruqaa),
      frame: pick(TitleFrame.values, j['frame'], TitleFrame.rules),
      ink: pick(VerseInk.values, j['ink'], VerseInk.none),
      argb: argb is int ? argb : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SurahTitleLook &&
      other.face == face &&
      other.frame == frame &&
      other.ink == ink &&
      other.argb == argb;

  @override
  int get hashCode => Object.hash(face, frame, ink, argb);
}
