import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/l10n.dart';
import 'dedication.dart';
import 'reel_recipe.dart';
import 'whole_file.dart';

/// A reel the user has exported, kept inside the app so it survives
/// restarts and shows up in "My Reels".
class SavedReel {
  final String id;

  /// File name inside the library directory. Stored relative because
  /// the documents path can change between installs (iOS).
  final String fileName;

  /// Identity of the render this reel came from: the styling key the
  /// exporter caches by. Two exports with the same key are the same
  /// reel byte for byte, so the library stores one entry and one file
  /// for them instead of a copy per tap. Empty for entries written
  /// before the field existed.
  final String sourceKey;

  /// Whether this reel has already been written to the device gallery.
  /// The gallery has no overwrite — a second put of identical bytes
  /// lands as "… (1).mp4" — so a repeat Save checks this instead.
  final bool inGallery;
  final String reciterName;
  final String surahName;
  final int startAyah;
  final int endAyah;

  /// Poster gradient of the background used, shown until (or instead
  /// of) the frame grabbed from the video itself.
  final List<int> gradientArgb;
  final DateTime createdAt;

  /// Everything that went into the render, so the reel can be opened
  /// again and changed. Null for reels made before the recipe was
  /// kept — those can still be played and shared, just not reopened.
  final ReelRecipe? recipe;

  const SavedReel({
    required this.id,
    required this.fileName,
    this.sourceKey = '',
    this.inGallery = false,
    required this.reciterName,
    required this.surahName,
    required this.startAyah,
    required this.endAyah,
    required this.gradientArgb,
    required this.createdAt,
    this.recipe,
  });

  /// Whether this reel can be opened for editing.
  bool get canEdit => recipe != null;

  /// What goes with the file when this reel is shared.
  ///
  /// A dedicated reel is being handed to a person rather than posted
  /// to a feed, so it goes with a message written to them — and that
  /// message carries the store links, because a gift nobody can answer
  /// with one of their own is a gift that stops where it lands. Every
  /// other reel goes with its surah and its voice, as it always has.
  ///
  /// Here rather than on each screen that shares: three of them do,
  /// and three copies of this rule is two too many.
  String shareCaption(L10n l) {
    final d = recipe?.dedication ?? Dedication.none;
    if (d.isNotEmpty) return l.dedicationShareMessage(d.kind, d.name);
    return l.reelShareCaption(surahName, reciterName);
  }

  SavedReel copyWith({bool? inGallery}) => SavedReel(
        id: id,
        fileName: fileName,
        sourceKey: sourceKey,
        inGallery: inGallery ?? this.inGallery,
        reciterName: reciterName,
        surahName: surahName,
        startAyah: startAyah,
        endAyah: endAyah,
        gradientArgb: gradientArgb,
        createdAt: createdAt,
        recipe: recipe,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'sourceKey': sourceKey,
        'inGallery': inGallery,
        'reciterName': reciterName,
        'surahName': surahName,
        'startAyah': startAyah,
        'endAyah': endAyah,
        'gradientArgb': gradientArgb,
        'createdAt': createdAt.toIso8601String(),
        if (recipe != null) 'recipe': recipe!.toJson(),
      };

  factory SavedReel.fromJson(Map<String, dynamic> j) => SavedReel(
        id: j['id'] as String,
        fileName: j['fileName'] as String,
        sourceKey: j['sourceKey'] as String? ?? '',
        inGallery: j['inGallery'] as bool? ?? false,
        reciterName: j['reciterName'] as String,
        surahName: j['surahName'] as String,
        startAyah: j['startAyah'] as int,
        endAyah: j['endAyah'] as int,
        gradientArgb: (j['gradientArgb'] as List).cast<int>(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        recipe: j['recipe'] is Map
            ? ReelRecipe.fromJson(
                (j['recipe'] as Map).cast<String, dynamic>())
            : null,
      );
}

/// Stores exported reels in the app documents directory with a JSON
/// index. No database: a handful of mp4s and one small file.
abstract final class ReelLibrary {
  /// Bumped whenever the library changes, so Home and My Reels can
  /// refresh without polling.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/reels');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<File> _indexFile() async =>
      File('${(await _dir()).path}/library.json');

