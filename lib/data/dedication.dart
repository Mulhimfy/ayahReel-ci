import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// Who a reel or a card was made for.
///
/// Two intentions, and the app keeps them apart because they are not
/// the same act:
///
///  * A **gift** is made for somebody who will see it. The point of it
///    is that they receive it.
///  * **Sadaqah jariyah** is made *on behalf of* somebody — most often
///    somebody who has died — and dedicated to them. The point of it
///    is that the reward carries on. The family still sees it, and
///    often shares it further, which is the whole idea.
///
/// Stored as the intention and the name rather than as a finished
/// sentence, so a reel dedicated in English and reopened in Arabic
/// prints an Arabic dedication — see [L10n.dedicationLine], which is
/// the one place the wording lives.
@immutable
class Dedication {
  final DedicationKind kind;

  /// Who it is for. Trimmed, and capped — see [maxName].
  final String name;

  const Dedication({this.kind = DedicationKind.gift, this.name = ''});

  static const none = Dedication();

  /// How long a name may be.
  ///
  /// Not a database limit: the dedication is drawn as one line above
  /// the app's mark, on a frame 1080 wide, and a name longer than this
  /// stops being a name and starts being a paragraph that has to be
  /// ellipsised in the middle of somebody's grandmother.
  static const maxName = 40;

  bool get isEmpty => name.isEmpty;
  bool get isNotEmpty => name.isNotEmpty;

  Dedication copyWith({DedicationKind? kind, String? name}) => Dedication(
        kind: kind ?? this.kind,
        name: _clean(name ?? this.name),
      );

  /// Whatever the user typed, as it will be drawn: one line, trimmed,
  /// and no longer than [maxName].
  static String _clean(String name) {
    final one = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Counted in characters as the field counts them: a cut by UTF-16
    // units shortened names with emoji or vowel marks that the field had
    // let through, and could split an emoji into a broken glyph.
    final chars = one.characters;
    return chars.length <= maxName
        ? one
        : chars.take(maxName).toString().trim();
  }

  /// Everything about a dedication that changes a pixel, for a render
  /// key. Empty when there is none, so a reel nobody dedicated keys
  /// exactly as it always did and no cached render is thrown away.
  String get key => isEmpty ? '' : '${kind.name}_${name.hashCode
      .toUnsigned(32)
      .toRadixString(36)}';

  @override
  bool operator ==(Object other) =>
      other is Dedication && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  Map<String, dynamic> toJson() => {'kind': kind.name, 'name': name};

  factory Dedication.fromJson(Map<String, dynamic>? j) => j == null
      ? none
      : Dedication(
          kind: DedicationKind.fromName(j['kind'] as String?),
          name: _clean(j['name'] as String? ?? ''),
        );
}

enum DedicationKind {
  /// For somebody who will see it.
  gift,

  /// On behalf of somebody, so the reward carries on.
  sadaqah;

  static DedicationKind fromName(String? name) => DedicationKind.values
      .firstWhere((k) => k.name == name, orElse: () => DedicationKind.gift);
}