  /// Newest first. Entries whose video file has vanished are dropped.
  static Future<List<SavedReel>> load() async {
    try {
      final index = await _indexFile();
      if (!index.existsSync()) return [];
      final dir = await _dir();
      final raw = jsonDecode(await index.readAsString()) as List;
      // One entry this build can't read costs only itself. Failing the
      // whole load answered "no reels", and the next save wrote that
      // back over every reel the user had.
      final out = <SavedReel>[];
      for (final e in raw) {
        try {
          final r = SavedReel.fromJson(e as Map<String, dynamic>);
          if (File('${dir.path}/${r.fileName}').existsSync()) out.add(r);
        } catch (_) {}
      }
      return out;
    } catch (_) {
      // Corrupt as a whole: start fresh rather than crash, but keep the
      // old index aside first, since the next save writes over it.
      try {
        final index = await _indexFile();
        if (index.existsSync()) index.copySync('${index.path}.bad');
      } catch (_) {}
      return [];
    }
  }

  static Future<File> videoFile(SavedReel reel) async =>
      File('${(await _dir()).path}/${reel.fileName}');

  /// Where the card thumbnail for [reel] lives. Written on first
  /// display rather than at export, so reels saved by older builds get
  /// one too. May not exist yet — see `ReelPoster.ensure`.
  static Future<File> posterFile(SavedReel reel) async {
    final base = reel.fileName.replaceAll(RegExp(r'\.mp4$'), '');
    return File('${(await _dir()).path}/$base.jpg');
  }

  /// The library entry for [sourceKey], or null if this reel has never
  /// been exported. Only entries whose video still exists count.
  static Future<SavedReel?> findBySource(String sourceKey) async {
    if (sourceKey.isEmpty) return null;
    for (final r in await load()) {
      if (r.sourceKey == sourceKey) return r;
    }
    return null;
  }

  /// Copies [video] into the library and records its metadata.
  ///
  /// Re-exporting a reel the user already has — same recitation, same
  /// background, same styling, so the same [sourceKey] — returns the
  /// existing entry untouched. Without that, Share-then-Save, or simply
  /// tapping Save twice, wrote a second identical mp4 and the folder
  /// grew a copy per tap.
  static Future<SavedReel> add({
    required File video,
    required String sourceKey,
    required String reciterName,
    required String surahName,
    required int startAyah,
    required int endAyah,
    required List<int> gradientArgb,
    ReelRecipe? recipe,
  }) async {
    final existing = await findBySource(sourceKey);
    if (existing != null) return existing;
    final dir = await _dir();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final fileName = 'reel_$id.mp4';
    await video.copy('${dir.path}/$fileName');
    final reel = SavedReel(
      id: id,
      fileName: fileName,
      sourceKey: sourceKey,
      reciterName: reciterName,
      surahName: surahName,
      startAyah: startAyah,
      endAyah: endAyah,
      gradientArgb: gradientArgb,
      createdAt: DateTime.now(),
      recipe: recipe,
    );
    await _write([reel, ...await load()]);
    return reel;
  }

  /// Records that [reel] now exists in the device gallery, so a later
  /// Save of the same reel can decline instead of writing a duplicate.
  static Future<SavedReel> markInGallery(SavedReel reel) async {
    final updated = reel.copyWith(inGallery: true);
    final all = await load();
    await _write([
      for (final r in all) r.id == reel.id ? updated : r,
    ]);
    return updated;
  }

  static Future<void> remove(SavedReel reel) async {
    final all = await load();
    final file = await videoFile(reel);
    if (file.existsSync()) await file.delete();
    final poster = await posterFile(reel);
    if (poster.existsSync()) await poster.delete();
    await _write(all.where((r) => r.id != reel.id).toList());
  }

  static Future<void> _write(List<SavedReel> reels) async {
    final index = await _indexFile();
    await writeWhole(
        index, jsonEncode(reels.map((r) => r.toJson()).toList()));
    revision.value++;
  }
}
